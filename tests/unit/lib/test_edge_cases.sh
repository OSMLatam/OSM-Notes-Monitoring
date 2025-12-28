#!/usr/bin/env bats
#
# Unit Tests: Edge Cases
# Tests edge cases and boundary conditions
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="EDGE_CASES"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_edge_cases.log"
    init_logging "${LOG_FILE}" "test_edge_cases"
    
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
# Test: record_metric with very large value
##
@test "record_metric handles very large metric value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    local large_value="999999999999999999"
    run record_metric "TEST_COMPONENT" "large_metric" "${large_value}" "component=test"
    assert_success
}

##
# Test: record_metric with zero value
##
@test "record_metric handles zero metric value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "TEST_COMPONENT" "zero_metric" "0" "component=test"
    assert_success
}

##
# Test: record_metric with negative value
##
@test "record_metric handles negative metric value" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "TEST_COMPONENT" "negative_metric" "-100" "component=test"
    assert_success
}

##
# Test: record_metric with very long component name
##
@test "record_metric handles very long component name" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    local long_component
    long_component="VERY_LONG_COMPONENT_NAME_$(printf 'A%.0s' {1..100})"
    run record_metric "${long_component}" "test_metric" "100" "component=test"
    assert_success
}

##
# Test: record_metric with empty metadata
##
@test "record_metric handles empty metadata" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" ""
    assert_success
}

##
# Test: send_alert with very long message
##
@test "send_alert handles very long message" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*alerts ]]; then
            return 0
        fi
        return 1
    }
    
    local long_message
    long_message="$(printf 'A%.0s' {1..1000})"
    run send_alert "TEST_COMPONENT" "warning" "test_alert" "${long_message}"
    assert_success
}

##
# Test: get_metric_value with non-existent metric
##
@test "get_metric_value handles non-existent metric" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run get_metric_value "TEST_COMPONENT" "nonexistent_metric_12345"
    assert_success
    assert [[ -z "${output}" ]]
}

##
# Test: check_rate_limit at exact limit boundary
##
@test "check_rate_limit handles request at exact limit boundary" {
    # Mock psql to return exact limit
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "100"
            return 0
        fi
        return 1
    }
    
    # At exact limit (100), should fail (exceeded)
    run check_rate_limit "192.168.1.1" "api_endpoint" 100 60
    assert_failure
}

##
# Test: check_rate_limit just below limit
##
@test "check_rate_limit allows request just below limit" {
    # Mock psql to return just below limit
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "99"
            return 0
        fi
        return 1
    }
    
    run check_rate_limit "192.168.1.1" "api_endpoint" 100 60
    assert_success
}

##
# Test: update_component_health with empty message
##
@test "update_component_health handles empty message" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "healthy" ""
    assert_success
}

##
# Test: aggregate_metrics with single data point
##
@test "aggregate_metrics handles single data point" {
    # Mock psql to return single value
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ AVG.*metric_value ]]; then
            echo "100"
        elif [[ "${*}" =~ COUNT ]]; then
            echo "1"
        fi
        return 0
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "avg" "24 hours"
    assert_success
    assert [[ "${output}" == "100" ]]
}

##
# Test: validate_ip_address with boundary IP values
##
@test "validate_ip_address handles boundary IP values" {
    # Test minimum IP
    run validate_ip_address "0.0.0.0"
    assert_success
    
    # Test maximum IP
    run validate_ip_address "255.255.255.255"
    assert_success
}

##
# Test: record_metric with special characters in metric name
##
@test "record_metric handles special characters in metric name" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "TEST_COMPONENT" "metric_with_underscores_and-numbers-123" "100" "component=test"
    assert_success
}
