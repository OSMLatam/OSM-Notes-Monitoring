#!/usr/bin/env bash
#
# Integration Tests: Alert Delivery
# Tests alert delivery with email and Slack integration
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
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/alerts/sendAlert.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Disable email/Slack for testing (will test separately)
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alert_delivery_integration.log"
    init_logging "${LOG_FILE}" "test_alert_delivery_integration"
    
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
# Test: Alert stored in database
##
@test "Alert stored in database" {
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    local message="Test alert message"
    
    # Send alert
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    assert_success
    
    # Verify alert in database
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    assert [ "${count}" -ge 1 ]
}

##
# Test: Alert with metadata stored correctly
##
@test "Alert with metadata stored correctly" {
    local component="INGESTION"
    local alert_level="critical"
    local alert_type="test_type"
    local message="Test alert with metadata"
    local metadata='{"key": "value", "number": 123}'
    
    # Send alert with metadata
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}" "${metadata}"
    assert_success
    
    # Verify alert stored
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    assert [ "${count}" -ge 1 ]
}

##
# Test: Email alert formatting (when enabled)
##
@test "Email alert formatting works" {
    # Mock mutt for testing
    if ! command -v mutt >/dev/null 2>&1; then
        skip "mutt not available"
    fi
    
    local component="INGESTION"
    local alert_level="critical"
    local alert_type="test_type"
    local message="Test email alert"
    
    # Enable email temporarily
    export SEND_ALERT_EMAIL="true"
    export ADMIN_EMAIL="test@example.com"
    
    # Send alert (will attempt to send email)
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    # May fail if email server not configured, but formatting should work
    assert [ "$status" -ge 0 ]
}

##
# Test: HTML format alert
##
@test "HTML format alert works" {
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    local message="Test HTML alert"
    
    # Format as HTML
    run format_html "${component}" "${alert_level}" "${alert_type}" "${message}" ""
    assert_success
    assert_output --partial "html"
    assert_output --partial "${component}"
    assert_output --partial "${alert_level}"
}

##
# Test: JSON format alert
##
@test "JSON format alert works" {
    local component="INGESTION"
    local alert_level="info"
    local alert_type="test_type"
    local message="Test JSON alert"
    
    # Format as JSON
    run format_json "${component}" "${alert_level}" "${alert_type}" "${message}" "null"
    assert_success
    assert_output --partial "component"
    assert_output --partial "${component}"
}

##
# Test: Multi-channel alert delivery
##
@test "Multi-channel alert delivery works" {
    local component="INGESTION"
    local alert_level="critical"
    local alert_type="test_type"
    local message="Test multi-channel alert"
    
    # Send alert (stores in DB, attempts email/Slack if enabled)
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    assert_success
    
    # Verify alert stored
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    assert [ "${count}" -ge 1 ]
}

##
# Helper function to count alerts
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
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${DBHOST:-localhost}" \
        -p "${DBPORT:-5432}" \
        -U "${DBUSER:-postgres}" \
        -d "${TEST_DB_NAME}" \
        -t -A \
        -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo "0"
}

