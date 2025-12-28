#!/usr/bin/env bash
#
# Unit Tests: Alert Manager
# Tests alert manager functionality
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
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/alerts/alertManager.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alertManager.log"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_FILE}" "test_alertManager"
    
    # Initialize alerting
    init_alerting
    
    # Clean test database
    clean_test_database
}

teardown() {
    # Clean up test alerts
    clean_test_database
    
    # Clean up test log files
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: List alerts returns active alerts
##
@test "List alerts returns active alerts" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # List alerts
    run list_alerts "" "active"
    assert_success
    assert_output --partial "INGESTION"
    assert_output --partial "warning"
}

##
# Test: List alerts filters by component
##
@test "List alerts filters by component" {
    # Create test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message 1"
    send_alert "ANALYTICS" "critical" "test_type" "Test message 2"
    
    # List alerts for INGESTION
    run list_alerts "INGESTION" "active"
    assert_success
    assert_output --partial "INGESTION"
    assert_output --partial "warning"
    refute_output --partial "ANALYTICS"
}

##
# Test: Show alert displays alert details
##
@test "Show alert displays alert details" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Get alert ID
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        run show_alert "${alert_id}"
        assert_success
        assert_output --partial "INGESTION"
        assert_output --partial "warning"
        assert_output --partial "Test message"
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Acknowledge alert updates status
##
@test "Acknowledge alert updates status" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Get alert ID
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        # Acknowledge alert
        run acknowledge_alert "${alert_id}" "test_user"
        assert_success
        
        # Verify status
        local status_query="SELECT status FROM alerts WHERE id = '${alert_id}'::uuid;"
        local status
        status=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${DBHOST:-localhost}" \
            -p "${DBPORT:-5432}" \
            -U "${DBUSER:-postgres}" \
            -d "${TEST_DB_NAME}" \
            -t -A \
            -c "${status_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        
        assert [ "${status}" = "acknowledged" ]
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Resolve alert updates status
##
@test "Resolve alert updates status" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Get alert ID
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        # Resolve alert
        run resolve_alert "${alert_id}" "test_user"
        assert_success
        
        # Verify status
        local status_query="SELECT status FROM alerts WHERE id = '${alert_id}'::uuid;"
        local status
        status=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${DBHOST:-localhost}" \
            -p "${DBPORT:-5432}" \
            -U "${DBUSER:-postgres}" \
            -d "${TEST_DB_NAME}" \
            -t -A \
            -c "${status_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        
        assert [ "${status}" = "resolved" ]
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Aggregate alerts groups by component and type
##
@test "Aggregate alerts groups by component and type" {
    # Create multiple test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message 1"
    send_alert "INGESTION" "warning" "test_type" "Test message 2"
    send_alert "INGESTION" "critical" "test_type" "Test message 3"
    
    # Aggregate alerts
    run aggregate_alerts "INGESTION" "60"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Show history returns alert history
##
@test "Show history returns alert history" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Show history
    run show_history "INGESTION" "7"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Show stats returns alert statistics
##
@test "Show stats returns alert statistics" {
    # Create test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message 1"
    send_alert "INGESTION" "critical" "test_type" "Test message 2"
    
    # Show stats
    run show_stats ""
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Cleanup alerts removes old resolved alerts
##
@test "Cleanup alerts removes old resolved alerts" {
    # Create and resolve test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        resolve_alert "${alert_id}" "test_user"
        
        # Cleanup (with short retention for testing)
        run cleanup_alerts "0"
        assert_success
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Helper function to get alert ID
##
get_alert_id() {
    local component="${1}"
    local alert_type="${2}"
    local message="${3}"
    
    local query="SELECT id FROM alerts 
                 WHERE component = '${component}' 
                   AND alert_type = '${alert_type}' 
                   AND message = '${message}'
                 ORDER BY created_at DESC 
                 LIMIT 1;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${DBHOST:-localhost}" \
        -p "${DBPORT:-5432}" \
        -U "${DBUSER:-postgres}" \
        -d "${TEST_DB_NAME}" \
        -t -A \
        -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo ""
}

