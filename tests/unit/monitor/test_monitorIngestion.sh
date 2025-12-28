#!/usr/bin/env bash
#
# Unit Tests: monitorIngestion.sh
# Tests ingestion monitoring check functions
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    export INGESTION_SCRIPTS_FOUND_THRESHOLD="3"
    export INGESTION_LAST_LOG_AGE_THRESHOLD="24"
    export INGESTION_MAX_ERROR_RATE="5"
    export INGESTION_ERROR_COUNT_THRESHOLD="1000"
    export INGESTION_WARNING_COUNT_THRESHOLD="2000"
    export INGESTION_WARNING_RATE_THRESHOLD="15"
    export INGESTION_DATA_QUALITY_THRESHOLD="95"
    export INGESTION_LATENCY_THRESHOLD="300"
    export INGESTION_DATA_FRESHNESS_THRESHOLD="3600"
    export INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD="95"
    export INFRASTRUCTURE_DISK_THRESHOLD="90"
    export PERFORMANCE_SLOW_QUERY_THRESHOLD="1000"
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Mock database functions to avoid real DB calls
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
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
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_monitorIngestion"
    
    # Initialize alerting
    init_alerting
    
    # Source monitorIngestion.sh functions
    # Set component name BEFORE sourcing (to allow override)
    export TEST_MODE=true
    export COMPONENT="INGESTION"
    
    # We'll source it but need to handle the main execution
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorIngestion.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Helper: Create test script
##
create_test_script() {
    local script_name="${1}"
    local executable="${2:-true}"
    
    local script_path="${TEST_INGESTION_DIR}/bin/${script_name}"
    echo "#!/bin/bash" > "${script_path}"
    echo "# Test script ${script_name}" >> "${script_path}"
    
    if [[ "${executable}" == "true" ]]; then
        chmod +x "${script_path}"
    fi
}

##
# Helper: Create test log file
##
create_test_log() {
    local log_name="${1}"
    local content="${2}"
    local age_hours="${3:-0}"
    
    local log_path="${TEST_INGESTION_DIR}/logs/${log_name}"
    echo "${content}" > "${log_path}"
    
    if [[ ${age_hours} -gt 0 ]]; then
        # Set file modification time to X hours ago
        local timestamp
        # shellcheck disable=SC2086
        timestamp=$(date -d "${age_hours} hours ago" +%s 2>/dev/null || date -v-"${age_hours}"H +%s 2>/dev/null || echo "")
        if [[ -n "${timestamp}" ]]; then
            touch -t "$(date -d "@${timestamp}" +%Y%m%d%H%M.%S 2>/dev/null || date -r "${timestamp}" +%Y%m%d%H%M.%S 2>/dev/null || echo "")" "${log_path}" 2>/dev/null || true
        fi
    fi
}

@test "check_script_execution_status finds scripts when they exist" {
    # Create test scripts
    create_test_script "processAPINotes.sh"
    create_test_script "processPlanetNotes.sh"
    create_test_script "notesCheckVerifier.sh"
    
    # Mock record_metric to avoid DB calls
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert to avoid alerts
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_script_execution_status
    
    # Should succeed
    assert_success
}

@test "check_script_execution_status alerts when scripts_found below threshold" {
    # Create only 2 scripts (below threshold of 3)
    create_test_script "processAPINotes.sh"
    create_test_script "processPlanetNotes.sh"
    
    local alert_sent=false
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Low number of scripts found"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check
    check_script_execution_status
    
    # Alert should have been sent
    assert_equal "true" "${alert_sent}"
}

@test "check_script_execution_status alerts when scripts not executable" {
    # Create scripts but make one non-executable
    create_test_script "processAPINotes.sh" "true"
    create_test_script "processPlanetNotes.sh" "false"  # Not executable
    
    local alert_sent=false
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Scripts executable count"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check
    check_script_execution_status
    
    # Alert should have been sent
    assert_equal "true" "${alert_sent}"
}

@test "check_error_rate calculates error rate correctly" {
    # Create log file with errors
    create_test_log "test.log" "INFO: Test message
ERROR: Test error
INFO: Another message
ERROR: Another error
WARNING: Test warning"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_error_rate
    
    # Should succeed
    assert_success
}

@test "check_error_rate alerts when error rate exceeds threshold" {
    # Create log file with high error rate (>5%)
    create_test_log "test.log" "ERROR: Error 1
ERROR: Error 2
ERROR: Error 3
ERROR: Error 4
ERROR: Error 5
ERROR: Error 6
INFO: Info 1
INFO: Info 2
INFO: Info 3
INFO: Info 4"
    
    local alert_sent=false
    # Redefine send_alert function (must be done after monitorIngestion.sh is sourced)
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"High error rate detected"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    
    # Set low threshold for testing
    export INGESTION_MAX_ERROR_RATE="50"
    
    # Run check (may return 1 if error rate exceeds threshold, which is expected)
    run check_error_rate || true
    
    # Alert should have been sent (error rate is 60%)
    assert_equal "true" "${alert_sent}"
}

@test "check_error_rate alerts when error count exceeds threshold" {
    # Create log file with many errors
    local error_log=""
    for i in {1..1001}; do
        error_log="${error_log}ERROR: Error ${i}"$'\n'
    done
    create_test_log "test.log" "${error_log}"
    
    local alert_sent=false
    # Redefine send_alert function (must be done after monitorIngestion.sh is sourced)
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"High error count"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check (may return 1 if error count exceeds threshold, which is expected)
    run check_error_rate || true
    
    # Alert should have been sent
    assert_equal "true" "${alert_sent}"
}

@test "check_disk_space checks disk usage" {
    # Mock df command to return test values
    # Note: df is called with a path, so we need to handle that
    # For unit tests, we'll skip this if df can't be mocked properly
    skip "df mocking requires more complex setup"
    
    # Alternative: Test that function exists and can be called
    # This is a simpler test that verifies the function is defined
    if type check_disk_space > /dev/null 2>&1; then
        assert_success
    else
        skip "check_disk_space function not available"
    fi
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_disk_space
    
    # Should succeed
    assert_success
}

@test "check_disk_space alerts when usage exceeds threshold" {
    # Mock df to return high usage
    # Note: This test requires proper df mocking which is complex
    # For now, we'll test the logic exists
    skip "df mocking requires more complex setup - tested in integration tests"
    
    local alert_sent=false
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"High disk usage"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check
    check_disk_space
    
    # Alert should have been sent
    assert_equal "true" "${alert_sent}"
}

@test "check_last_execution_time alerts when log is too old" {
    # Create old log file (25 hours ago)
    create_test_log "old.log" "INFO: Old log" "25"
    
    local alert_sent=false
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"No recent activity"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check
    check_last_execution_time
    
    # Alert should have been sent
    assert_equal "true" "${alert_sent}"
}

@test "check_last_execution_time does not alert for recent logs" {
    # Create recent log file
    create_test_log "recent.log" "INFO: Recent log" "1"
    
    local alert_sent=false
    # shellcheck disable=SC2317
    send_alert() {
        alert_sent=true
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run check
    check_last_execution_time
    
    # Alert should NOT have been sent
    assert_equal "false" "${alert_sent}"
}

@test "check_ingestion_health fails when repository not found" {
    # Remove test repository
    rm -rf "${TEST_INGESTION_DIR}"
    
    local alert_sent=false
    # Redefine send_alert function (must be done after monitorIngestion.sh is sourced)
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${2}" == "CRITICAL" ]]; then
            alert_sent=true
        fi
        return 0
    }
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    
    # Run check (should fail when repository not found)
    run check_ingestion_health || true
    
    # Should fail and send critical alert
    assert_equal "true" "${alert_sent}"
}

@test "check_ingestion_health passes when repository exists" {
    # Repository already exists from setup
    create_test_log "recent.log" "INFO: Recent activity" "1"
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock check_script_execution_status
    # shellcheck disable=SC2317
    check_script_execution_status() {
        return 0
    }
    export -f check_script_execution_status
    
    # Run check
    run check_ingestion_health
    
    # Should succeed
    assert_success
}

@test "check_data_freshness records metric when data is fresh" {
    # Mock database query to return fresh data
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"freshness_seconds"* ]]; then
            echo "1800|100"  # 30 minutes old, 100 recent updates
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    local metric_recorded=false
    # shellcheck disable=SC2317
    record_metric() {
        if [[ "${2}" == "data_freshness_seconds" ]]; then
            metric_recorded=true
        fi
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    check_data_freshness
    
    # Metric should have been recorded
    assert_equal "true" "${metric_recorded}"
}

@test "check_data_freshness alerts when data is stale" {
    # Mock database query to return stale data
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"freshness_seconds"* ]]; then
            echo "7200|0"  # 2 hours old (exceeds 1 hour threshold)
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    local alert_sent=false
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"Data freshness exceeded"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    export -f send_alert
    
    # Run check
    check_data_freshness
    
    # Alert should have been sent
    assert_equal "true" "${alert_sent}"
}

@test "check_processing_latency calculates latency from database" {
    # Mock database query to return processing log data
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"latency_seconds"* ]]; then
            echo "180"  # 3 minutes latency
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_processing_latency
    
    # Should succeed
    assert_success
}

@test "check_processing_latency alerts when latency exceeds threshold" {
    # Mock database query to return high latency
    # shellcheck disable=SC2317
    execute_sql_query() {
        if [[ "${1}" == *"latency_seconds"* ]]; then
            echo "600"  # 10 minutes (exceeds 5 minute threshold)
        fi
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    local alert_sent=false
    # Redefine send_alert function (must be done after monitorIngestion.sh is sourced)
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"High processing latency"* ]]; then
            alert_sent=true
        fi
        return 0
    }
    
    # Run check (may return 1 if latency exceeds threshold, which is expected)
    run check_processing_latency || true
    
    # Alert should have been sent
    assert_equal "true" "${alert_sent}"
}

@test "check_api_download_status detects recent activity" {
    # Create log file with recent API download activity
    create_test_log "api_download.log" "INFO: Downloading from API
INFO: Download completed successfully
INFO: 200 OK"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_api_download_status
    
    # Should succeed
    assert_success
}

@test "check_api_download_status alerts when no recent activity" {
    # Remove API script to ensure it's not considered recent
    rm -f "${TEST_INGESTION_DIR}/bin/processAPINotes.sh"
    
    # Create old log file (25 hours old)
    create_test_log "old_api.log" "INFO: Old download" "25"
    
    # Verify log file exists and is old
    local log_file="${TEST_INGESTION_DIR}/logs/old_api.log"
    assert_file_exists "${log_file}"
    
    # Use a temp file to track alert status (since run executes in subshell)
    local alert_file="${TEST_INGESTION_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # Redefine send_alert function (must be done after monitorIngestion.sh is sourced)
    # shellcheck disable=SC2317
    send_alert() {
        echo "DEBUG: send_alert called with args: $*" >&2
        if [[ "${4}" == *"No recent API download activity"* ]]; then
            touch "${alert_file}"
            echo "DEBUG: alert_sent file created" >&2
        fi
        return 0
    }
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    
    # Debug: Check what logs exist
    echo "DEBUG: Logs in ${TEST_INGESTION_DIR}/logs:" >&2
    ls -la "${TEST_INGESTION_DIR}/logs/" >&2 || true
    
    # Debug: Check TEST_MODE
    echo "DEBUG: TEST_MODE=${TEST_MODE:-not set}" >&2
    
    # Run check (may return 1 if no recent activity, which is expected)
    run check_api_download_status || true
    
    # Debug: Check output
    echo "DEBUG: Function output: ${output:-empty}" >&2
    echo "DEBUG: alert_file exists: $([ -f "${alert_file}" ] && echo "yes" || echo "no")" >&2
    echo "DEBUG: status=${status}" >&2
    
    # Alert should have been sent
    assert_file_exists "${alert_file}"
}

@test "check_api_download_success_rate calculates success rate" {
    # Create log files with download attempts
    create_test_log "download1.log" "INFO: Download success
INFO: 200 OK"
    create_test_log "download2.log" "INFO: Download failed
ERROR: 500 Internal Server Error"
    create_test_log "download3.log" "INFO: Download success
INFO: 200 OK"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check
    run check_api_download_success_rate
    
    # Should succeed
    assert_success
}

@test "check_api_download_success_rate alerts when success rate is low" {
    # Create log files with mostly failures
    # The function looks for patterns: "download|fetch|GET|POST" for total downloads
    # and "success|completed|200 OK|downloaded" for successful downloads
    # IMPORTANT: Each log file should have exactly ONE download attempt line
    # to match the expected 30% success rate (3 successful out of 10 total)
    for i in {1..10}; do
        if [[ $((i % 3)) -eq 0 ]]; then
            # Successful download (3 out of 10 = 30% success rate)
            # Only ONE line with "download" pattern, and ONE with "success" pattern
            create_test_log "download${i}.log" "INFO: GET /api/download success completed 200 OK downloaded"
        else
            # Failed download (7 out of 10)
            # Only ONE line with "download" pattern, NO success patterns
            create_test_log "download${i}.log" "INFO: GET /api/download failed 500 Error"
        fi
    done
    
    # Use a temp file to track alert status (since run executes in subshell)
    local alert_file="${TEST_INGESTION_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # Redefine send_alert function (must be done after monitorIngestion.sh is sourced)
    # shellcheck disable=SC2317
    send_alert() {
        echo "DEBUG: send_alert called with args: $*" >&2
        if [[ "${4}" == *"Low API download success rate"* ]]; then
            touch "${alert_file}"
            echo "DEBUG: alert_sent file created" >&2
        fi
        return 0
    }
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    
    # Set high threshold for testing
    export INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD="50"
    
    # Debug: Check what logs exist
    echo "DEBUG: Logs in ${TEST_INGESTION_DIR}/logs:" >&2
    ls -la "${TEST_INGESTION_DIR}/logs/" >&2 || true
    
    # Debug: Check TEST_MODE and threshold
    echo "DEBUG: TEST_MODE=${TEST_MODE:-not set}" >&2
    echo "DEBUG: INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD=${INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD:-not set}" >&2
    
    # Run check (may return 1 if success rate is low, which is expected)
    run check_api_download_success_rate || true
    
    # Debug: Check output
    echo "DEBUG: Function output: ${output:-empty}" >&2
    echo "DEBUG: alert_file exists: $([ -f "${alert_file}" ] && echo "yes" || echo "no")" >&2
    echo "DEBUG: status=${status}" >&2
    
    # Alert should have been sent (success rate is 30%, threshold is 50%)
    assert_file_exists "${alert_file}"
}

@test "check_ingestion_data_quality calculates quality score" {
    # Mock notesCheckVerifier script
    local verifier_script="${TEST_INGESTION_DIR}/bin/monitor/notesCheckVerifier.sh"
    mkdir -p "$(dirname "${verifier_script}")"
    echo "#!/bin/bash" > "${verifier_script}"
    echo "exit 0" >> "${verifier_script}"
    chmod +x "${verifier_script}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    check_data_completeness() {
        return 0
    }
    export -f check_data_completeness
    
    # shellcheck disable=SC2317
    check_data_freshness() {
        return 0
    }
    export -f check_data_freshness
    
    # Run check
    run check_ingestion_data_quality
    
    # Should succeed
    assert_success
}

@test "check_ingestion_data_quality alerts when quality score is low" {
    # Mock notesCheckVerifier script that fails
    local verifier_script="${TEST_INGESTION_DIR}/bin/monitor/notesCheckVerifier.sh"
    mkdir -p "$(dirname "${verifier_script}")"
    echo "#!/bin/bash" > "${verifier_script}"
    echo "echo 'ERROR: Data quality issues found'" >> "${verifier_script}"
    echo "exit 1" >> "${verifier_script}"
    chmod +x "${verifier_script}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    
    # Use a temp file to track alert status (since run executes in subshell)
    local alert_file="${TEST_INGESTION_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # Redefine send_alert function (must be done after monitorIngestion.sh is sourced)
    # shellcheck disable=SC2317
    send_alert() {
        echo "DEBUG: send_alert called with args: $*" >&2
        if [[ "${4}" == *"Data quality below threshold"* ]]; then
            touch "${alert_file}"
            echo "DEBUG: alert_sent file created" >&2
        fi
        return 0
    }
    
    # shellcheck disable=SC2317
    check_data_completeness() {
        return 0
    }
    
    # shellcheck disable=SC2317
    check_data_freshness() {
        return 0
    }
    
    # Debug: Verify script exists
    echo "DEBUG: Verifier script: ${verifier_script}" >&2
    ls -la "${verifier_script}" >&2 || echo "DEBUG: Script not found!" >&2
    
    # Debug: Check TEST_MODE and threshold
    echo "DEBUG: TEST_MODE=${TEST_MODE:-not set}" >&2
    echo "DEBUG: INGESTION_DATA_QUALITY_THRESHOLD=${INGESTION_DATA_QUALITY_THRESHOLD:-not set}" >&2
    
    # Run check (may return 1 if quality score is low, which is expected)
    run check_ingestion_data_quality || true
    
    # Debug: Check output
    echo "DEBUG: Function output: ${output:-empty}" >&2
    echo "DEBUG: alert_file exists: $([ -f "${alert_file}" ] && echo "yes" || echo "no")" >&2
    echo "DEBUG: status=${status}" >&2
    
    # Alert should have been sent (quality_score should be 90% when script fails, threshold is 95%)
    assert_file_exists "${alert_file}"
}

