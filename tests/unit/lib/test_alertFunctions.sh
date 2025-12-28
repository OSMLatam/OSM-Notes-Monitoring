#!/usr/bin/env bats
#
# Unit Tests: alertFunctions.sh
# Tests for alert functions library
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alertFunctions.log"
    init_logging "${LOG_FILE}" "test_alertFunctions"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Initialize alerting
    init_alerting
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: store_alert - stores alert successfully
##
@test "store_alert stores alert with critical level" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run store_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_success
}

##
# Test: store_alert - stores alert with warning level
##
@test "store_alert stores alert with warning level" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run store_alert "TEST_COMPONENT" "warning" "test_alert" "Test warning"
    assert_success
}

##
# Test: store_alert - stores alert with info level
##
@test "store_alert stores alert with info level" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run store_alert "TEST_COMPONENT" "info" "test_alert" "Test info"
    assert_success
}

##
# Test: store_alert - rejects invalid alert level
##
@test "store_alert rejects invalid alert level" {
    run store_alert "TEST_COMPONENT" "invalid" "test_alert" "Test message"
    assert_failure
}

##
# Test: send_alert - sends alert successfully
##
@test "send_alert sends alert and stores it" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    # Mock send_alert_email (if exists)
    # shellcheck disable=SC2317
    function send_alert_email() {
        return 0
    }
    
    run send_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_success
}

##
# Test: send_alert - handles database error
##
@test "send_alert handles database error gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run send_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    # Should handle error gracefully
    assert_failure
}

##
# Test: is_alert_duplicate - detects duplicate alert
##
@test "is_alert_duplicate detects duplicate alert" {
    # Mock psql to return existing alert
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.alerts ]]; then
            echo "1"
            return 0
        fi
        return 1
    }
    
    run is_alert_duplicate "TEST_COMPONENT" "test_alert" "Test message"
    assert_success
}

##
# Test: is_alert_duplicate - no duplicate found
##
@test "is_alert_duplicate returns false for new alert" {
    # Mock psql to return no results
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run is_alert_duplicate "TEST_COMPONENT" "new_alert" "New message"
    assert_failure
}

##
# Test: get_active_alerts - retrieves active alerts
##
@test "get_active_alerts retrieves active alerts for component" {
    # Mock psql to return alerts
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.alerts ]]; then
            echo "1|critical|test_alert|Test message|2025-12-28 10:00:00"
            return 0
        fi
        return 1
    }
    
    run get_active_alerts "TEST_COMPONENT"
    assert_success
    assert [[ "${output}" =~ test_alert ]]
}

##
# Test: acknowledge_alert - acknowledges alert
##
@test "acknowledge_alert acknowledges alert successfully" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run acknowledge_alert "1" "Test user"
    assert_success
}
