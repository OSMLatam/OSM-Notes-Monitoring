#!/usr/bin/env bash
#
# Performance Tests: Monitoring System Overhead
# Measures the performance overhead introduced by the monitoring system
#
# Version: 1.0.0
# Date: 2025-12-26
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration (set before loading test_helper to allow override)
export TEST_COMPONENT="INGESTION"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Set LOG_DIR before loading monitorIngestion.sh
export LOG_DIR="${LOG_DIR:-${BATS_TEST_DIRNAME}/../tmp/logs}"
mkdir -p "${LOG_DIR}"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh"

PERFORMANCE_ITERATIONS="${PERFORMANCE_ITERATIONS:-10}"
PERFORMANCE_THRESHOLD_MS="${PERFORMANCE_THRESHOLD_MS:-1000}"

# Performance thresholds (in milliseconds)
THRESHOLD_CHECK_SCRIPT_EXECUTION=500
THRESHOLD_CHECK_ERROR_RATE=300
THRESHOLD_CHECK_DISK_SPACE=200
THRESHOLD_STORE_METRIC=50
THRESHOLD_SEND_ALERT=100
THRESHOLD_DB_QUERY=100

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_WARN}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Set mock ingestion path
    MOCK_INGESTION_DIR="${BATS_TEST_DIRNAME}/../tmp/mock_ingestion_perf"
    export INGESTION_REPO_PATH="${MOCK_INGESTION_DIR}"
    export INGESTION_LOG_DIR="${MOCK_INGESTION_DIR}/logs"
    
    # Create mock ingestion directory structure
    mkdir -p "${MOCK_INGESTION_DIR}/bin"
    mkdir -p "${MOCK_INGESTION_DIR}/logs"
    
    # Create test scripts
    touch "${MOCK_INGESTION_DIR}/bin/processAPINotes.sh"
    touch "${MOCK_INGESTION_DIR}/bin/processPlanetNotes.sh"
    touch "${MOCK_INGESTION_DIR}/bin/notesCheckVerifier.sh"
    chmod +x "${MOCK_INGESTION_DIR}/bin"/*.sh
    
    # Create test log file
    echo "$(date -u +"%Y-%m-%d %H:%M:%S") INFO: Test log entry" > "${MOCK_INGESTION_DIR}/logs/ingestion.log"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Load monitoring configuration
    export INGESTION_SCRIPTS_FOUND_THRESHOLD=3
    export INGESTION_LAST_LOG_AGE_THRESHOLD=24
    export INGESTION_MAX_ERROR_RATE=5
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_monitoring_overhead.log"
    init_logging "${LOG_FILE}" "test_monitoring_overhead"
    
    # Initialize alerting
    init_alerting
}

teardown() {
    # Clean up test directories
    rm -rf "${MOCK_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Helper function to measure execution time
##
measure_time() {
    local start_time
    start_time=$(date +%s%N)
    "$@"
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    echo "${duration_ms}"
}

##
# Helper function to get memory usage
##
get_memory_usage() {
    if command -v ps > /dev/null 2>&1; then
        ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0"
    else
        echo "0"
    fi
}

##
# Helper function to calculate average
##
calculate_average() {
    local sum=0
    local count=0
    while IFS= read -r value; do
        if [[ -n "${value}" ]] && [[ "${value}" =~ ^[0-9]+$ ]]; then
            sum=$((sum + value))
            count=$((count + 1))
        fi
    done
    if [[ ${count} -gt 0 ]]; then
        echo $((sum / count))
    else
        echo "0"
    fi
}

@test "Performance: check_script_execution_status overhead" {
    skip_if_database_not_available
    
    local times=()
    local memory_before
    memory_before=$(get_memory_usage)
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_script_execution_status)
        times+=("${duration}")
    done
    
    local memory_after
    memory_after=$(get_memory_usage)
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Calculate max time
    local max_time=0
    for time in "${times[@]}"; do
        if [[ ${time} -gt ${max_time} ]]; then
            max_time=${time}
        fi
    done
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_SCRIPT_EXECUTION}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_SCRIPT_EXECUTION}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
    echo "# Max time: ${max_time}ms" >&3
    echo "# Memory before: ${memory_before}KB" >&3
    echo "# Memory after: ${memory_after}KB" >&3
}

@test "Performance: check_error_rate overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_error_rate)
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_ERROR_RATE}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_ERROR_RATE}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_disk_space overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_disk_space)
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_DISK_SPACE}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_DISK_SPACE}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: store_metric overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time store_metric "ingestion" "test_metric" "100" "count" "null")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_STORE_METRIC}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_STORE_METRIC}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: send_alert overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time send_alert "INGESTION" "INFO" "test_alert" "Test alert message")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_SEND_ALERT}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_SEND_ALERT}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: database query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time execute_sql_query "SELECT 1;")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_DB_QUERY}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_DB_QUERY}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: complete monitoring cycle overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of complete monitoring cycle
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local start_time
        start_time=$(date +%s%N)
        
        check_script_execution_status
        check_error_rate
        check_disk_space
        
        local end_time
        end_time=$(date +%s%N)
        local duration_ms
        duration_ms=$(( (end_time - start_time) / 1000000 ))
        times+=("${duration_ms}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Calculate total threshold (sum of individual thresholds)
    local total_threshold
    total_threshold=$((THRESHOLD_CHECK_SCRIPT_EXECUTION + THRESHOLD_CHECK_ERROR_RATE + THRESHOLD_CHECK_DISK_SPACE))
    
    # Verify performance is within threshold (allow some overhead for coordination)
    local adjusted_threshold
    adjusted_threshold=$((total_threshold + 200))
    assert [ "${avg_time}" -lt "${adjusted_threshold}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${adjusted_threshold}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
    echo "# Threshold: ${adjusted_threshold}ms" >&3
}

@test "Performance: memory overhead of monitoring functions" {
    skip_if_database_not_available
    
    local memory_before
    memory_before=$(get_memory_usage)
    
    # Run monitoring checks multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        check_script_execution_status
        check_error_rate
        check_disk_space
    done
    
    local memory_after
    memory_after=$(get_memory_usage)
    
    local memory_increase
    memory_increase=$((memory_after - memory_before))
    
    # Memory increase should be reasonable (less than 10MB for 10 iterations)
    local max_memory_increase=10240
    assert [ "${memory_increase}" -lt "${max_memory_increase}" ] \
        "Memory increase (${memory_increase}KB) exceeds threshold (${max_memory_increase}KB)"
    
    # Log results
    echo "# Memory before: ${memory_before}KB" >&3
    echo "# Memory after: ${memory_after}KB" >&3
    echo "# Memory increase: ${memory_increase}KB" >&3
}

@test "Performance: concurrent monitoring checks overhead" {
    skip_if_database_not_available
    
    local start_time
    start_time=$(date +%s%N)
    
    # Run monitoring checks concurrently
    check_script_execution_status &
    local pid1=$!
    check_error_rate &
    local pid2=$!
    check_disk_space &
    local pid3=$!
    
    # Wait for all to complete
    wait "${pid1}" "${pid2}" "${pid3}"
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Concurrent execution should be faster than sequential
    # (but may be slower due to database contention)
    local sequential_threshold
    sequential_threshold=$((THRESHOLD_CHECK_SCRIPT_EXECUTION + THRESHOLD_CHECK_ERROR_RATE + THRESHOLD_CHECK_DISK_SPACE))
    
    # Log results
    echo "# Concurrent execution time: ${duration_ms}ms" >&3
    echo "# Sequential threshold: ${sequential_threshold}ms" >&3
    
    # Note: We don't assert here as concurrent execution may be slower due to DB contention
    # This test is mainly for measurement purposes
}

@test "Performance: record_metric overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time record_metric "INGESTION" "test_metric" "100" "component=ingestion")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # record_metric calls store_metric, so threshold should be similar
    local threshold
    threshold=$((THRESHOLD_STORE_METRIC + 50))
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${threshold}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${threshold}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

