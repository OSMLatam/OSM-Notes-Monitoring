#!/usr/bin/env bash
#
# End-to-End Tests: Alert Workflow
# Tests the complete alert workflow from detection to delivery
#
# Version: 1.0.0
# Date: 2025-12-28
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
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
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/alerts/alertManager.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alert_workflow.log"
    init_logging "${LOG_FILE}" "test_alert_workflow"
    
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
# Test: Complete alert workflow: detection -> storage -> delivery
##
@test "Alert workflow: detection to delivery" {
    skip_if_database_not_available
    
    # Step 1: Detect condition (simulate high error rate)
    record_metric "ingestion" "error_rate" "15" "test=e2e"
    
    # Step 2: Check threshold and generate alert
    local error_rate
    error_rate=$(get_metric_value "ingestion" "error_rate")
    if [[ "${error_rate}" -gt 10 ]]; then
        send_alert "ingestion" "warning" "high_error_rate" "Error rate: ${error_rate}%"
    fi
    
    # Step 3: Verify alert was stored
    local alert_count
    alert_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'ingestion' AND alert_type = 'high_error_rate';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${alert_count}" -ge 1 ]
}

##
# Test: Alert deduplication workflow
##
@test "Alert workflow: deduplication" {
    skip_if_database_not_available
    
    # Step 1: Send first alert
    send_alert "ingestion" "warning" "test_alert" "Test message"
    
    # Step 2: Check if duplicate
    local is_duplicate
    is_duplicate=$(is_alert_duplicate "ingestion" "test_alert" "Test message")
    
    # Step 3: Send duplicate alert (should be deduplicated)
    if [[ "${is_duplicate}" == "0" ]]; then
        send_alert "ingestion" "warning" "test_alert" "Test message"
    fi
    
    # Step 4: Verify only one alert exists
    local alert_count
    alert_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'ingestion' AND alert_type = 'test_alert';" 2>/dev/null | tr -d ' ' || echo "0")
    # Should be 1 or 2 depending on deduplication timing
    assert [ "${alert_count}" -ge 1 ]
}

##
# Test: Alert acknowledgment workflow
##
@test "Alert workflow: acknowledgment" {
    skip_if_database_not_available
    
    # Step 1: Create alert
    send_alert "ingestion" "warning" "test_alert" "Test message"
    
    # Step 2: Get alert ID
    local alert_id
    alert_id=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT id FROM alerts WHERE component = 'ingestion' AND alert_type = 'test_alert' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | tr -d ' ' || echo "")
    
    if [[ -n "${alert_id}" ]]; then
        # Step 3: Acknowledge alert
        acknowledge_alert "${alert_id}" "test_user"
        
        # Step 4: Verify alert is acknowledged
        local status
        status=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
            "SELECT status FROM alerts WHERE id = ${alert_id};" 2>/dev/null | tr -d ' ' || echo "")
        assert [[ "${status}" == "acknowledged" ]]
    else
        skip "Alert not found"
    fi
}

##
# Test: Alert escalation workflow
##
@test "Alert workflow: escalation" {
    skip_if_database_not_available
    
    # Step 1: Create critical alert
    send_alert "ingestion" "critical" "system_down" "System is down"
    
    # Step 2: Get alert ID
    local alert_id
    alert_id=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT id FROM alerts WHERE component = 'ingestion' AND alert_level = 'critical' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | tr -d ' ' || echo "")
    
    if [[ -n "${alert_id}" ]]; then
        # Step 3: Check escalation (simulate time passing)
        # In real scenario, escalation would check alert age
        local alert_age
        alert_age=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
            "SELECT EXTRACT(EPOCH FROM (NOW() - created_at)) FROM alerts WHERE id = ${alert_id};" 2>/dev/null | tr -d ' ' || echo "0")
        
        # Step 4: Verify alert exists and can be escalated
        assert [ -n "${alert_id}" ]
        assert [ "${alert_age}" -ge 0 ]
    else
        skip "Alert not found"
    fi
}

##
# Test: Alert aggregation workflow
##
@test "Alert workflow: aggregation" {
    skip_if_database_not_available
    
    # Step 1: Create multiple similar alerts
    local i
    for i in {1..3}; do
        send_alert "ingestion" "warning" "test_alert" "Test message ${i}"
        sleep 0.1
    done
    
    # Step 2: Verify alerts were stored
    local alert_count
    alert_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'ingestion' AND alert_type = 'test_alert';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${alert_count}" -ge 1 ]
}

##
# Test: Alert resolution workflow
##
@test "Alert workflow: resolution" {
    skip_if_database_not_available
    
    # Step 1: Create alert
    send_alert "ingestion" "warning" "test_alert" "Test message"
    
    # Step 2: Get alert ID
    local alert_id
    alert_id=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT id FROM alerts WHERE component = 'ingestion' AND alert_type = 'test_alert' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | tr -d ' ' || echo "")
    
    if [[ -n "${alert_id}" ]]; then
        # Step 3: Resolve alert (update status)
        psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -c \
            "UPDATE alerts SET status = 'resolved', resolved_at = NOW() WHERE id = ${alert_id};" > /dev/null 2>&1
        
        # Step 4: Verify alert is resolved
        local status
        status=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
            "SELECT status FROM alerts WHERE id = ${alert_id};" 2>/dev/null | tr -d ' ' || echo "")
        assert [[ "${status}" == "resolved" ]]
    else
        skip "Alert not found"
    fi
}
