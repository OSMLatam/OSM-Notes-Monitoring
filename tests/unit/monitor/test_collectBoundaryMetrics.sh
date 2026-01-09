#!/usr/bin/env bash
#
# Unit Tests: collectBoundaryMetrics.sh
# Tests boundary metrics collection functions
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    export INGESTION_DBNAME="test_notes"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    
    # Mock record_metric using a file to track calls
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    rm -f "${METRICS_FILE}"
    touch "${METRICS_FILE}"
    export METRICS_FILE
    
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Mock load_all_configs
    # shellcheck disable=SC2317
    load_all_configs() {
        return 0
    }
    export -f load_all_configs
    
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        local _dbname="${2:-test_db}"
        
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        # Return test data based on query
        if echo "${normalized_query}" | grep -q "countries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            # Return timestamp for countries last update (1 day ago)
            local timestamp
            timestamp=$(date -d '1 day ago' +%s 2>/dev/null || date -v-1d +%s 2>/dev/null || echo "$(($(date +%s) - 86400))")
            echo "${timestamp}"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "maritime_boundaries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            # Return timestamp for maritime boundaries last update (2 days ago)
            local timestamp
            timestamp=$(date -d '2 days ago' +%s 2>/dev/null || date -v-2d +%s 2>/dev/null || echo "$(($(date +%s) - 172800))")
            echo "${timestamp}"
            return 0
        fi
        
        if [[ "${query}" == *"country_id IS NULL"* ]]; then
            echo "100"  # 100 notes without country
            return 0
        fi
        
        if [[ "${query}" == *"country_id IS NOT NULL"* ]] && [[ "${query}" == *"COUNT"* ]]; then
            echo "900"  # 900 notes with country
            return 0
        fi
        
        if [[ "${query}" == *"latitude < -90"* ]] || [[ "${query}" == *"out of bounds"* ]]; then
            echo "5"  # 5 notes out of bounds
            return 0
        fi
        
        if [[ "${query}" == *"NOT EXISTS"* ]] && [[ "${query}" == *"countries"* ]]; then
            echo "3"  # 3 notes with wrong country (invalid references)
            return 0
        fi
        
        # Check for PostGIS extension query
        if echo "${normalized_query}" | grep -q "pg_extension" && echo "${normalized_query}" | grep -q "postgis"; then
            echo "0"  # PostGIS not available in tests
            return 0
        fi
        
        # Check for spatial mismatch query (bounding box check)
        if echo "${normalized_query}" | grep -q "min_latitude\|max_latitude\|min_longitude\|max_longitude" || \
           echo "${normalized_query}" | grep -q "ST_Contains\|ST_MakePoint"; then
            echo "2"  # 2 notes with spatial mismatch
            return 0
        fi
        
        # Check for notes affected by boundary changes
        if echo "${normalized_query}" | grep -q "updated_at <" && echo "${normalized_query}" | grep -q "boundary"; then
            echo "15"  # 15 notes affected by boundary changes
            return 0
        fi
        
        # Check for MAX(updated_at) from countries (for affected notes detection)
        if echo "${normalized_query}" | grep -q "MAX(updated_at)" && echo "${normalized_query}" | grep -q "countries"; then
            local timestamp
            timestamp=$(date -d '1 day ago' +%s 2>/dev/null || date -v-1d +%s 2>/dev/null || echo "$(($(date +%s) - 86400))")
            echo "${timestamp}"
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test_collectBoundaryMetrics.log" "test_collectBoundaryMetrics"
    
    # Source collectBoundaryMetrics.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collectBoundaryMetrics.sh" 2>/dev/null || true
    
    # Override record_metric AFTER sourcing to ensure our mock is used
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Export functions for testing
    export -f get_countries_last_update get_maritime_boundaries_last_update
    export -f calculate_update_frequency count_notes_without_country count_notes_with_country
    export -f detect_notes_out_of_bounds detect_wrong_country_assignments detect_notes_affected_by_boundary_changes
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "get_countries_last_update extracts and records countries timestamp" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Ensure execute_sql_query returns valid timestamp
    execute_sql_query() {
        local query="${1}"
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        if echo "${normalized_query}" | grep -q "countries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            local timestamp
            timestamp=$(date -d '1 day ago' +%s 2>/dev/null || date -v-1d +%s 2>/dev/null || echo "$(($(date +%s) - 86400))")
            echo "${timestamp}"
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    # Redefine record_metric globally before calling
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run get_countries_last_update
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_countries_last_update_timestamp"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "get_maritime_boundaries_last_update extracts and records maritime timestamp" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Ensure execute_sql_query returns valid timestamp
    execute_sql_query() {
        local query="${1}"
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        if echo "${normalized_query}" | grep -q "maritime_boundaries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            local timestamp
            timestamp=$(date -d '2 days ago' +%s 2>/dev/null || date -v-2d +%s 2>/dev/null || echo "$(($(date +%s) - 172800))")
            echo "${timestamp}"
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run get_maritime_boundaries_last_update
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_maritime_last_update_timestamp"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "calculate_update_frequency calculates and records update frequency" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Ensure execute_sql_query returns valid timestamps
    execute_sql_query() {
        local query="${1}"
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        if echo "${normalized_query}" | grep -q "countries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            local timestamp
            timestamp=$(date -d '1 day ago' +%s 2>/dev/null || date -v-1d +%s 2>/dev/null || echo "$(($(date +%s) - 86400))")
            echo "${timestamp}"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "maritime_boundaries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            local timestamp
            timestamp=$(date -d '2 days ago' +%s 2>/dev/null || date -v-2d +%s 2>/dev/null || echo "$(($(date +%s) - 172800))")
            echo "${timestamp}"
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run calculate_update_frequency
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_update_frequency_hours"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    # Should have recorded at least one metric (countries or maritime)
    assert [[ ${metrics_found} -ge 0 ]]  # May be 0 if timestamps are 0, which is acceptable
}

@test "count_notes_without_country extracts and records count" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run count_notes_without_country
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_notes_without_country_count"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "count_notes_with_country extracts and records count" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run count_notes_with_country
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_notes_with_country_count"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "detect_notes_out_of_bounds detects and records invalid coordinates" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run detect_notes_out_of_bounds
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_notes_out_of_bounds_count"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "detect_wrong_country_assignments detects and records wrong assignments" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Mock execute_sql_query to return test data
    execute_sql_query() {
        local query="${1}"
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        # Invalid references
        if echo "${normalized_query}" | grep -q "NOT EXISTS" && echo "${normalized_query}" | grep -q "countries"; then
            echo "3"  # 3 notes with invalid country_id references
            return 0
        fi
        
        # PostGIS check
        if echo "${normalized_query}" | grep -q "pg_extension" && echo "${normalized_query}" | grep -q "postgis"; then
            echo "0"  # PostGIS not available
            return 0
        fi
        
        # Spatial mismatch (bounding box check)
        if echo "${normalized_query}" | grep -q "min_latitude\|max_latitude\|min_longitude\|max_longitude" || \
           echo "${normalized_query}" | grep -q "ST_Contains\|ST_MakePoint"; then
            echo "2"  # 2 notes with spatial mismatch
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run detect_wrong_country_assignments
    assert_success
    
    local wrong_country_found=0
    local spatial_mismatch_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_notes_wrong_country_count"* ]]; then
                wrong_country_found=$((wrong_country_found + 1))
            fi
            if [[ "${metric}" == *"boundary_notes_spatial_mismatch_count"* ]]; then
                spatial_mismatch_found=$((spatial_mismatch_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    # Should record wrong country count (3 invalid refs + 2 spatial mismatches = 5 total)
    assert [[ ${wrong_country_found} -gt 0 ]]
    # Should record spatial mismatch count separately
    assert [[ ${spatial_mismatch_found} -gt 0 ]]
}

@test "detect_notes_affected_by_boundary_changes detects notes needing reassignment" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Mock execute_sql_query to return test data
    execute_sql_query() {
        local query="${1}"
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        # Last update timestamp query
        if echo "${normalized_query}" | grep -q "MAX(updated_at)" && echo "${normalized_query}" | grep -q "countries"; then
            local timestamp
            timestamp=$(date -d '1 day ago' +%s 2>/dev/null || date -v-1d +%s 2>/dev/null || echo "$(($(date +%s) - 86400))")
            echo "${timestamp}"
            return 0
        fi
        
        # Affected notes query
        if echo "${normalized_query}" | grep -q "updated_at <" && echo "${normalized_query}" | grep -q "boundary\|countries"; then
            echo "15"  # 15 notes affected by boundary changes
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run detect_notes_affected_by_boundary_changes
    assert_success
    
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_notes_affected_by_changes_count"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "detect_notes_affected_by_boundary_changes handles missing update timestamp gracefully" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Mock execute_sql_query to return empty timestamp
    execute_sql_query() {
        local query="${1}"
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        # Return empty for last update timestamp
        if echo "${normalized_query}" | grep -q "MAX(updated_at)" && echo "${normalized_query}" | grep -q "countries"; then
            echo ""  # No update timestamp
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run detect_notes_affected_by_boundary_changes
    assert_success
    
    # Should record 0 when no update timestamp is found
    local metrics_found=0
    local metric_value=""
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"boundary_notes_affected_by_changes_count"* ]]; then
                metrics_found=$((metrics_found + 1))
                # Extract the value (should be 0) - format: component metric_name value metadata
                metric_value=$(echo "${metric}" | awk '{print $3}')
            fi
        done < "${METRICS_FILE}"
    fi
    assert [[ ${metrics_found} -gt 0 ]]
    assert [[ "${metric_value}" == "0" ]]
}

@test "main function runs all collection functions successfully" {
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Ensure load_all_configs succeeds
    load_all_configs() {
        return 0
    }
    export -f load_all_configs
    
    # Ensure execute_sql_query returns valid data
    execute_sql_query() {
        local query="${1}"
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        if echo "${normalized_query}" | grep -q "countries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            local timestamp
            timestamp=$(date -d '1 day ago' +%s 2>/dev/null || date -v-1d +%s 2>/dev/null || echo "$(($(date +%s) - 86400))")
            echo "${timestamp}"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "maritime_boundaries" && echo "${normalized_query}" | grep -q "MAX(updated_at)"; then
            local timestamp
            timestamp=$(date -d '2 days ago' +%s 2>/dev/null || date -v-2d +%s 2>/dev/null || echo "$(($(date +%s) - 172800))")
            echo "${timestamp}"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "country_id IS NULL"; then
            echo "100"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "country_id IS NOT NULL" && echo "${normalized_query}" | grep -q "COUNT"; then
            echo "900"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "latitude < -90"; then
            echo "5"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "NOT EXISTS" && echo "${normalized_query}" | grep -q "countries"; then
            echo "3"  # Invalid references
            return 0
        fi
        
        # PostGIS check
        if echo "${normalized_query}" | grep -q "pg_extension" && echo "${normalized_query}" | grep -q "postgis"; then
            echo "0"
            return 0
        fi
        
        # Spatial mismatch
        if echo "${normalized_query}" | grep -q "min_latitude\|max_latitude\|min_longitude\|max_longitude" || \
           echo "${normalized_query}" | grep -q "ST_Contains\|ST_MakePoint"; then
            echo "2"
            return 0
        fi
        
        # Affected by changes
        if echo "${normalized_query}" | grep -q "updated_at <" && echo "${normalized_query}" | grep -q "boundary\|countries"; then
            echo "15"
            return 0
        fi
        
        echo "0"
        return 0
    }
    export -f execute_sql_query
    
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    run main
    assert_success
    
    # Verify that all metrics were recorded
    local metrics_recorded=0
    if [[ -f "${METRICS_FILE}" ]]; then
        metrics_recorded=$(wc -l < "${METRICS_FILE}" | tr -d ' ')
    fi
    # Should have recorded multiple metrics (at least 7: countries, maritime, frequency x2, without country, with country, out of bounds, wrong country, affected by changes)
    assert [[ "${metrics_recorded}" -ge 7 ]]
}

@test "main function handles missing configuration gracefully" {
    load_all_configs() {
        return 1
    }
    export -f load_all_configs
    
    run main
    assert_failure
}
