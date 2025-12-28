#!/usr/bin/env bash
#
# End-to-End Tests: Complete Monitoring Cycle
# Tests the complete monitoring cycle across all components
#
# Version: 1.0.0
# Date: 2025-12-28
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="E2E"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

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

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_complete_monitoring_cycle.log"
    init_logging "${LOG_FILE}" "test_complete_monitoring_cycle"
    
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
# Helper: Count metrics for component
##
count_metrics() {
    local component="${1}"
    psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = '${component}';" 2>/dev/null | tr -d ' ' || echo "0"
}

##
# Helper: Count alerts for component
##
count_alerts() {
    local component="${1}"
    psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = '${component}';" 2>/dev/null | tr -d ' ' || echo "0"
}

##
# Helper: Get latest metric value
##
get_latest_metric_value() {
    local component="${1}"
    local metric_name="${2}"
    psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT metric_value FROM metrics WHERE component = '${component}' AND metric_name = '${metric_name}' ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null | tr -d ' ' || echo ""
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
# Test: Complete monitoring cycle for ingestion component
##
@test "Complete monitoring cycle: ingestion component" {
    skip_if_database_not_available
    
    # Step 1: Record initial metrics
    record_metric "ingestion" "test_metric" "100" "test=e2e"
    record_metric "ingestion" "error_count" "5" "test=e2e"
    
    # Step 2: Update component health
    update_component_health "ingestion" "healthy" "All checks passed"
    
    # Step 3: Generate alert if threshold exceeded
    local error_count
    error_count=$(get_latest_metric_value "ingestion" "error_count")
    if [[ "${error_count}" -gt 10 ]]; then
        send_alert "ingestion" "warning" "high_error_rate" "Error count: ${error_count}"
    fi
    
    # Step 4: Verify metrics were stored
    local total_metrics
    total_metrics=$(count_metrics "ingestion")
    assert [ "${total_metrics}" -ge 2 ]
    
    # Step 5: Verify component health was updated
    local health_status
    health_status=$(get_component_health "ingestion")
    assert [[ "${health_status}" =~ healthy ]]
}

##
# Test: Complete monitoring cycle with alert escalation
##
@test "Complete monitoring cycle: alert escalation" {
    skip_if_database_not_available
    
    # Step 1: Create critical alert
    send_alert "ingestion" "critical" "system_down" "System is down"
    
    # Step 2: Wait for potential escalation
    sleep 1
    
    # Step 3: Verify alert was stored
    local alert_count
    alert_count=$(count_alerts "ingestion")
    assert [ "${alert_count}" -ge 1 ]
    
    # Step 4: Verify alert is active
    local active_alerts
    active_alerts=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'ingestion' AND status = 'active';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${active_alerts}" -ge 1 ]
}

##
# Test: Complete monitoring cycle across multiple components
##
@test "Complete monitoring cycle: multiple components" {
    skip_if_database_not_available
    
    # Step 1: Monitor ingestion
    record_metric "ingestion" "test_metric" "100" "test=e2e"
    update_component_health "ingestion" "healthy" "OK"
    
    # Step 2: Monitor analytics
    record_metric "analytics" "test_metric" "200" "test=e2e"
    update_component_health "analytics" "healthy" "OK"
    
    # Step 3: Monitor WMS
    record_metric "wms" "test_metric" "300" "test=e2e"
    update_component_health "wms" "healthy" "OK"
    
    # Step 4: Verify all components have metrics
    local ingestion_metrics
    ingestion_metrics=$(count_metrics "ingestion")
    assert [ "${ingestion_metrics}" -ge 1 ]
    
    local analytics_metrics
    analytics_metrics=$(count_metrics "analytics")
    assert [ "${analytics_metrics}" -ge 1 ]
    
    local wms_metrics
    wms_metrics=$(count_metrics "wms")
    assert [ "${wms_metrics}" -ge 1 ]
}

##
# Test: Complete monitoring cycle with error recovery
##
@test "Complete monitoring cycle: error recovery" {
    skip_if_database_not_available
    
    # Step 1: Simulate error state
    update_component_health "ingestion" "down" "System error"
    send_alert "ingestion" "critical" "system_error" "System is down"
    
    # Step 2: Simulate recovery
    sleep 1
    update_component_health "ingestion" "healthy" "System recovered"
    
    # Step 3: Verify recovery was recorded
    local health_status
    health_status=$(get_component_health "ingestion")
    assert [[ "${health_status}" =~ healthy ]]
    
    # Step 4: Verify alert history exists
    local alert_count
    alert_count=$(count_alerts "ingestion")
    assert [ "${alert_count}" -ge 1 ]
}

##
# Test: Complete monitoring cycle with metric aggregation
##
@test "Complete monitoring cycle: metric aggregation" {
    skip_if_database_not_available
    
    # Step 1: Record multiple metrics
    local i
    for i in {1..5}; do
        record_metric "ingestion" "test_metric" "${i}00" "test=e2e"
        sleep 0.1
    done
    
    # Step 2: Aggregate metrics
    local avg_value
    avg_value=$(aggregate_metrics "ingestion" "test_metric" "avg" "1 hour")
    
    # Step 3: Verify aggregation worked
    assert [ -n "${avg_value}" ]
    assert [[ "${avg_value}" =~ ^[0-9]+\.?[0-9]*$ ]]
}

##
# Test: Complete monitoring cycle with database failure handling
##
@test "Complete monitoring cycle: database failure handling" {
    skip_if_database_not_available
    
    # Step 1: Record metrics successfully
    record_metric "ingestion" "test_metric" "100" "test=e2e"
    
    # Step 2: Simulate database failure (by using invalid connection)
    local old_dbhost="${DBHOST}"
    export DBHOST="invalid_host"
    
    # Step 3: Attempt to record metric (should handle gracefully)
    run record_metric "ingestion" "test_metric" "200" "test=e2e"
    # Should fail gracefully
    assert_failure
    
    # Step 4: Restore connection
    export DBHOST="${old_dbhost}"
    
    # Step 5: Verify system can recover
    record_metric "ingestion" "test_metric" "300" "test=e2e"
    assert_success
}
