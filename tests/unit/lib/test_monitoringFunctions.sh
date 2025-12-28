#!/usr/bin/env bats
#
# Unit Tests: monitoringFunctions.sh
# Tests for monitoring functions library
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="MONITORING"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_monitoringFunctions.log"
    init_logging "${LOG_FILE}" "test_monitoringFunctions"
    
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
# Test: check_database_connection - success case
##
@test "check_database_connection succeeds with valid connection" {
    # Mock psql to return success
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -c.*SELECT.*1 ]]; then
            echo "1"
            return 0
        fi
        return 1
    }
    
    run check_database_connection
    assert_success
}

##
# Test: check_database_connection - failure case
##
@test "check_database_connection fails with invalid connection" {
    # Mock psql to return failure
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run check_database_connection
    assert_failure
}

##
# Test: update_component_health - healthy status
##
@test "update_component_health updates status to healthy" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "healthy" "All checks passed"
    assert_success
}

##
# Test: update_component_health - degraded status
##
@test "update_component_health updates status to degraded" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "degraded" "Some checks failed"
    assert_success
}

##
# Test: update_component_health - down status
##
@test "update_component_health updates status to down" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "down" "Component unavailable"
    assert_success
}

##
# Test: update_component_health - invalid status
##
@test "update_component_health handles invalid status" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "invalid" "Invalid status"
    # Should handle gracefully
    assert_failure
}

##
# Test: get_component_health - retrieves health status
##
@test "get_component_health retrieves current health status" {
    # Mock psql to return health data
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*component_health ]]; then
            echo "healthy|All checks passed|2025-12-28 10:00:00"
            return 0
        fi
        return 1
    }
    
    run get_component_health "TEST_COMPONENT"
    assert_success
    assert [[ "${output}" =~ healthy ]]
}

##
# Test: check_database_server_health - healthy database
##
@test "check_database_server_health detects healthy database" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -c.*SELECT.*version ]]; then
            echo "PostgreSQL 14.0"
            return 0
        fi
        return 1
    }
    
    run check_database_server_health
    assert_success
}

##
# Test: check_database_server_health - unhealthy database
##
@test "check_database_server_health detects unhealthy database" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run check_database_server_health
    assert_failure
}
