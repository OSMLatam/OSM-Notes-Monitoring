#!/usr/bin/env bash
#
# Performance Tests: Load Testing - Metrics
# Tests system performance under load for metric operations
#
# Version: 1.0.0
# Date: 2025-12-28
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="LOAD_METRICS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_load_metrics.log"
    init_logging "${LOG_FILE}" "test_load_metrics"
    
    # Configure database connection (use DB* variables, fallback to PG*, then system user)
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-${PGHOST:-localhost}}"
    export DBPORT="${DBPORT:-${PGPORT:-5432}}"
    export DBUSER="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
    # Don't set PGPASSWORD if not configured - let psql use .pgpass or other auth methods
    if [[ -n "${PGPASSWORD:-}" ]]; then
        export PGPASSWORD
    fi
    
    # Initialize database schema if needed
    skip_if_database_not_available
    initialize_test_database_schema
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Skip test if database not available
##
skip_if_database_not_available() {
    if ! check_database_connection; then
        skip "Database not available"
    fi
}

##
# Test: Load test - insert 100 metrics sequentially
##
@test "Load test: insert 100 metrics sequentially" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'load_test';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Insert 100 metrics
    local i
    for i in {1..100}; do
        record_metric "ingestion" "load_test" "${i}" "test=load"
    done
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify all metrics were inserted
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'load_test';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 100 ]
    # Should complete in reasonable time (< 10 seconds)
    assert [ "${duration_ms}" -lt 10000 ]
}

##
# Test: Load test - insert 1000 metrics sequentially
##
@test "Load test: insert 1000 metrics sequentially" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'load_test_1k';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Insert 1000 metrics
    local i
    for i in {1..1000}; do
        record_metric "ingestion" "load_test_1k" "${i}" "test=load"
    done
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify all metrics were inserted
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'load_test_1k';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 1000 ]
    # Should complete in reasonable time (< 90 seconds for 1000 inserts)
    assert [ "${duration_ms}" -lt 90000 ]
}

##
# Test: Load test - concurrent metric inserts (10 parallel)
##
@test "Load test: concurrent metric inserts (10 parallel)" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'concurrent_load';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Insert metrics concurrently
    local i
    for i in {1..10}; do
        (
            local j
            for j in {1..10}; do
                record_metric "ingestion" "concurrent_load" "$((i * 10 + j))" "test=load"
            done
        ) &
    done
    
    # Wait for all background jobs
    wait
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify all metrics were inserted
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'concurrent_load';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 100 ]
    # Concurrent should be faster than sequential
    assert [ "${duration_ms}" -lt 5000 ]
}

##
# Test: Load test - query performance with large dataset
##
@test "Load test: query performance with large dataset" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'query_load';" > /dev/null 2>&1 || true
    
    # Insert 500 metrics first
    local i
    for i in {1..500}; do
        record_metric "ingestion" "query_load" "${i}" "test=load"
    done
    
    # Test query performance
    local start_time
    start_time=$(date +%s%N)
    
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'query_load';" | tr -d ' ' || echo "0")
    
    local end_time
    end_time=$(date +%s%N)
    local query_time_ms
    query_time_ms=$(( (end_time - start_time) / 1000000 ))
    
    assert [ "${metric_count}" -eq 500 ]
    # Query should be fast even with large dataset (< 1 second)
    assert [ "${query_time_ms}" -lt 1000 ]
}

##
# Test: Load test - aggregation performance
##
@test "Load test: aggregation performance" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'agg_load';" > /dev/null 2>&1 || true
    
    # Insert 200 metrics
    local i
    for i in {1..200}; do
        record_metric "ingestion" "agg_load" "${i}" "test=load"
    done
    
    # Test aggregation performance
    local start_time
    start_time=$(date +%s%N)
    
    # aggregate_metrics returns aggregated data by period (hour, day, week)
    local agg_result
    agg_result=$(aggregate_metrics "ingestion" "agg_load" "hour")
    
    local end_time
    end_time=$(date +%s%N)
    local agg_time_ms
    agg_time_ms=$(( (end_time - start_time) / 1000000 ))
    
    assert [ -n "${agg_result}" ]
    # Aggregation should be fast (< 2 seconds)
    assert [ "${agg_time_ms}" -lt 2000 ]
}

##
# Test: Load test - multiple components simultaneously
##
@test "Load test: multiple components simultaneously" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE metric_name = 'multi_comp';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Insert metrics for multiple components concurrently
    (
        local i
        for i in {1..50}; do
            record_metric "ingestion" "multi_comp" "${i}" "test=load"
        done
    ) &
    (
        local i
        for i in {1..50}; do
            record_metric "analytics" "multi_comp" "${i}" "test=load"
        done
    ) &
    (
        local i
        for i in {1..50}; do
            record_metric "wms" "multi_comp" "${i}" "test=load"
        done
    ) &
    
    wait
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify all components have metrics
    local total_metrics
    total_metrics=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE metric_name = 'multi_comp';" | tr -d ' ' || echo "0")
    
    assert [ "${total_metrics}" -eq 150 ]
    assert [ "${duration_ms}" -lt 10000 ]
}
