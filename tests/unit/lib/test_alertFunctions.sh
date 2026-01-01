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
# Test: is_alert_duplicate - handles custom deduplication window
##
@test "is_alert_duplicate uses custom deduplication window" {
    export ALERT_DEDUPLICATION_WINDOW_MINUTES="30"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.alerts ]] && [[ "${*}" =~ INTERVAL.*30.*minutes ]]; then
            echo "0"
            return 0
        fi
        return 1
    }
    
    run is_alert_duplicate "TEST_COMPONENT" "test_alert" "Test message"
    assert_failure  # Not duplicate
}

##
# Test: send_email_alert - handles mutt not available
##
@test "send_email_alert handles mutt not available" {
    # shellcheck disable=SC2030,SC2031
    export SEND_ALERT_EMAIL="true"
    
    # Mock command -v to return false
    # shellcheck disable=SC2317
    function command() {
        if [[ "${1}" == "-v" ]] && [[ "${2}" == "mutt" ]]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    run send_email_alert "test@example.com" "Test Subject" "Test message"
    assert_failure
}

##
# Test: send_slack_alert - handles curl not available
##
@test "send_slack_alert handles curl not available" {
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="true"
    # shellcheck disable=SC2030,SC2031
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
    
    # Mock command -v to return false
    # shellcheck disable=SC2317
    function command() {
        if [[ "${1}" == "-v" ]] && [[ "${2}" == "curl" ]]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    run send_slack_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_failure
}

##
# Test: send_alert - handles info level with no recipients
##
@test "send_alert handles info level with no recipients" {
    # shellcheck disable=SC2030,SC2031
    export INFO_ALERT_RECIPIENTS=""
    # shellcheck disable=SC2030,SC2031
    export ADMIN_EMAIL=""
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run send_alert "TEST_COMPONENT" "info" "test_alert" "Test message"
    assert_success
}

##
# Test: send_slack_alert - handles different alert level colors
##
@test "send_slack_alert uses correct color for critical level" {
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="true"
    # shellcheck disable=SC2030,SC2031
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        if [[ "${*}" =~ https://hooks.slack.com ]] && [[ "${*}" =~ danger ]]; then
            return 0
        fi
        return 1
    }
    export -f curl
    
    run send_slack_alert "TEST_COMPONENT" "critical" "test_alert" "Test message"
    assert_success
}

##
# Test: init_alerting - initializes alerting system
##
@test "init_alerting initializes alerting with defaults" {
    # Clear any existing config
    unset ADMIN_EMAIL SEND_ALERT_EMAIL SLACK_ENABLED
    
    # Run init_alerting directly (not via run) to set variables in current shell
    init_alerting
    
    # Verify defaults are set
    # shellcheck disable=SC2031
    assert [ -n "${ADMIN_EMAIL:-}" ]
    # shellcheck disable=SC2031
    assert [ "${SEND_ALERT_EMAIL:-false}" = "false" ]
    # shellcheck disable=SC2031
    assert [ "${SLACK_ENABLED:-false}" = "false" ]
}

##
# Test: send_email_alert - sends email alert
##
@test "send_email_alert sends email when enabled" {
    # shellcheck disable=SC2030,SC2031
    export SEND_ALERT_EMAIL="true"
    # shellcheck disable=SC2030,SC2031
    export ADMIN_EMAIL="test@example.com"
    
    # Mock mutt
    # shellcheck disable=SC2317
    function mutt() {
        echo "Email sent to ${2}"
        return 0
    }
    export -f mutt
    
    run send_email_alert "test@example.com" "Test Subject" "Test message"
    assert_success
}

##
# Test: send_email_alert - skips when disabled
##
@test "send_email_alert skips when email disabled" {
    # shellcheck disable=SC2030,SC2031
    export SEND_ALERT_EMAIL="false"
    
    run send_email_alert "test@example.com" "Test Subject" "Test message"
    assert_success
}

##
# Test: send_slack_alert - sends Slack alert
##
@test "send_slack_alert sends Slack message when enabled" {
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="true"
    # shellcheck disable=SC2030,SC2031
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        if [[ "${*}" =~ https://hooks.slack.com ]]; then
            return 0
        fi
        return 1
    }
    export -f curl
    
    run send_slack_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_success
}

##
# Test: send_slack_alert - skips when disabled
##
@test "send_slack_alert skips when Slack disabled" {
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="false"
    
    run send_slack_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_success
}

##
# Test: send_alert - sends via multiple channels
##
@test "send_alert sends via email and Slack when both enabled" {
    # shellcheck disable=SC2030,SC2031
    export SEND_ALERT_EMAIL="true"
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="true"
    # shellcheck disable=SC2030,SC2031
    export ADMIN_EMAIL="test@example.com"
    # shellcheck disable=SC2030,SC2031
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/test"
    
    # Mock mutt
    # shellcheck disable=SC2317
    function mutt() {
        return 0
    }
    export -f mutt
    
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        if [[ "${*}" =~ https://hooks.slack.com ]]; then
            return 0
        fi
        return 1
    }
    export -f curl
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run send_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_success
}

##
# Test: store_alert - handles deduplication enabled
##
@test "store_alert respects deduplication when enabled" {
    # shellcheck disable=SC2030,SC2031
    export ALERT_DEDUPLICATION_ENABLED="true"
    
    # Mock is_alert_duplicate to return true (duplicate)
    # shellcheck disable=SC2317
    function is_alert_duplicate() {
        return 0
    }
    export -f is_alert_duplicate
    
    # Mock psql should not be called
    # shellcheck disable=SC2317
    function psql() {
        return 1  # Should not be called
    }
    
    run store_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_success
}

##
# Test: store_alert - handles metadata JSON
##
@test "store_alert stores alert with metadata JSON" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]] && [[ "${*}" =~ metadata ]]; then
            return 0
        fi
        return 1
    }
    
    local metadata='{"key": "value"}'
    run store_alert "TEST_COMPONENT" "warning" "test_alert" "Test message" "${metadata}"
    assert_success
}

##
# Test: store_alert - handles deduplication disabled
##
@test "store_alert stores alert when deduplication disabled" {
    # shellcheck disable=SC2030,SC2031
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    run store_alert "TEST_COMPONENT" "warning" "test_alert" "Test message"
    assert_success
}


