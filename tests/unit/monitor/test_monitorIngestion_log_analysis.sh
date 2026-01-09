#!/usr/bin/env bash
#
# Unit Tests: monitorIngestion.sh - Structured Log Metrics
# Tests check_structured_log_metrics function
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

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
    export DAEMON_LOG_FILE="${TEST_LOG_DIR}/processAPINotesDaemon.log"
    
    # Create test log file
    touch "${DAEMON_LOG_FILE}"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    export INGESTION_LOG_ANALYSIS_WINDOW_HOURS="24"
    export INGESTION_SLOW_STAGE_THRESHOLD_SECONDS="30"
    
    # Mock send_alert using a file to track calls
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_called.txt"
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    export ALERTS_FILE
    
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock get_metric_value
    # shellcheck disable=SC2317
    get_metric_value() {
        local _component="${1}"
        local metric_name="${2}"
        local _metadata="${3:-}"
        
        # Return test values based on metric name
        if [[ "${metric_name}" == "daemon_cycles_failed_count" ]]; then
            echo "0"  # No failed cycles
            return 0
        fi
        
        if [[ "${metric_name}" == "log_slowest_stage_duration_seconds" ]]; then
            echo "15"  # Below threshold
            return 0
        fi
        
        if [[ "${metric_name}" == "log_cycles_frequency_per_hour" ]]; then
            echo "60"  # Normal frequency
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f get_metric_value
    
    # Mock parse_structured_logs
    # shellcheck disable=SC2317
    parse_structured_logs() {
        local log_file="${1}"
        local _time_window="${2}"
        
        if [[ ! -f "${log_file}" ]]; then
            return 1
        fi
        
        # Simulate successful parsing
        return 0
    }
    export -f parse_structured_logs
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/parseStructuredLogs.sh"
    
    # Source monitorIngestion.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorIngestion.sh" 2>/dev/null || true
    
    # Override mocks AFTER sourcing to ensure they are used
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    get_metric_value() {
        local _component="${1}"
        local metric_name="${2}"
        local _metadata="${3:-}"
        
        if [[ "${metric_name}" == "daemon_cycles_failed_count" ]]; then
            echo "0"
            return 0
        fi
        
        if [[ "${metric_name}" == "log_slowest_stage_duration_seconds" ]]; then
            echo "15"
            return 0
        fi
        
        if [[ "${metric_name}" == "log_cycles_frequency_per_hour" ]]; then
            echo "60"
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f get_metric_value
    
    # shellcheck disable=SC2317
    parse_structured_logs() {
        local log_file="${1}"
        local _time_window="${2}"
        
        if [[ ! -f "${log_file}" ]]; then
            return 1
        fi
        
        return 0
    }
    export -f parse_structured_logs
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test_monitorIngestion_log_analysis.log" "test_monitorIngestion_log_analysis"
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "check_structured_log_metrics succeeds when all metrics are healthy" {
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_called.txt"
    : > "${ALERTS_FILE}"
    
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    get_metric_value() {
        local metric_name="${2}"
        
        if [[ "${metric_name}" == "daemon_cycles_failed_count" ]]; then
            echo "0"
        elif [[ "${metric_name}" == "log_slowest_stage_duration_seconds" ]]; then
            echo "15"
        elif [[ "${metric_name}" == "log_cycles_frequency_per_hour" ]]; then
            echo "60"
        else
            echo "0"
        fi
        return 0
    }
    export -f get_metric_value
    
    parse_structured_logs() {
        return 0
    }
    export -f parse_structured_logs
    
    run check_structured_log_metrics
    
    assert_success
    
    # Should not have sent any alerts
    local alerts_count=0
    if [[ -f "${ALERTS_FILE}" ]]; then
        alerts_count=$(wc -l < "${ALERTS_FILE}" | tr -d ' ')
    fi
    assert [[ "${alerts_count}" -eq 0 ]]
}

@test "check_structured_log_metrics alerts when failed cycles detected" {
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_called.txt"
    : > "${ALERTS_FILE}"
    
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    get_metric_value() {
        local metric_name="${2}"
        
        if [[ "${metric_name}" == "daemon_cycles_failed_count" ]]; then
            echo "5"  # Failed cycles detected
        elif [[ "${metric_name}" == "log_slowest_stage_duration_seconds" ]]; then
            echo "15"
        elif [[ "${metric_name}" == "log_cycles_frequency_per_hour" ]]; then
            echo "60"
        else
            echo "0"
        fi
        return 0
    }
    export -f get_metric_value
    
    parse_structured_logs() {
        return 0
    }
    export -f parse_structured_logs
    
    run check_structured_log_metrics
    
    assert_success
    
    # Should have sent alert for failed cycles
    local alerts_found=0
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"cycles_failed"* ]]; then
                alerts_found=$((alerts_found + 1))
            fi
        done < "${ALERTS_FILE}"
    fi
    assert [[ ${alerts_found} -gt 0 ]]
}

@test "check_structured_log_metrics alerts when slow stage detected" {
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_called.txt"
    : > "${ALERTS_FILE}"
    
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    get_metric_value() {
        local metric_name="${2}"
        
        if [[ "${metric_name}" == "daemon_cycles_failed_count" ]]; then
            echo "0"
        elif [[ "${metric_name}" == "log_slowest_stage_duration_seconds" ]]; then
            echo "45"  # Above threshold (30 seconds)
        elif [[ "${metric_name}" == "log_cycles_frequency_per_hour" ]]; then
            echo "60"
        else
            echo "0"
        fi
        return 0
    }
    export -f get_metric_value
    
    parse_structured_logs() {
        return 0
    }
    export -f parse_structured_logs
    
    run check_structured_log_metrics
    
    assert_success
    
    # Should have sent alert for slow stage
    local alerts_found=0
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"slow_stage"* ]]; then
                alerts_found=$((alerts_found + 1))
            fi
        done < "${ALERTS_FILE}"
    fi
    assert [[ ${alerts_found} -gt 0 ]]
}

@test "check_structured_log_metrics alerts when log gap detected" {
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_called.txt"
    : > "${ALERTS_FILE}"
    
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    get_metric_value() {
        local metric_name="${2}"
        
        if [[ "${metric_name}" == "daemon_cycles_failed_count" ]]; then
            echo "0"
        elif [[ "${metric_name}" == "log_slowest_stage_duration_seconds" ]]; then
            echo "15"
        elif [[ "${metric_name}" == "log_cycles_frequency_per_hour" ]]; then
            echo "0"  # No cycles detected (log gap)
        else
            echo "0"
        fi
        return 0
    }
    export -f get_metric_value
    
    parse_structured_logs() {
        return 0
    }
    export -f parse_structured_logs
    
    run check_structured_log_metrics
    
    assert_success
    
    # Should have sent alert for log gap
    local alerts_found=0
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"log_gap"* ]]; then
                alerts_found=$((alerts_found + 1))
            fi
        done < "${ALERTS_FILE}"
    fi
    assert [[ ${alerts_found} -gt 0 ]]
}

@test "check_structured_log_metrics handles missing log file gracefully" {
    # Remove log file
    rm -f "${DAEMON_LOG_FILE}"
    
    run check_structured_log_metrics
    
    assert_success
}

@test "check_structured_log_metrics handles parsing failure gracefully" {
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_called.txt"
    : > "${ALERTS_FILE}"
    
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    parse_structured_logs() {
        return 1  # Simulate parsing failure
    }
    export -f parse_structured_logs
    
    run check_structured_log_metrics
    
    assert_failure
    
    # Should have sent alert for parsing failure
    local alerts_found=0
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"structured_log_parsing_failed"* ]]; then
                alerts_found=$((alerts_found + 1))
            fi
        done < "${ALERTS_FILE}"
    fi
    assert [[ ${alerts_found} -gt 0 ]]
}
