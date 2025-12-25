#!/usr/bin/env bash
#
# Logging Performance Tests
# Tests logging performance and impact
#
# Version: 1.0.0
# Date: 2025-12-24
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test log directory
readonly TEST_LOG_DIR="${PROJECT_ROOT}/tests/tmp/logs"
readonly TEST_LOG_FILE="${TEST_LOG_DIR}/performance.log"

# Test parameters
readonly ITERATIONS=10000
readonly BATCH_SIZE=100

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Cleanup test files
##
cleanup() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Setup test environment
##
setup_test() {
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_FILE}"
    rm -f "${TEST_LOG_FILE}"
}

##
# Get current time in milliseconds
##
get_time_ms() {
    date +%s%3N 2>/dev/null || date +%s000
}

##
# Test single log write performance
##
test_single_log_performance() {
    print_message "${BLUE}" "\n=== Testing Single Log Write Performance ==="
    
    setup_test
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    local start_time
    start_time=$(get_time_ms)
    
    for ((i=1; i<=ITERATIONS; i++)); do
        log_info "Test message ${i}"
    done
    
    local end_time
    end_time=$(get_time_ms)
    local duration=$((end_time - start_time))
    local avg_time=$((duration / ITERATIONS))
    
    print_message "${GREEN}" "  Total time: ${duration}ms"
    print_message "${GREEN}" "  Iterations: ${ITERATIONS}"
    print_message "${GREEN}" "  Average time per log: ${avg_time}ms"
    print_message "${GREEN}" "  Logs per second: $((ITERATIONS * 1000 / duration))"
    
    # Verify log file size
    local file_size
    file_size=$(stat -f%z "${TEST_LOG_FILE}" 2>/dev/null || stat -c%s "${TEST_LOG_FILE}" 2>/dev/null || echo "0")
    print_message "${GREEN}" "  Log file size: ${file_size} bytes"
}

##
# Test batch log write performance
##
test_batch_log_performance() {
    print_message "${BLUE}" "\n=== Testing Batch Log Write Performance ==="
    
    setup_test
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    local start_time
    start_time=$(get_time_ms)
    
    local batch_count=$((ITERATIONS / BATCH_SIZE))
    
    for ((batch=1; batch<=batch_count; batch++)); do
        for ((i=1; i<=BATCH_SIZE; i++)); do
            log_info "Batch ${batch}, message ${i}"
        done
    done
    
    local end_time
    end_time=$(get_time_ms)
    local duration=$((end_time - start_time))
    local avg_time=$((duration / ITERATIONS))
    
    print_message "${GREEN}" "  Total time: ${duration}ms"
    print_message "${GREEN}" "  Iterations: ${ITERATIONS}"
    print_message "${GREEN}" "  Batch size: ${BATCH_SIZE}"
    print_message "${GREEN}" "  Average time per log: ${avg_time}ms"
    print_message "${GREEN}" "  Logs per second: $((ITERATIONS * 1000 / duration))"
}

##
# Test log level filtering performance
##
test_log_level_filtering() {
    print_message "${BLUE}" "\n=== Testing Log Level Filtering Performance ==="
    
    setup_test
    export LOG_LEVEL="${LOG_LEVEL_WARNING}"
    
    local start_time
    start_time=$(get_time_ms)
    
    # Log messages at different levels
    for ((i=1; i<=ITERATIONS; i++)); do
        log_debug "Debug message ${i}"
        log_info "Info message ${i}"
        log_warning "Warning message ${i}"
        log_error "Error message ${i}"
    done
    
    local end_time
    end_time=$(get_time_ms)
    local duration=$((end_time - start_time))
    
    # Count actual log entries (should only have WARNING and ERROR)
    local log_count
    log_count=$(wc -l < "${TEST_LOG_FILE}" 2>/dev/null || echo "0")
    local expected_count=$((ITERATIONS * 2))  # WARNING + ERROR
    
    print_message "${GREEN}" "  Total time: ${duration}ms"
    print_message "${GREEN}" "  Messages logged: ${log_count}"
    print_message "${GREEN}" "  Expected: ${expected_count} (WARNING + ERROR)"
    print_message "${GREEN}" "  Filtering overhead: $((duration / ITERATIONS))ms per message"
}

##
# Test concurrent logging performance
##
test_concurrent_logging() {
    print_message "${BLUE}" "\n=== Testing Concurrent Logging Performance ==="
    
    setup_test
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    local num_processes=10
    local messages_per_process=$((ITERATIONS / num_processes))
    
    local start_time
    start_time=$(get_time_ms)
    
    # Create multiple processes logging simultaneously
    local pids=()
    for ((p=1; p<=num_processes; p++)); do
        (
            for ((i=1; i<=messages_per_process; i++)); do
                log_info "Process ${p}, message ${i}"
            done
        ) &
        pids+=($!)
    done
    
    # Wait for all processes
    for pid in "${pids[@]}"; do
        wait "${pid}"
    done
    
    local end_time
    end_time=$(get_time_ms)
    local duration=$((end_time - start_time))
    
    local log_count
    log_count=$(wc -l < "${TEST_LOG_FILE}" 2>/dev/null || echo "0")
    
    print_message "${GREEN}" "  Total time: ${duration}ms"
    print_message "${GREEN}" "  Processes: ${num_processes}"
    print_message "${GREEN}" "  Messages per process: ${messages_per_process}"
    print_message "${GREEN}" "  Total messages: ${log_count}"
    print_message "${GREEN}" "  Average time per message: $((duration / ITERATIONS))ms"
}

##
# Test log file size impact
##
test_log_file_size_impact() {
    print_message "${BLUE}" "\n=== Testing Log File Size Impact ==="
    
    setup_test
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    local sizes=(100 1000 10000 100000)
    
    for size in "${sizes[@]}"; do
        rm -f "${TEST_LOG_FILE}"
        
        local start_time
        start_time=$(get_time_ms)
        
        for ((i=1; i<=size; i++)); do
            log_info "Test message ${i}"
        done
        
        local end_time
        end_time=$(get_time_ms)
        local duration=$((end_time - start_time))
        
        local file_size
        file_size=$(stat -f%z "${TEST_LOG_FILE}" 2>/dev/null || stat -c%s "${TEST_LOG_FILE}" 2>/dev/null || echo "0")
        
        print_message "${GREEN}" "  Size: ${size} messages"
        print_message "${GREEN}" "    Time: ${duration}ms"
        print_message "${GREEN}" "    File size: ${file_size} bytes"
        print_message "${GREEN}" "    Time per message: $((duration / size))ms"
    done
}

##
# Test different log levels performance
##
test_log_levels_performance() {
    print_message "${BLUE}" "\n=== Testing Different Log Levels Performance ==="
    
    local levels=("DEBUG" "INFO" "WARNING" "ERROR")
    
    for level in "${levels[@]}"; do
        setup_test
        
        case "${level}" in
            DEBUG)
                export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
                ;;
            INFO)
                export LOG_LEVEL="${LOG_LEVEL_INFO}"
                ;;
            WARNING)
                export LOG_LEVEL="${LOG_LEVEL_WARNING}"
                ;;
            ERROR)
                export LOG_LEVEL="${LOG_LEVEL_ERROR}"
                ;;
        esac
        
        local start_time
        start_time=$(get_time_ms)
        
        # Log all levels
        for ((i=1; i<=ITERATIONS; i++)); do
            log_debug "Debug ${i}"
            log_info "Info ${i}"
            log_warning "Warning ${i}"
            log_error "Error ${i}"
        done
        
        local end_time
        end_time=$(get_time_ms)
        local duration=$((end_time - start_time))
        
        local log_count
        log_count=$(wc -l < "${TEST_LOG_FILE}" 2>/dev/null || echo "0")
        
        print_message "${GREEN}" "  Level: ${level}"
        print_message "${GREEN}" "    Time: ${duration}ms"
        print_message "${GREEN}" "    Messages logged: ${log_count}"
        print_message "${GREEN}" "    Average: $((duration / ITERATIONS))ms per iteration"
    done
}

##
# Test memory usage
##
test_memory_usage() {
    print_message "${BLUE}" "\n=== Testing Memory Usage ==="
    
    setup_test
    export LOG_LEVEL="${LOG_LEVEL_INFO}"
    
    # Get initial memory (if available)
    local initial_memory=0
    if command -v ps > /dev/null 2>&1; then
        initial_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    fi
    
    # Log messages
    for ((i=1; i<=ITERATIONS; i++)); do
        log_info "Test message ${i}"
    done
    
    # Get final memory
    local final_memory=0
    if command -v ps > /dev/null 2>&1; then
        final_memory=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    fi
    
    if [[ ${initial_memory} -gt 0 ]] && [[ ${final_memory} -gt 0 ]]; then
        local memory_diff=$((final_memory - initial_memory))
        print_message "${GREEN}" "  Initial memory: ${initial_memory} KB"
        print_message "${GREEN}" "  Final memory: ${final_memory} KB"
        print_message "${GREEN}" "  Memory increase: ${memory_diff} KB"
        print_message "${GREEN}" "  Memory per message: $((memory_diff / ITERATIONS)) bytes"
    else
        print_message "${YELLOW}" "  Memory measurement not available"
    fi
}

##
# Print summary
##
print_summary() {
    echo
    print_message "${BLUE}" "=== Performance Test Summary ==="
    print_message "${GREEN}" "All performance tests completed"
    print_message "${BLUE}" "Review results above for performance metrics"
}

##
# Main
##
main() {
    print_message "${GREEN}" "Logging Performance Test Suite"
    print_message "${BLUE}" "Iterations per test: ${ITERATIONS}"
    echo
    
    # Setup
    trap cleanup EXIT
    mkdir -p "${TEST_LOG_DIR}"
    
    # Run performance tests
    test_single_log_performance
    test_batch_log_performance
    test_log_level_filtering
    test_concurrent_logging
    test_log_file_size_impact
    test_log_levels_performance
    test_memory_usage
    
    # Summary
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

