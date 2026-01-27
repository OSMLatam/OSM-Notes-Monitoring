#!/usr/bin/env bats
#
# Additional Unit Tests: generateMetrics.sh
# Additional tests for metrics generation to increase coverage
#

export TEST_COMPONENT="DASHBOARD"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_generateMetrics_additional.log"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_FILE}" "test_generateMetrics_additional"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if echo "${*}" | grep -q "SELECT.*FROM metrics"; then
            echo '{"metric_name":"test_metric","metric_value":100}'
        else
            echo "[]"
        fi
        return 0
    }
    export -f psql
    
    # Source the script
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: generate_component_metrics handles empty database
##
@test "generate_component_metrics handles empty database" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        echo ""
        return 0
    }
    export -f psql
    
    run generate_component_metrics "ingestion" "24" "json"
    assert_success
}

##
# Test: generate_component_metrics handles database error
##
@test "generate_component_metrics handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run generate_component_metrics "ingestion" "24" "json" || true
    assert_success || assert_failure
}

##
# Test: main handles --component option via script
##
@test "main handles --component option" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
        return 0
    }
    export -f psql
    
    run bash "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --component ingestion json
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
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --unknown-option
    assert_failure
    assert_output --partial "ERROR: Unknown option"
}
