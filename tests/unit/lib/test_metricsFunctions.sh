#!/usr/bin/env bats
#
# Unit Tests: metricsFunctions.sh
# Tests for metrics functions library
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="METRICS"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_metricsFunctions.log"
    init_logging "${LOG_FILE}" "test_metricsFunctions"
    
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
# Test: record_metric - records metric successfully
##
@test "record_metric records metric to database" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" "component=test"
    assert_success
}

##
# Test: record_metric - handles database error
##
@test "record_metric handles database error gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" "component=test"
    # Should handle error gracefully
    assert_failure
}

##
# Test: get_metric_value - retrieves metric
##
@test "get_metric_value retrieves latest metric value" {
    # Mock psql to return metric value
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*metric_value ]]; then
            echo "100"
            return 0
        fi
        return 1
    }
    
    run get_metric_value "TEST_COMPONENT" "test_metric"
    assert_success
    assert [[ "${output}" == "100" ]]
}

##
# Test: get_metric_value - no metric found
##
@test "get_metric_value returns empty when metric not found" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run get_metric_value "TEST_COMPONENT" "nonexistent_metric"
    assert_success
    assert [[ -z "${output}" ]]
}

##
# Test: get_metrics_by_component - retrieves multiple metrics
##
@test "get_metrics_by_component retrieves all metrics for component" {
    # Mock psql to return multiple metrics
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.metrics ]]; then
            echo "metric1|100|2025-12-28 10:00:00"
            echo "metric2|200|2025-12-28 10:00:00"
            return 0
        fi
        return 1
    }
    
    run get_metrics_by_component "TEST_COMPONENT"
    assert_success
    assert [[ "${output}" =~ metric1 ]]
    assert [[ "${output}" =~ metric2 ]]
}

##
# Test: aggregate_metrics - calculates average
##
@test "aggregate_metrics calculates average correctly" {
    # Mock psql to return metric values
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ AVG.*metric_value ]]; then
            echo "150.5"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "avg" "24 hours"
    assert_success
    assert [[ "${output}" =~ 150 ]]
}

##
# Test: aggregate_metrics - calculates max
##
@test "aggregate_metrics calculates max correctly" {
    # Mock psql to return max value
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ MAX.*metric_value ]]; then
            echo "300"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "max" "24 hours"
    assert_success
    assert [[ "${output}" == "300" ]]
}

##
# Test: aggregate_metrics - calculates min
##
@test "aggregate_metrics calculates min correctly" {
    # Mock psql to return min value
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ MIN.*metric_value ]]; then
            echo "50"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "min" "24 hours"
    assert_success
    assert [[ "${output}" == "50" ]]
}
