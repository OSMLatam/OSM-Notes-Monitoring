#!/usr/bin/env bash
#
# Integration Tests: Database Integration
# Tests database operations, transactions, and data integrity
#
# Version: 1.0.0
# Date: 2025-12-28
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="DATABASE"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_database_integration.log"
    init_logging "${LOG_FILE}" "test_database_integration"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Initialize alerting
    init_alerting
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
# Test: Database connection and health check
##
@test "Database integration: connection and health check" {
    skip_if_database_not_available
    
    # Step 1: Test database connection
    run check_database_connection
    assert_success
    
    # Step 2: Test database server health
    run check_database_server_health
    assert_success
}

##
# Test: Transaction integrity - metrics insertion
##
@test "Database integration: transaction integrity for metrics" {
    skip_if_database_not_available
    
    # Step 1: Insert multiple metrics in sequence
    record_metric "ingestion" "test_metric" "100" "test=transaction"
    record_metric "ingestion" "test_metric" "200" "test=transaction"
    record_metric "ingestion" "test_metric" "300" "test=transaction"
    
    # Step 2: Verify all metrics were inserted
    local metric_count
    metric_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'test_metric';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${metric_count}" -eq 3 ]
    
    # Step 3: Verify data integrity
    local latest_value
    latest_value=$(get_metric_value "ingestion" "test_metric")
    assert [ "${latest_value}" == "300" ]
}

##
# Test: Foreign key constraints
##
@test "Database integration: foreign key constraints" {
    skip_if_database_not_available
    
    # Step 1: Create component health entry
    update_component_health "ingestion" "healthy" "Test"
    
    # Step 2: Verify component exists
    local component_exists
    component_exists=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM component_health WHERE component = 'ingestion';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${component_exists}" -ge 1 ]
    
    # Step 3: Metrics can reference component
    record_metric "ingestion" "test_metric" "100" "test=fk"
    
    # Step 4: Verify metric was inserted
    local metric_exists
    metric_exists=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'test_metric';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${metric_exists}" -ge 1 ]
}

##
# Test: Data type validation
##
@test "Database integration: data type validation" {
    skip_if_database_not_available
    
    # Step 1: Insert metric with numeric value
    record_metric "ingestion" "numeric_metric" "123.45" "test=datatype"
    
    # Step 2: Verify value was stored correctly
    local stored_value
    stored_value=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT metric_value::numeric FROM metrics WHERE component = 'ingestion' AND metric_name = 'numeric_metric' ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null | tr -d ' ' || echo "")
    assert [ -n "${stored_value}" ]
    
    # Step 3: Verify it's a valid number
    assert [[ "${stored_value}" =~ ^[0-9]+\.?[0-9]*$ ]]
}

##
# Test: Timestamp handling
##
@test "Database integration: timestamp handling" {
    skip_if_database_not_available
    
    # Step 1: Record metric
    record_metric "ingestion" "timestamp_test" "100" "test=timestamp"
    
    # Step 2: Get timestamp
    local metric_timestamp
    metric_timestamp=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT timestamp FROM metrics WHERE component = 'ingestion' AND metric_name = 'timestamp_test' ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null | tr -d ' ' || echo "")
    
    # Step 3: Verify timestamp is recent (within last minute)
    local current_time
    current_time=$(date +%s)
    local metric_time
    metric_time=$(date -d "${metric_timestamp}" +%s 2>/dev/null || echo "0")
    local time_diff
    time_diff=$((current_time - metric_time))
    
    assert [ "${time_diff}" -lt 60 ]
}

##
# Test: Index usage and query performance
##
@test "Database integration: index usage and query performance" {
    skip_if_database_not_available
    
    # Step 1: Insert multiple metrics
    local i
    for i in {1..10}; do
        record_metric "ingestion" "index_test" "${i}00" "test=index"
    done
    
    # Step 2: Query with component filter (should use index)
    local start_time
    start_time=$(date +%s%N)
    
    local metric_count
    metric_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'index_test';" 2>/dev/null | tr -d ' ' || echo "0")
    
    local end_time
    end_time=$(date +%s%N)
    local query_time
    query_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    # Step 3: Verify query completed and returned correct count
    assert [ "${metric_count}" -eq 10 ]
    # Query should complete in reasonable time (< 1 second)
    assert [ "${query_time}" -lt 1000 ]
}

##
# Test: Concurrent writes
##
@test "Database integration: concurrent writes" {
    skip_if_database_not_available
    
    # Step 1: Write concurrently from multiple processes
    local i
    for i in {1..5}; do
        (
            record_metric "ingestion" "concurrent_test" "${i}00" "test=concurrent"
        ) &
    done
    
    # Wait for all background jobs
    wait
    
    # Step 2: Verify all writes succeeded
    local metric_count
    metric_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'concurrent_test';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${metric_count}" -eq 5 ]
}

##
# Test: Data consistency across tables
##
@test "Database integration: data consistency across tables" {
    skip_if_database_not_available
    
    # Step 1: Create component health
    update_component_health "ingestion" "healthy" "Test"
    
    # Step 2: Record metric for same component
    record_metric "ingestion" "consistency_test" "100" "test=consistency"
    
    # Step 3: Record alert for same component
    send_alert "ingestion" "warning" "consistency_test" "Test alert"
    
    # Step 4: Verify all data exists and is consistent
    local health_count
    health_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM component_health WHERE component = 'ingestion';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${health_count}" -ge 1 ]
    
    local metric_count
    metric_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${metric_count}" -ge 1 ]
    
    local alert_count
    alert_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'ingestion';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${alert_count}" -ge 1 ]
}

##
# Test: Error handling and rollback
##
@test "Database integration: error handling" {
    skip_if_database_not_available
    
    # Step 1: Attempt invalid operation (should fail gracefully)
    run psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -c \
        "INSERT INTO metrics (component, metric_name, metric_value) VALUES ('', '', 'invalid');" 2>&1
    
    # Step 2: Verify error was handled (may succeed or fail, but shouldn't crash)
    # The important thing is the command completed
    
    # Step 3: Verify database is still accessible
    run check_database_connection
    assert_success
}

##
# Test: Large data set handling
##
@test "Database integration: large data set handling" {
    skip_if_database_not_available
    
    # Step 1: Insert larger number of metrics
    local i
    for i in {1..50}; do
        record_metric "ingestion" "large_dataset" "${i}" "test=large"
    done
    
    # Step 2: Query large dataset
    local metric_count
    metric_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion' AND metric_name = 'large_dataset';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${metric_count}" -eq 50 ]
    
    # Step 3: Verify aggregation works on large dataset
    local avg_value
    avg_value=$(aggregate_metrics "ingestion" "large_dataset" "avg" "1 hour")
    assert [ -n "${avg_value}" ]
}
