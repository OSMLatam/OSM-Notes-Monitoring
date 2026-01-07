#!/usr/bin/env bash
#
# Run bashcov in background and monitor progress
#
# Version: 1.0.0
# Date: 2026-01-02
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Output directories
readonly COVERAGE_DIR="${PROJECT_ROOT}/coverage"
readonly BASHCOV_OUTPUT="${COVERAGE_DIR}/bashcov"
readonly LOG_FILE="${COVERAGE_DIR}/bashcov_background.log"
readonly PID_FILE="${COVERAGE_DIR}/bashcov.pid"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if bashcov is running
##
is_bashcov_running() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || echo "")
        if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
            return 0
        else
            rm -f "${PID_FILE}"
            return 1
        fi
    fi
    return 1
}

##
# Start bashcov in background
##
start_bashcov() {
    if is_bashcov_running; then
        print_message "${YELLOW}" "bashcov is already running (PID: $(cat "${PID_FILE}"))"
        return 1
    fi
    
    print_message "${BLUE}" "Starting bashcov in background..."
    
    # Create directories
    mkdir -p "${COVERAGE_DIR}"
    mkdir -p "${BASHCOV_OUTPUT}/all"
    
    # Run bashcov in background
    # Redirect stdin to /dev/null to prevent password prompts from psql
    nohup bash "${SCRIPT_DIR}/generate_coverage_instrumented_optimized.sh" </dev/null > "${LOG_FILE}" 2>&1 &
    local pid=$!
    
    # Save PID
    echo "${pid}" > "${PID_FILE}"
    
    print_message "${GREEN}" "✓ bashcov started in background (PID: ${pid})"
    print_message "${BLUE}" "Log file: ${LOG_FILE}"
    print_message "${BLUE}" "PID file: ${PID_FILE}"
    echo ""
    print_message "${YELLOW}" "Use 'bash scripts/monitor_bashcov.sh' to monitor progress"
}

##
# Monitor bashcov progress
##
monitor_bashcov() {
    if ! is_bashcov_running; then
        print_message "${YELLOW}" "bashcov is not running"
        return 1
    fi
    
    local pid
    pid=$(cat "${PID_FILE}")
    
    print_message "${BLUE}" "Monitoring bashcov (PID: ${pid})..."
    echo ""
    
    # Count test files
    local total_tests
    total_tests=$(find "${PROJECT_ROOT}/tests" -name "*.sh" -type f 2>/dev/null | wc -l)
    
    while is_bashcov_running; do
        # Count processed tests from log
        local processed=0
        if [[ -f "${LOG_FILE}" ]]; then
            # Use grep without -c and count lines manually to avoid issues
            local grep_result
            grep_result=$(grep "Processed.*test files" "${LOG_FILE}" 2>/dev/null | wc -l || echo "0")
            # Clean result: remove whitespace and ensure it's a number
            grep_result=$(echo "${grep_result}" | tr -d '[:space:]')
            if [[ -z "${grep_result}" ]] || ! [[ "${grep_result}" =~ ^[0-9]+$ ]]; then
                grep_result="0"
            fi
            processed=$((grep_result * 10))  # Progress shown every 10 tests
        fi
        
        # Check resultset file size
        local resultset_size="0"
        if [[ -f "${COVERAGE_DIR}/.resultset.json" ]]; then
            local du_result
            du_result=$(du -h "${COVERAGE_DIR}/.resultset.json" 2>/dev/null | cut -f1 || echo "0")
            # Clean result: remove whitespace
            du_result=$(echo "${du_result}" | tr -d '[:space:]')
            if [[ -n "${du_result}" ]]; then
                resultset_size="${du_result}"
            fi
        fi
        
        # Show progress
        printf "\r${BLUE}Progress: ${processed}/${total_tests} tests | Results: ${resultset_size}${NC}"
        
        sleep 2
    done
    
    echo ""
    echo ""
    
    if [[ -f "${COVERAGE_DIR}/coverage_report_instrumented.txt" ]]; then
        print_message "${GREEN}" "✓ bashcov completed!"
        print_message "${BLUE}" "Report: ${COVERAGE_DIR}/coverage_report_instrumented.txt"
        tail -20 "${COVERAGE_DIR}/coverage_report_instrumented.txt"
    else
        print_message "${YELLOW}" "bashcov finished but report not found. Check log: ${LOG_FILE}"
    fi
}

##
# Stop bashcov
##
stop_bashcov() {
    if ! is_bashcov_running; then
        print_message "${YELLOW}" "bashcov is not running"
        return 1
    fi
    
    local pid
    pid=$(cat "${PID_FILE}")
    
    print_message "${BLUE}" "Stopping bashcov (PID: ${pid})..."
    kill "${pid}" 2>/dev/null || true
    
    # Wait a bit
    sleep 2
    
    if ps -p "${pid}" >/dev/null 2>&1; then
        print_message "${YELLOW}" "Process still running, force killing..."
        kill -9 "${pid}" 2>/dev/null || true
    fi
    
    rm -f "${PID_FILE}"
    print_message "${GREEN}" "✓ bashcov stopped"
}

##
# Show status
##
show_status() {
    if is_bashcov_running; then
        local pid
        pid=$(cat "${PID_FILE}")
        print_message "${GREEN}" "bashcov is running (PID: ${pid})"
        
        # Show log tail
        if [[ -f "${LOG_FILE}" ]]; then
            echo ""
            print_message "${BLUE}" "Last 10 lines of log:"
            tail -10 "${LOG_FILE}"
        fi
    else
        print_message "${YELLOW}" "bashcov is not running"
        
        if [[ -f "${LOG_FILE}" ]]; then
            echo ""
            print_message "${BLUE}" "Last 20 lines of log:"
            tail -20 "${LOG_FILE}"
        fi
    fi
}

##
# Main
##
main() {
    case "${1:-status}" in
        start)
            start_bashcov
            ;;
        monitor)
            monitor_bashcov
            ;;
        stop)
            stop_bashcov
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 {start|monitor|stop|status}"
            echo ""
            echo "Commands:"
            echo "  start   - Start bashcov in background"
            echo "  monitor - Monitor bashcov progress"
            echo "  stop    - Stop running bashcov"
            echo "  status  - Show current status"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
