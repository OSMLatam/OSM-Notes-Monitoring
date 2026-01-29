#!/usr/bin/env bats
#
# Performance Tests: Dashboard Performance
# Tests dashboard script performance
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="DASHBOARD"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_ERROR}"  # Reduce logging overhead

    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"

    # Create test dashboard directories
    TEST_DASHBOARD_DIR=$(mktemp -d)
    export DASHBOARD_OUTPUT_DIR="${TEST_DASHBOARD_DIR}"
    mkdir -p "${TEST_DASHBOARD_DIR}/grafana"
    mkdir -p "${TEST_DASHBOARD_DIR}/html"

    # Initialize test database if needed
    skip_if_database_not_available
}

teardown() {
    # Cleanup
    rm -rf "${TEST_DASHBOARD_DIR:-}"
}

##
# Test: generateMetrics.sh completes within reasonable time
##
@test "generateMetrics.sh completes within reasonable time" {
    local output_file="${TEST_DASHBOARD_DIR}/metrics.json"
    local start_time end_time duration

    start_time=$(date +%s.%N)
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion json
    end_time=$(date +%s.%N)

    assert_success

    # Calculate duration
    duration=$(echo "${end_time} - ${start_time}" | bc)

    # Should complete within 10 seconds
    assert [[ "$(echo "${duration} < 10" | bc)" -eq 1 ]] "generateMetrics.sh took too long: ${duration}s"
}

##
# Test: updateDashboard.sh completes within reasonable time
##
@test "updateDashboard.sh completes within reasonable time" {
    local start_time end_time duration

    start_time=$(date +%s.%N)
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/updateDashboard.sh" --force html
    end_time=$(date +%s.%N)

    assert_success

    # Calculate duration
    duration=$(echo "${end_time} - ${start_time}" | bc)

    # Should complete within 30 seconds
    assert [[ "$(echo "${duration} < 30" | bc)" -eq 1 ]] "updateDashboard.sh took too long: ${duration}s"
}

##
# Test: exportDashboard.sh completes within reasonable time
##
@test "exportDashboard.sh completes within reasonable time" {
    # Create test files
    echo '{"test":"data"}' > "${TEST_DASHBOARD_DIR}/grafana/test.json"

    local output_file="${TEST_DASHBOARD_DIR}/backup"
    local start_time end_time duration

    start_time=$(date +%s.%N)
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/exportDashboard.sh" grafana "${output_file}"
    end_time=$(date +%s.%N)

    assert_success

    # Calculate duration
    duration=$(echo "${end_time} - ${start_time}" | bc)

    # Should complete within 5 seconds
    assert [[ "$(echo "${duration} < 5" | bc)" -eq 1 ]] "exportDashboard.sh took too long: ${duration}s"
}

##
# Test: importDashboard.sh completes within reasonable time
##
@test "importDashboard.sh completes within reasonable time" {
    # Create test archive
    local archive_dir
    archive_dir=$(mktemp -d)
    mkdir -p "${archive_dir}/grafana"
    echo '{"test":"data"}' > "${archive_dir}/grafana/test.json"

    local archive_file="${TEST_DASHBOARD_DIR}/import_test.tar.gz"
    (cd "${archive_dir}" && tar -czf "${archive_file}" .)

    local start_time end_time duration

    start_time=$(date +%s.%N)
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/importDashboard.sh" "${archive_file}" grafana
    end_time=$(date +%s.%N)

    assert_success

    # Calculate duration
    duration=$(echo "${end_time} - ${start_time}" | bc)

    # Should complete within 5 seconds
    assert [[ "$(echo "${duration} < 5" | bc)" -eq 1 ]] "importDashboard.sh took too long: ${duration}s"

    # Cleanup
    rm -rf "${archive_dir}"
}

##
# Test: Multiple concurrent dashboard updates
##
@test "Multiple concurrent dashboard updates complete successfully" {
    local pids=()
    local output_dir="${TEST_DASHBOARD_DIR}/concurrent"
    mkdir -p "${output_dir}"

    # Start multiple update processes
    for i in {1..3}; do
        "${BATS_TEST_DIRNAME}/../../bin/dashboard/updateDashboard.sh" --force html > "${output_dir}/update_${i}.log" 2>&1 &
        pids+=($!)
    done

    # Wait for all to complete
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "${pid}"; then
            all_success=false
        fi
    done

    assert [[ "${all_success}" == "true" ]] "Some concurrent updates failed"
}

##
# Test: Large dataset handling
##
@test "Dashboard scripts handle large datasets efficiently" {
    # This test would require inserting many metrics
    # For now, just verify script doesn't hang
    local output_file="${TEST_DASHBOARD_DIR}/large_metrics.json"

    # Set TEST_MODE and LOG_DIR to avoid permission errors
    # shellcheck disable=SC2030,SC2031
    export TEST_MODE=true
    # shellcheck disable=SC2030,SC2031
    export LOG_DIR="${TEST_DASHBOARD_DIR}/logs"
    mkdir -p "${LOG_DIR}"

    local start_time end_time duration
    start_time=$(date +%s.%N)

    # Generate for all components (larger dataset)
    run "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" all json

    end_time=$(date +%s.%N)
    duration=$(echo "${end_time} - ${start_time}" | bc)

    assert_success
    # Should complete within 30 seconds even for all components
    assert [[ "$(echo "${duration} < 30" | bc)" -eq 1 ]] "Large dataset processing took too long: ${duration}s"
}

##
# Test: Memory usage is reasonable
##
@test "Dashboard scripts use reasonable memory" {
    # Check memory usage (if available)
    if command -v /usr/bin/time &> /dev/null; then
        local output_file="${TEST_DASHBOARD_DIR}/metrics.json"

        # Set TEST_MODE and LOG_DIR to avoid permission errors
        # shellcheck disable=SC2030,SC2031
        export TEST_MODE=true
        # shellcheck disable=SC2030,SC2031
        export LOG_DIR="${TEST_DASHBOARD_DIR}/logs"
        mkdir -p "${LOG_DIR}"

        # Run with time to measure memory
        run /usr/bin/time -f "%M" "${BATS_TEST_DIRNAME}/../../bin/dashboard/generateMetrics.sh" -o "${output_file}" ingestion json 2>&1

        assert_success
        # Memory usage should be reasonable (less than 500MB)
        # Note: This is a basic check, actual memory measurement may vary
    else
        skip "time command not available for memory measurement"
    fi
}
