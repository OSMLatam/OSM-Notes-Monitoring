#!/usr/bin/env bash
#
# Integration Tests: Alert Delivery for Ingestion
# Tests that alerts are properly stored and delivered when ingestion issues are detected
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
TEST_COMPONENT="INGESTION"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"

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
    
    # Disable alert deduplication for testing
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alert_delivery.log"
    init_logging "${LOG_FILE}" "test_alert_delivery"
    
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
# Helper function to count alerts in database
##
count_alerts() {
    local component="${1}"
    local alert_level="${2:-}"
    local alert_type="${3:-}"
    
    local query="SELECT COUNT(*) FROM alerts WHERE component = '${component}'"
    
    if [[ -n "${alert_level}" ]]; then
        query="${query} AND alert_level = '${alert_level}'"
    fi
    
    if [[ -n "${alert_type}" ]]; then
        query="${query} AND alert_type = '${alert_type}'"
    fi
    
    run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]' || echo "0"
}

##
# Helper function to get latest alert message
##
get_latest_alert_message() {
    local component="${1}"
    
    local query="SELECT message FROM alerts 
                 WHERE component = '${component}' 
                 ORDER BY created_at DESC 
                 LIMIT 1;"
    
    run_sql_query "${query}" 2>/dev/null | head -1 || echo ""
}

@test "Alert is stored in database when send_alert is called" {
    skip_if_database_not_available
    
    # Send a test alert
    send_alert "WARNING" "${TEST_COMPONENT}" "test_alert" "Test alert message"
    
    # Wait a moment for database write
    sleep 1
    
    # Verify alert was stored
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "1" "${alert_count}"
}

@test "Alert has correct component name" {
    skip_if_database_not_available
    
    send_alert "WARNING" "${TEST_COMPONENT}" "test_alert" "Test message"
    sleep 1
    
    local query="SELECT component FROM alerts WHERE component = '${TEST_COMPONENT}' LIMIT 1;"
    local result
    result=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    assert_equal "${TEST_COMPONENT}" "${result}"
}

@test "Alert has correct alert level" {
    skip_if_database_not_available
    
    send_alert "CRITICAL" "${TEST_COMPONENT}" "test_alert" "Critical test message"
    sleep 1
    
    local query="SELECT alert_level FROM alerts WHERE component = '${TEST_COMPONENT}' LIMIT 1;"
    local result
    result=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    assert_equal "critical" "${result}"
}

@test "Alert has correct message" {
    skip_if_database_not_available
    
    local test_message="Test alert message for ingestion monitoring"
    send_alert "WARNING" "${TEST_COMPONENT}" "test_alert" "${test_message}"
    sleep 1
    
    local result
    result=$(get_latest_alert_message "${TEST_COMPONENT}")
    
    assert_equal "${test_message}" "${result}"
}

@test "Multiple alerts can be stored" {
    skip_if_database_not_available
    
    send_alert "WARNING" "${TEST_COMPONENT}" "alert1" "First alert"
    sleep 1
    send_alert "WARNING" "${TEST_COMPONENT}" "alert2" "Second alert"
    sleep 1
    send_alert "INFO" "${TEST_COMPONENT}" "alert3" "Third alert"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "3" "${alert_count}"
}

@test "Alerts are filtered by alert level" {
    skip_if_database_not_available
    
    send_alert "CRITICAL" "${TEST_COMPONENT}" "critical_alert" "Critical alert"
    sleep 1
    send_alert "WARNING" "${TEST_COMPONENT}" "warning_alert" "Warning alert"
    sleep 1
    send_alert "INFO" "${TEST_COMPONENT}" "info_alert" "Info alert"
    sleep 1
    
    local critical_count
    critical_count=$(count_alerts "${TEST_COMPONENT}" "critical")
    local warning_count
    warning_count=$(count_alerts "${TEST_COMPONENT}" "warning")
    local info_count
    info_count=$(count_alerts "${TEST_COMPONENT}" "info")
    
    assert_equal "1" "${critical_count}"
    assert_equal "1" "${warning_count}"
    assert_equal "1" "${info_count}"
}

@test "Alert deduplication works when enabled" {
    skip_if_database_not_available
    
    # Enable deduplication
    export ALERT_DEDUPLICATION_ENABLED="true"
    
    # Send same alert twice
    send_alert "WARNING" "${TEST_COMPONENT}" "duplicate_test" "Duplicate alert message"
    sleep 1
    send_alert "WARNING" "${TEST_COMPONENT}" "duplicate_test" "Duplicate alert message"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    # Should only have one alert due to deduplication
    assert_equal "1" "${alert_count}"
}

@test "Alert metadata is stored correctly" {
    skip_if_database_not_available
    
    local metadata='{"source":"test","metric":"error_rate","value":10}'
    send_alert "WARNING" "${TEST_COMPONENT}" "metadata_test" "Test with metadata" "${metadata}"
    sleep 1
    
    local query="SELECT metadata FROM alerts WHERE component = '${TEST_COMPONENT}' LIMIT 1;"
    local result
    result=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    # Check that metadata contains expected values
    echo "${result}" | grep -q "source" || return 1
    echo "${result}" | grep -q "test" || return 1
}

@test "Alert status is active by default" {
    skip_if_database_not_available
    
    send_alert "WARNING" "${TEST_COMPONENT}" "status_test" "Test status"
    sleep 1
    
    local query="SELECT status FROM alerts WHERE component = '${TEST_COMPONENT}' LIMIT 1;"
    local result
    result=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    assert_equal "active" "${result}"
}

@test "Alert timestamp is set correctly" {
    skip_if_database_not_available
    
    local before_time
    before_time=$(date +%s)
    
    send_alert "WARNING" "${TEST_COMPONENT}" "timestamp_test" "Test timestamp"
    sleep 1
    
    local after_time
    after_time=$(date +%s)
    
    local query="SELECT EXTRACT(EPOCH FROM created_at)::bigint FROM alerts WHERE component = '${TEST_COMPONENT}' LIMIT 1;"
    local alert_time
    alert_time=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    # Alert time should be between before and after
    assert [ "${alert_time}" -ge "${before_time}" ]
    assert [ "${alert_time}" -le "${after_time}" ]
}

@test "Invalid alert level is rejected" {
    skip_if_database_not_available
    
    # Try to send alert with invalid level
    if store_alert "${TEST_COMPONENT}" "invalid_level" "test_type" "Test message"; then
        fail "Should have rejected invalid alert level"
    fi
    
    # Verify no alert was stored
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "0" "${alert_count}"
}

@test "Alert can be queried by alert type" {
    skip_if_database_not_available
    
    send_alert "WARNING" "${TEST_COMPONENT}" "error_rate" "High error rate"
    sleep 1
    send_alert "WARNING" "${TEST_COMPONENT}" "data_quality" "Low data quality"
    sleep 1
    
    local error_rate_count
    error_rate_count=$(count_alerts "${TEST_COMPONENT}" "" "error_rate")
    local data_quality_count
    data_quality_count=$(count_alerts "${TEST_COMPONENT}" "" "data_quality")
    
    assert_equal "1" "${error_rate_count}"
    assert_equal "1" "${data_quality_count}"
}

@test "Email alerts are skipped when disabled" {
    skip_if_database_not_available
    skip_if_command_not_found mutt
    
    export SEND_ALERT_EMAIL="false"
    
    # This should not fail even if mutt is not configured
    send_alert "WARNING" "${TEST_COMPONENT}" "email_test" "Test email alert"
    sleep 1
    
    # Alert should still be stored in database
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "1" "${alert_count}"
}

@test "Multiple alert types for same component are stored separately" {
    skip_if_database_not_available
    
    send_alert "WARNING" "${TEST_COMPONENT}" "script_execution" "Script execution failed"
    sleep 1
    send_alert "WARNING" "${TEST_COMPONENT}" "data_quality" "Data quality below threshold"
    sleep 1
    send_alert "CRITICAL" "${TEST_COMPONENT}" "health_status" "Component health check failed"
    sleep 1
    
    local total_count
    total_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "3" "${total_count}"
    
    # Verify each type is stored
    local script_count
    script_count=$(count_alerts "${TEST_COMPONENT}" "" "script_execution")
    local quality_count
    quality_count=$(count_alerts "${TEST_COMPONENT}" "" "data_quality")
    local health_count
    health_count=$(count_alerts "${TEST_COMPONENT}" "" "health_status")
    
    assert_equal "1" "${script_count}"
    assert_equal "1" "${quality_count}"
    assert_equal "1" "${health_count}"
}

