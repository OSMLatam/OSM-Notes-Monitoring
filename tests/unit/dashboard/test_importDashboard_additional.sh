#!/usr/bin/env bats
#
# Additional Unit Tests: importDashboard.sh
# Additional tests for dashboard import to increase coverage
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
    init_logging "${LOG_DIR}/test_importDashboard_additional.log" "test_importDashboard_additional"
    
    # Set up dashboard output directory for tests
    export DASHBOARD_OUTPUT_DIR="${TEST_LOG_DIR}/dashboards"
    mkdir -p "${DASHBOARD_OUTPUT_DIR}/grafana"
    mkdir -p "${DASHBOARD_OUTPUT_DIR}/html"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
    rm -rf "${DASHBOARD_OUTPUT_DIR:-}"
}

##
# Test: importDashboard.sh handles invalid archive file
##
@test "importDashboard.sh handles invalid archive file" {
    local invalid_file="${TEST_LOG_DIR}/invalid.tar.gz"
    echo "invalid archive content" > "${invalid_file}"
    
    # Should fail when trying to extract invalid archive
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --dashboard "${DASHBOARD_OUTPUT_DIR}" "${invalid_file}" grafana
    assert_failure
    
    rm -f "${invalid_file}"
}

##
# Test: importDashboard.sh handles JSON file
##
@test "importDashboard.sh handles JSON file" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    # JSON files are copied directly, so this should succeed
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --dashboard "${DASHBOARD_OUTPUT_DIR}" "${test_file}" grafana
    assert_success
    
    rm -f "${test_file}"
}

##
# Test: importDashboard.sh handles input file as positional argument
##
@test "importDashboard.sh handles input file as positional argument" {
    local test_file="${TEST_LOG_DIR}/test_dashboard.json"
    echo '{"dashboard": {"title": "Test"}}' > "${test_file}"
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --dashboard "${DASHBOARD_OUTPUT_DIR}" "${test_file}" grafana
    assert_success
    
    rm -f "${test_file}"
}

##
# Test: importDashboard.sh handles --help option
##
@test "importDashboard.sh handles --help option" {
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/importDashboard.sh" --help
    assert_success
    assert_output --partial "Usage:"
}
