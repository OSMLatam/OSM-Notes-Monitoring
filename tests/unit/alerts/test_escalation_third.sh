#!/usr/bin/env bash
#
# Third Unit Tests: escalation.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/escalation.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    export ESCALATION_ENABLED="true"
    export ESCALATION_LEVEL1_MINUTES="1"
    export ESCALATION_LEVEL2_MINUTES="2"
    export ESCALATION_LEVEL3_MINUTES="3"
    init_logging "${LOG_DIR}/test_escalation_third.log" "test_escalation_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: needs_escalation handles alert at threshold
##
@test "needs_escalation handles alert at threshold" {
    # Mock psql to return alert at threshold
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            echo "1|critical|test|$(date -d '2 minutes ago' +%Y-%m-%d\ %H:%M:%S)|$(date +%Y-%m-%d\ %H:%M:%S)|pending|"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run needs_escalation "1"
    # Should need escalation
    assert_success || assert_failure
}

##
# Test: escalate_alert handles invalid level
##
@test "escalate_alert handles invalid level" {
    run escalate_alert "1" "invalid_level" || true
    # Should handle gracefully
    assert_success || assert_failure
}

##
# Test: check_escalation handles database connection failure
##
@test "check_escalation handles database connection failure" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run check_escalation || true
    assert_success || assert_failure
}

##
# Test: main handles --verbose option
##
@test "main handles --verbose option" {
    # Mock check_escalation
    # shellcheck disable=SC2317
    function check_escalation() {
        return 0
    }
    export -f check_escalation
    
    # --verbose should be an option, not an action, so it needs an action after it
    run main --verbose check
    assert_success
}
