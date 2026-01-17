#!/usr/bin/env bash
#
# Additional Unit Tests: Alert Escalation
# Additional tests for escalation to increase coverage
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

export TEST_MODE=true
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../../tmp/logs"
mkdir -p "${TEST_LOG_DIR}"
export TEST_LOG_DIR="${TEST_LOG_DIR}"
export LOG_DIR="${TEST_LOG_DIR}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    export ESCALATION_ENABLED="true"
    export ESCALATION_LEVEL1_MINUTES="1"
    export ESCALATION_LEVEL2_MINUTES="2"
    export ESCALATION_LEVEL3_MINUTES="3"
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/alerts/escalation.sh"
    
    init_logging "${LOG_DIR}/test_escalation_additional.log" "test_escalation_additional"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: needs_escalation handles alert not found
##
@test "needs_escalation handles alert not found" {
    # Mock psql to return empty (alert not found)
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run needs_escalation "99999"
    assert_failure
}

##
# Test: needs_escalation handles already escalated alert
##
@test "needs_escalation handles already escalated alert" {
    # Mock psql to return escalated alert
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*alerts ]]; then
            echo "1|critical|test|2025-12-28 10:00:00|2025-12-28 10:05:00|escalated|level3"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run needs_escalation "1"
    # Should return false (already escalated)
    assert_failure
}

##
# Test: escalate_alert handles database error
##
@test "escalate_alert handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run escalate_alert "1" "level1"
    assert_failure
}

##
# Test: check_escalation handles no alerts needing escalation
##
@test "check_escalation handles no alerts needing escalation" {
    # Mock needs_escalation to return false for all
    # shellcheck disable=SC2317
    function needs_escalation() {
        return 1  # No escalation needed
    }
    export -f needs_escalation
    
    # Mock psql to return alert list
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*id.*FROM.*alerts ]]; then
            echo "1"
            echo "2"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run check_escalation
    assert_success
}

##
# Test: show_rules displays escalation rules
##
@test "show_rules displays escalation rules" {
    run show_rules
    assert_success
    assert_output --partial "Level"
}

##
# Test: show_oncall displays on-call information
##
@test "show_oncall displays on-call information" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*oncall ]]; then
            echo "user1|2025-12-28"
            return 0
        fi
        return 1
    }
    export -f psql
    
    run show_oncall
    assert_success
}

##
# Test: rotate_oncall handles rotation
##
@test "rotate_oncall handles rotation" {
    # Enable on-call rotation
    export ONCALL_ROTATION_ENABLED="true"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*oncall ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    run rotate_oncall
    assert_success
}

##
# Test: main handles --check option
##
@test "main handles --check option" {
    # Mock check_escalation
    # shellcheck disable=SC2317
    function check_escalation() {
        return 0
    }
    export -f check_escalation
    
    run main --check
    assert_success
}

##
# Test: main handles --rules option
##
@test "main handles --rules option" {
    # Mock show_rules
    # shellcheck disable=SC2317
    function show_rules() {
        return 0
    }
    export -f show_rules
    
    run main --rules
    assert_success
}

##
# Test: main handles --oncall option
##
@test "main handles --oncall option" {
    # Mock show_oncall
    # shellcheck disable=SC2317
    function show_oncall() {
        return 0
    }
    export -f show_oncall
    
    run main --oncall
    assert_success
}

##
# Test: main handles --rotate option
##
@test "main handles --rotate option" {
    # Mock rotate_oncall
    # shellcheck disable=SC2317
    function rotate_oncall() {
        return 0
    }
    export -f rotate_oncall
    
    run main --rotate
    assert_success
}

##
# Test: main handles unknown option
##
@test "main handles unknown option" {
    # Mock usage
    # shellcheck disable=SC2317
    function usage() {
        return 0
    }
    export -f usage
    
    run main --unknown-option || true
    assert_failure
}

##
# Test: escalate_alert handles level2 escalation
##
@test "escalate_alert handles level2 escalation" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        # First query: SELECT current escalation level
        if [[ "${*}" =~ SELECT.*escalation_level ]]; then
            echo "1"  # Current level is 1
            return 0
        fi
        # Second query: UPDATE to level2
        if [[ "${*}" =~ UPDATE.*alerts ]] && [[ "${*}" =~ 2 ]]; then
            echo "00000000-0000-0000-0000-000000000001"  # Return alert ID
            return 0
        fi
        return 1
    }
    export -f psql
    
    run escalate_alert "00000000-0000-0000-0000-000000000001" "2"
    assert_success
}

##
# Test: escalate_alert handles level3 escalation
##
@test "escalate_alert handles level3 escalation" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        # First query: SELECT current escalation level
        if [[ "${*}" =~ SELECT.*escalation_level ]]; then
            echo "2"  # Current level is 2
            return 0
        fi
        # Second query: UPDATE to level3
        if [[ "${*}" =~ UPDATE.*alerts ]] && [[ "${*}" =~ 3 ]]; then
            echo "00000000-0000-0000-0000-000000000001"  # Return alert ID
            return 0
        fi
        return 1
    }
    export -f psql
    
    run escalate_alert "00000000-0000-0000-0000-000000000001" "3"
    assert_success
}
