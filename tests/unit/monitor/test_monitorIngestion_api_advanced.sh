#!/usr/bin/env bash
#
# Unit Tests: monitorIngestion.sh - Advanced API Metrics Tests
# Tests advanced API metrics check function
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    export INGESTION_REPO_PATH="${TEST_LOG_DIR}/ingestion_repo"
    mkdir -p "${INGESTION_REPO_PATH}/logs"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    export INGESTION_API_SUCCESS_RATE_THRESHOLD="95"
    export INGESTION_API_RATE_LIMIT_THRESHOLD="10"
    export INGESTION_API_SYNC_GAP_THRESHOLD="3600"
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    export ADMIN_EMAIL="test@example.com"
    export ALERT_RECIPIENTS="test@example.com"
    
    # Use a file to track alerts
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_sent.txt"
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    export ALERTS_FILE
    
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        # Return sync gap query result
        if [[ "${query}" == *"EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))"* ]]; then
            echo "300"  # 5 minutes ago
            return 0
        fi
        
        return 0
    }
    export -f execute_sql_query
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock parseApiLogs functions
    # shellcheck disable=SC2317
    parse_api_logs_aggregated() {
        # Parameters are required by function signature but not used in mock
        # shellcheck disable=SC2034
        local _log_dir="${1}"
        # shellcheck disable=SC2034
        local _time_window="${2}"
        
        # Return test metrics
        echo "total_requests=100"
        echo "successful_requests=98"
        echo "failed_requests=2"
        echo "timeout_requests=0"
        echo "errors_4xx=2"
        echo "errors_5xx=0"
        echo "rate_limit_hits=0"
        echo "avg_response_time_ms=250"
        echo "avg_response_size_bytes=12345"
        echo "avg_notes_per_request=50"
        echo "success_rate_percent=98"
        echo "timeout_rate_percent=0"
        echo "requests_per_minute=10"
        echo "requests_per_hour=600"
        echo "last_request_timestamp=$(date +%s)"
        echo "last_note_timestamp=$(date +%s)"
        
        return 0
    }
    export -f parse_api_logs_aggregated
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/parseApiLogs.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test_monitorIngestion_api_advanced.log" "test_monitorIngestion_api_advanced"
    
    # Initialize alerting (but we'll override send_alert)
    init_alerting
    
    # Override send_alert BEFORE sourcing monitorIngestion.sh
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Source monitorIngestion.sh functions
    export TEST_MODE=true
    export COMPONENT="INGESTION"
    
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorIngestion.sh" 2>/dev/null || true
    
    # Ensure send_alert is still our mock after sourcing
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Ensure parse_api_logs_aggregated is still our mock
    # shellcheck disable=SC2317
    parse_api_logs_aggregated() {
        # Parameters are required by function signature but not used in mock
        # shellcheck disable=SC2034
        local _log_dir="${1}"
        # shellcheck disable=SC2034
        local _time_window="${2}"
        
        echo "total_requests=100"
        echo "successful_requests=98"
        echo "failed_requests=2"
        echo "timeout_requests=0"
        echo "errors_4xx=2"
        echo "errors_5xx=0"
        echo "rate_limit_hits=0"
        echo "avg_response_time_ms=250"
        echo "avg_response_size_bytes=12345"
        echo "avg_notes_per_request=50"
        echo "success_rate_percent=98"
        echo "timeout_rate_percent=0"
        echo "requests_per_minute=10"
        echo "requests_per_hour=600"
        echo "last_request_timestamp=$(date +%s)"
        echo "last_note_timestamp=$(date +%s)"
        
        return 0
    }
    export -f parse_api_logs_aggregated
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "check_advanced_api_metrics succeeds when all metrics are healthy" {
    # Run check
    run check_advanced_api_metrics
    
    # Should succeed
    assert_success
}

@test "check_advanced_api_metrics alerts when success rate is below threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Redefine parse_api_logs_aggregated to return low success rate
    # shellcheck disable=SC2317
    parse_api_logs_aggregated() {
        echo "total_requests=100"
        echo "successful_requests=90"
        echo "failed_requests=10"
        echo "timeout_requests=0"
        echo "errors_4xx=10"
        echo "errors_5xx=0"
        echo "rate_limit_hits=0"
        echo "avg_response_time_ms=250"
        echo "avg_response_size_bytes=12345"
        echo "avg_notes_per_request=50"
        echo "success_rate_percent=90"  # Below threshold of 95
        echo "timeout_rate_percent=0"
        echo "requests_per_minute=10"
        echo "requests_per_hour=600"
        echo "last_request_timestamp=$(date +%s)"
        echo "last_note_timestamp=$(date +%s)"
        return 0
    }
    export -f parse_api_logs_aggregated
    
    # Run check in subshell to ensure mock is used
    run check_advanced_api_metrics
    
    # Should succeed (function returns 0 even with warnings)
    assert_success
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"api_success_rate_low"* ]] || [[ "${alert}" == *"success rate"* ]] || [[ "${alert}" == *"WARNING"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    # Alert should be found
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_api_metrics alerts when 5xx errors detected" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock parse_api_logs_aggregated to return 5xx errors
    # shellcheck disable=SC2317
    parse_api_logs_aggregated() {
        echo "total_requests=100"
        echo "successful_requests=95"
        echo "failed_requests=5"
        echo "timeout_requests=0"
        echo "errors_4xx=0"
        echo "errors_5xx=5"  # 5xx errors
        echo "rate_limit_hits=0"
        echo "avg_response_time_ms=250"
        echo "avg_response_size_bytes=12345"
        echo "avg_notes_per_request=50"
        echo "success_rate_percent=95"
        echo "timeout_rate_percent=0"
        echo "requests_per_minute=10"
        echo "requests_per_hour=600"
        echo "last_request_timestamp=$(date +%s)"
        echo "last_note_timestamp=$(date +%s)"
        return 0
    }
    export -f parse_api_logs_aggregated
    
    # Run check - should fail due to 5xx errors
    run check_advanced_api_metrics
    
    # Should fail (return 1)
    assert_failure
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"api_errors_5xx"* ]] || [[ "${alert}" == *"5xx"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_api_metrics alerts when rate limit hits exceed threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Redefine parse_api_logs_aggregated to return high rate limit hits
    # shellcheck disable=SC2317
    parse_api_logs_aggregated() {
        # Parameters are required by function signature but not used in mock
        # shellcheck disable=SC2034
        local _log_dir="${1}"
        # shellcheck disable=SC2034
        local _time_window="${2}"
        
        echo "total_requests=100"
        echo "successful_requests=98"
        echo "failed_requests=2"
        echo "timeout_requests=0"
        echo "errors_4xx=2"
        echo "errors_5xx=0"
        echo "rate_limit_hits=15"  # Above threshold of 10
        echo "avg_response_time_ms=250"
        echo "avg_response_size_bytes=12345"
        echo "avg_notes_per_request=50"
        echo "success_rate_percent=98"
        echo "timeout_rate_percent=0"
        echo "requests_per_minute=10"
        echo "requests_per_hour=600"
        echo "last_request_timestamp=$(date +%s)"
        echo "last_note_timestamp=$(date +%s)"
        return 0
    }
    export -f parse_api_logs_aggregated
    
    # Run check in subshell to ensure mock is used
    run check_advanced_api_metrics
    
    # Should succeed (function returns 0 even with warnings)
    assert_success
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"api_rate_limit_frequent"* ]] || [[ "${alert}" == *"rate limit"* ]] || [[ "${alert}" == *"WARNING"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    # Alert should be found
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_api_metrics handles missing repository gracefully" {
    # Set non-existent repository path
    export INGESTION_REPO_PATH="/nonexistent/path"
    
    # Run check
    run check_advanced_api_metrics
    
    # Should succeed (graceful handling)
    assert_success
}

@test "check_advanced_api_metrics handles missing log directory gracefully" {
    # Set repository path without logs directory
    export INGESTION_REPO_PATH="${TEST_LOG_DIR}/no_logs_repo"
    mkdir -p "${INGESTION_REPO_PATH}"
    # Don't create logs directory
    
    # Run check
    run check_advanced_api_metrics
    
    # Should succeed (graceful handling)
    assert_success
}

@test "check_advanced_api_metrics handles empty log parsing gracefully" {
    # Mock parse_api_logs_aggregated to return empty output
    # shellcheck disable=SC2317
    parse_api_logs_aggregated() {
        echo ""
        return 0
    }
    export -f parse_api_logs_aggregated
    
    # Run check
    run check_advanced_api_metrics
    
    # Should succeed (graceful handling)
    assert_success
}
