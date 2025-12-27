#!/usr/bin/env bash
#
# Monitor Test Execution
# Monitors the progress of tests running in background
#
# Version: 1.0.0
# Date: 2025-12-27
#

set -euo pipefail

LOG_FILE="${1:-/tmp/test_results.log}"
CHECK_INTERVAL="${2:-5}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if test process is running
##
is_test_running() {
    pgrep -f "run_all_tests.sh" > /dev/null 2>&1
}

##
# Show current progress
##
show_progress() {
    local current_line
    current_line=$(wc -l < "${LOG_FILE}" 2>/dev/null || echo "0")
    
    print_message "${BLUE}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "${BLUE}" "Monitoring test execution..."
    print_message "${BLUE}" "Log file: ${LOG_FILE}"
    print_message "${BLUE}" "Lines logged: ${current_line}"
    print_message "${BLUE}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Show last 10 lines
    if [[ -f "${LOG_FILE}" ]] && [[ ${current_line} -gt 0 ]]; then
        print_message "${GREEN}" "Last 10 lines:"
        tail -10 "${LOG_FILE}" 2>/dev/null || true
    else
        print_message "${YELLOW}" "Log file not found or empty yet..."
    fi
    echo
}

##
# Show summary when tests complete
##
show_summary() {
    print_message "${GREEN}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "${GREEN}" "Tests completed!"
    print_message "${GREEN}" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Extract summary from log
    if grep -q "TEST SUMMARY" "${LOG_FILE}" 2>/dev/null; then
        print_message "${BLUE}" "Final Summary:"
        grep -A 10 "TEST SUMMARY" "${LOG_FILE}" | tail -15
    else
        print_message "${YELLOW}" "Summary not found in log yet. Showing last 30 lines:"
        tail -30 "${LOG_FILE}" 2>/dev/null || true
    fi
}

##
# Main monitoring loop
##
main() {
    print_message "${GREEN}" "Starting test monitor..."
    print_message "${BLUE}" "Checking every ${CHECK_INTERVAL} seconds"
    echo
    
    local start_time
    start_time=$(date +%s)
    local last_line_count=0
    
    while is_test_running; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        
        clear
        print_message "${GREEN}" "═══════════════════════════════════════════════════════════"
        print_message "${GREEN}" "  Test Monitor - Running for ${minutes}m ${seconds}s"
        print_message "${GREEN}" "═══════════════════════════════════════════════════════════"
        echo
        
        # Check if log file is growing
        local current_line_count
        current_line_count=$(wc -l < "${LOG_FILE}" 2>/dev/null || echo "0")
        
        if [[ ${current_line_count} -gt ${last_line_count} ]]; then
            print_message "${GREEN}" "✓ Tests are progressing (${current_line_count} lines logged)"
        else
            print_message "${YELLOW}" "⚠ No new output in last check"
        fi
        last_line_count=${current_line_count}
        
        show_progress
        
        print_message "${BLUE}" "Press Ctrl+C to stop monitoring (tests will continue)"
        sleep "${CHECK_INTERVAL}"
    done
    
    # Tests completed
    clear
    show_summary
    
    # Check exit code
    if grep -q "ALL TESTS PASSED" "${LOG_FILE}" 2>/dev/null; then
        print_message "${GREEN}" "✓ All tests passed!"
        exit 0
    elif grep -q "SOME TESTS FAILED" "${LOG_FILE}" 2>/dev/null; then
        print_message "${RED}" "✗ Some tests failed"
        exit 1
    else
        print_message "${YELLOW}" "⚠ Could not determine final status"
        exit 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

