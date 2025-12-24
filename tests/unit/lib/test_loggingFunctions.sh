#!/usr/bin/env bash
#
# Unit Tests: loggingFunctions.sh
#

load "$(dirname "$0")/../../test_helper.bash"

# Source the library
source "$(dirname "$0")/../../../bin/lib/loggingFunctions.sh"

@test "log_info writes to log file" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test.log"
    
    init_logging "${test_log_file}" "test_script"
    
    log_info "Test message"
    
    assert_file_exists "${test_log_file}"
    assert grep -q "Test message" "${test_log_file}"
}

@test "log_error writes error message" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_error.log"
    
    init_logging "${test_log_file}" "test_script"
    
    log_error "Error message"
    
    assert_file_exists "${test_log_file}"
    assert grep -q "ERROR" "${test_log_file}"
    assert grep -q "Error message" "${test_log_file}"
}

@test "get_timestamp returns formatted timestamp" {
    local timestamp
    timestamp=$(get_timestamp)
    
    # Should match YYYY-MM-DD HH:MM:SS format
    assert [[ "${timestamp}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "log_message respects log level" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_level.log"
    
    init_logging "${test_log_file}" "test_script"
    LOG_LEVEL=${LOG_LEVEL_INFO}
    
    log_debug "Debug message"
    log_info "Info message"
    
    # Debug should not be logged (level too low)
    run grep -q "Debug message" "${test_log_file}"
    assert_failure
    
    # Info should be logged
    assert grep -q "Info message" "${test_log_file}"
}

