#!/usr/bin/env bats
#
# Unit Tests: securityFunctions.sh
# Tests for security functions library
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="SECURITY"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_securityFunctions.log"
    init_logging "${LOG_FILE}" "test_securityFunctions"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: validate_ip_address - validates correct IP
##
@test "validate_ip_address validates correct IPv4 address" {
    run validate_ip_address "192.168.1.1"
    assert_success
}

##
# Test: validate_ip_address - rejects invalid IP
##
@test "validate_ip_address rejects invalid IP address" {
    run validate_ip_address "999.999.999.999"
    assert_failure
}

##
# Test: validate_ip_address - rejects non-IP string
##
@test "validate_ip_address rejects non-IP string" {
    run validate_ip_address "not-an-ip"
    assert_failure
}

##
# Test: is_ip_whitelisted - checks whitelist
##
@test "is_ip_whitelisted checks IP against whitelist" {
    # Mock psql to return whitelist status
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]]; then
            echo "1"
            return 0
        fi
        return 1
    }
    
    run is_ip_whitelisted "192.168.1.1"
    assert_success
}

##
# Test: is_ip_blacklisted - checks blacklist
##
@test "is_ip_blacklisted checks IP against blacklist" {
    # Mock psql to return blacklist status
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]]; then
            echo "1"
            return 0
        fi
        return 1
    }
    
    run is_ip_blacklisted "192.168.1.100"
    assert_success
}

##
# Test: log_security_event - logs security event
##
@test "log_security_event logs security event to database" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*security_events ]]; then
            return 0
        fi
        return 1
    }
    
    run log_security_event "rate_limit_exceeded" "192.168.1.1" "Rate limit exceeded"
    assert_success
}

##
# Test: check_rate_limit - allows request within limit
##
@test "check_rate_limit allows request within limit" {
    # Mock psql to return low count
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "5"
            return 0
        fi
        return 1
    }
    
    run check_rate_limit "192.168.1.1" "api_endpoint" 100 60
    assert_success
}

##
# Test: check_rate_limit - blocks request exceeding limit
##
@test "check_rate_limit blocks request exceeding limit" {
    # Mock psql to return high count
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "150"
            return 0
        fi
        return 1
    }
    
    run check_rate_limit "192.168.1.1" "api_endpoint" 100 60
    assert_failure
}

##
# Test: sanitize_input - sanitizes user input
##
@test "sanitize_input removes dangerous characters" {
    local input="test'; DROP TABLE users; --"
    local sanitized
    sanitized=$(sanitize_input "${input}")
    
    # shellcheck disable=SC2035
    assert [[ "${sanitized}" != *"DROP"* ]]
    # shellcheck disable=SC2035
    assert [[ "${sanitized}" != *";"* ]]
}
