#!/usr/bin/env bash
#
# Unit Tests: loggingFunctions.sh
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source the library
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"

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
    # Check format without using complex regex in assert
    local year month day hour min sec
    IFS=' -:' read -r year month day hour min sec <<< "${timestamp}"
    assert [[ -n "${year}" ]] && [[ ${#year} -eq 4 ]]
    assert [[ -n "${month}" ]] && [[ ${#month} -eq 2 ]]
    assert [[ -n "${day}" ]] && [[ ${#day} -eq 2 ]]
    assert [[ -n "${hour}" ]] && [[ ${#hour} -eq 2 ]]
    assert [[ -n "${min}" ]] && [[ ${#min} -eq 2 ]]
    assert [[ -n "${sec}" ]] && [[ ${#sec} -eq 2 ]]
}

@test "log_message respects log level" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_level.log"
    
    init_logging "${test_log_file}" "test_script"
    # shellcheck disable=SC2030,SC2031
    export LOG_LEVEL=${LOG_LEVEL_INFO}
    
    log_debug "Debug message"
    log_info "Info message"
    
    # Debug should not be logged (level too low)
    run grep -q "Debug message" "${test_log_file}"
    assert_failure
    
    # Info should be logged
    assert grep -q "Info message" "${test_log_file}"
}

@test "log_warning writes warning message" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_warning.log"
    
    init_logging "${test_log_file}" "test_script"
    
    log_warning "Warning message"
    
    assert_file_exists "${test_log_file}"
    assert grep -q "WARNING" "${test_log_file}"
    assert grep -q "Warning message" "${test_log_file}"
}

@test "log_debug writes debug message when level is DEBUG" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_debug.log"
    
    init_logging "${test_log_file}" "test_script"
    # shellcheck disable=SC2030,SC2031
    export LOG_LEVEL=${LOG_LEVEL_DEBUG}
    
    log_debug "Debug message"
    
    assert_file_exists "${test_log_file}"
    assert grep -q "DEBUG" "${test_log_file}"
    assert grep -q "Debug message" "${test_log_file}"
}

@test "log_error_and_exit logs error and exits" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_exit.log"
    
    init_logging "${test_log_file}" "test_script"
    
    # Run in subshell to catch exit
    run bash -c "source '${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh' && init_logging '${test_log_file}' 'test_script' && log_error_and_exit 42 'Exit error message'"
    
    assert [ "$status" -eq 42 ]
    assert_file_exists "${test_log_file}"
    assert grep -q "ERROR" "${test_log_file}"
    assert grep -q "Exit error message" "${test_log_file}"
}

@test "init_logging creates log directory if missing" {
    local test_log_dir="${TEST_ROOT}/tests/tmp/new_log_dir"
    local test_log_file="${test_log_dir}/test.log"
    
    # Ensure directory doesn't exist
    rm -rf "${test_log_dir}"
    
    init_logging "${test_log_file}" "test_script"
    log_info "Test message"
    
    assert_dir_exists "${test_log_dir}"
    assert_file_exists "${test_log_file}"
}

@test "log_message respects WARNING level threshold" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_warning_level.log"
    
    init_logging "${test_log_file}" "test_script"
    # shellcheck disable=SC2030,SC2031
    export LOG_LEVEL=${LOG_LEVEL_WARNING}
    
    log_info "Info message"
    log_warning "Warning message"
    log_error "Error message"
    
    # Info should not be logged
    run grep -q "Info message" "${test_log_file}"
    assert_failure
    
    # Warning and error should be logged
    assert grep -q "Warning message" "${test_log_file}"
    assert grep -q "Error message" "${test_log_file}"
}

@test "log_message respects ERROR level threshold" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_error_level.log"
    
    init_logging "${test_log_file}" "test_script"
    # shellcheck disable=SC2031
    export LOG_LEVEL=${LOG_LEVEL_ERROR}
    
    log_info "Info message"
    log_warning "Warning message"
    log_error "Error message"
    
    # Info and warning should not be logged
    run grep -q "Info message" "${test_log_file}"
    assert_failure
    run grep -q "Warning message" "${test_log_file}"
    assert_failure
    
    # Only error should be logged
    assert grep -q "Error message" "${test_log_file}"
}

@test "init_logging uses default script name when not provided" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_default.log"
    
    init_logging "${test_log_file}"
    log_info "Test message"
    
    assert_file_exists "${test_log_file}"
    # Should contain some script name (could be bats or test script name)
    assert grep -q ":" "${test_log_file}"
}

@test "log_message handles unknown log level gracefully" {
    local test_log_file="${TEST_ROOT}/tests/tmp/test_unknown.log"
    
    init_logging "${test_log_file}" "test_script"
    
    # Call log_message directly with unknown level
    log_message "UNKNOWN" "Unknown level message"
    
    assert_file_exists "${test_log_file}"
    # Should still log (treats as INFO)
    assert grep -q "Unknown level message" "${test_log_file}"
}

@test "get_timestamp returns consistent format" {
    local timestamp1
    timestamp1=$(get_timestamp)
    sleep 1
    local timestamp2
    timestamp2=$(get_timestamp)
    
    # Both should be valid timestamps (check format)
    local year1
    IFS=' -:' read -r year1 _ _ <<< "${timestamp1}"
    assert [[ -n "${year1}" ]] && [[ ${#year1} -eq 4 ]]
    
    local year2
    IFS=' -:' read -r year2 _ _ <<< "${timestamp2}"
    assert [[ -n "${year2}" ]] && [[ ${#year2} -eq 4 ]]
    
    # Second should be later (or equal if same second)
    assert [ "${timestamp2}" > "${timestamp1}" ] || [ "${timestamp2}" == "${timestamp1}" ]
}
