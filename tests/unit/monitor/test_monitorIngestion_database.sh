#!/usr/bin/env bash
#
# Unit Tests: monitorIngestion.sh - Advanced Database Metrics Tests
# Tests advanced database metrics check function
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_INGESTION_DIR}/bin"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export INGESTION_ENABLED="true"
    export INGESTION_DB_CACHE_HIT_THRESHOLD="95"
    export INGESTION_DB_CONNECTION_USAGE_THRESHOLD="80"
    
    # Disable alerts for unit tests
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    export ADMIN_EMAIL="test@example.com"
    export ALERT_RECIPIENTS="test@example.com"
    
    # Mock database functions
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Use a file to track alerts
    ALERTS_FILE="${TEST_LOG_DIR}/alerts_sent.txt"
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    export ALERTS_FILE
    
    # Mock execute_sql_query to return test data
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        # Return cache hit ratio = 98% (above threshold)
        if [[ "${query}" == *"db_cache_hit_ratio"* ]]; then
            echo "98"
            return 0
        fi
        
        # Return slow queries = 0
        if [[ "${query}" == *"db_slow_queries_count"* ]]; then
            echo "0"
            return 0
        fi
        
        # Return connection usage = 10% (below threshold)
        if [[ "${query}" == *"db_connection_usage_percent"* ]]; then
            echo "10"
            return 0
        fi
        
        # Return deadlocks = 0
        if [[ "${query}" == *"db_deadlocks_count"* ]]; then
            echo "0"
            return 0
        fi
        
        return 0
    }
    export -f execute_sql_query
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        echo "" 2>/dev/null
        return 0
    }
    export -f psql
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test_monitorIngestion_database.log" "test_monitorIngestion_database"
    
    # Initialize alerting (but we'll override send_alert)
    init_alerting
    
    # Override send_alert BEFORE sourcing monitorIngestion.sh
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
    
    # Source monitorIngestion.sh functions
    export TEST_MODE=true
    export COMPONENT="INGESTION"
    
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorIngestion.sh" 2>/dev/null || true
    
    # Ensure send_alert is still our mock after sourcing
    # shellcheck disable=SC2317
    send_alert() {
        echo "$*" >> "${ALERTS_FILE}"
        return 0
    }
    export -f send_alert
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

@test "check_advanced_database_metrics succeeds when all metrics are healthy" {
    # Mock bash to handle collectDatabaseMetrics.sh execution
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDatabaseMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Run check
    run check_advanced_database_metrics
    
    # Should succeed
    assert_success
}

@test "check_advanced_database_metrics alerts when cache hit ratio is below threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDatabaseMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Mock execute_sql_query to return low cache hit ratio
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"db_cache_hit_ratio"* ]]; then
            echo "90"  # Below threshold of 95
            return 0
        fi
        
        if [[ "${query}" == *"db_slow_queries_count"* ]]; then
            echo "0"
            return 0
        fi
        
        if [[ "${query}" == *"db_connection_usage_percent"* ]]; then
            echo "10"
            return 0
        fi
        
        if [[ "${query}" == *"db_deadlocks_count"* ]]; then
            echo "0"
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_advanced_database_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"db_cache_hit_ratio"* ]] || [[ "${alert}" == *"Cache hit ratio"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_database_metrics alerts when slow queries detected" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDatabaseMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Mock execute_sql_query to return slow queries
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"db_cache_hit_ratio"* ]]; then
            echo "98"
            return 0
        fi
        
        if [[ "${query}" == *"db_slow_queries_count"* ]]; then
            echo "5"  # Slow queries detected
            return 0
        fi
        
        if [[ "${query}" == *"db_connection_usage_percent"* ]]; then
            echo "10"
            return 0
        fi
        
        if [[ "${query}" == *"db_deadlocks_count"* ]]; then
            echo "0"
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_advanced_database_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"db_slow_queries"* ]] || [[ "${alert}" == *"slow queries"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_database_metrics alerts when connection usage exceeds threshold" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDatabaseMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Mock execute_sql_query to return high connection usage
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"db_cache_hit_ratio"* ]]; then
            echo "98"
            return 0
        fi
        
        if [[ "${query}" == *"db_slow_queries_count"* ]]; then
            echo "0"
            return 0
        fi
        
        if [[ "${query}" == *"db_connection_usage_percent"* ]]; then
            echo "85"  # Above threshold of 80
            return 0
        fi
        
        if [[ "${query}" == *"db_deadlocks_count"* ]]; then
            echo "0"
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    check_advanced_database_metrics
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"db_connection_usage"* ]] || [[ "${alert}" == *"Connection usage"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_database_metrics alerts critically when deadlocks detected" {
    # Reset alerts file
    rm -f "${ALERTS_FILE}"
    touch "${ALERTS_FILE}"
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        local script_path="${1}"
        if [[ "${script_path}" == *"collectDatabaseMetrics.sh" ]]; then
            return 0
        fi
        command bash "$@"
    }
    export -f bash
    
    # Mock execute_sql_query to return deadlocks
    # shellcheck disable=SC2317
    execute_sql_query() {
        local query="${1}"
        
        if [[ "${query}" == *"db_cache_hit_ratio"* ]]; then
            echo "98"
            return 0
        fi
        
        if [[ "${query}" == *"db_slow_queries_count"* ]]; then
            echo "0"
            return 0
        fi
        
        if [[ "${query}" == *"db_connection_usage_percent"* ]]; then
            echo "10"
            return 0
        fi
        
        if [[ "${query}" == *"db_deadlocks_count"* ]]; then
            echo "2"  # Deadlocks detected
            return 0
        fi
        
        echo ""
        return 0
    }
    export -f execute_sql_query
    
    # Run check
    run check_advanced_database_metrics
    
    # Should fail (deadlocks are critical)
    assert_failure
    
    # Check that alert was sent
    local alert_found=false
    if [[ -f "${ALERTS_FILE}" ]]; then
        while IFS= read -r alert; do
            if [[ "${alert}" == *"db_deadlocks"* ]] || [[ "${alert}" == *"deadlocks"* ]] || [[ "${alert}" == *"CRITICAL"* ]]; then
                alert_found=true
                break
            fi
        done < "${ALERTS_FILE}"
    fi
    
    assert_equal "true" "${alert_found}"
}

@test "check_advanced_database_metrics handles missing script gracefully" {
    # Mock test to check if script file exists check works
    # The function checks for script existence, so we'll test that path
    
    # Mock bash
    # shellcheck disable=SC2317
    bash() {
        return 0
    }
    export -f bash
    
    # The actual test: if the script file doesn't exist at SCRIPT_DIR/collectDatabaseMetrics.sh,
    # the function should return 0 (success) with a warning, not fail
    local script_path="${SCRIPT_DIR}/collectDatabaseMetrics.sh"
    if [[ ! -f "${script_path}" ]]; then
        # Script doesn't exist, test should pass (graceful handling)
        run check_advanced_database_metrics
        assert_success
    else
        # Script exists, skip this test or test a different scenario
        skip "collectDatabaseMetrics.sh exists, cannot test missing script scenario easily"
    fi
}
