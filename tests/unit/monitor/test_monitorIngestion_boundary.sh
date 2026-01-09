#!/usr/bin/env bash
#
# Unit Tests: monitorIngestion.sh - Boundary Metrics Tests
# Tests boundary metrics check function
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
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    export INGESTION_BOUNDARY_UPDATE_AGE_THRESHOLD="168"
    export INGESTION_BOUNDARY_NO_COUNTRY_THRESHOLD="10"
    
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
    
    # Mock execute_sql_query to return test data
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        # Return healthy update age (24 hours = 24)
        if [[ "${query}" == *"boundary_update_frequency_hours"* ]] && [[ "${query}" == *"type=countries"* ]]; then
            echo "24"
            return 0
        fi
        
        # Return healthy notes without country (5%)
        if [[ "${query}" == *"boundary_notes_without_country_count"* ]]; then
            echo "50"
            return 0
        fi
        
        # Return notes with country
        if [[ "${query}" == *"boundary_notes_with_country_count"* ]]; then
            echo "950"
            return 0
        fi
        
        # Return no wrong country assignments
        if [[ "${query}" == *"boundary_notes_wrong_country_count"* ]]; then
            echo "0"
            return 0
        fi
        
        echo ""
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
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectBoundaryMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
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
    init_logging "${TEST_LOG_DIR}/test_monitorIngestion_boundary.log" "test_monitorIngestion_boundary"
    
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
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "check_boundary_metrics succeeds when all metrics are healthy" {
    # Run check
    run check_boundary_metrics
    
    # Should succeed
    assert_success
}

@test "check_boundary_metrics alerts when boundary update age exceeds threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock execute_sql_query to return high update age
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"boundary_update_frequency_hours"* ]] && [[ "${query}" == *"type=countries"* ]]; then
            echo "200"  # Above threshold of 168 hours
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_without_country_count"* ]]; then
            echo "50"
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_with_country_count"* ]]; then
            echo "950"
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_wrong_country_count"* ]]; then
            echo "0"
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_boundary_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"boundary_update_stale"* ]] || [[ "${alert}" == *"stale"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_boundary_metrics alerts when percentage without country exceeds threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock execute_sql_query to return high percentage without country
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"boundary_update_frequency_hours"* ]]; then
            echo "24"
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_without_country_count"* ]]; then
            echo "150"  # 15% of 1000 notes
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_with_country_count"* ]]; then
            echo "850"
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_wrong_country_count"* ]]; then
            echo "0"
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_boundary_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"boundary_no_country_high"* ]] || [[ "${alert}" == *"without country"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_boundary_metrics alerts when wrong country assignments detected" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock execute_sql_query to return wrong country assignments
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"boundary_update_frequency_hours"* ]]; then
            echo "24"
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_without_country_count"* ]]; then
            echo "50"
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_with_country_count"* ]]; then
            echo "950"
            return 0
        fi
        
        if [[ "${query}" == *"boundary_notes_wrong_country_count"* ]]; then
            echo "5"  # Wrong country assignments detected
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_boundary_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"boundary_wrong_country"* ]] || [[ "${alert}" == *"wrong country"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_boundary_metrics handles missing script gracefully" {
    # Mock test to check if script file exists check works
    local script_path="${SCRIPT_DIR}/collectBoundaryMetrics.sh"
    if [[ ! -f "${script_path}" ]]; then
        # Script doesn't exist, test should pass (graceful handling)
        run check_boundary_metrics
        assert_success
    else
        # Script exists, skip this test or test a different scenario
        skip "collectBoundaryMetrics.sh exists, cannot test missing script scenario easily"
    fi
}

@test "check_boundary_metrics handles non-executable script gracefully" {
    local script_path="${SCRIPT_DIR}/collectBoundaryMetrics.sh"
    local was_executable=false
    
    if [[ -f "${script_path}" ]]; then
        # Check if currently executable
        if [[ -x "${script_path}" ]]; then
            was_executable=true
            chmod -x "${script_path}"
        fi
        
        # Mock bash
        # shellcheck disable=SC2317
        bash() {
            return 0
        }
        export -f bash
        
        # Mock execute_sql_query
        # shellcheck disable=SC2317
        execute_sql_query() {
            echo ""
            return 0
        }
        export -f execute_sql_query
        
        # Run check - should succeed (graceful handling)
        run check_boundary_metrics
        
        # Restore permissions if needed
        if [[ "${was_executable}" == "true" ]]; then
            chmod +x "${script_path}"
        fi
        
        # Should succeed (graceful handling - returns 0 with warning)
        assert_success
    else
        # Script doesn't exist, skip test
        skip "collectBoundaryMetrics.sh not found"
    fi
}
