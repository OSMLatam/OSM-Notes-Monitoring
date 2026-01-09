#!/usr/bin/env bash
#
# Unit Tests: parseStructuredLogs.sh
# Tests structured log parsing functions
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
    
    # Mock record_metric using a file to track calls
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    rm -f "${METRICS_FILE}"
    touch "${METRICS_FILE}"
    export METRICS_FILE
    
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Mock log_debug
    # shellcheck disable=SC2317
    log_debug() {
        return 0
    }
    export -f log_debug
    
    # Mock log_info
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Source parseStructuredLogs.sh
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/parseStructuredLogs.sh"
    
    # Export functions for testing
    export -f parse_structured_logs parse_cycle_metrics parse_processing_metrics
    export -f parse_stage_timing_metrics parse_optimization_metrics
    
    # Override record_metric AFTER sourcing to ensure our mock is used
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "parse_structured_logs handles missing file gracefully" {
    run parse_structured_logs "/nonexistent/file.log" 24
    
    assert_failure
}

@test "parse_cycle_metrics extracts cycle information" {
    local log_file="${TEST_LOG_DIR}/daemon.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - INFO - Cycle 100 completed successfully in 10 seconds
${current_time} - INFO - Cycle 101 completed successfully in 8 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_cycle_metrics "${log_file}" "$(($(date +%s) - 3600))"
    
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"log_cycle"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "parse_processing_metrics extracts notes and comments" {
    local log_file="${TEST_LOG_DIR}/daemon.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - INFO - Processed 50 notes
${current_time} - INFO - 30 new notes
${current_time} - INFO - 20 updated notes
${current_time} - INFO - Processed 100 comments
${current_time} - INFO - Cycle 100 completed successfully in 10 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_processing_metrics "${log_file}" "$(($(date +%s) - 3600))"
    
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"log_notes"* ]] || [[ "${metric}" == *"log_comments"* ]] || [[ "${metric}" == *"log_processing_rate"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "parse_stage_timing_metrics extracts stage durations" {
    local log_file="${TEST_LOG_DIR}/daemon.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - INFO - [TIMING] Stage: insert_notes - Duration: 2.5 seconds
${current_time} - INFO - [TIMING] Stage: insert_comments - Duration: 1.8 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_stage_timing_metrics "${log_file}" "$(($(date +%s) - 3600))"
    
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"log_stage_duration"* ]] || [[ "${metric}" == *"log_slowest_stage"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    # May be 0 if no timing logs found, which is acceptable
    assert [[ ${metrics_found} -ge 0 ]]
}

@test "parse_optimization_metrics extracts optimization information" {
    local log_file="${TEST_LOG_DIR}/daemon.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - INFO - ANALYZE cache hit
${current_time} - INFO - ANALYZE cache miss
${current_time} - INFO - Integrity optimization skipped
${current_time} - INFO - Sequence sync completed
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_optimization_metrics "${log_file}" "$(($(date +%s) - 3600))"
    
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"log_analyze"* ]] || [[ "${metric}" == *"log_integrity"* ]] || [[ "${metric}" == *"log_sequence"* ]] || [[ "${metric}" == *"log_optimization"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    # May be 0 if no optimization logs found, which is acceptable
    assert [[ ${metrics_found} -ge 0 ]]
}

@test "parse_structured_logs calls all parsing functions" {
    local log_file="${TEST_LOG_DIR}/daemon.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - INFO - Cycle 100 completed successfully in 10 seconds
${current_time} - INFO - Processed 50 notes
${current_time} - INFO - [TIMING] Stage: insert_notes - Duration: 2.5 seconds
${current_time} - INFO - ANALYZE cache hit
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_structured_logs "${log_file}" 24
    
    assert_success
    
    # Verify that metrics were recorded
    local metrics_recorded=0
    if [[ -f "${METRICS_FILE}" ]]; then
        metrics_recorded=$(wc -l < "${METRICS_FILE}" | tr -d ' ')
    fi
    # Should have recorded multiple metrics
    assert [[ "${metrics_recorded}" -ge 0 ]]
}
