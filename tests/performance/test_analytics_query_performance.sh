#!/usr/bin/env bash
#
# Performance Tests: Analytics Query Performance
# Measures the performance of analytics monitoring queries to ensure they don't degrade the system
#
# Version: 1.0.0
# Date: 2025-12-27
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration (set before loading test_helper to allow override)
export TEST_COMPONENT="ANALYTICS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
export TEST_ANALYTICS_DB_NAME="${TEST_ANALYTICS_DB_NAME:-analytics_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Set LOG_DIR before loading monitorAnalytics.sh
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
source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorAnalytics.sh"

PERFORMANCE_ITERATIONS="${PERFORMANCE_ITERATIONS:-10}"
PERFORMANCE_THRESHOLD_MS="${PERFORMANCE_THRESHOLD_MS:-1000}"

# Performance thresholds (in milliseconds)
THRESHOLD_CHECK_ETL_EXECUTION=500
THRESHOLD_CHECK_DATA_WAREHOUSE_FRESHNESS=300
THRESHOLD_CHECK_ETL_DURATION=400
THRESHOLD_CHECK_DATA_MART_STATUS=300
THRESHOLD_CHECK_QUERY_PERFORMANCE=500
THRESHOLD_CHECK_STORAGE_GROWTH=400
THRESHOLD_DB_QUERY=100
THRESHOLD_COMPLEX_QUERY=500

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_WARN}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    export ANALYTICS_DBNAME="${TEST_ANALYTICS_DB_NAME}"
    
    # Set mock analytics path
    MOCK_ANALYTICS_DIR="${BATS_TEST_DIRNAME}/../tmp/mock_analytics_perf"
    export ANALYTICS_REPO_PATH="${MOCK_ANALYTICS_DIR}"
    export ANALYTICS_LOG_DIR="${MOCK_ANALYTICS_DIR}/logs"
    
    # Create mock analytics directory structure
    mkdir -p "${MOCK_ANALYTICS_DIR}/bin"
    mkdir -p "${MOCK_ANALYTICS_DIR}/logs"
    
    # Create test ETL scripts
    touch "${MOCK_ANALYTICS_DIR}/bin/etl_job1.sh"
    touch "${MOCK_ANALYTICS_DIR}/bin/etl_job2.sh"
    chmod +x "${MOCK_ANALYTICS_DIR}/bin"/*.sh
    
    # Create test ETL log file
    echo "INFO: ETL job started
INFO: ETL job completed
INFO: duration: 1800s" > "${MOCK_ANALYTICS_DIR}/logs/etl_job1.log"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Load monitoring configuration
    export ANALYTICS_ENABLED="true"
    export ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD=2
    export ANALYTICS_ETL_LAST_EXECUTION_AGE_THRESHOLD=3600
    export ANALYTICS_DATA_FRESHNESS_THRESHOLD=3600
    export ANALYTICS_DATA_MART_UPDATE_AGE_THRESHOLD=3600
    export ANALYTICS_SLOW_QUERY_THRESHOLD=1000
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_analytics_query_performance.log"
    init_logging "${LOG_FILE}" "test_analytics_query_performance"
    
    # Initialize alerting
    init_alerting
    
    # Setup test analytics database schema
    setup_test_analytics_db
}

teardown() {
    # Clean up test directories
    rm -rf "${MOCK_ANALYTICS_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Helper function to setup test analytics database
##
setup_test_analytics_db() {
    skip_if_database_not_available
    
    # Create test tables in analytics database if they don't exist
    local create_tables_query="
        CREATE TABLE IF NOT EXISTS test_data_warehouse (
            id SERIAL PRIMARY KEY,
            data_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            data_value TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE TABLE IF NOT EXISTS test_data_mart (
            id SERIAL PRIMARY KEY,
            mart_name VARCHAR(100),
            last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            record_count INTEGER DEFAULT 0
        );
        
        -- Insert some test data
        INSERT INTO test_data_warehouse (data_timestamp, data_value, updated_at)
        SELECT 
            CURRENT_TIMESTAMP - (random() * INTERVAL '7 days'),
            'test_data_' || generate_series,
            CURRENT_TIMESTAMP - (random() * INTERVAL '7 days')
        FROM generate_series(1, 100)
        ON CONFLICT DO NOTHING;
        
        INSERT INTO test_data_mart (mart_name, last_update, record_count)
        VALUES 
            ('test_mart_1', CURRENT_TIMESTAMP - INTERVAL '30 minutes', 100),
            ('test_mart_2', CURRENT_TIMESTAMP - INTERVAL '1 hour', 200),
            ('test_mart_3', CURRENT_TIMESTAMP - INTERVAL '2 hours', 150)
        ON CONFLICT DO NOTHING;
    "
    
    # Execute in analytics database
    execute_sql_query "${create_tables_query}" "${TEST_ANALYTICS_DB_NAME}" 2>/dev/null || true
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

@test "Performance: check_etl_job_execution_status query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_etl_job_execution_status)
        times+=("${duration}")
    done
    
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
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_ETL_EXECUTION}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_ETL_EXECUTION}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
    echo "# Max time: ${max_time}ms" >&3
}

@test "Performance: check_data_warehouse_freshness query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_data_warehouse_freshness)
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_DATA_WAREHOUSE_FRESHNESS}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_DATA_WAREHOUSE_FRESHNESS}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_etl_processing_duration query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_etl_processing_duration)
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_ETL_DURATION}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_ETL_DURATION}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_data_mart_update_status query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_data_mart_update_status)
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_DATA_MART_STATUS}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_DATA_MART_STATUS}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_query_performance query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_query_performance)
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_QUERY_PERFORMANCE}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_QUERY_PERFORMANCE}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: check_storage_growth query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time multiple times
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time check_storage_growth)
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_CHECK_STORAGE_GROWTH}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_CHECK_STORAGE_GROWTH}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: simple database query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of simple query
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time execute_sql_query "SELECT 1;" "${TEST_ANALYTICS_DB_NAME}")
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

@test "Performance: complex data warehouse freshness query" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of complex freshness query
    local freshness_query="
        SELECT 
            MAX(updated_at) as last_update,
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(updated_at)))::bigint as freshness_seconds,
            COUNT(*) FILTER (WHERE updated_at > CURRENT_TIMESTAMP - INTERVAL '1 hour') as recent_updates
        FROM test_data_warehouse;
    "
    
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time execute_sql_query "${freshness_query}" "${TEST_ANALYTICS_DB_NAME}")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_COMPLEX_QUERY}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_COMPLEX_QUERY}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: complex data mart status query" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of complex data mart query
    local mart_query="
        SELECT 
            mart_name,
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - last_update))::bigint as update_age_seconds,
            COUNT(*) FILTER (WHERE last_update > CURRENT_TIMESTAMP - INTERVAL '1 hour') as recent_updates,
            SUM(record_count) as total_records
        FROM test_data_mart
        GROUP BY mart_name, last_update;
    "
    
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time execute_sql_query "${mart_query}" "${TEST_ANALYTICS_DB_NAME}")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_COMPLEX_QUERY}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_COMPLEX_QUERY}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: pg_stat_statements query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of pg_stat_statements query (if available)
    local pg_stat_query="
        SELECT COUNT(*) 
        FROM pg_extension 
        WHERE extname = 'pg_stat_statements';
    "
    
    local pg_stat_available
    pg_stat_available=$(execute_sql_query "${pg_stat_query}" "${TEST_ANALYTICS_DB_NAME}" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    if [[ "${pg_stat_available}" != "1" ]]; then
        skip "pg_stat_statements extension not available"
    fi
    
    # Query slow queries from pg_stat_statements
    local slow_query_query="
        SELECT 
            COUNT(*) as slow_query_count,
            SUM(mean_exec_time) as total_time_ms,
            MAX(mean_exec_time) as max_time_ms,
            AVG(mean_exec_time) as avg_time_ms
        FROM pg_stat_statements
        WHERE mean_exec_time > 1000
          AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
        LIMIT 100;
    "
    
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time execute_sql_query "${slow_query_query}" "${TEST_ANALYTICS_DB_NAME}")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_COMPLEX_QUERY}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_COMPLEX_QUERY}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: database size query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of database size query
    local size_query="
        SELECT 
            pg_database.datname,
            pg_size_pretty(pg_database_size(pg_database.datname)) AS size,
            pg_database_size(pg_database.datname) AS size_bytes
        FROM pg_database
        WHERE datname = current_database();
    "
    
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time execute_sql_query "${size_query}" "${TEST_ANALYTICS_DB_NAME}")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_COMPLEX_QUERY}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_COMPLEX_QUERY}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: table size query overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of table size query
    local table_size_query="
        SELECT 
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
            pg_total_relation_size(schemaname||'.'||tablename) AS size_bytes
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
        LIMIT 20;
    "
    
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local duration
        duration=$(measure_time execute_sql_query "${table_size_query}" "${TEST_ANALYTICS_DB_NAME}")
        times+=("${duration}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Verify performance is within threshold
    assert [ "${avg_time}" -lt "${THRESHOLD_COMPLEX_QUERY}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${THRESHOLD_COMPLEX_QUERY}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
}

@test "Performance: complete analytics monitoring cycle overhead" {
    skip_if_database_not_available
    
    local times=()
    
    # Measure execution time of complete monitoring cycle
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local start_time
        start_time=$(date +%s%N)
        
        check_etl_job_execution_status
        check_data_warehouse_freshness
        check_data_mart_update_status
        check_storage_growth
        
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
    total_threshold=$((THRESHOLD_CHECK_ETL_EXECUTION + THRESHOLD_CHECK_DATA_WAREHOUSE_FRESHNESS + THRESHOLD_CHECK_DATA_MART_STATUS + THRESHOLD_CHECK_STORAGE_GROWTH))
    
    # Verify performance is within threshold (allow some overhead for coordination)
    local adjusted_threshold
    adjusted_threshold=$((total_threshold + 300))
    assert [ "${avg_time}" -lt "${adjusted_threshold}" ] \
        "Average execution time (${avg_time}ms) exceeds threshold (${adjusted_threshold}ms)"
    
    # Log results
    echo "# Average time: ${avg_time}ms" >&3
    echo "# Threshold: ${adjusted_threshold}ms" >&3
}

@test "Performance: concurrent analytics queries overhead" {
    skip_if_database_not_available
    
    local start_time
    start_time=$(date +%s%N)
    
    # Run analytics checks concurrently
    check_etl_job_execution_status &
    local pid1=$!
    check_data_warehouse_freshness &
    local pid2=$!
    check_data_mart_update_status &
    local pid3=$!
    check_storage_growth &
    local pid4=$!
    
    # Wait for all to complete
    wait "${pid1}" "${pid2}" "${pid3}" "${pid4}"
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Calculate sequential threshold
    local sequential_threshold
    sequential_threshold=$((THRESHOLD_CHECK_ETL_EXECUTION + THRESHOLD_CHECK_DATA_WAREHOUSE_FRESHNESS + THRESHOLD_CHECK_DATA_MART_STATUS + THRESHOLD_CHECK_STORAGE_GROWTH))
    
    # Log results
    echo "# Concurrent execution time: ${duration_ms}ms" >&3
    echo "# Sequential threshold: ${sequential_threshold}ms" >&3
    
    # Note: We don't assert here as concurrent execution may be slower due to DB contention
    # This test is mainly for measurement purposes
}

@test "Performance: query performance under load" {
    skip_if_database_not_available
    
    local times=()
    
    # Run multiple queries in quick succession to simulate load
    for _ in $(seq 1 "${PERFORMANCE_ITERATIONS}"); do
        local start_time
        start_time=$(date +%s%N)
        
        # Execute multiple queries
        execute_sql_query "SELECT COUNT(*) FROM test_data_warehouse;" "${TEST_ANALYTICS_DB_NAME}" > /dev/null
        execute_sql_query "SELECT COUNT(*) FROM test_data_mart;" "${TEST_ANALYTICS_DB_NAME}" > /dev/null
        execute_sql_query "SELECT MAX(updated_at) FROM test_data_warehouse;" "${TEST_ANALYTICS_DB_NAME}" > /dev/null
        
        local end_time
        end_time=$(date +%s%N)
        local duration_ms
        duration_ms=$(( (end_time - start_time) / 1000000 ))
        times+=("${duration_ms}")
    done
    
    # Calculate average time
    local avg_time
    avg_time=$(printf '%s\n' "${times[@]}" | calculate_average)
    
    # Under load, queries should still complete within reasonable time
    local load_threshold
    load_threshold=$((THRESHOLD_DB_QUERY * 3 + 100))
    assert [ "${avg_time}" -lt "${load_threshold}" ] \
        "Average execution time under load (${avg_time}ms) exceeds threshold (${load_threshold}ms)"
    
    # Log results
    echo "# Average time under load: ${avg_time}ms" >&3
    echo "# Threshold: ${load_threshold}ms" >&3
}

