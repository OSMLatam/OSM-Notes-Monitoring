#!/usr/bin/env bash
#
# Integration Tests: Alert Delivery for WMS
# Tests that alerts are properly stored and delivered when WMS issues are detected
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
TEST_COMPONENT="WMS"
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
    export LOG_FILE="${TEST_LOG_DIR}/test_wms_alert_delivery.log"
    init_logging "${LOG_FILE}" "test_wms_alert_delivery"
    
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
    send_alert "${TEST_COMPONENT}" "WARNING" "test_alert" "Test alert message"
    
    # Wait a moment for database write
    sleep 1
    
    # Verify alert was stored
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "1" "${alert_count}"
}

@test "Service unavailable alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "CRITICAL" "service_unavailable" "WMS service is unavailable (HTTP 503, URL: http://localhost:8080)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "service_unavailable")
    
    assert_equal "1" "${alert_count}"
}

@test "Health check failed alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "CRITICAL" "health_check_failed" "WMS health check failed (HTTP 500, status: unhealthy, URL: http://localhost:8080/health)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "health_check_failed")
    
    assert_equal "1" "${alert_count}"
}

@test "Response time exceeded alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "response_time_exceeded" "WMS response time (2500ms) exceeds threshold (2000ms, URL: http://localhost:8080)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "response_time_exceeded")
    
    assert_equal "1" "${alert_count}"
}

@test "Error rate exceeded alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "error_rate_exceeded" "WMS error rate (7%) exceeds threshold (5%, errors: 70, requests: 1000)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "error_rate_exceeded")
    
    assert_equal "1" "${alert_count}"
}

@test "Tile generation slow alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "tile_generation_slow" "WMS tile generation time (6000ms) exceeds threshold (5000ms, URL: http://localhost:8080/tile/10/512/512.png)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "tile_generation_slow")
    
    assert_equal "1" "${alert_count}"
}

@test "Tile generation failed alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "tile_generation_failed" "WMS tile generation failed (HTTP 500, URL: http://localhost:8080/tile/10/512/512.png)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "tile_generation_failed")
    
    assert_equal "1" "${alert_count}"
}

@test "Cache hit rate low alert is stored correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "WARNING" "cache_hit_rate_low" "WMS cache hit rate (75%) is below threshold (80%, hits: 750, misses: 250)"
    sleep 1
    
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}" "" "cache_hit_rate_low")
    
    assert_equal "1" "${alert_count}"
}

@test "Multiple WMS alert types are stored separately" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "CRITICAL" "service_unavailable" "WMS service is unavailable"
    sleep 1
    send_alert "${TEST_COMPONENT}" "WARNING" "response_time_exceeded" "WMS response time exceeded"
    sleep 1
    send_alert "${TEST_COMPONENT}" "WARNING" "error_rate_exceeded" "WMS error rate exceeded"
    sleep 1
    
    local total_count
    total_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "3" "${total_count}"
    
    # Verify each type is stored
    local service_count
    service_count=$(count_alerts "${TEST_COMPONENT}" "" "service_unavailable")
    local response_count
    response_count=$(count_alerts "${TEST_COMPONENT}" "" "response_time_exceeded")
    local error_count
    error_count=$(count_alerts "${TEST_COMPONENT}" "" "error_rate_exceeded")
    
    assert_equal "1" "${service_count}"
    assert_equal "1" "${response_count}"
    assert_equal "1" "${error_count}"
}

@test "Alerts are filtered by alert level correctly" {
    skip_if_database_not_available
    
    send_alert "${TEST_COMPONENT}" "CRITICAL" "service_unavailable" "WMS service is unavailable"
    sleep 1
    send_alert "${TEST_COMPONENT}" "WARNING" "response_time_exceeded" "WMS response time exceeded"
    sleep 1
    
    local critical_count
    critical_count=$(count_alerts "${TEST_COMPONENT}" "critical")
    local warning_count
    warning_count=$(count_alerts "${TEST_COMPONENT}" "warning")
    
    assert_equal "1" "${critical_count}"
    assert_equal "1" "${warning_count}"
}

@test "Alert message contains detailed information" {
    skip_if_database_not_available
    
    local test_message="WMS response time (2500ms) exceeds threshold (2000ms, URL: http://localhost:8080)"
    send_alert "${TEST_COMPONENT}" "WARNING" "response_time_exceeded" "${test_message}"
    sleep 1
    
    local result
    result=$(get_latest_alert_message "${TEST_COMPONENT}")
    
    assert_equal "${test_message}" "${result}"
}

@test "Alert timestamp is set correctly" {
    skip_if_database_not_available
    
    local before_time
    before_time=$(date +%s)
    
    send_alert "${TEST_COMPONENT}" "WARNING" "timestamp_test" "Test timestamp"
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

@test "Email alerts are skipped when disabled" {
    skip_if_database_not_available
    skip_if_command_not_found mutt
    
    export SEND_ALERT_EMAIL="false"
    
    # This should not fail even if mutt is not configured
    send_alert "${TEST_COMPONENT}" "WARNING" "email_test" "Test email alert"
    sleep 1
    
    # Alert should still be stored in database
    local alert_count
    alert_count=$(count_alerts "${TEST_COMPONENT}")
    
    assert_equal "1" "${alert_count}"
}

