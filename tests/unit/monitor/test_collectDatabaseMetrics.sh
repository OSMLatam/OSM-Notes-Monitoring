#!/usr/bin/env bash
#
# Unit Tests: collectDatabaseMetrics.sh
# Tests advanced database metrics collection functions
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

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
    
    # Mock database functions
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock psql to avoid DB connections
    # shellcheck disable=SC2317
    psql() {
        echo "" 2>/dev/null
        return 0
    }
    export -f psql
    
    # IMPORTANT: Mock execute_sql_query BEFORE sourcing libraries
    # This ensures our mock is used even when monitoringFunctions.sh defines it
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        local _dbname="${2:-test_db}"
        
        # Normalize query by removing whitespace and newlines for matching
        local normalized_query
        normalized_query=$(echo "${query}" | tr -d '\n' | tr -s ' ')
        
        # Debug: log query to file for debugging
        echo "QUERY: ${normalized_query}" >> "${TEST_LOG_DIR}/sql_queries.log" 2>&1 || true
        
        # Return table sizes data (format: tablename|total_size|table_size|indexes_size)
        # Match queries that contain pg_total_relation_size and tablename
        if echo "${normalized_query}" | grep -q "pg_total_relation_size" && echo "${normalized_query}" | grep -q "tablename"; then
            echo "notes|1234567890|1000000000|234567890"
            echo "note_comments|987654321|800000000|187654321"
            echo "MATCHED: table_sizes" >> "${TEST_LOG_DIR}/sql_queries.log" 2>&1 || true
            return 0
        fi
        
        # Return bloat data
        if echo "${normalized_query}" | grep -q "bloat_ratio_percent"; then
            echo "notes|1000000|50000|4.76"
            echo "note_comments|500000|10000|1.96"
            return 0
        fi
        
        # Return index usage data
        if echo "${normalized_query}" | grep -q "index_scan_ratio_percent"; then
            echo "notes|9500|500|95.00"
            echo "note_comments|8000|200|97.56"
            return 0
        fi
        
        # Return unused indexes data
        if echo "${normalized_query}" | grep -q "unused_index_count"; then
            echo "2|1048576"
            return 0
        fi
        
        # Return slow queries data
        if echo "${normalized_query}" | grep -q "slow_query_count"; then
            echo "3"
            return 0
        fi
        
        # Return cache hit ratio
        if echo "${normalized_query}" | grep -q "cache_hit_ratio_percent"; then
            echo "98.5"
            return 0
        fi
        
        # Return connection stats
        if echo "${normalized_query}" | grep -q "application_name" && echo "${normalized_query}" | grep -q "COUNT"; then
            echo "osm-ingestion|5"
            echo "osm-monitoring|2"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "total_connections" && echo "${normalized_query}" | grep -q "active_connections"; then
            echo "10|3|5|1|1"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "connection_usage_percent"; then
            echo "10|100|10.00"
            return 0
        fi
        
        # Return lock stats
        if echo "${normalized_query}" | grep -q "total_locks" && echo "${normalized_query}" | grep -q "granted_locks"; then
            echo "25|24|1"
            return 0
        fi
        
        if echo "${normalized_query}" | grep -q "deadlocks_count\|deadlocks AS"; then
            echo "0"
            return 0
        fi
        
        # Return empty for other queries
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Source libraries (execute_sql_query mock is already set, so it won't be overwritten)
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test_collectDatabaseMetrics.log" "test_collectDatabaseMetrics"
    
    # Source collectDatabaseMetrics.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collectDatabaseMetrics.sh" 2>/dev/null || true
    
    # Mock record_metric AFTER sourcing (metricsFunctions.sh defines it, but we override)
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Export functions for testing
    export -f collect_table_sizes collect_table_bloat collect_index_usage collect_unused_indexes
    export -f collect_slow_queries collect_cache_hit_ratio collect_connection_stats collect_lock_stats
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "collect_table_sizes extracts and records table size metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Redefine record_metric globally before calling
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run function directly (not in wrapper, to avoid subshell issues)
    run collect_table_sizes
    
    # Should succeed
    assert_success
    
    # Debug: Check if metrics file exists and has content
    if [[ -f "${METRICS_FILE}" ]]; then
        local file_size
        file_size=$(wc -l < "${METRICS_FILE}" || echo "0")
        if [[ ${file_size} -eq 0 ]]; then
            echo "DEBUG: METRICS_FILE is empty. Output: ${output}"
            if [[ -f "${TEST_LOG_DIR}/sql_queries.log" ]]; then
                echo "DEBUG: SQL queries log:"
                cat "${TEST_LOG_DIR}/sql_queries.log" || true
            fi
        fi
    else
        echo "DEBUG: METRICS_FILE does not exist. Output: ${output}"
    fi
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"db_table_size_bytes"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded at least some metrics
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "collect_table_bloat extracts and records bloat metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Redefine record_metric just before calling the function
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run function
    run collect_table_bloat
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"db_table_bloat_ratio"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded at least some metrics
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "collect_index_usage extracts and records index usage metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Redefine record_metric just before calling the function
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run function
    run collect_index_usage
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"db_index_scan_ratio"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded at least some metrics
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "collect_unused_indexes extracts and records unused index metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Redefine record_metric just before calling the function
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run function
    run collect_unused_indexes
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"db_unused_indexes"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded metrics
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "collect_slow_queries handles pg_stat_statements not available" {
    # Mock execute_sql_query to return 0 for extension check
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        if [[ "${query}" == *"pg_extension"* ]]; then
            echo "0"
            return 0
        fi
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run function
    run collect_slow_queries
    
    # Should succeed (graceful handling)
    assert_success
}

@test "collect_cache_hit_ratio extracts and records cache hit ratio" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Redefine record_metric just before calling the function
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run function
    run collect_cache_hit_ratio
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"db_cache_hit_ratio"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded metric
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "collect_connection_stats extracts and records connection metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Redefine record_metric just before calling the function
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run function
    run collect_connection_stats
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"db_connections"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded multiple connection metrics
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "collect_lock_stats extracts and records lock metrics" {
    # Reset metrics file
    METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
    : > "${METRICS_FILE}"
    
    # Redefine record_metric just before calling the function
    # shellcheck disable=SC2317
    record_metric() {
        echo "$*" >> "${METRICS_FILE}"
        return 0
    }
    export -f record_metric
    
    # Run function
    run collect_lock_stats
    
    # Should succeed
    assert_success
    
    # Check that metrics were recorded
    local metrics_found=0
    if [[ -f "${METRICS_FILE}" ]]; then
        while IFS= read -r metric; do
            if [[ "${metric}" == *"db_locks"* ]] || [[ "${metric}" == *"db_deadlocks"* ]]; then
                metrics_found=$((metrics_found + 1))
            fi
        done < "${METRICS_FILE}"
    fi
    
    # Should have recorded lock metrics
    assert [[ ${metrics_found} -gt 0 ]]
}

@test "main function runs all collection functions successfully" {
    # Mock load_all_configs
    # shellcheck disable=SC2317
    load_all_configs() {
        return 0
    }
    export -f load_all_configs
    
    # Run main function
    run main
    
    # Should succeed
    assert_success
}

@test "main function handles missing configuration gracefully" {
    # Mock load_all_configs to fail
    # shellcheck disable=SC2317
    load_all_configs() {
        return 1
    }
    export -f load_all_configs
    
    # Run main function
    run main
    
    # Should fail gracefully
    assert_failure
}
