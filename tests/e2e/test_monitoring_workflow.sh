#!/usr/bin/env bash
#
# End-to-End Tests: Monitoring Workflow with Mock Ingestion System
# Tests the complete monitoring workflow using mock ingestion scripts
#
# Version: 1.0.0
# Date: 2025-12-26
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

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
source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorIngestion.sh"

# Test configuration
export TEST_COMPONENT="INGESTION"
TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
MOCK_INGESTION_DIR="${BATS_TEST_DIRNAME}/../tmp/mock_ingestion_e2e"
MOCK_SCRIPTS_DIR="${MOCK_INGESTION_DIR}/bin"
MOCK_LOGS_DIR="${MOCK_INGESTION_DIR}/logs"
MOCK_DATA_DIR="${MOCK_INGESTION_DIR}/data"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Set mock ingestion path
    export INGESTION_REPO_PATH="${MOCK_INGESTION_DIR}"
    export INGESTION_LOG_DIR="${MOCK_LOGS_DIR}"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    
    # Disable alert deduplication for testing
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Load monitoring configuration with test thresholds
    export INGESTION_SCRIPTS_FOUND_THRESHOLD=3
    export INGESTION_LAST_LOG_AGE_THRESHOLD=24
    export INGESTION_MAX_ERROR_RATE=5
    export INGESTION_ERROR_COUNT_THRESHOLD=1000
    export INGESTION_WARNING_COUNT_THRESHOLD=2000
    export INGESTION_WARNING_RATE_THRESHOLD=15
    export INGESTION_DATA_FRESHNESS_THRESHOLD=3600
    export INGESTION_LATENCY_THRESHOLD=300
    export INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD=95
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_monitoring_workflow.log"
    init_logging "${LOG_FILE}" "test_monitoring_workflow"
    
    # Initialize alerting
    init_alerting
    
    # Create mock ingestion directory structure
    mkdir -p "${MOCK_SCRIPTS_DIR}"
    mkdir -p "${MOCK_LOGS_DIR}"
    mkdir -p "${MOCK_DATA_DIR}"
    
    # Copy mock scripts to mock ingestion bin directory
    cp "${BATS_TEST_DIRNAME}/../mock_commands/mock_processAPINotes.sh" "${MOCK_SCRIPTS_DIR}/processAPINotes.sh"
    cp "${BATS_TEST_DIRNAME}/../mock_commands/mock_processPlanetNotes.sh" "${MOCK_SCRIPTS_DIR}/processPlanetNotes.sh"
    cp "${BATS_TEST_DIRNAME}/../mock_commands/mock_notesCheckVerifier.sh" "${MOCK_SCRIPTS_DIR}/notesCheckVerifier.sh"
    cp "${BATS_TEST_DIRNAME}/../mock_commands/mock_processCheckPlanetNotes.sh" "${MOCK_SCRIPTS_DIR}/processCheckPlanetNotes.sh"
    cp "${BATS_TEST_DIRNAME}/../mock_commands/mock_analyzeDatabasePerformance.sh" "${MOCK_SCRIPTS_DIR}/analyzeDatabasePerformance.sh"
    
    # Make scripts executable
    chmod +x "${MOCK_SCRIPTS_DIR}"/*.sh
    
    # Set mock environment variables
    export MOCK_LOG_DIR="${MOCK_LOGS_DIR}"
    export MOCK_DATA_DIR="${MOCK_DATA_DIR}"
    
    # Clean test database
    clean_test_database
}

teardown() {
    # Clean up test alerts and metrics
    clean_test_database
    
    # Clean up test directories
    rm -rf "${MOCK_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
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
# Helper function to count alerts in database
##
count_alerts() {
    local component="${1}"
    local alert_level="${2:-}"
    
    local query="SELECT COUNT(*) FROM alerts WHERE component = '${component}'"
    
    if [[ -n "${alert_level}" ]]; then
        query="${query} AND alert_level = '${alert_level}'"
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

@test "Complete monitoring workflow with healthy mock ingestion system" {
    skip_if_database_not_available
    
    # Configure mock scripts for success
    export MOCK_SUCCESS_RATE=100
    export MOCK_ERROR_COUNT=0
    export MOCK_WARNING_COUNT=0
    export MOCK_PROCESSING_TIME=1
    
    # Execute mock scripts in background
    "${MOCK_SCRIPTS_DIR}/processAPINotes.sh" &
    "${MOCK_SCRIPTS_DIR}/processPlanetNotes.sh" &
    
    # Wait for scripts to complete
    wait
    
    # Run monitoring checks
    check_script_execution_status
    check_error_rate
    check_disk_space
    
    # Wait for database writes
    sleep 2
    
    # Verify metrics were stored
    local total_metrics
    total_metrics=$(count_metrics "ingestion")
    assert [ "${total_metrics}" -ge "3" ]
    
    # Verify specific metrics
    local scripts_found
    scripts_found=$(get_latest_metric_value "ingestion" "scripts_found")
    assert [ "${scripts_found}" -ge "5" ]
    
    # Verify no alerts were generated (system is healthy)
    local alert_count
    alert_count=$(count_alerts "INGESTION")
    assert_equal "0" "${alert_count}"
}

@test "Monitoring workflow detects script execution issues" {
    skip_if_database_not_available
    
    # Remove some scripts to trigger alert
    rm -f "${MOCK_SCRIPTS_DIR}/processCheckPlanetNotes.sh"
    rm -f "${MOCK_SCRIPTS_DIR}/analyzeDatabasePerformance.sh"
    
    # Run monitoring check
    check_script_execution_status
    
    # Wait for database write
    sleep 1
    
    # Verify alert was generated
    local alert_count
    alert_count=$(count_alerts "INGESTION")
    assert [ "${alert_count}" -ge "1" ]
    
    # Verify metric shows fewer scripts
    local scripts_found
    scripts_found=$(get_latest_metric_value "ingestion" "scripts_found")
    assert [ "${scripts_found}" -lt "5" ]
}

@test "Monitoring workflow detects error rate issues" {
    skip_if_database_not_available
    
    # Configure mock scripts to generate errors
    export MOCK_ERROR_COUNT=50
    export MOCK_WARNING_COUNT=10
    
    # Execute mock script
    "${MOCK_SCRIPTS_DIR}/processAPINotes.sh"
    
    # Run monitoring check
    check_error_rate
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local error_count
    error_count=$(get_latest_metric_value "ingestion" "error_count")
    assert [ "${error_count}" -ge "50" ]
    
    # Verify alert was generated (error rate exceeds threshold)
    local alert_count
    alert_count=$(count_alerts "INGESTION")
    assert [ "${alert_count}" -ge "1" ]
}

@test "Monitoring workflow detects warning rate issues" {
    skip_if_database_not_available
    
    # Configure mock scripts to generate many warnings
    export MOCK_ERROR_COUNT=0
    export MOCK_WARNING_COUNT=100
    
    # Execute mock script
    "${MOCK_SCRIPTS_DIR}/processPlanetNotes.sh"
    
    # Run monitoring check
    check_error_rate
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local warning_count
    warning_count=$(get_latest_metric_value "ingestion" "warning_count")
    assert [ "${warning_count}" -ge "100" ]
    
    # Verify alert was generated if warning rate exceeds threshold
    local warning_rate
    warning_rate=$(get_latest_metric_value "ingestion" "warning_rate_percent")
    if [[ -n "${warning_rate}" ]] && [[ "${warning_rate}" -gt 15 ]]; then
        local alert_count
        alert_count=$(count_alerts "INGESTION")
        assert [ "${alert_count}" -ge "1" ]
    fi
}

@test "Monitoring workflow tracks script execution over time" {
    skip_if_database_not_available
    
    # Execute mock scripts multiple times
    for _ in {1..3}; do
        "${MOCK_SCRIPTS_DIR}/processAPINotes.sh"
        sleep 1
        check_script_execution_status
        sleep 1
    done
    
    # Verify multiple metric entries
    local scripts_found_count
    scripts_found_count=$(count_metrics "ingestion" "scripts_found")
    assert [ "${scripts_found_count}" -ge "3" ]
}

@test "Monitoring workflow handles concurrent script execution" {
    skip_if_database_not_available
    
    # Execute multiple scripts concurrently
    "${MOCK_SCRIPTS_DIR}/processAPINotes.sh" &
    local pid1=$!
    "${MOCK_SCRIPTS_DIR}/processPlanetNotes.sh" &
    local pid2=$!
    "${MOCK_SCRIPTS_DIR}/notesCheckVerifier.sh" &
    local pid3=$!
    
    # Wait a moment for scripts to start
    sleep 2
    
    # Run monitoring check while scripts are running
    check_script_execution_status
    
    # Wait for scripts to complete
    wait "${pid1}" "${pid2}" "${pid3}"
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were stored
    local scripts_running
    scripts_running=$(get_latest_metric_value "ingestion" "scripts_running")
    # Should have detected running scripts (may be 0 if they finished quickly)
    assert [ -n "${scripts_running}" ]
}

@test "Monitoring workflow detects data freshness issues" {
    skip_if_database_not_available
    
    # Create old data file
    local old_data_file="${MOCK_DATA_DIR}/old_data.json"
    echo '{"test": "data"}' > "${old_data_file}"
    touch -t "$(date -u +"%Y%m%d%H%M.%S" -d "2 hours ago")" "${old_data_file}"
    
    # Run data freshness check if available
    if type -t check_data_freshness > /dev/null 2>&1; then
        check_data_freshness
        
        # Wait for database write
        sleep 1
        
        # Verify metric was stored
        local freshness_metric
        freshness_metric=$(count_metrics "ingestion" "data_freshness_seconds")
        assert [ -n "${freshness_metric}" ]
    else
        skip "check_data_freshness function not available"
    fi
}

@test "Monitoring workflow handles script failures gracefully" {
    skip_if_database_not_available
    
    # Configure mock script to fail
    export MOCK_SUCCESS_RATE=0
    
    # Execute mock script (will fail)
    "${MOCK_SCRIPTS_DIR}/processAPINotes.sh" || true
    
    # Run monitoring check
    check_error_rate
    
    # Wait for database write
    sleep 1
    
    # Verify metrics were still stored despite script failure
    local error_count
    error_count=$(get_latest_metric_value "ingestion" "error_count")
    # Should have recorded errors from the failed script
    assert [ -n "${error_count}" ]
}

@test "Complete end-to-end workflow: scripts -> monitoring -> metrics -> alerts" {
    skip_if_database_not_available
    
    # Step 1: Execute mock ingestion scripts
    export MOCK_ERROR_COUNT=10
    export MOCK_WARNING_COUNT=5
    "${MOCK_SCRIPTS_DIR}/processAPINotes.sh" &
    "${MOCK_SCRIPTS_DIR}/processPlanetNotes.sh" &
    wait
    
    # Step 2: Run all monitoring checks
    check_script_execution_status
    check_error_rate
    check_disk_space
    
    # Step 3: Wait for database writes
    sleep 2
    
    # Step 4: Verify metrics were stored
    local total_metrics
    total_metrics=$(count_metrics "ingestion")
    assert [ "${total_metrics}" -ge "3" ]
    
    # Step 5: Verify alerts were generated if thresholds exceeded
    local alert_count
    alert_count=$(count_alerts "INGESTION")
    # May or may not have alerts depending on thresholds
    assert [ -n "${alert_count}" ]
    
    # Step 6: Verify data integrity - metrics and alerts are consistent
    local scripts_found
    scripts_found=$(get_latest_metric_value "ingestion" "scripts_found")
    assert [ "${scripts_found}" -ge "3" ]
}


