#!/usr/bin/env bash
#
# Unit Tests: ipBlocking.sh
# Tests IP blocking management functionality
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Mock database functions to avoid real DB calls
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_ipBlocking"
    
    # Initialize security functions
    init_security
    
    # Initialize alerting
    init_alerting
    
    # Source ipBlocking.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/ipBlocking.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
    rm -f "${TMP_DIR}/.ip_added"
    rm -f "${TMP_DIR}/.ip_removed"
}

@test "whitelist_add adds IP to whitelist" {
    # Mock is_valid_ip
    # shellcheck disable=SC2317
    is_valid_ip() {
        return 0
    }
    export -f is_valid_ip
    
    # Mock psql to track INSERT
    local insert_called=false
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"INSERT INTO ip_management"* ]] && [[ "${*}" == *"whitelist"* ]]; then
            insert_called=true
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run whitelist add
    run whitelist_add "192.168.1.100" "Test server"
    
    # Should succeed
    assert_success
    assert_equal "true" "${insert_called}"
}

@test "whitelist_add rejects invalid IP" {
    # Mock is_valid_ip to return false
    # shellcheck disable=SC2317
    is_valid_ip() {
        return 1
    }
    export -f is_valid_ip
    
    # Run whitelist add with invalid IP
    run whitelist_add "invalid.ip" "Test"
    
    # Should fail
    assert_failure
}

@test "whitelist_remove removes IP from whitelist" {
    # Mock psql to track DELETE
    local delete_called=false
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]] && [[ "${*}" == *"whitelist"* ]]; then
            delete_called=true
        fi
        return 0
    }
    export -f psql
    
    # Run whitelist remove
    run whitelist_remove "192.168.1.100"
    
    # Should succeed
    assert_success
    assert_equal "true" "${delete_called}"
}

@test "whitelist_list queries database" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]]; then
            echo "192.168.1.100|Test|2025-12-27|user"
        fi
        return 0
    }
    export -f psql
    
    # Run whitelist list
    run whitelist_list
    
    # Should succeed
    assert_success
}

@test "blacklist_add adds IP to blacklist" {
    # Mock is_valid_ip
    # shellcheck disable=SC2317
    is_valid_ip() {
        return 0
    }
    export -f is_valid_ip
    
    # Mock psql to track INSERT
    local insert_called=false
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"INSERT INTO ip_management"* ]] && [[ "${*}" == *"blacklist"* ]]; then
            insert_called=true
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run blacklist add
    run blacklist_add "192.168.1.200" "Known attacker"
    
    # Should succeed
    assert_success
    assert_equal "true" "${insert_called}"
}

@test "blacklist_remove removes IP from blacklist" {
    # Mock psql to track DELETE
    local delete_called=false
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]] && [[ "${*}" == *"blacklist"* ]]; then
            delete_called=true
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run blacklist remove
    run blacklist_remove "192.168.1.200"
    
    # Should succeed
    assert_success
    assert_equal "true" "${delete_called}"
}

@test "block_ip_temporary blocks IP with expiration" {
    # Mock is_valid_ip
    # shellcheck disable=SC2317
    is_valid_ip() {
        return 0
    }
    export -f is_valid_ip
    
    # Mock block_ip
    local block_file="${TMP_DIR}/.ip_added"
    rm -f "${block_file}"
    
    # shellcheck disable=SC2317
    block_ip() {
        if [[ "${1}" == "192.168.1.100" ]] && [[ "${2}" == "temp_block" ]]; then
            touch "${block_file}"
        fi
        return 0
    }
    export -f block_ip
    
    # Run temporary block
    run block_ip_temporary "192.168.1.100" "60" "Test block"
    
    # Should succeed
    assert_success
    assert_file_exists "${block_file}"
}

@test "unblock_ip removes IP from blocks" {
    # Mock psql to track DELETE
    local delete_called=false
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]]; then
            delete_called=true
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run unblock
    run unblock_ip "192.168.1.100"
    
    # Should succeed
    assert_success
    assert_equal "true" "${delete_called}"
}

@test "list_ips queries database" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]]; then
            echo "192.168.1.100|temp_block|Test|2025-12-27|2025-12-28|user"
        fi
        return 0
    }
    export -f psql
    
    # Run list
    run list_ips "temp_block"
    
    # Should succeed
    assert_success
}

@test "check_ip_status shows IP status" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        if [[ "${1}" == "192.168.1.100" ]]; then
            return 0
        fi
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock is_ip_blacklisted
    # shellcheck disable=SC2317
    is_ip_blacklisted() {
        return 1
    }
    export -f is_ip_blacklisted
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]]; then
            echo "whitelist|Test|2025-12-27||user"
        fi
        return 0
    }
    export -f psql
    
    # Run status check
    run check_ip_status "192.168.1.100"
    
    # Should succeed
    assert_success
}

@test "cleanup_expired removes expired blocks" {
    # Mock psql to return deleted count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "5"
        elif [[ "${*}" == *"DELETE"* ]]; then
            return 0
        fi
        return 0
    }
    export -f psql
    
    # Run cleanup
    run cleanup_expired
    
    # Should succeed
    assert_success
}

@test "main function whitelist add action works" {
    # Mock functions
    # shellcheck disable=SC2317
    is_valid_ip() { return 0; }
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"INSERT"* ]]; then
            return 0
        fi
        return 0
    }
    # shellcheck disable=SC2317
    record_security_event() { return 0; }
    
    export -f is_valid_ip psql record_security_event
    
    # Run main with whitelist add
    run main "whitelist" "add" "192.168.1.100" "Test"
    
    # Should succeed
    assert_success
}

@test "main function blacklist add action works" {
    # Mock functions
    # shellcheck disable=SC2317
    is_valid_ip() { return 0; }
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"INSERT"* ]]; then
            return 0
        fi
        return 0
    }
    # shellcheck disable=SC2317
    record_security_event() { return 0; }
    
    export -f is_valid_ip psql record_security_event
    
    # Run main with blacklist add
    run main "blacklist" "add" "192.168.1.200" "Attacker"
    
    # Should succeed
    assert_success
}

@test "main function block action works" {
    # Mock functions
    # shellcheck disable=SC2317
    is_valid_ip() { return 0; }
    # shellcheck disable=SC2317
    block_ip() { return 0; }
    
    export -f is_valid_ip block_ip
    
    # Run main with block action
    run main "block" "192.168.1.100" "60" "Test"
    
    # Should succeed
    assert_success
}

@test "main function unblock action works" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]]; then
            return 0
        fi
        return 0
    }
    # shellcheck disable=SC2317
    record_security_event() { return 0; }
    
    export -f psql record_security_event
    
    # Run main with unblock action
    run main "unblock" "192.168.1.100"
    
    # Should succeed
    assert_success
}

@test "main function status action works" {
    # Mock functions
    # shellcheck disable=SC2317
    is_ip_whitelisted() { return 1; }
    # shellcheck disable=SC2317
    is_ip_blacklisted() { return 1; }
    # shellcheck disable=SC2317
    psql() {
        echo "test status"
        return 0
    }
    
    export -f is_ip_whitelisted is_ip_blacklisted psql
    
    # Run main with status action
    run main "status" "192.168.1.100"
    
    # Should succeed
    assert_success
}

@test "main function cleanup action works" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "3"
        fi
        return 0
    }
    export -f psql
    
    # Run main with cleanup action
    run main "cleanup"
    
    # Should succeed
    assert_success
}

@test "whitelist_add handles database errors gracefully" {
    # Mock is_valid_ip
    # shellcheck disable=SC2317
    is_valid_ip() {
        return 0
    }
    export -f is_valid_ip
    
    # Mock psql to fail
    # shellcheck disable=SC2317
    psql() {
        return 1
    }
    export -f psql
    
    # Run whitelist add
    run whitelist_add "192.168.1.100" "Test"
    
    # Should fail
    assert_failure
}

@test "block_ip_temporary rejects invalid IP" {
    # Mock is_valid_ip to return false
    # shellcheck disable=SC2317
    is_valid_ip() {
        return 1
    }
    export -f is_valid_ip
    
    # Run block with invalid IP
    run block_ip_temporary "invalid.ip" "60" "Test"
    
    # Should fail
    assert_failure
}

