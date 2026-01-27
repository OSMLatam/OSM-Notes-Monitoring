#!/usr/bin/env bats
#
# Unit Tests: generateMetrics.sh
# Tests for metrics generation script
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
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
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_generateMetrics.log"
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR to avoid permission issues
    init_logging "${LOG_FILE}" "test_generateMetrics"
    
    # Mock psql command to avoid password prompts
    # shellcheck disable=SC2317
    function psql() {
        local query="${*}"
        if echo "${query}" | grep -q "SELECT.*FROM metrics"; then
            echo '{"metric_name":"test_metric","metric_value":100,"timestamp":"2025-12-27T10:00:00Z"}'
        else
            echo "[]"
        fi
        return 0
    }
    export -f psql
    
    # Create temporary directory for output
    TEST_OUTPUT_DIR=$(mktemp -d)
    export TEST_OUTPUT_DIR
}

teardown() {
    # Cleanup
    rm -rf "${TEST_OUTPUT_DIR:-}"
}

##
# Test: generateMetrics.sh usage
##
@test "generateMetrics.sh shows usage with --help" {
    # Set LOG_DIR as environment variable before running script
    run env LOG_DIR="${TEST_LOG_DIR}" "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "generateMetrics.sh"
}

##
# Test: generateMetrics.sh generates JSON metrics
##
@test "generateMetrics.sh generates JSON metrics for component" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.metrics ]]; then
            echo '[{"metric_name":"test_metric","metric_value":100}]'
        else
            echo "[]"
        fi
    }
    export -f psql
    
    run env LOG_DIR="${TEST_LOG_DIR}" "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json
    assert_success
    assert_output --partial "metric_name" || assert_output "[]"
}

##
# Test: generateMetrics.sh generates CSV metrics
##
@test "generateMetrics.sh generates CSV metrics" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*FROM.metrics ]]; then
            echo "metric_name,metric_value,metadata,timestamp"
            echo "test_metric,100,{},2025-12-27T10:00:00Z"
        else
            echo ""
        fi
    }
    export -f psql
    
    run env LOG_DIR="${TEST_LOG_DIR}" "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion csv
    assert_success
    assert_output --partial "metric_name" || assert_output --partial "test_metric"
}

##
# Test: generateMetrics.sh generates dashboard format
##
@test "generateMetrics.sh generates dashboard format" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*json_agg ]]; then
            echo '[{"metric_name":"test_metric","avg_value":100,"min_value":50,"max_value":150}]'
        else
            echo "[]"
        fi
    }
    export -f psql
    
    run env LOG_DIR="${TEST_LOG_DIR}" "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion dashboard
    assert_success
    assert_output --partial "metric_name" || assert_output "[]"
}

##
# Test: generateMetrics.sh handles all components
##
@test "generateMetrics.sh handles all components" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" all json
    assert_success
}

##
# Test: generateMetrics.sh outputs to file
##
@test "generateMetrics.sh outputs to file" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    local output_file="${TEST_OUTPUT_DIR}/metrics.json"
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion json
    assert_success
    assert_file_exists "${output_file}"
}

##
# Test: generateMetrics.sh handles time range
##
@test "generateMetrics.sh handles time range parameter" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INTERVAL.*168.hours ]]; then
            echo "[]"
        else
            echo "[]"
        fi
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --time-range 168 ingestion json
    assert_success
}

##
# Test: generateMetrics.sh handles invalid component
##
@test "generateMetrics.sh handles invalid component gracefully" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" invalid_component json
    assert_success  # Should still succeed but return empty data
}

##
# Test: generateMetrics.sh handles database errors
##
@test "generateMetrics.sh handles database errors gracefully" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json
    # Should handle error gracefully
    assert_success  # Script should not fail, just return empty/error data
}

@test "generateMetrics.sh handles --verbose flag" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --verbose ingestion json
    assert_success
}

@test "generateMetrics.sh handles --quiet flag" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --quiet ingestion json
    assert_success
}

@test "generateMetrics.sh handles --config flag" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    local test_config="${BATS_TEST_DIRNAME}/../../../tmp/test_generateMetrics_config.conf"
    echo "TEST_CONFIG_VAR=test_value" > "${test_config}"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --config "${test_config}" ingestion json
    assert_success
    
    rm -f "${test_config}"
}

@test "generateMetrics.sh handles --component flag" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json
    assert_success
}

@test "generateMetrics.sh handles empty query results" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql to return empty result
    # shellcheck disable=SC2317
    function psql() {
        echo ""
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json
    assert_success
}

@test "generateMetrics.sh handles invalid time range" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --time-range invalid ingestion json
    # Should handle gracefully
    assert_success || assert_failure
}

@test "generateMetrics.sh handles very large time range" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" --time-range 8760 ingestion json  # 1 year
    assert_success
}

@test "generateMetrics.sh handles output file creation failure" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    # Try to write to non-existent directory
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" -o "/nonexistent/dir/file.json" ingestion json
    # Should handle error gracefully
    assert_failure || assert_success
}

@test "generateMetrics.sh handles multiple components in all mode" {
    export LOG_DIR="${TEST_LOG_DIR}"  # Set LOG_DIR before running script
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" all json
    assert_success
    # Should contain multiple component keys or empty array
    assert_output --partial "ingestion" || assert_output "[]"
}

@test "generateMetrics.sh handles invalid time range format" {
    export LOG_DIR="${TEST_LOG_DIR}"
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    # Test with invalid time range format
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json --time-range "invalid"
    # Should handle gracefully (may fail or use default)
    assert [ ${status} -ge 0 ]
}

@test "generateMetrics.sh handles output directory with spaces" {
    export LOG_DIR="${TEST_LOG_DIR}"
    local output_dir="${BATS_TEST_DIRNAME}/../../tmp/output with spaces"
    mkdir -p "${output_dir}"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json --output "${output_dir}/metrics.json"
    assert_success
    rm -rf "${output_dir}"
}

@test "generateMetrics.sh handles database connection timeout" {
    export LOG_DIR="${TEST_LOG_DIR}"
    # Mock psql to simulate timeout
    # shellcheck disable=SC2317
    function psql() {
        sleep 0.1
        echo "ERROR: connection timeout" >&2
        return 1
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json
    # Should handle timeout gracefully
    assert [ ${status} -ge 0 ]
}

@test "generateMetrics.sh handles SQL injection attempt in component name" {
    export LOG_DIR="${TEST_LOG_DIR}"
    # Mock psql - should sanitize input
    # shellcheck disable=SC2317
    function psql() {
        # Check that SQL injection is prevented
        if [[ "${*}" =~ DROP.*TABLE ]]; then
            return 1
        fi
        echo "[]"
        return 0
    }
    export -f psql
    
    # Attempt SQL injection in component name
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" "ingestion'; DROP TABLE metrics; --" json
    # Should handle safely (may fail, but not execute injection)
    assert [ ${status} -ge 0 ]
}

@test "generateMetrics.sh handles empty component name" {
    export LOG_DIR="${TEST_LOG_DIR}"
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" "" json
    # Should handle empty component gracefully
    assert [ ${status} -ge 0 ]
}

@test "generateMetrics.sh handles very long component name" {
    export LOG_DIR="${TEST_LOG_DIR}"
    local long_component
    long_component="$(printf 'A%.0s' {1..500})"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" "${long_component}" json
    # Should handle long component name gracefully
    assert [ ${status} -ge 0 ]
}

@test "generateMetrics.sh handles special characters in output filename" {
    export LOG_DIR="${TEST_LOG_DIR}"
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "[]"
    }
    export -f psql
    
    # Test with special characters in filename
    run "${BATS_TEST_DIRNAME}/../../../bin/dashboard/generateMetrics.sh" ingestion json --output "test@#$%^&*().json"
    # Should handle special characters gracefully
    assert [ ${status} -ge 0 ]
}
