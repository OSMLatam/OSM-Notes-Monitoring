#!/usr/bin/env bash
#
# Performance Tests: WMS Monitoring Overhead
# Measures the performance overhead introduced by WMS monitoring
#
# Version: 1.0.0
# Date: 2025-12-27
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration (set before loading test_helper to allow override)
export TEST_COMPONENT="WMS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Set TEST_MODE and LOG_DIR before loading monitorWMS.sh
export TEST_MODE=true
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
source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorWMS.sh"

PERFORMANCE_ITERATIONS="${PERFORMANCE_ITERATIONS:-10}"
PERFORMANCE_THRESHOLD_MS="${PERFORMANCE_THRESHOLD_MS:-1000}"

# Performance thresholds (in milliseconds)
THRESHOLD_CHECK_SERVICE_AVAILABILITY=500
THRESHOLD_CHECK_HEALTH=300
THRESHOLD_CHECK_RESPONSE_TIME=300
THRESHOLD_CHECK_ERROR_RATE=200
THRESHOLD_CHECK_TILE_PERFORMANCE=500
THRESHOLD_CHECK_CACHE=200

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_WARN}"

    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"

    # Set test WMS configuration
    export WMS_ENABLED="true"
    export WMS_BASE_URL="http://localhost:8080"
    export WMS_HEALTH_CHECK_URL="http://localhost:8080/health"
    export WMS_CHECK_TIMEOUT="10"
    export WMS_RESPONSE_TIME_THRESHOLD="2000"
    export WMS_ERROR_RATE_THRESHOLD="5"
    export WMS_TILE_GENERATION_THRESHOLD="5000"
    export WMS_CACHE_HIT_RATE_THRESHOLD="80"
    export WMS_LOG_DIR="${TEST_LOG_DIR}"

    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"

    # Mock curl for fast responses
    # shellcheck disable=SC2317
    curl() {
        if [[ "${1}" == "-w" ]]; then
            echo "200"
            return 0
        fi
        echo "OK"
        return 0
    }
    export -f curl

    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_wms_monitoring_overhead.log"
    init_logging "${LOG_FILE}" "test_wms_monitoring_overhead"

    # Initialize alerting
    init_alerting
}

teardown() {
    # Clean up test directories
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

@test "Performance: check_wms_service_availability overhead" {
    skip_if_database_not_available

    local times=()

    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_wms_service_availability)
        times+=("${duration}")
    done

    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)

    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_SERVICE_AVAILABILITY}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_SERVICE_AVAILABILITY}ms)"

    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_http_health overhead" {
    skip_if_database_not_available

    local times=()

    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_http_health)
        times+=("${duration}")
    done

    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)

    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_HEALTH}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_HEALTH}ms)"

    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_response_time overhead" {
    skip_if_database_not_available

    local times=()

    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_response_time)
        times+=("${duration}")
    done

    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)

    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_RESPONSE_TIME}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_RESPONSE_TIME}ms)"

    # Log results
    echo "# Average time: ${avg_time}ms" >&3
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

@test "Performance: check_tile_generation_performance overhead" {
    skip_if_database_not_available

    local times=()

    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_tile_generation_performance)
        times+=("${duration}")
    done

    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)

    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_TILE_PERFORMANCE}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_TILE_PERFORMANCE}ms)"

    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_cache_hit_rate overhead" {
    skip_if_database_not_available

    local times=()

    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_cache_hit_rate)
        times+=("${duration}")
    done

    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)

    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_CACHE}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_CACHE}ms)"

    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: complete WMS monitoring cycle overhead" {
    skip_if_database_not_available

    local times=()

    # Measure execution time of complete monitoring cycle
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local start_time
        start_time=$(date +%s%N)

        check_wms_service_availability
        check_http_health
        check_response_time
        check_error_rate

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
    total_threshold=$((THRESHOLD_CHECK_SERVICE_AVAILABILITY + THRESHOLD_CHECK_HEALTH + THRESHOLD_CHECK_RESPONSE_TIME + THRESHOLD_CHECK_ERROR_RATE))

    # Verify performance is within threshold (allow some overhead for coordination)
    local adjusted_threshold
    adjusted_threshold=$((total_threshold + 200))
    assert [ "${avg_time}" -lt "${adjusted_threshold}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${adjusted_threshold}ms)"

    # Log results
    echo "# Average time: ${avg_time}ms" >&3
    echo "# Threshold: ${adjusted_threshold}ms" >&3
}

@test "Performance: concurrent WMS checks overhead" {
    skip_if_database_not_available

    local start_time
    start_time=$(date +%s%N)

    # Run WMS checks concurrently
    check_wms_service_availability &
    local pid1=$!
    check_http_health &
    local pid2=$!
    check_response_time &
    local pid3=$!
    check_error_rate &
    local pid4=$!

    # Wait for all to complete
    wait "${pid1}" "${pid2}" "${pid3}" "${pid4}"

    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))

    # Calculate sequential threshold
    local sequential_threshold
    sequential_threshold=$((THRESHOLD_CHECK_SERVICE_AVAILABILITY + THRESHOLD_CHECK_HEALTH + THRESHOLD_CHECK_RESPONSE_TIME + THRESHOLD_CHECK_ERROR_RATE))

    # Log results
    echo "# Concurrent execution time: ${duration_ms}ms" >&3
    echo "# Sequential threshold: ${sequential_threshold}ms" >&3

    # Note: We don't assert here as concurrent execution may be slower due to DB contention
    # This test is mainly for measurement purposes
}

