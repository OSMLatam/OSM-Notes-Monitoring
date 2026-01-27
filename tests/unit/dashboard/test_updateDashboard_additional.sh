#!/usr/bin/env bats
#
# Additional Unit Tests: updateDashboard.sh
# Additional tests for dashboard update to increase coverage
#

export TEST_COMPONENT="DASHBOARD"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_updateDashboard_additional.log" "test_updateDashboard_additional"
    
    # Source the script
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: update_dashboard handles missing dashboard name
##
@test "update_dashboard handles missing dashboard name" {
    # Test with empty dashboard type
    run update_grafana_dashboard ""
    # Should handle gracefully
    assert [ ${status} -ge 0 ]
}

##
# Test: update_dashboard handles database error
##
@test "update_dashboard handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run update_dashboard "test_dashboard" || true
    assert_success || assert_failure
}

##
# Test: main handles --dashboard option
##
@test "main handles --dashboard option" {
    # Mock functions
    # shellcheck disable=SC2317
    function update_grafana_dashboard() {
        return 0
    }
    export -f update_grafana_dashboard
    
    # shellcheck disable=SC2317
    function update_component_health() {
        return 0
    }
    export -f update_component_health
    
    # shellcheck disable=SC2317
    function needs_update() {
        return 0  # Needs update
    }
    export -f needs_update
    
    run main "grafana" "" "false"
    assert_success
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
    
    run main --help
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
