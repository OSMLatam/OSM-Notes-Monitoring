#!/usr/bin/env bash
#
# Performance Tests: Resource Usage Analysis
# Tests and analyzes resource usage (CPU, memory, disk, database)
#
# Version: 1.0.0
# Date: 2025-12-28
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="RESOURCE_USAGE"
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
    export LOG_FILE="${TEST_LOG_DIR}/test_resource_usage.log"
    init_logging "${LOG_FILE}" "test_resource_usage"
    
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
# Test: CPU usage during metric operations
##
@test "Resource usage: CPU usage during metric operations" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'cpu_test';" > /dev/null 2>&1 || true
    
    # Get initial CPU time (captured for monitoring, not explicitly verified)
    # shellcheck disable=SC2034
    local initial_cpu
    # shellcheck disable=SC2034
    initial_cpu=$(ps -o cputime= -p $$ 2>/dev/null | tr -d ' ' || echo "00:00:00")
    
    # Perform operations
    local i
    for i in {1..100}; do
        record_metric "ingestion" "cpu_test" "${i}" "test=resource"
        get_latest_metric_value "ingestion" "cpu_test" > /dev/null
    done
    
    # Get final CPU time (captured for monitoring, not explicitly verified)
    # shellcheck disable=SC2034
    local final_cpu
    # shellcheck disable=SC2034
    final_cpu=$(ps -o cputime= -p $$ 2>/dev/null | tr -d ' ' || echo "00:00:00")
    
    # Verify operations completed
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'cpu_test';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 100 ]
    # CPU usage should be reasonable (operations completed)
}

##
# Test: Memory usage during batch operations
##
@test "Resource usage: memory usage during batch operations" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'memory_test';" > /dev/null 2>&1 || true
    
    # Get initial memory
    local initial_memory
    initial_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    
    # Batch operations
    local i
    for i in {1..200}; do
        record_metric "ingestion" "memory_test" "${i}" "test=resource"
    done
    
    # Get final memory
    local final_memory
    final_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    
    # Verify operations completed
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'memory_test';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 200 ]
    
    # Memory increase should be reasonable
    if [[ "${initial_memory}" != "0" ]] && [[ "${final_memory}" != "0" ]]; then
        local memory_increase
        memory_increase=$((final_memory - initial_memory))
        # Should not increase by more than 100MB
        assert [ "${memory_increase}" -lt 102400 ]
    fi
}

##
# Test: Database connection pool usage
##
@test "Resource usage: database connection pool usage" {
    skip_if_database_not_available
    
    # Test multiple rapid connections
    local connection_count=0
    local i
    for i in {1..20}; do
        if check_database_connection; then
            connection_count=$((connection_count + 1))
        fi
    done
    
    # All connections should succeed
    assert [ "${connection_count}" -eq 20 ]
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'connection_test';" > /dev/null 2>&1 || true
    
    # Verify we can still use database
    record_metric "ingestion" "connection_test" "100" "test=resource"
    
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'connection_test';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 1 ]
}

##
# Test: Disk I/O during metric writes
##
@test "Resource usage: disk I/O during metric writes" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'disk_test';" > /dev/null 2>&1 || true
    
    # Get initial disk stats (if available, captured for monitoring, not explicitly verified)
    # shellcheck disable=SC2034
    local initial_io
    # shellcheck disable=SC2034
    initial_io=$(cat /proc/$$/io 2>/dev/null | grep "write_bytes" | awk '{print $2}' || echo "0")
    
    # Write many metrics
    local i
    for i in {1..300}; do
        record_metric "ingestion" "disk_test" "${i}" "test=resource"
    done
    
    # Get final disk stats (captured for monitoring, not explicitly verified)
    # shellcheck disable=SC2034
    local final_io
    # shellcheck disable=SC2034
    final_io=$(cat /proc/$$/io 2>/dev/null | grep "write_bytes" | awk '{print $2}' || echo "0")
    
    # Verify operations completed
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'disk_test';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 300 ]
    # Disk I/O should be reasonable (operations completed)
}

##
# Test: Database query performance
##
@test "Resource usage: database query performance" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'query_perf';" > /dev/null 2>&1 || true
    
    # Insert test data
    local i
    for i in {1..100}; do
        record_metric "ingestion" "query_perf" "${i}" "test=resource"
    done
    
    # Measure query performance
    local start_time
    start_time=$(date +%s%N)
    
    local result
    result=$(run_sql_query "SELECT AVG(metric_value::numeric) FROM metrics WHERE component = 'ingestion' AND metric_name = 'query_perf';" | tr -d ' ' || echo "")
    
    local end_time
    end_time=$(date +%s%N)
    local query_time_ms
    query_time_ms=$(( (end_time - start_time) / 1000000 ))
    
    assert [ -n "${result}" ]
    # Query should be fast (< 500ms)
    assert [ "${query_time_ms}" -lt 500 ]
}

##
# Test: Concurrent resource usage
##
@test "Resource usage: concurrent resource usage" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE metric_name = 'concurrent_resource';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Concurrent operations
    (
        local i
        for i in {1..50}; do
            record_metric "ingestion" "concurrent_resource" "${i}" "test=resource"
        done
    ) &
    (
        local i
        for i in {1..50}; do
            record_metric "analytics" "concurrent_resource" "${i}" "test=resource"
        done
    ) &
    (
        local i
        for i in {1..50}; do
            record_metric "wms" "concurrent_resource" "${i}" "test=resource"
        done
    ) &
    
    wait
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify all operations completed
    local total_metrics
    total_metrics=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE metric_name = 'concurrent_resource';" | tr -d ' ' || echo "0")
    
    assert [ "${total_metrics}" -eq 150 ]
    # Concurrent operations should complete efficiently
    assert [ "${duration_ms}" -lt 10000 ]
}

##
# Test: Resource cleanup after operations
##
@test "Resource usage: resource cleanup after operations" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'cleanup_test';" > /dev/null 2>&1 || true
    
    # Get initial memory
    local initial_memory
    initial_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    
    # Perform operations
    local i
    for i in {1..100}; do
        record_metric "ingestion" "cleanup_test" "${i}" "test=resource"
        get_latest_metric_value "ingestion" "cleanup_test" > /dev/null
    done
    
    # Force cleanup (garbage collection if applicable)
    sleep 1
    
    # Get memory after cleanup
    local final_memory
    final_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    
    # Verify operations completed
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'cleanup_test';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 100 ]
    # Memory should not grow excessively
    if [[ "${initial_memory}" != "0" ]] && [[ "${final_memory}" != "0" ]]; then
        local memory_increase
        memory_increase=$((final_memory - initial_memory))
        # Should not increase by more than 50MB
        assert [ "${memory_increase}" -lt 51200 ]
    fi
}
