#!/usr/bin/env bash
#
# Integration Tests: Alert Deduplication
# Tests alert deduplication functionality
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

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Enable deduplication for testing
    export ALERT_DEDUPLICATION_ENABLED="true"
    export ALERT_DEDUPLICATION_WINDOW_MINUTES="60"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alert_deduplication.log"
    init_logging "${LOG_FILE}" "test_alert_deduplication"
    
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
# Test: Duplicate alerts are deduplicated
##
@test "Duplicate alerts are deduplicated" {
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    local message="Test duplicate message"
    
    # Send first alert
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    assert_success
    
    # Count alerts before second send
    local count_before
    count_before=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    
    # Send duplicate alert (should be deduplicated)
    run send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    assert_success
    
    # Count alerts after second send
    local count_after
    count_after=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    
    # Count should be the same (deduplicated)
    assert [ "${count_after}" -eq "${count_before}" ]
}

##
# Test: Different messages are not deduplicated
##
@test "Different messages are not deduplicated" {
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    
    # Send first alert
    send_alert "${component}" "${alert_level}" "${alert_type}" "Message 1"
    
    # Send second alert with different message
    send_alert "${component}" "${alert_level}" "${alert_type}" "Message 2"
    
    # Count alerts
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    
    # Should have 2 alerts
    assert [ "${count}" -eq 2 ]
}

##
# Test: Deduplication respects time window
##
@test "Deduplication respects time window" {
    local component="INGESTION"
    local alert_level="warning"
    local alert_type="test_type"
    local message="Test message"
    
    # Set short window for testing
    export ALERT_DEDUPLICATION_WINDOW_MINUTES="1"
    
    # Send first alert
    send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    
    # Wait a bit
    sleep 2
    
    # Send second alert (should be deduplicated if within window)
    send_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    
    # Count alerts
    local count
    count=$(count_alerts "${component}" "${alert_level}" "${alert_type}")
    
    # Should have 1 alert (deduplicated)
    assert [ "${count}" -eq 1 ]
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

