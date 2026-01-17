#!/usr/bin/env bash
#
# Unit Tests: collectDaemonMetrics.sh
# Tests daemon metrics collection functions
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
TEST_DAEMON_LOG_DIR="/tmp/test_daemon_logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    mkdir -p "${TEST_DAEMON_LOG_DIR}/daemon"
    mkdir -p "/tmp/test_osm_notes_ingestion/locks"
    
    # Set test paths
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    export DAEMON_LOG_FILE="${TEST_DAEMON_LOG_DIR}/daemon/processAPINotesDaemon.log"
    export DAEMON_LOCK_FILE="/tmp/test_osm_notes_ingestion/locks/processAPINotesDaemon.lock"
    export DAEMON_SERVICE_NAME="osm-notes-ingestion-daemon.service"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    
    # Mock database functions
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock record_metric to capture calls (avoid DB calls)
    METRICS_CALLED=()
    # shellcheck disable=SC2317
    record_metric() {
        METRICS_CALLED+=("$*")
        return 0
    }
    export -f record_metric
    
    # Mock psql to avoid DB connections - must be defined before sourcing libraries
    # shellcheck disable=SC2317
    psql() {
        # Return empty result for any query, suppress errors
        echo "" 2>/dev/null
        return 0
    }
    export -f psql
    
    # Mock execute_sql_query to avoid DB connections
    # shellcheck disable=SC2317
    execute_sql_query() {
        return 0
    }
    export -f execute_sql_query
    
    # Mock store_metric to avoid DB calls
    # shellcheck disable=SC2317
    store_metric() {
        return 0
    }
    export -f store_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock systemctl
    # shellcheck disable=SC2317
    systemctl() {
        case "${1}" in
            is-active)
                echo "active"
                return 0
                ;;
            is-enabled)
                echo "enabled"
                return 0
                ;;
            show)
                if [[ "${3}" == "NRestarts" ]]; then
                    echo "NRestarts=0"
                fi
                return 0
                ;;
            list-unit-files)
                echo "osm-notes-ingestion-daemon.service enabled"
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    export -f systemctl
    
    # Mock pgrep
    # shellcheck disable=SC2317
    pgrep() {
        if [[ "${1}" == "-f" ]] && [[ "${2}" == "processAPINotesDaemon" ]]; then
            echo "12345"
            return 0
        fi
        return 1
    }
    export -f pgrep
    
    # Mock ps
    # shellcheck disable=SC2317
    ps() {
        if [[ "${1}" == "-o" ]] && [[ "${2}" == "etime=" ]] && [[ "${3}" == "-p" ]]; then
            echo "01:23:45"
            return 0
        fi
        return 1
    }
    export -f ps
    
    # Mock date
    # shellcheck disable=SC2317
    date() {
        if [[ "${1}" == "+%s" ]]; then
            echo "1704672000"  # Fixed timestamp
            return 0
        elif [[ "${1}" == "-d" ]]; then
            local date_arg="${2}"
            if [[ "${date_arg}" == "1 hour ago" ]]; then
                echo "2026-01-08 21"
                return 0
            elif [[ "${date_arg}" == "60 minutes ago" ]]; then
                echo "1704668400"  # 60 minutes before fixed timestamp
                return 0
            elif [[ "${date_arg}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
                # Parse timestamp and convert to epoch (simplified for testing)
                # For test purposes, return a fixed epoch for any valid timestamp format
                echo "1704672000"
                return 0
            fi
        fi
        # Fallback: try to use real date command if available
        if command -v date >/dev/null 2>&1; then
            command date "$@"
        else
            return 1
        fi
    }
    export -f date
    
    # Source libraries (psql mock must be defined before this)
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Override record_metric after sourcing to use our mock
    # shellcheck disable=SC2317
    record_metric() {
        METRICS_CALLED+=("$*")
        return 0
    }
    export -f record_metric
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test_collectDaemonMetrics.log" "test_collectDaemonMetrics"
    
    # Source collectDaemonMetrics.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collectDaemonMetrics.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
    rm -rf "${TEST_DAEMON_LOG_DIR}"
    rm -rf "/tmp/test_osm_notes_ingestion"
}

##
# Helper: Create daemon log file with cycle information
##
create_daemon_log() {
    local log_content="${1}"
    echo "${log_content}" > "${DAEMON_LOG_FILE}"
}

##
# Helper: Create lock file
##
create_lock_file() {
    touch "${DAEMON_LOCK_FILE}"
}

@test "check_daemon_service_status returns active when service is active" {
    # Mock systemctl to return active
    # shellcheck disable=SC2317
    systemctl() {
        case "${1}" in
            is-active)
                echo "active"
                return 0
                ;;
            is-enabled)
                echo "enabled"
                return 0
                ;;
            list-unit-files)
                echo "osm-notes-ingestion-daemon.service enabled"
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    export -f systemctl
    
    # Run check
    run check_daemon_service_status
    
    # Should succeed and return "active"
    assert_success
    assert_output "active"
}

@test "check_daemon_service_status returns inactive when service is inactive" {
    # Mock systemctl to return inactive
    # shellcheck disable=SC2317
    systemctl() {
        case "${1}" in
            is-active)
                echo "inactive"
                return 0
                ;;
            is-enabled)
                echo "disabled"
                return 0
                ;;
            list-unit-files)
                echo "osm-notes-ingestion-daemon.service disabled"
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }
    export -f systemctl
    
    # Run check
    run check_daemon_service_status
    
    # Should succeed and return "inactive"
    assert_success
    assert_output "inactive"
}

@test "get_daemon_process_info finds process and calculates uptime" {
    # Mock pgrep to return PID
    # shellcheck disable=SC2317
    pgrep() {
        if [[ "${1}" == "-f" ]] && [[ "${2}" == "processAPINotesDaemon" ]]; then
            echo "12345"
            return 0
        fi
        return 1
    }
    export -f pgrep
    
    # Mock ps to return elapsed time
    # shellcheck disable=SC2317
    ps() {
        if [[ "${1}" == "-o" ]] && [[ "${2}" == "etime=" ]] && [[ "${3}" == "-p" ]]; then
            echo "01:23:45"  # 1 hour, 23 minutes, 45 seconds
            return 0
        fi
        return 1
    }
    export -f ps
    
    # Run check
    run get_daemon_process_info
    
    # Should succeed and return PID
    assert_success
    assert_output "12345"
}

@test "get_daemon_process_info returns 0 when process not found" {
    # Mock pgrep to return nothing
    # shellcheck disable=SC2317
    pgrep() {
        return 1
    }
    export -f pgrep
    
    # Run check
    run get_daemon_process_info
    
    # Should succeed but return 0 (no PID)
    assert_success
    assert_output "0"
}

@test "check_daemon_lock_file returns 1 when lock file exists" {
    # Create lock file
    create_lock_file
    
    # Mock stat to return modification time
    # shellcheck disable=SC2317
    stat() {
        if [[ "${1}" == "-c" ]] && [[ "${2}" == "%Y" ]]; then
            echo "1704671700"  # 5 minutes ago
            return 0
        fi
        return 1
    }
    export -f stat
    
    # Run check
    run check_daemon_lock_file
    
    # Should succeed and return 1 (lock exists)
    assert_success
    assert_output "1"
}

@test "check_daemon_lock_file returns 0 when lock file does not exist" {
    # Ensure lock file doesn't exist
    rm -f "${DAEMON_LOCK_FILE}"
    
    # Run check
    run check_daemon_lock_file
    
    # Should succeed and return 0 (no lock)
    assert_success
    assert_output "0"
}

@test "parse_log_timestamp handles basic timestamp format" {
    # Test basic format: YYYY-MM-DD HH:MM:SS
    local test_line="2026-01-08 22:03:26 - INFO - Cycle 3225 completed successfully"
    run parse_log_timestamp "${test_line}"
    
    assert_success
    # Should return a valid epoch timestamp (greater than 0)
    assert [ "${output}" -gt 0 ]
}

@test "parse_log_timestamp handles timestamp with microseconds" {
    # Test format with microseconds: YYYY-MM-DD HH:MM:SS.microseconds
    local test_line="2026-01-08 22:03:26.123456 - INFO - Cycle 3225 completed successfully"
    run parse_log_timestamp "${test_line}"
    
    assert_success
    # Should return a valid epoch timestamp
    assert [ "${output}" -gt 0 ]
}

@test "parse_log_timestamp handles ISO format" {
    # Test ISO format: YYYY-MM-DDTHH:MM:SS
    local test_line="2026-01-08T22:03:26 - INFO - Cycle 3225 completed successfully"
    run parse_log_timestamp "${test_line}"
    
    assert_success
    # Should return a valid epoch timestamp
    assert [ "${output}" -gt 0 ]
}

@test "parse_log_timestamp handles timestamp with timezone" {
    # Test format with timezone: YYYY-MM-DD HH:MM:SS+timezone
    local test_line="2026-01-08 22:03:26+00:00 - INFO - Cycle 3225 completed successfully"
    run parse_log_timestamp "${test_line}"
    
    assert_success
    # Should return a valid epoch timestamp
    assert [ "${output}" -gt 0 ]
}

@test "parse_log_timestamp returns 0 for invalid input" {
    # Test with invalid input
    run parse_log_timestamp ""
    
    assert_success
    assert_output "0"
}

@test "parse_log_timestamp returns 0 for line without timestamp" {
    # Test with line that doesn't contain a timestamp
    local test_line="This is a log line without a timestamp"
    run parse_log_timestamp "${test_line}"
    
    assert_success
    assert_output "0"
}

@test "parse_daemon_cycle_metrics extracts cycle information from logs" {
    # Create log file with cycle completion messages
    create_daemon_log "2026-01-08 22:03:26 - bin/process/processAPINotesDaemon.sh:__daemon_loop:1021 - INFO - Cycle 3225 completed successfully in 10 seconds
2026-01-08 22:04:26 - bin/process/processAPINotesDaemon.sh:__daemon_loop:1021 - INFO - Cycle 3226 completed successfully in 8 seconds
2026-01-08 22:05:26 - bin/process/processAPINotesDaemon.sh:__daemon_loop:1021 - INFO - Cycle 3227 completed successfully in 12 seconds"
    
    # Mock grep to return log lines
    # shellcheck disable=SC2317
    grep() {
        if [[ "${1}" == "-E" ]] && [[ "${2}" == "Cycle [0-9]+ completed successfully in [0-9]+ seconds" ]]; then
            cat "${DAEMON_LOG_FILE}"
            return 0
        fi
        return 1
    }
    export -f grep
    
    # Run check
    run parse_daemon_cycle_metrics
    
    # Should succeed
    assert_success
}

@test "parse_daemon_cycle_metrics handles missing log file gracefully" {
    # Ensure log file doesn't exist
    rm -f "${DAEMON_LOG_FILE}"
    
    # Run check
    run parse_daemon_cycle_metrics
    
    # Should succeed (graceful handling)
    assert_success
}

@test "parse_daemon_processing_metrics extracts processing statistics" {
    # Create log file with processing information
    create_daemon_log "2026-01-08 22:03:20 - INFO - Processed 100 notes (50 new, 50 updated)
2026-01-08 22:03:21 - INFO - Processed 250 comments
2026-01-08 22:03:26 - INFO - Cycle 3225 completed successfully in 10 seconds"
    
    # Mock grep to return log lines
    # shellcheck disable=SC2317
    grep() {
        if [[ "${1}" == "-E" ]] && [[ "${2}" == "Cycle [0-9]+ completed successfully" ]]; then
            echo "2026-01-08 22:03:26 - INFO - Cycle 3225 completed successfully in 10 seconds"
            return 0
        elif [[ "${1}" == "-B" ]] && [[ "${2}" == "50" ]]; then
            cat "${DAEMON_LOG_FILE}"
            return 0
        fi
        return 1
    }
    export -f grep
    
    # Mock sed
    # shellcheck disable=SC2317
    sed() {
        if [[ "${1}" == "-n" ]] && [[ "${2}" == "s/.*in \([0-9]*\) seconds.*/\1/p" ]]; then
            echo "10"
            return 0
        fi
        return 1
    }
    export -f sed
    
    # Run check
    run parse_daemon_processing_metrics
    
    # Should succeed
    assert_success
}

@test "main function runs all checks successfully" {
    # Create daemon log file
    create_daemon_log "2026-01-08 22:03:26 - INFO - Cycle 3225 completed successfully in 10 seconds"
    
    # Create lock file
    create_lock_file
    
    # Mock load_all_configs
    # shellcheck disable=SC2317
    load_all_configs() {
        return 0
    }
    export -f load_all_configs
    
    # Mock grep to return log lines
    # shellcheck disable=SC2317
    grep() {
        if [[ "${1}" == "-E" ]] && [[ "${2}" == "Cycle [0-9]+ completed successfully in [0-9]+ seconds" ]]; then
            cat "${DAEMON_LOG_FILE}"
            return 0
        elif [[ "${1}" == "-E" ]] && [[ "${2}" == "Cycle [0-9]+ completed successfully" ]]; then
            cat "${DAEMON_LOG_FILE}"
            return 0
        fi
        return 1
    }
    export -f grep
    
    # Mock stat
    # shellcheck disable=SC2317
    stat() {
        if [[ "${1}" == "-c" ]] && [[ "${2}" == "%Y" ]]; then
            echo "1704672000"
            return 0
        fi
        return 1
    }
    export -f stat
    
    # Run main function
    run main
    
    # Should succeed
    assert_success
}

@test "main function handles missing configuration gracefully" {
    # Mock load_all_configs to fail
    # shellcheck disable=SC2317
    load_all_configs() {
        return 1
    }
    export -f load_all_configs
    
    # Run main function
    run main
    
    # Should fail gracefully
    assert_failure
}
