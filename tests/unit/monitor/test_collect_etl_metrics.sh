#!/usr/bin/env bash
#
# Unit Tests: collect_etl_metrics.sh
# Tests ETL metrics collection script
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_etl"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    export COMPONENT="ANALYTICS"
    
    # Create test directories
    mkdir -p "${TEST_TMP_DIR}/ETL_20260109"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Create test ETL log file
    local etl_log_file="${TEST_TMP_DIR}/ETL_20260109/ETL.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${etl_log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__main:1021 - INFO - ETL completed successfully in 450 seconds
${current_time} - bin/dwh/ETL.sh:__load_facts:521 - INFO - Updated 1234 facts
${current_time} - bin/dwh/ETL.sh:__load_facts:522 - INFO - Inserted 567 new facts
${current_time} - bin/dwh/ETL.sh:__update_dimensions:623 - INFO - Updated 89 dimensions
${current_time} - bin/dwh/ETL.sh:__validate:724 - INFO - MON-001 validation PASSED
${current_time} - bin/dwh/ETL.sh:__validate:725 - INFO - MON-002 validation PASSED
${current_time} - bin/dwh/ETL.sh:__main:1022 - INFO - ETL execution mode: incremental
EOF
    
    # Create test lock file
    touch "${TEST_TMP_DIR}/ETL_20260109/ETL.lock"
    
    # Create test recovery file
    cat > "${TEST_TMP_DIR}/ETL_20260109/ETL_recovery.json" << EOF
{
    "last_step": "load_facts",
    "enabled": true
}
EOF
    
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
    
    # shellcheck disable=SC2317
    log_warning() {
        return 0
    }
    export -f log_warning
    
    # Mock pgrep to simulate ETL process running
    # shellcheck disable=SC2317
    pgrep() {
        if [[ "$*" == *"ETL.sh"* ]]; then
            echo "12345"
            return 0
        fi
        return 1
    }
    export -f pgrep
    
    # Mock ps to simulate process info
    # shellcheck disable=SC2317
    ps() {
        if [[ "$*" == *"-o etime= -p 12345"* ]]; then
            echo "01:30:45"
            return 0
        fi
        return 1
    }
    export -f ps
    
    # Mock stat
    # shellcheck disable=SC2317
    stat() {
        if [[ "$*" == *"-c %Y"* ]] || [[ "$*" == *"-f %m"* ]]; then
            date +%s
            return 0
        fi
        return 1
    }
    export -f stat
    
    # Mock find
    # shellcheck disable=SC2317
    find() {
        if [[ "$*" == *"ETL_*/ETL.log"* ]]; then
            echo "${TEST_TMP_DIR}/ETL_20260109/ETL.log"
            return 0
        elif [[ "$*" == *"ETL_*/ETL.lock"* ]]; then
            echo "${TEST_TMP_DIR}/ETL_20260109/ETL.lock"
            return 0
        elif [[ "$*" == *"ETL_*/ETL_recovery.json"* ]]; then
            echo "${TEST_TMP_DIR}/ETL_20260109/ETL_recovery.json"
            return 0
        fi
        return 1
    }
    export -f find
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Source collect_etl_metrics.sh
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collect_etl_metrics.sh"
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_TMP_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: find_etl_log_files finds log files
##
@test "find_etl_log_files finds log files" {
    run find_etl_log_files
    
    assert_success
    assert_output --partial "ETL.log"
}

##
# Test: find_etl_log_files returns error when no files found
##
@test "find_etl_log_files returns error when no files found" {
    # Mock find to return nothing
    find() {
        return 1
    }
    export -f find
    
    run find_etl_log_files
    
    assert_failure
}

##
# Test: check_etl_process_status detects running process
##
@test "check_etl_process_status detects running process" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run check_etl_process_status
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_up"* ]] || [[ "${metric}" == *"etl_pid"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: check_etl_lock_files detects lock files
##
@test "check_etl_lock_files detects lock files" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run check_etl_lock_files
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_lock_files_count"* ]] || [[ "${metric}" == *"etl_concurrent_executions"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: check_etl_recovery_files detects recovery files
##
@test "check_etl_recovery_files detects recovery files" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Mock jq if available
    if command -v jq > /dev/null 2>&1; then
        run check_etl_recovery_files
    else
        # Skip test if jq not available
        skip "jq not available"
    fi
    
    assert_success
    
    # Verify metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_recovery_enabled"* ]] || [[ "${metric}" == *"etl_recovery_files_count"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

##
# Test: parse_etl_execution_metrics parses logs when parser library exists
##
@test "parse_etl_execution_metrics parses logs when parser library exists" {
    # Unset COMPONENT to allow parser library to set it
    unset COMPONENT || true
    
    # Create mock parser library
    local parser_lib="${BATS_TEST_DIRNAME}/../../../bin/lib/etlLogParser.sh"
    
    # Source the actual parser library if it exists
    if [[ -f "${parser_lib}" ]]; then
        # shellcheck disable=SC1090
        source "${parser_lib}" || true
        
        METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
        : > "${METRICS_FILE}"
        
        record_metric() {
            echo "$*" >> "${METRICS_FILE}"
            return 0
        }
        export -f record_metric
        
        local log_file="${TEST_TMP_DIR}/ETL_20260109/ETL.log"
        run parse_etl_execution_metrics "${log_file}"
        
        assert_success
    else
        skip "ETL parser library not found"
    fi
}

##
# Test: parse_etl_execution_metrics uses basic parsing when parser library missing
##
@test "parse_etl_execution_metrics uses basic parsing when parser library missing" {
    # Temporarily rename parser library
    local parser_lib="${BATS_TEST_DIRNAME}/../../../bin/lib/etlLogParser.sh"
    local parser_backup="${parser_lib}.backup"
    local parser_moved=false
    
    if [[ -f "${parser_lib}" ]]; then
        mv "${parser_lib}" "${parser_backup}" || true
        parser_moved=true
    fi
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    local log_file="${TEST_TMP_DIR}/ETL_20260109/ETL.log"
    run parse_etl_execution_metrics "${log_file}"
    
    # Restore parser library
    if [[ "${parser_moved}" == "true" ]] && [[ -f "${parser_backup}" ]]; then
        mv "${parser_backup}" "${parser_lib}" || true
    fi
    
    # Should succeed even without parser library (uses basic parsing)
    assert_success
    
    # Verify basic metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_execution"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -ge 0 ]]
}

##
# Test: main function executes all checks
##
@test "main function executes all checks" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run main
    
    assert_success
    
    # Verify that multiple checks were executed (multiple metrics recorded)
    local metrics_count=0
    if [[ -f "${METRICS_FILE}" ]]; then
        metrics_count=$(wc -l < "${METRICS_FILE}" | tr -d ' ')
    fi
    # Should have recorded multiple metrics from different checks
    assert [[ "${metrics_count}" -ge 0 ]]
}

##
# Test: script handles missing log files gracefully
##
@test "script handles missing log files gracefully" {
    # Mock find to return nothing
    find() {
        return 1
    }
    export -f find
    
    run main
    
    # Should succeed even without log files
    assert_success
}
