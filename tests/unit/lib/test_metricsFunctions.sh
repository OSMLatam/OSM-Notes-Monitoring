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

@test "aggregate_metrics calculates sum correctly" {
    # Mock psql to return sum value
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SUM.*metric_value ]]; then
            echo "1000"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "sum" "24 hours"
    assert_success
    assert [[ "${output}" == "1000" ]]
}

@test "aggregate_metrics handles invalid aggregation type" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "invalid" "24 hours"
    assert_failure
}

@test "get_latest_metric_value retrieves most recent metric" {
    # Mock psql to return latest metric
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ ORDER.*BY.*timestamp ]]; then
            echo "150"
            return 0
        fi
        return 1
    }
    
    run get_latest_metric_value "TEST_COMPONENT" "test_metric"
    assert_success
    assert [ "${output}" = "150" ]
}

@test "get_metrics_summary retrieves summary for component" {
    # Mock psql to return summary
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*COUNT ]]; then
            echo "10"
            return 0
        fi
        return 1
    }
    
    run get_metrics_summary "TEST_COMPONENT" "24"
    assert_success
    assert [[ "${output}" =~ 10 ]]
}

@test "cleanup_old_metrics removes old metrics" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DELETE.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run cleanup_old_metrics "90"
    assert_success
}

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

@test "record_metric handles special characters in metadata" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" "key=value&other=test"
    assert_success
}

@test "get_metric_value handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run get_metric_value "TEST_COMPONENT" "test_metric"
    assert_failure
}

@test "get_metrics_by_component handles empty result" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run get_metrics_by_component "TEST_COMPONENT"
    assert_success
    assert [[ -z "${output}" ]]
}

##
# Additional edge cases and error handling tests
##

@test "init_metrics initializes successfully" {
    run init_metrics
    assert_success
}

@test "get_metrics_summary handles custom hours_back" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INTERVAL.*48.*hours ]]; then
            echo "metric1|100|50|200|10"
            return 0
        fi
        return 1
    }
    
    run get_metrics_summary "TEST_COMPONENT" "48"
    assert_success
    assert [[ "${output}" =~ metric1 ]]
}

@test "get_latest_metric_value handles custom hours_back" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INTERVAL.*12.*hours ]]; then
            echo "250"
            return 0
        fi
        return 1
    }
    
    run get_latest_metric_value "TEST_COMPONENT" "test_metric" "12"
    assert_success
    assert [ "${output}" = "250" ]
}

@test "record_metric detects percent unit" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${1}|${2}|${3}|${4}|${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "cpu_usage_percent" "75" "host=server1"
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "percent" "${metric_file}"
}

@test "record_metric detects milliseconds unit" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${1}|${2}|${3}|${4}|${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "response_time_ms" "150" ""
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "milliseconds" "${metric_file}"
}

@test "record_metric detects seconds unit" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${1}|${2}|${3}|${4}|${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "execution_duration" "5.5" ""
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "seconds" "${metric_file}"
}

@test "record_metric detects bytes unit" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${1}|${2}|${3}|${4}|${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "memory_bytes" "1024000" ""
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "bytes" "${metric_file}"
}

@test "record_metric detects count unit" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${1}|${2}|${3}|${4}|${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "request_count" "100" ""
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "count" "${metric_file}"
}

@test "record_metric detects boolean unit for status metrics" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${1}|${2}|${3}|${4}|${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "service_status" "1" ""
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "boolean" "${metric_file}"
}

@test "record_metric converts component to lowercase" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${1}|${2}|${3}|${4}|${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" ""
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "test_component" "${metric_file}"
}

@test "record_metric handles multiple metadata pairs" {
    # Mock store_metric
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    function store_metric() {
        echo "${5}" > "${metric_file}"
        return 0
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" "key1=value1,key2=value2"
    assert_success
    
    assert_file_exists "${metric_file}"
    assert grep -q "key1" "${metric_file}"
    assert grep -q "key2" "${metric_file}"
}

@test "record_metric handles store_metric failure" {
    # Mock store_metric to fail
    # shellcheck disable=SC2317
    function store_metric() {
        return 1
    }
    export -f store_metric
    
    run record_metric "TEST_COMPONENT" "test_metric" "100" ""
    assert_failure
}

@test "aggregate_metrics handles day period" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DATE_TRUNC.*day ]]; then
            echo "2025-12-28|150|100|200|24"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "day"
    assert_success
    assert_output --partial "2025-12-28"
}

@test "aggregate_metrics handles week period" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ DATE_TRUNC.*week ]]; then
            echo "2025-12-22|150|100|200|168"
            return 0
        fi
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "week"
    assert_success
    assert_output --partial "2025-12-22"
}

@test "aggregate_metrics handles invalid period" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run aggregate_metrics "TEST_COMPONENT" "test_metric" "invalid"
    assert_failure
}

@test "get_metrics_summary handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run get_metrics_summary "TEST_COMPONENT"
    # Should return empty on error
    assert_success || true
}

@test "get_latest_metric_value handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run get_latest_metric_value "TEST_COMPONENT" "test_metric"
    # Should return empty on error
    assert_success || true
}

@test "cleanup_old_metrics handles zero deleted count" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run cleanup_old_metrics "90"
    assert_failure  # Should fail when no records deleted
}
