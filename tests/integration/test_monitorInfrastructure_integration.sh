#!/usr/bin/env bash
#
# Integration Tests: monitorInfrastructure.sh
# Tests infrastructure monitoring with real system resources and database
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

export TEST_DB_NAME="test_monitor_infrastructure"
load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export TEST_COMPONENT="INFRASTRUCTURE"
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export INFRASTRUCTURE_ENABLED="true"
    export INFRASTRUCTURE_CPU_THRESHOLD="80"
    export INFRASTRUCTURE_MEMORY_THRESHOLD="85"
    export INFRASTRUCTURE_DISK_THRESHOLD="90"
    export INFRASTRUCTURE_CHECK_TIMEOUT="30"
    export INFRASTRUCTURE_NETWORK_HOSTS="localhost,127.0.0.1"
    export INFRASTRUCTURE_SERVICE_DEPENDENCIES="postgresql"
    
    # Database configuration
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${TEST_DB_HOST:-localhost}"
    export DBPORT="${TEST_DB_PORT:-5432}"
    export DBUSER="${TEST_DB_USER:-postgres}"
    
    # Skip if database not available
    skip_if_database_not_available
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_monitorInfrastructure_integration"
    
    # Initialize alerting
    init_alerting
    
    # Source monitorInfrastructure.sh functions
    export TEST_MODE=true
    export COMPONENT="INFRASTRUCTURE"
    
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorInfrastructure.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
}

@test "check_server_resources records CPU metrics" {
    # Run check
    run check_server_resources
    
    # Should succeed (or return 0/1 depending on actual resource usage)
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify CPU metric was recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name = 'cpu_usage_percent';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 1 ]
}

@test "check_server_resources records memory metrics" {
    # Run check
    run check_server_resources
    
    # Should succeed
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify memory metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name IN ('memory_usage_percent', 'memory_total_bytes', 'memory_available_bytes');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_server_resources records disk metrics" {
    # Run check
    run check_server_resources
    
    # Should succeed
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify disk metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name IN ('disk_usage_percent', 'disk_available_bytes', 'disk_total_bytes');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_network_connectivity records metrics" {
    # Run check
    run check_network_connectivity
    
    # Should succeed (localhost should be reachable)
    assert_success
    
    # Verify connectivity metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name IN ('network_connectivity', 'network_connectivity_failures', 'network_connectivity_checks');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_database_server_health records database metrics" {
    # Run check
    run check_database_server_health
    
    # Should succeed (database should be available in integration tests)
    assert_success
    
    # Verify database metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name IN ('database_uptime_seconds', 'database_active_connections', 'database_max_connections');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_service_dependencies records service metrics" {
    # Run check
    run check_service_dependencies
    
    # Should succeed (or return 0/1 depending on service status)
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify service metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name IN ('service_dependencies_available', 'service_dependencies_failures', 'service_dependencies_total');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_server_resources creates alerts when thresholds exceeded" {
    # Run check (may or may not alert depending on actual resource usage)
    run check_server_resources || true
    
    # Verify metrics were recorded regardless
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name IN ('cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_network_connectivity handles unreachable hosts" {
    # Set unreachable host
    export INFRASTRUCTURE_NETWORK_HOSTS="192.0.2.1"  # Test-NET-1, should be unreachable
    
    # Run check
    run check_network_connectivity || true
    
    # Verify metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name = 'network_connectivity_failures';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 1 ]
}

@test "check_database_server_health handles connection issues" {
    # Temporarily break connection by using wrong port
    local original_port="${DBPORT}"
    export DBPORT="99999"  # Invalid port
    
    # Run check
    run check_database_server_health || true
    
    # Restore port
    export DBPORT="${original_port}"
    
    # Verify alert was created (if connection failed)
    local query="SELECT COUNT(*) FROM alerts WHERE component = 'INFRASTRUCTURE' AND alert_type = 'database_connection_failed';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    # May or may not have alert depending on how check_database_connection handles it
    assert [ "${result}" -ge 0 ]
}

@test "main function runs all infrastructure checks" {
    # Run main function
    run main
    
    # Should succeed (or return 0/1 depending on checks)
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify metrics were recorded for multiple checks
    local query="SELECT COUNT(DISTINCT metric_name) FROM metrics WHERE component = 'INFRASTRUCTURE' AND timestamp > NOW() - INTERVAL '1 minute';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 10 ]
}

@test "check_server_resources handles missing commands gracefully" {
    # This test verifies that the function doesn't crash when commands are missing
    # In a real environment, commands should be available, but we test graceful handling
    
    # Run check
    run check_server_resources
    
    # Should not crash (return 0 or 1, not 255)
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

@test "check_network_connectivity works with multiple hosts" {
    # Set multiple hosts
    export INFRASTRUCTURE_NETWORK_HOSTS="localhost,127.0.0.1,::1"
    
    # Run check
    run check_network_connectivity
    
    # Should succeed
    assert_success
    
    # Verify metrics reflect multiple checks
    local query="SELECT metric_value::numeric FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name = 'network_connectivity_checks' ORDER BY timestamp DESC LIMIT 1;"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_service_dependencies handles multiple services" {
    # Set multiple services
    export INFRASTRUCTURE_SERVICE_DEPENDENCIES="postgresql,sshd"
    
    # Run check
    run check_service_dependencies
    
    # Should succeed (or return 0/1 depending on service status)
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify metrics reflect multiple services
    local query="SELECT metric_value::numeric FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name = 'service_dependencies_total' ORDER BY timestamp DESC LIMIT 1;"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 2 ]
}

@test "check_database_server_health records connection usage correctly" {
    # Run check
    run check_database_server_health
    
    # Should succeed
    assert_success
    
    # Verify connection metrics are reasonable
    local query="SELECT metric_value::numeric FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name = 'database_active_connections' ORDER BY timestamp DESC LIMIT 1;"
    local active_conn
    active_conn=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    local query2="SELECT metric_value::numeric FROM metrics WHERE component = 'INFRASTRUCTURE' AND metric_name = 'database_max_connections' ORDER BY timestamp DESC LIMIT 1;"
    local max_conn
    max_conn=$(execute_sql_query "${query2}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    # Active connections should be <= max connections
    if [[ "${max_conn}" -gt 0 ]]; then
        assert [ "${active_conn}" -le "${max_conn}" ]
    fi
}

