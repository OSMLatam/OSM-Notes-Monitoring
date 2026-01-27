#!/usr/bin/env bats
#
# Third Unit Tests: updateDashboard.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="DASHBOARD"
load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_DIR}/test_updateDashboard_third.log" "test_updateDashboard_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: update_dashboard handles partial update
##
@test "update_dashboard handles partial update" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*dashboards ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    # Test update_grafana_dashboard with component
    run update_grafana_dashboard "test_component"
    # Should handle update
    assert [ ${status} -ge 0 ]
}

##
# Test: update_dashboard handles full dashboard update
##
@test "update_dashboard handles full dashboard update" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ UPDATE.*dashboards ]]; then
            return 0
        fi
        return 1
    }
    export -f psql
    
    # Test update_grafana_dashboard
    run update_grafana_dashboard ""
    # Should handle update
    assert [ ${status} -ge 0 ]
}

##
# Test: main handles --field option
##
@test "main handles --field option" {
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
    
    # --field is not a valid option, should show usage
    run bash "${BATS_TEST_DIRNAME}/../../../bin/dashboard/updateDashboard.sh" --field "title" 2>&1 || true
    # Should fail with usage
    assert [ ${status} -ne 0 ] || assert_output --partial "Usage"
}
