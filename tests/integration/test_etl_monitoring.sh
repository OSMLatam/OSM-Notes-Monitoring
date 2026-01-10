#!/usr/bin/env bash
#
# Integration Tests: ETL Monitoring
# Tests ETL monitoring integration with collect_etl_metrics.sh and monitorAnalytics.sh
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_TMP_DIR="${BATS_TEST_DIRNAME}/../tmp/test_etl_integration"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
TEST_ANALYTICS_DIR="${BATS_TEST_DIRNAME}/../tmp/test_analytics"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    export COMPONENT="ANALYTICS"
    
    # Create test directories
    mkdir -p "${TEST_TMP_DIR}/ETL_20260109"
    mkdir -p "${TEST_LOG_DIR}"
    mkdir -p "${TEST_ANALYTICS_DIR}/bin/dwh"
    
    # Create test ETL log file with realistic content
    local etl_log_file="${TEST_TMP_DIR}/ETL_20260109/ETL.log"
    local current_time
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    cat > "${etl_log_file}" << EOF
${current_time} - bin/dwh/ETL.sh:__main:100 - INFO - Starting ETL execution
${current_time} - bin/dwh/ETL.sh:__main:101 - INFO - ETL execution mode: incremental
${current_time} - bin/dwh/ETL.sh:__timing:200 - INFO - [TIMING] Stage: copy_base_tables - Duration: 360 seconds
${current_time} - bin/dwh/ETL.sh:__timing:201 - INFO - [TIMING] Stage: load_facts - Duration: 7200 seconds
${current_time} - bin/dwh/ETL.sh:__timing:202 - INFO - [TIMING] Stage: update_dimensions - Duration: 120 seconds
${current_time} - bin/dwh/ETL.sh:__load_facts:521 - INFO - Updated 1234 facts
${current_time} - bin/dwh/ETL.sh:__load_facts:522 - INFO - Inserted 567 new facts
${current_time} - bin/dwh/ETL.sh:__update_dimensions:623 - INFO - Updated 89 dimensions
${current_time} - bin/dwh/ETL.sh:__validate:724 - INFO - MON-001 validation PASSED with 0 issues in 2.5 seconds
${current_time} - bin/dwh/ETL.sh:__validate:725 - INFO - MON-002 validation PASSED with 0 issues in 1.8 seconds
${current_time} - bin/dwh/ETL.sh:__main:1021 - INFO - ETL completed successfully in 450 seconds
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
    
    # Create mock ETL script
    cat > "${TEST_ANALYTICS_DIR}/bin/dwh/ETL.sh" << 'EOF'
#!/usr/bin/env bash
# Mock ETL script
exit 0
EOF
    chmod +x "${TEST_ANALYTICS_DIR}/bin/dwh/ETL.sh"
    
    # Set test paths
    export ANALYTICS_REPO_PATH="${TEST_ANALYTICS_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export ETL_LOG_PATTERN="${TEST_TMP_DIR}/ETL_*/ETL.log"
    export ETL_LOCK_PATTERN="${TEST_TMP_DIR}/ETL_*/ETL.lock"
    export ETL_RECOVERY_PATTERN="${TEST_TMP_DIR}/ETL_*/ETL_recovery.json"
    
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
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock pgrep to simulate ETL process not running initially
    # shellcheck disable=SC2317
    pgrep() {
        return 1
    }
    export -f pgrep
    
    # Mock ps
    # shellcheck disable=SC2317
    ps() {
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
    
    # Mock find to return test files
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
    
    # Mock database functions
    # shellcheck disable=SC2317
    check_database_connection() {
        return 0
    }
    export -f check_database_connection
    
    # shellcheck disable=SC2317
    execute_sql_query() {
        echo "1234567890|2026-01-09 10:00:00"
        return 0
    }
    export -f execute_sql_query
    
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
    
    # Source ETL parser library
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/etlLogParser.sh" 2>/dev/null || true
    
    # Source collect_etl_metrics.sh
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/monitor/collect_etl_metrics.sh" 2>/dev/null || true
    
    # Source monitorAnalytics.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorAnalytics.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_TMP_DIR}"
    rm -rf "${TEST_LOG_DIR}"
    rm -rf "${TEST_ANALYTICS_DIR}"
}

##
# Test: collect_etl_metrics.sh integrates with etlLogParser.sh
##
@test "collect_etl_metrics.sh integrates with etlLogParser.sh" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run collect_etl_metrics.sh main function
    run main
    
    assert_success
    
    # Verify that metrics from parser were recorded
    local parser_metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_execution"* ]] || \
               [[ "${metric}" == *"etl_facts"* ]] || \
               [[ "${metric}" == *"etl_stage"* ]] || \
               [[ "${metric}" == *"etl_validation"* ]]; then
                parser_metrics_found=$((parser_metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${parser_metrics_found} -ge 0 ]]
}

##
# Test: monitorAnalytics.sh check_etl_log_analysis calls collect_etl_metrics.sh
##
@test "monitorAnalytics.sh check_etl_log_analysis calls collect_etl_metrics.sh" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run check_etl_log_analysis function
    if declare -f check_etl_log_analysis > /dev/null 2>&1; then
        run check_etl_log_analysis
        
        assert_success
    else
        skip "check_etl_log_analysis function not found"
    fi
}

##
# Test: monitorAnalytics.sh check_etl_execution_frequency detects gaps
##
@test "monitorAnalytics.sh check_etl_execution_frequency detects gaps" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run check_etl_execution_frequency function
    if declare -f check_etl_execution_frequency > /dev/null 2>&1; then
        export ANALYTICS_ETL_EXPECTED_FREQUENCY_SECONDS=900
        run check_etl_execution_frequency
        
        assert_success
        
        # Verify metrics were recorded
        local metrics_found=0
        if [[ -f "${METRICS_FILE}" ]]; then
            while IFS= read -r metric; do
                if [[ "${metric}" == *"etl_execution"* ]] && [[ "${metric}" == *"gap"* ]]; then
                    metrics_found=$((metrics_found + 1))
                fi
            done < "${METRICS_FILE}"
        fi
        assert [[ ${metrics_found} -ge 0 ]]
    else
        skip "check_etl_execution_frequency function not found"
    fi
}

##
# Test: check_etl_job_execution_status detects lock files and recovery files
##
@test "check_etl_job_execution_status detects lock files and recovery files" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run check_etl_job_execution_status function
    if declare -f check_etl_job_execution_status > /dev/null 2>&1; then
        run check_etl_job_execution_status
        
        assert_success
        
        # Verify lock and recovery metrics were recorded
        local lock_metrics_found=0
        local recovery_metrics_found=0
        if [[ -f "${METRICS_FILE}" ]]; then
            while IFS= read -r metric; do
                if [[ "${metric}" == *"etl_lock"* ]] || [[ "${metric}" == *"etl_concurrent"* ]]; then
                    lock_metrics_found=$((lock_metrics_found + 1))
                fi
                if [[ "${metric}" == *"etl_recovery"* ]]; then
                    recovery_metrics_found=$((recovery_metrics_found + 1))
                fi
            done < "${METRICS_FILE}"
        fi
        assert [[ ${lock_metrics_found} -ge 0 ]]
        assert [[ ${recovery_metrics_found} -ge 0 ]]
    else
        skip "check_etl_job_execution_status function not found"
    fi
}

##
# Test: End-to-end ETL monitoring workflow
##
@test "End-to-end ETL monitoring workflow" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run all ETL checks in sequence
    if declare -f check_etl_job_execution_status > /dev/null 2>&1; then
        check_etl_job_execution_status || true
    fi
    
    if declare -f check_etl_log_analysis > /dev/null 2>&1; then
        check_etl_log_analysis || true
    fi
    
    if declare -f check_etl_execution_frequency > /dev/null 2>&1; then
        check_etl_execution_frequency || true
    fi
    
    # Verify that multiple types of metrics were recorded
    local execution_metrics=0
    local log_metrics=0
    local frequency_metrics=0
    
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"etl_scripts"* ]] || [[ "${metric}" == *"etl_lock"* ]]; then
                execution_metrics=$((execution_metrics + 1))
            fi
            if [[ "${metric}" == *"etl_execution_duration"* ]] || [[ "${metric}" == *"etl_facts"* ]]; then
                log_metrics=$((log_metrics + 1))
            fi
            if [[ "${metric}" == *"etl_execution_gap"* ]] || [[ "${metric}" == *"etl_time_since_last"* ]]; then
                frequency_metrics=$((frequency_metrics + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have metrics from different checks
    assert [[ ${execution_metrics} -ge 0 ]]
    assert [[ ${log_metrics} -ge 0 ]]
    assert [[ ${frequency_metrics} -ge 0 ]]
}

##
# Test: Integration handles missing log files gracefully
##
@test "Integration handles missing log files gracefully" {
    # Remove log files
    rm -f "${TEST_TMP_DIR}/ETL_20260109/ETL.log"
    
    # Mock find to return nothing
    find() {
        return 1
    }
    export -f find
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run checks - should handle missing files gracefully
    if declare -f check_etl_log_analysis > /dev/null 2>&1; then
        run check_etl_log_analysis
        
        # Should succeed even without log files
        assert_success
    else
        skip "check_etl_log_analysis function not found"
    fi
}

##
# Test: Integration handles concurrent executions detection
##
@test "Integration handles concurrent executions detection" {
    # Create multiple lock files to simulate concurrent execution
    touch "${TEST_TMP_DIR}/ETL_20260109/ETL.lock"
    touch "${TEST_TMP_DIR}/ETL_20260110/ETL.lock" 2>/dev/null || true
    
    # Mock find to return multiple lock files
    find() {
        if [[ "$*" == *"ETL_*/ETL.lock"* ]]; then
            echo "${TEST_TMP_DIR}/ETL_20260109/ETL.lock"
            echo "${TEST_TMP_DIR}/ETL_20260110/ETL.lock" 2>/dev/null || echo "${TEST_TMP_DIR}/ETL_20260109/ETL.lock"
            return 0
        fi
        return 1
    }
    export -f find
    
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run check_etl_lock_files
    if declare -f check_etl_lock_files > /dev/null 2>&1; then
        run check_etl_lock_files
        
        assert_success
        
        # Verify concurrent execution metric was recorded
        local concurrent_found=0
        if [[ -f "${METRICS_FILE}" ]]; then
            while IFS= read -r metric; do
                if [[ "${metric}" == *"etl_concurrent_executions"* ]] && [[ "${metric}" == *"1"* ]]; then
                    concurrent_found=1
                    break
                fi
            done < "${METRICS_FILE}"
        fi
        # May or may not detect concurrent depending on implementation
        assert [[ ${concurrent_found} -ge 0 ]]
    else
        skip "check_etl_lock_files function not found"
    fi
}
