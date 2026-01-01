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
# Test: is_valid_ip - validates correct IP
##
@test "is_valid_ip validates correct IPv4 address" {
    run is_valid_ip "192.168.1.1"
    assert_success
}

##
# Test: is_valid_ip - rejects invalid IP
##
@test "is_valid_ip rejects invalid IP address" {
    run is_valid_ip "999.999.999.999"
    assert_failure
}

##
# Test: is_valid_ip - rejects non-IP string
##
@test "is_valid_ip rejects non-IP string" {
    run is_valid_ip "not-an-ip"
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
# Test: record_security_event - logs security event
##
@test "record_security_event logs security event to database" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*security_events ]]; then
            return 0
        fi
        return 1
    }
    
    run record_security_event "rate_limit_exceeded" "192.168.1.1" "endpoint" "{}"
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
# Test: is_valid_ip - handles edge cases
##
@test "is_valid_ip handles IPv4 with different formats" {
    # Valid formats
    run is_valid_ip "10.0.0.1"
    assert_success
    
    run is_valid_ip "172.16.0.1"
    assert_success
    
    run is_valid_ip "8.8.8.8"
    assert_success
}

##
# Test: init_security - initializes security system
##
@test "init_security initializes security functions" {
    run init_security
    assert_success
}

##
# Test: is_valid_ip - validates various IP formats
##
@test "is_valid_ip validates IPv4 with leading zeros" {
    run is_valid_ip "192.168.001.001"
    assert_success
}

##
# Test: is_valid_ip - rejects empty string
##
@test "is_valid_ip rejects empty string" {
    run is_valid_ip ""
    assert_failure
}

##
# Test: block_ip - blocks IP successfully
##
@test "block_ip blocks IP successfully" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*ip_management ]] || [[ "${*}" =~ INSERT.*security_events ]]; then
            return 0
        fi
        return 1
    }
    
    run block_ip "192.168.1.100" "Test reason"
    assert_success
}

##
# Test: block_ip - handles invalid IP
##
@test "block_ip handles invalid IP" {
    run block_ip "invalid.ip" "Test reason"
    assert_failure
}

##
# Test: record_security_event - records event with metadata
##
@test "record_security_event records event with metadata" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*security_events ]] && [[ "${*}" =~ metadata ]]; then
            return 0
        fi
        return 1
    }
    
    local metadata='{"key": "value"}'
    run record_security_event "test_event" "192.168.1.1" "endpoint" "${metadata}"
    assert_success
}

##
# Test: check_rate_limit - handles edge case with zero limit
##
@test "check_rate_limit handles zero limit" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "0"
            return 0
        fi
        return 1
    }
    
    # check_rate_limit signature: ip, window_seconds, max_requests
    # With zero limit, any count >= 0 should fail
    run check_rate_limit "192.168.1.1" 60 0
    assert_failure  # Should fail because 0 >= 0
}

##
# Test: is_ip_whitelisted - handles IP not in whitelist
##
@test "is_ip_whitelisted returns false for non-whitelisted IP" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run is_ip_whitelisted "192.168.1.999"
    assert_failure
}

##
# Test: is_ip_blacklisted - handles IP not in blacklist
##
@test "is_ip_blacklisted returns false for non-blacklisted IP" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run is_ip_blacklisted "192.168.1.999"
    assert_failure
}
