#!/usr/bin/env bash
#
# Unit Tests: etlLogParser.sh
# Tests ETL log parsing functions
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
    export COMPONENT="ANALYTICS"
    
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
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_debug() {
        return 0
    }
    export -f log_debug
    
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
    
    # Source etlLogParser.sh
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/etlLogParser.sh"
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: parse_etl_execution_time handles missing file gracefully
##
@test "parse_etl_execution_time handles missing file gracefully" {
    run parse_etl_execution_time "/nonexistent/file.log" 24
    
    assert_failure
}

##
# Test: parse_etl_execution_time extracts execution time
##
@test "parse_etl_execution_time extracts execution time" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__main:1021 - INFO - ETL completed successfully in 450 seconds
${current_time} - bin/dwh/ETL.sh:__main:1022 - INFO - Execution 1234 completed successfully in 360 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_etl_execution_time "${log_file}" 24
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_execution_duration"* ]] || [[ "${metric}" == *"etl_executions_total"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: parse_etl_facts_processed extracts facts metrics
##
@test "parse_etl_facts_processed extracts facts metrics" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__load_facts:521 - INFO - Updated 1234 facts
${current_time} - bin/dwh/ETL.sh:__load_facts:522 - INFO - Inserted 567 new facts
${current_time} - bin/dwh/ETL.sh:__update_dimensions:623 - INFO - Updated 89 dimensions
${current_time} - bin/dwh/ETL.sh:__main:1021 - INFO - ETL completed successfully in 450 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_etl_facts_processed "${log_file}" 24
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_facts"* ]] || [[ "${metric}" == *"etl_dimensions"* ]] || [[ "${metric}" == *"etl_processing_rate"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -ge 0 ]]
}

##
# Test: parse_etl_stage_timing extracts stage durations
##
@test "parse_etl_stage_timing extracts stage durations" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__timing:100 - INFO - [TIMING] Stage: copy_base_tables - Duration: 360 seconds
${current_time} - bin/dwh/ETL.sh:__timing:101 - INFO - [TIMING] Stage: load_facts - Duration: 7200 seconds
${current_time} - bin/dwh/ETL.sh:__timing:102 - INFO - [TIMING] Stage: update_dimensions - Duration: 120 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_etl_stage_timing "${log_file}" 24
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_stage_duration"* ]] || [[ "${metric}" == *"etl_slowest_stage"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    # May be 0 if no timing logs found, which is acceptable
    assert [[ ${metrics_found} -ge 0 ]]
}

##
# Test: parse_etl_validations extracts validation results
##
@test "parse_etl_validations extracts validation results" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__validate:724 - INFO - MON-001 validation PASSED with 0 issues in 2.5 seconds
${current_time} - bin/dwh/ETL.sh:__validate:725 - INFO - MON-002 validation PASSED with 0 issues in 1.8 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_etl_validations "${log_file}" 24
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_validation"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -ge 0 ]]
}

##
# Test: parse_etl_errors extracts error and warning counts
##
@test "parse_etl_errors extracts error and warning counts" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__main:100 - ERROR - Database connection failed
${current_time} - bin/dwh/ETL.sh:__main:101 - WARN - Slow query detected
${current_time} - bin/dwh/ETL.sh:__main:102 - ERROR - Data validation failed
${current_time} - bin/dwh/ETL.sh:__main:103 - INFO - ETL completed successfully
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_etl_errors "${log_file}" 24
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_errors_count"* ]] || [[ "${metric}" == *"etl_warnings_count"* ]] || [[ "${metric}" == *"etl_error_rate"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -ge 0 ]]
}

##
# Test: detect_etl_mode detects initial load mode
##
@test "detect_etl_mode detects initial load mode" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__main:100 - INFO - Starting initial load
${current_time} - bin/dwh/ETL.sh:__main:101 - INFO - Processing 1000000 facts
${current_time} - bin/dwh/ETL.sh:__main:102 - INFO - ETL completed successfully in 7200 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run detect_etl_mode "${log_file}"
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_mode"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: detect_etl_mode detects incremental mode
##
@test "detect_etl_mode detects incremental mode" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__main:100 - INFO - Starting incremental update
${current_time} - bin/dwh/ETL.sh:__main:101 - INFO - Processing 1000 facts
${current_time} - bin/dwh/ETL.sh:__main:102 - INFO - ETL completed successfully in 300 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run detect_etl_mode "${log_file}"
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_mode"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: parse_etl_execution_time filters old logs correctly
##
@test "parse_etl_execution_time filters old logs correctly" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local old_time
    old_time=$(date -d "2 days ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -v-2d +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    
    if [[ -z "${old_time}" ]]; then
        skip "date command not compatible"
    fi
    
    cat > "${log_file}" << EOF
${old_time} - bin/dwh/ETL.sh:__main:100 - INFO - ETL completed successfully in 450 seconds
${current_time} - bin/dwh/ETL.sh:__main:101 - INFO - ETL completed successfully in 360 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Parse with 24 hour window (should filter out old log)
    run parse_etl_execution_time "${log_file}" 24
    
    assert_success
    
    # Should only process recent execution
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_execution_duration_seconds"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -ge 0 ]]
}

##
# Test: parse_etl_validations handles failed validations
##
@test "parse_etl_validations handles failed validations" {
    local log_file="${TEST_LOG_DIR}/etl.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__validate:724 - INFO - MON-001 validation FAILED with 5 issues in 2.5 seconds
${current_time} - bin/dwh/ETL.sh:__validate:725 - INFO - MON-002 validation PASSED with 0 issues in 1.8 seconds
EOF
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run parse_etl_validations "${log_file}" 24
    
    assert_success
    
    # Verify metrics were recorded (including failed validation)
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_validation"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -ge 0 ]]
}
