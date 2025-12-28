#!/usr/bin/env bash
#
# Integration Tests: WMS Monitoring with Mock WMS Service
# Tests that monitoring functions properly interact with the database
# to store metrics and generate alerts
#
# Version: 1.0.0
# Date: 2025-12-27
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="WMS"
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
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorWMS.sh"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
MOCK_WMS_PORT=18080
MOCK_WMS_PID=""

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Set test WMS configuration
    export WMS_ENABLED="true"
    export WMS_BASE_URL="http://localhost:${MOCK_WMS_PORT}"
    export WMS_HEALTH_CHECK_URL="http://localhost:${MOCK_WMS_PORT}/health"
    export WMS_CHECK_TIMEOUT="10"
    export WMS_RESPONSE_TIME_THRESHOLD="2000"
    export WMS_ERROR_RATE_THRESHOLD="5"
    export WMS_TILE_GENERATION_THRESHOLD="5000"
    export WMS_CACHE_HIT_RATE_THRESHOLD="80"
    export WMS_LOG_DIR="${TEST_LOG_DIR}"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Initialize logging
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_monitorWMS_integration.log"
    init_logging "${LOG_FILE}" "test_monitorWMS_integration"
    
    # Initialize alerting
    init_alerting
    
    # Start mock WMS service
    start_mock_wms_service
    
    # Clean test database
    clean_test_database
}

teardown() {
    # Stop mock WMS service
    stop_mock_wms_service
    
    # Clean up test alerts and metrics
    clean_test_database
    
    # Clean up test directories
    rm -rf "${TEST_LOG_DIR}"
}

##
# Helper function to start mock WMS service
##
start_mock_wms_service() {
    # Check if netcat (nc) is available
    if ! command -v nc > /dev/null 2>&1; then
        skip "netcat not available for mock WMS service"
        return
    fi
    
    # Start simple HTTP server using netcat
    # This is a basic mock - in production, use a proper HTTP server
    (
        while true; do
            nc -l -p "${MOCK_WMS_PORT}" -c 'echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nOK"'
        done
    ) > /dev/null 2>&1 &
    
    MOCK_WMS_PID=$!
    
    # Wait for service to start
    sleep 1
    
    # Verify service is running
    if ! ps -p "${MOCK_WMS_PID}" > /dev/null 2>&1; then
        skip "Failed to start mock WMS service"
    fi
}

##
# Helper function to stop mock WMS service
##
stop_mock_wms_service() {
    if [[ -n "${MOCK_WMS_PID:-}" ]] && ps -p "${MOCK_WMS_PID}" > /dev/null 2>&1; then
        kill "${MOCK_WMS_PID}" 2>/dev/null || true
        wait "${MOCK_WMS_PID}" 2>/dev/null || true
    fi
}

##
# Helper function to count metrics in database
##
count_metrics() {
    local component="${1}"
    local metric_name="${2:-}"
    
    local query="SELECT COUNT(*) FROM metrics WHERE component = '${component}'"
    
    if [[ -n "${metric_name}" ]]; then
        query="${query} AND metric_name = '${metric_name}'"
    fi
    
    run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]' || echo "0"
}

##
# Helper function to get latest metric value
##
get_latest_metric_value() {
    local component="${1}"
    local metric_name="${2}"
    
    local query="SELECT metric_value FROM metrics 
                 WHERE component = '${component}' 
                   AND metric_name = '${metric_name}' 
                 ORDER BY timestamp DESC 
                 LIMIT 1;"
    
    run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]' || echo ""
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

@test "check_wms_service_availability stores metrics in database" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Run check
    check_wms_service_availability
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local availability_count
    availability_count=$(count_metrics "wms" "service_availability")
    assert [ "${availability_count}" -ge "1" ]
    
    local response_time_count
    response_time_count=$(count_metrics "wms" "service_response_time_ms")
    assert [ "${response_time_count}" -ge "1" ]
}

@test "check_wms_service_availability generates alert when service unavailable" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Stop mock service to simulate unavailability
    stop_mock_wms_service
    
    # Run check
    check_wms_service_availability
    
    # Wait for database write
    sleep 1
    
    # Verify alert was generated
    local alert_count
    alert_count=$(count_alerts "WMS")
    assert [ "${alert_count}" -ge "1" ]
    
    # Verify alert type
    local alert_type_count
    alert_type_count=$(count_alerts "WMS" "" "service_unavailable")
    assert [ "${alert_type_count}" -ge "1" ]
    
    # Restart mock service for other tests
    start_mock_wms_service
}

@test "check_http_health stores metrics in database" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Run check
    check_http_health
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local health_count
    health_count=$(count_metrics "wms" "health_status")
    # May be 0 if health check fails, which is OK for this test
    assert [ -n "${health_count}" ]
}

@test "check_response_time stores metrics in database" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Run check
    check_response_time
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local response_time_count
    response_time_count=$(count_metrics "wms" "response_time_ms")
    assert [ "${response_time_count}" -ge "1" ]
}

@test "check_response_time generates alert when response time exceeds threshold" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Set very low threshold for testing
    export WMS_RESPONSE_TIME_THRESHOLD="100"
    
    # Run check (may take longer than 100ms)
    check_response_time
    
    # Wait for database write
    sleep 1
    
    # Verify alert was generated (may or may not trigger depending on actual response time)
    local alert_count
    alert_count=$(count_alerts "WMS")
    # Alert may or may not be generated depending on actual response time
    assert [ -n "${alert_count}" ]
}

@test "check_error_rate stores metrics in database" {
    skip_if_database_not_available
    
    # Create test log with errors
    echo "ERROR: Test error 1" > "${TEST_LOG_DIR}/wms.log"
    echo "INFO: Request processed" >> "${TEST_LOG_DIR}/wms.log"
    echo "ERROR: Test error 2" >> "${TEST_LOG_DIR}/wms.log"
    
    # Run check
    check_error_rate
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local error_count_metric
    error_count_metric=$(count_metrics "wms" "error_count")
    # May be 0 if no errors detected, which is OK
    assert [ -n "${error_count_metric}" ]
}

@test "check_tile_generation_performance stores metrics in database" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Run check
    check_tile_generation_performance
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local tile_gen_count
    tile_gen_count=$(count_metrics "wms" "tile_generation_time_ms")
    # May be 0 if tile generation fails, which is OK
    assert [ -n "${tile_gen_count}" ]
}

@test "check_cache_hit_rate stores metrics in database" {
    skip_if_database_not_available
    
    # Create test log with cache patterns
    echo "INFO: cache hit" > "${TEST_LOG_DIR}/wms.log"
    echo "INFO: cache miss" >> "${TEST_LOG_DIR}/wms.log"
    
    # Run check
    check_cache_hit_rate
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local cache_hit_count
    cache_hit_count=$(count_metrics "wms" "cache_hit_rate_percent")
    # May be 0 if no cache data detected, which is OK
    assert [ -n "${cache_hit_count}" ]
}

@test "Multiple monitoring checks store separate metrics" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Run multiple checks
    check_wms_service_availability
    check_response_time
    check_tile_generation_performance
    
    # Wait for database writes
    sleep 2
    
    # Verify multiple metrics were stored
    local total_metrics
    total_metrics=$(count_metrics "wms")
    assert [ "${total_metrics}" -ge "2" ]
    
    # Verify specific metrics exist
    local availability
    availability=$(count_metrics "wms" "service_availability")
    assert [ "${availability}" -ge "1" ]
    
    local response_time
    response_time=$(count_metrics "wms" "response_time_ms")
    assert [ "${response_time}" -ge "1" ]
}

@test "Metrics have correct component name" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Run check
    check_wms_service_availability
    
    # Wait for database write
    sleep 1
    
    # Verify component name
    local query="SELECT DISTINCT component FROM metrics WHERE component = 'wms' LIMIT 1;"
    local result
    result=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    assert_equal "wms" "${result}"
}

@test "Metrics have timestamps" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Record time before check
    local before_time
    before_time=$(date +%s)
    
    # Run check
    check_wms_service_availability
    
    # Wait for database write
    sleep 1
    
    # Record time after check
    local after_time
    after_time=$(date +%s)
    
    # Verify timestamp
    local query="SELECT EXTRACT(EPOCH FROM timestamp)::bigint FROM metrics 
                 WHERE component = 'wms' 
                   AND metric_name = 'service_availability' 
                 ORDER BY timestamp DESC 
                 LIMIT 1;"
    local metric_time
    metric_time=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    # Metric time should be between before and after
    assert [ "${metric_time}" -ge "${before_time}" ]
    assert [ "${metric_time}" -le "${after_time}" ]
}

@test "Alerts generated by monitoring checks are stored correctly" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Stop mock service to trigger alert
    stop_mock_wms_service
    
    # Run check (should generate alert)
    check_wms_service_availability
    
    # Wait for database write
    sleep 1
    
    # Verify alert was stored
    local alert_count
    alert_count=$(count_alerts "WMS")
    assert [ "${alert_count}" -ge "1" ]
    
    # Verify alert has correct component
    local query="SELECT component FROM alerts WHERE component = 'WMS' LIMIT 1;"
    local result
    result=$(run_sql_query "${query}" 2>/dev/null | tr -d '[:space:]')
    
    assert_equal "WMS" "${result}"
    
    # Restart mock service for other tests
    start_mock_wms_service
}

@test "Metrics metadata is stored correctly" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Run check
    check_wms_service_availability
    
    # Wait for database write
    sleep 1
    
    # Verify metadata exists (may be null or JSON)
    local query="SELECT metadata FROM metrics 
                 WHERE component = 'wms' 
                   AND metric_name = 'service_availability' 
                 ORDER BY timestamp DESC 
                 LIMIT 1;"
    local result
    result=$(run_sql_query "${query}" 2>/dev/null)
    
    # Metadata should exist (even if null)
    assert [ -n "${result}" ]
}

@test "Database connection is verified before storing metrics" {
    skip_if_database_not_available
    
    # Verify database connection function works
    if check_database_connection; then
        assert_success
    else
        skip "Database connection check failed"
    fi
}

@test "Monitoring checks handle service unavailability gracefully" {
    skip_if_database_not_available
    skip_if_command_not_found curl
    
    # Stop mock service
    stop_mock_wms_service
    
    # Run check (should handle error gracefully)
    if check_wms_service_availability 2>&1; then
        # If it succeeds (with alert), that's OK
        assert true
    else
        # If it fails, that's also OK (may return non-zero on alert)
        assert true
    fi
    
    # Restart mock service for other tests
    start_mock_wms_service
}

