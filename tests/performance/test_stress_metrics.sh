#!/usr/bin/env bash
#
# Performance Tests: Stress Testing - Metrics
# Tests system behavior under extreme load conditions
#
# Version: 1.0.0
# Date: 2025-12-28
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="STRESS_METRICS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_WARNING}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_stress_metrics.log"
    init_logging "${LOG_FILE}" "test_stress_metrics"
    
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
# Test: Stress test - rapid metric inserts (burst)
##
@test "Stress test: rapid metric inserts (burst)" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_burst';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Rapid burst of 200 metrics
    local i
    for i in {1..200}; do
        record_metric "ingestion" "stress_burst" "${i}" "test=stress" &
    done
    
    # Wait for all background jobs
    wait
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify system handled the burst
    sleep 2  # Allow time for database writes
    
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_burst';" | tr -d ' ' || echo "0")
    
    # Should handle at least most of the inserts
    assert [ "${metric_count}" -ge 150 ]
    # Should complete in reasonable time
    assert [ "${duration_ms}" -lt 30000 ]
}

##
# Test: Stress test - sustained high load
##
@test "Stress test: sustained high load" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_sustained';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Sustained load: 50 metrics per second for 5 seconds
    local i
    for i in {1..250}; do
        record_metric "ingestion" "stress_sustained" "${i}" "test=stress"
        if [[ $((i % 50)) -eq 0 ]]; then
            sleep 1
        fi
    done
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify system maintained performance
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_sustained';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 250 ]
    # Should maintain reasonable performance (< 25 seconds for 250 inserts with sleeps)
    assert [ "${duration_ms}" -lt 25000 ]
}

##
# Test: Stress test - mixed operations (read/write)
##
@test "Stress test: mixed operations (read/write)" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_mixed';" > /dev/null 2>&1 || true
    
    # Insert initial metrics
    local i
    for i in {1..100}; do
        record_metric "ingestion" "stress_mixed" "${i}" "test=stress"
    done
    
    local start_time
    start_time=$(date +%s%N)
    
    # Mix of reads and writes
    local j
    for j in {1..50}; do
        # Write
        record_metric "ingestion" "stress_mixed" "$((100 + j))" "test=stress"
        # Read
        get_latest_metric_value "ingestion" "stress_mixed" > /dev/null
    done
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify system handled mixed load
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_mixed';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -ge 150 ]
    assert [ "${duration_ms}" -lt 10000 ]
}

##
# Test: Stress test - concurrent alerts and metrics
##
@test "Stress test: concurrent alerts and metrics" {
    skip_if_database_not_available
    
    # Disable alert deduplication for this test to ensure all alerts are recorded
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Clean up any existing test data
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_concurrent';" > /dev/null 2>&1 || true
    run_sql_query "DELETE FROM alerts WHERE component = 'ingestion' AND alert_type = 'stress_alert';" > /dev/null 2>&1 || true
    
    local start_time
    start_time=$(date +%s%N)
    
    # Concurrent metrics and alerts
    (
        local i
        for i in {1..50}; do
            record_metric "ingestion" "stress_concurrent" "${i}" "test=stress"
        done
    ) &
    (
        local i
        for i in {1..20}; do
            send_alert "ingestion" "warning" "stress_alert" "Stress test alert ${i}"
        done
    ) &
    
    wait
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    # Verify both operations completed
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_concurrent';" | tr -d ' ' || echo "0")
    
    local alert_count
    alert_count=$(run_sql_query "SELECT COUNT(*) FROM alerts WHERE component = 'ingestion' AND alert_type = 'stress_alert';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 50 ]
    assert [ "${alert_count}" -eq 20 ]  # All alerts should be recorded when deduplication is disabled
    assert [ "${duration_ms}" -lt 15000 ]
}

##
# Test: Stress test - database connection resilience
##
@test "Stress test: database connection resilience" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_resilience';" > /dev/null 2>&1 || true
    
    # Test that system recovers from connection issues
    local connection_ok=true
    
    # Multiple rapid connection checks
    local i
    for i in {1..20}; do
        if ! check_database_connection; then
            connection_ok=false
            break
        fi
    done
    
    assert [ "${connection_ok}" == "true" ]
    
    # Verify we can still write after many checks
    record_metric "ingestion" "stress_resilience" "100" "test=stress"
    
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_resilience';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 1 ]
}

##
# Test: Stress test - memory usage under load
##
@test "Stress test: memory usage under load" {
    skip_if_database_not_available
    
    # Clean up any existing test metrics
    run_sql_query "DELETE FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_memory';" > /dev/null 2>&1 || true
    
    # Get initial memory usage (if available)
    local initial_memory
    initial_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    
    # Insert many metrics
    local i
    for i in {1..500}; do
        record_metric "ingestion" "stress_memory" "${i}" "test=stress"
    done
    
    # Get memory usage after load
    local final_memory
    final_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    
    # Verify metrics were inserted
    local metric_count
    metric_count=$(run_sql_query "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'stress_memory';" | tr -d ' ' || echo "0")
    
    assert [ "${metric_count}" -eq 500 ]
    # Memory increase should be reasonable (less than 50MB)
    if [[ "${initial_memory}" != "0" ]] && [[ "${final_memory}" != "0" ]]; then
        local memory_increase
        memory_increase=$((final_memory - initial_memory))
        assert [ "${memory_increase}" -lt 51200 ]  # 50MB in KB
    fi
}
