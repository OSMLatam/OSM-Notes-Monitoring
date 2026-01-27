#!/usr/bin/env bash
#
# Additional Unit Tests: ipBlocking.sh
# Additional tests for IP blocking to increase coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock functions BEFORE sourcing
    # shellcheck disable=SC2317
    load_config() { return 0; }
    export -f load_config
    # shellcheck disable=SC2317
    init_alerting() { return 0; }
    export -f init_alerting
    # shellcheck disable=SC2317
    psql() { return 0; }
    export -f psql
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/ipBlocking.sh"
    
    init_logging "${TEST_LOG_DIR}/test_ipBlocking_additional.log" "test_ipBlocking_additional"
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: add_ip_to_list handles whitelist addition
##
@test "add_ip_to_list handles whitelist addition" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*ip_management ]] && [[ "${*}" =~ whitelist ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run add_ip_to_list "192.168.1.1" "whitelist"
    assert_success
}

##
# Test: add_ip_to_list handles blacklist addition with expiration
##
@test "add_ip_to_list handles blacklist addition with expiration" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*ip_management ]] && [[ "${*}" =~ blacklist ]] && [[ "${*}" =~ expires_at ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run add_ip_to_list "192.168.1.1" "blacklist" "60"
    assert_success
}

##
# Test: remove_ip_from_list handles removal
##
@test "remove_ip_from_list handles removal" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DELETE.*ip_management ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run blacklist_remove "192.168.1.1"
    assert_success
}

##
# Test: list_ips_in_list handles empty result
##
@test "list_ips_in_list handles empty result" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run whitelist_list
    assert_success
}

##
# Test: list_ips_in_list displays IPs with expiration
##
@test "list_ips_in_list displays IPs with expiration" {
    # Mock psql to return IPs with expiration
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]]; then
            echo "192.168.1.1|2025-12-29 10:00:00"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run blacklist_list
    assert_success
    assert_output --partial "192.168.1.1"
}

##
# Test: get_ip_status handles IP not in any list
##
@test "get_ip_status handles IP not in any list" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run get_ip_status "192.168.1.1"
    assert_success
    assert_output --partial "not found" || assert_output --partial "unknown"
}

##
# Test: cleanup_expired_blocks removes expired entries
##
@test "cleanup_expired_blocks removes expired entries" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DELETE.*ip_management ]] && [[ "${*}" =~ expires_at ]]; then
            echo "5"  # 5 rows deleted
            return 0
        fi
        return 1
    }
    export -f psql
    
    run cleanup_expired
    assert_success
}

##
# Test: cleanup_expired_blocks handles no expired entries
##
@test "cleanup_expired_blocks handles no expired entries" {
    # Mock psql to return no rows deleted
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DELETE.*ip_management ]]; then
            echo "0"  # No rows deleted
            return 0
        fi
        return 1
    }
    export -f psql
    
    run cleanup_expired
    assert_success
}

##
# Test: main handles add action
##
@test "main handles add action" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
    run main "blacklist" "add" "192.168.1.1"
    assert_success
}

##
# Test: main handles remove action
##
@test "main handles remove action" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
    run main "blacklist" "remove" "192.168.1.1"
    assert_success
}

##
# Test: main handles list action
##
@test "main handles list action" {
    # Mock list_ips_in_list
    # shellcheck disable=SC2317
    function list_ips_in_list() {
        return 0
    }
    export -f list_ips_in_list
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
    run main "whitelist" "list"
    assert_success
}

##
# Test: main handles status action
##
@test "main handles status action" {
    # Mock get_ip_status
    # shellcheck disable=SC2317
    function get_ip_status() {
        return 0
    }
    export -f get_ip_status
    
    run main "status" "192.168.1.1"
    assert_success
}

##
# Test: main handles cleanup action
##
@test "main handles cleanup action" {
    # Mock cleanup_expired_blocks
    # shellcheck disable=SC2317
    function cleanup_expired_blocks() {
        return 0
    }
    export -f cleanup_expired_blocks
    
    run main "cleanup"
    assert_success
}

##
# Test: add_ip_to_list handles invalid IP
##
@test "add_ip_to_list handles invalid IP" {
    run add_ip_to_list "invalid_ip" "blacklist"
    assert_failure
}

##
# Test: add_ip_to_list handles invalid list type
##
@test "add_ip_to_list handles invalid list type" {
    run add_ip_to_list "192.168.1.1" "invalid_list"
    assert_failure
}

##
# Test: get_ip_status handles IP in whitelist
##
@test "get_ip_status handles IP in whitelist" {
    # Mock psql to return whitelist entry
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]]; then
            echo "192.168.1.1|whitelist|"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run get_ip_status "192.168.1.1"
    assert_success
    assert_output --partial "whitelist"
}

##
# Test: get_ip_status handles IP in blacklist
##
@test "get_ip_status handles IP in blacklist" {
    # Mock psql to return blacklist entry
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*ip_management ]]; then
            echo "192.168.1.1|blacklist|2025-12-29 10:00:00"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run get_ip_status "192.168.1.1"
    assert_success
    assert_output --partial "blacklist"
}

##
# Test: main handles --help option
##
@test "main handles --help option" {
    # Mock usage
    # shellcheck disable=SC2317
    function usage() {
        return 0
    }
    export -f usage
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/security/ipBlocking.sh" --help
    assert_success
}
