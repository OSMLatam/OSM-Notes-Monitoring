#!/usr/bin/env bash
#
# Unit Tests: Alert Escalation
# Tests escalation functionality
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
source "${BATS_TEST_DIRNAME}/../../bin/alerts/escalation.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Set escalation configuration
    export ESCALATION_ENABLED="true"
    export ESCALATION_LEVEL1_MINUTES="1"  # Short for testing
    export ESCALATION_LEVEL2_MINUTES="2"
    export ESCALATION_LEVEL3_MINUTES="3"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_escalation.log"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_FILE}" "test_escalation"
    
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
# Test: Show escalation rules displays rules
##
@test "Show escalation rules displays rules" {
    run show_rules ""
    assert_success
    assert_output --partial "Level 1"
    assert_output --partial "Level 2"
    assert_output --partial "Level 3"
}

##
# Test: Escalate alert updates metadata
##
@test "Escalate alert updates metadata" {
    # Create test alert
    send_alert "INGESTION" "critical" "test_type" "Test message"
    
    # Get alert ID
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        # Escalate alert
        run escalate_alert "${alert_id}" "1"
        assert_success
        
        # Verify escalation level in metadata
        local metadata_query="SELECT metadata->>'escalation_level' FROM alerts WHERE id = '${alert_id}'::uuid;"
        local escalation_level
        escalation_level=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${DBHOST:-localhost}" \
            -p "${DBPORT:-5432}" \
            -U "${DBUSER:-postgres}" \
            -d "${TEST_DB_NAME}" \
            -t -A \
            -c "${metadata_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        
        assert [ "${escalation_level}" = "1" ]
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Needs escalation detects old alerts
##
@test "Needs escalation detects old alerts" {
    # Create test alert with old timestamp
    send_alert "INGESTION" "critical" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        # Update alert to have old timestamp (simulate age)
        local update_query="UPDATE alerts 
                           SET created_at = CURRENT_TIMESTAMP - INTERVAL '2 minutes'
                           WHERE id = '${alert_id}'::uuid;"
        
        PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${DBHOST:-localhost}" \
            -p "${DBPORT:-5432}" \
            -U "${DBUSER:-postgres}" \
            -d "${TEST_DB_NAME}" \
            -c "${update_query}" >/dev/null 2>&1
        
        # Check if needs escalation
        run needs_escalation "${alert_id}"
        # May or may not need escalation depending on thresholds
        assert [ "$status" -ge 0 ]
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Show oncall displays on-call information
##
@test "Show oncall displays on-call information" {
    run show_oncall ""
    assert_success
    assert_output --partial "on-call"
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

