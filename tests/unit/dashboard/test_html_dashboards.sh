#!/usr/bin/env bats
#
# Unit Tests: HTML Dashboards
# Tests for HTML dashboard files
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

setup() {
    # Set test directories
    TEST_DASHBOARD_DIR="${BATS_TEST_DIRNAME}/../../../dashboards/html"
    TEST_DATA_DIR=$(mktemp -d)
    
    # Create test data files
    echo '{"ingestion":{"test":"data"}}' > "${TEST_DATA_DIR}/overview_data.json"
    echo '{"status":"healthy","last_check":"2025-12-27T10:00:00Z"}' > "${TEST_DATA_DIR}/component_health.json"
    echo '[{"component":"ingestion","alert_level":"warning","message":"Test alert"}]' > "${TEST_DATA_DIR}/recent_alerts.json"
    
    # Create component data files
    for comp in ingestion analytics wms api infrastructure data; do
        echo "[{\"metric_name\":\"test_metric\",\"metric_value\":100,\"timestamp\":\"2025-12-27T10:00:00Z\"}]" > "${TEST_DATA_DIR}/${comp}_data.json"
    done
}

teardown() {
    rm -rf "${TEST_DATA_DIR:-}"
}

##
# Test: overview.html exists and is valid HTML
##
@test "overview.html exists and is valid HTML" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/overview.html"
    
    # Check for basic HTML structure (case-insensitive)
    run grep -qi "<!doctype html>" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
    
    run grep -qi "<html" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
    
    run grep -qi "</html>" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
}

##
# Test: overview.html contains required JavaScript
##
@test "overview.html contains required JavaScript functions" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/overview.html"
    
    # Check for key JavaScript functions
    run grep -q "function loadData" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
    
    run grep -q "updateStatusGrid" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
    
    run grep -q "updateAlerts" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
}

##
# Test: overview.html loads data files
##
@test "overview.html references required data files" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/overview.html"
    
    # Check for data file references
    run grep -q "overview_data.json" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
    
    run grep -q "component_health.json" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
    
    run grep -q "recent_alerts.json" "${TEST_DASHBOARD_DIR}/overview.html"
    assert_success
}

##
# Test: component_status.html exists and is valid HTML
##
@test "component_status.html exists and is valid HTML" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/component_status.html"
    
    # Check for basic HTML structure (case-insensitive)
    run grep -qi "<!doctype html>" "${TEST_DASHBOARD_DIR}/component_status.html"
    assert_success
    
    run grep -qi "<html" "${TEST_DASHBOARD_DIR}/component_status.html"
    assert_success
}

##
# Test: component_status.html contains component rendering
##
@test "component_status.html contains component rendering functions" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/component_status.html"
    
    # Check for component rendering
    run grep -q "renderComponent" "${TEST_DASHBOARD_DIR}/component_status.html"
    assert_success
    
    run grep -q "loadData" "${TEST_DASHBOARD_DIR}/component_status.html"
    assert_success
}

##
# Test: component_status.html loads component data
##
@test "component_status.html references component data files" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/component_status.html"
    
    # Check for component data references
    run grep -q "_data.json" "${TEST_DASHBOARD_DIR}/component_status.html"
    assert_success
    
    run grep -q "component_health.json" "${TEST_DASHBOARD_DIR}/component_status.html"
    assert_success
}

##
# Test: health_check.html exists and is valid HTML
##
@test "health_check.html exists and is valid HTML" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/health_check.html"
    
    # Check for basic HTML structure (case-insensitive)
    run grep -qi "<!doctype html>" "${TEST_DASHBOARD_DIR}/health_check.html"
    assert_success
    
    run grep -qi "<html" "${TEST_DASHBOARD_DIR}/health_check.html"
    assert_success
}

##
# Test: health_check.html contains health check logic
##
@test "health_check.html contains health check functions" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/health_check.html"
    
    # Check for health check functions
    run grep -q "loadHealthCheck" "${TEST_DASHBOARD_DIR}/health_check.html"
    assert_success
    
    run grep -q "calculateOverallHealth" "${TEST_DASHBOARD_DIR}/health_check.html"
    assert_success
    
    run grep -q "updateHealthStatus" "${TEST_DASHBOARD_DIR}/health_check.html"
    assert_success
}

##
# Test: health_check.html loads component health data
##
@test "health_check.html references component health data" {
    assert_file_exists "${TEST_DASHBOARD_DIR}/health_check.html"
    
    # Check for component health reference
    run grep -q "component_health.json" "${TEST_DASHBOARD_DIR}/health_check.html"
    assert_success
}

##
# Test: HTML dashboards have navigation links
##
@test "HTML dashboards have navigation links between pages" {
    # Check if at least one dashboard has navigation links
    local has_nav=false
    
    # Check overview.html
    if grep -q "component_status.html" "${TEST_DASHBOARD_DIR}/overview.html" || \
       grep -q "health_check.html" "${TEST_DASHBOARD_DIR}/overview.html"; then
        has_nav=true
    fi
    
    # Check component_status.html
    if grep -q "overview.html" "${TEST_DASHBOARD_DIR}/component_status.html" || \
       grep -q "health_check.html" "${TEST_DASHBOARD_DIR}/component_status.html"; then
        has_nav=true
    fi
    
    # Check health_check.html
    if grep -q "overview.html" "${TEST_DASHBOARD_DIR}/health_check.html" || \
       grep -q "component_status.html" "${TEST_DASHBOARD_DIR}/health_check.html"; then
        has_nav=true
    fi
    
    # At least one dashboard should have navigation links
    if [[ "${has_nav}" == "false" ]]; then
        echo "No navigation links found in any HTML dashboard"
        return 1
    fi
}

##
# Test: HTML dashboards have refresh functionality
##
@test "HTML dashboards have refresh functionality" {
    # Check for refresh buttons or auto-refresh
    for html_file in "${TEST_DASHBOARD_DIR}"/*.html; do
        run grep -q "refresh\|Refresh\|setInterval" "${html_file}"
        if [[ ${status} -ne 0 ]]; then
            echo "Missing refresh functionality in $(basename "${html_file}")" >&2
            return 1
        fi
        assert_success
    done
}

##
# Test: HTML dashboards have proper CSS styling
##
@test "HTML dashboards have proper CSS styling" {
    for html_file in "${TEST_DASHBOARD_DIR}"/*.html; do
        # Check for style tag, inline styles, or link to stylesheet
        run grep -qiE "<style|style=|\.css|<link.*stylesheet" "${html_file}"
        if [[ ${status} -ne 0 ]]; then
            echo "Missing CSS styling in $(basename "${html_file}")" >&2
            return 1
        fi
        assert_success
    done
}
