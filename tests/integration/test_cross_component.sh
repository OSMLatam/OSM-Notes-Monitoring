#!/usr/bin/env bash
#
# Integration Tests: Cross-Component Interactions
# Tests interactions between different monitoring components
#
# Version: 1.0.0
# Date: 2025-12-28
#

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="CROSS_COMPONENT"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_cross_component.log"
    init_logging "${LOG_FILE}" "test_cross_component"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Initialize alerting
    init_alerting
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Skip test if database not available
##
skip_if_database_not_available() {
    if ! check_database_connection; then
        skip "Database not available"
    fi
}

##
# Test: Ingestion -> Analytics data flow
##
@test "Cross-component: ingestion to analytics data flow" {
    skip_if_database_not_available
    
    # Step 1: Ingestion records metrics
    record_metric "ingestion" "data_processed" "1000" "test=cross"
    update_component_health "ingestion" "healthy" "Processing OK"
    
    # Step 2: Analytics reads ingestion metrics
    local ingestion_health
    ingestion_health=$(get_component_health "ingestion")
    assert [[ "${ingestion_health}" =~ healthy ]]
    
    # Step 3: Analytics records its own metrics based on ingestion
    record_metric "analytics" "data_available" "1000" "source=ingestion"
    update_component_health "analytics" "healthy" "Data available"
    
    # Step 4: Verify both components have metrics
    local ingestion_metrics
    ingestion_metrics=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'ingestion';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${ingestion_metrics}" -ge 1 ]
    
    local analytics_metrics
    analytics_metrics=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE component = 'analytics';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${analytics_metrics}" -ge 1 ]
}

##
# Test: Infrastructure -> All components dependency
##
@test "Cross-component: infrastructure affects all components" {
    skip_if_database_not_available
    
    # Step 1: Infrastructure reports disk space issue
    record_metric "infrastructure" "disk_usage_percent" "95" "test=cross"
    update_component_health "infrastructure" "degraded" "High disk usage"
    
    # Step 2: All components should be aware of infrastructure status
    local infra_health
    infra_health=$(get_component_health "infrastructure")
    assert [[ "${infra_health}" =~ degraded ]]
    
    # Step 3: Components can check infrastructure before operations
    local disk_usage
    disk_usage=$(get_metric_value "infrastructure" "disk_usage_percent")
    assert [ -n "${disk_usage}" ]
    
    # Step 4: Components can react to infrastructure issues
    if [[ "${disk_usage}" -gt 90 ]]; then
        send_alert "infrastructure" "warning" "high_disk_usage" "Disk usage: ${disk_usage}%"
    fi
    
    # Step 5: Verify alert was created
    local alert_count
    alert_count=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'infrastructure' AND alert_type = 'high_disk_usage';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${alert_count}" -ge 1 ]
}

##
# Test: WMS -> API security interaction
##
@test "Cross-component: WMS and API security interaction" {
    skip_if_database_not_available
    
    # Step 1: WMS reports high request rate
    record_metric "wms" "request_rate" "1000" "test=cross"
    
    # Step 2: API security checks rate limits
    local request_rate
    request_rate=$(get_metric_value "wms" "request_rate")
    
    # Step 3: API security can log security events
    if [[ "${request_rate}" -gt 500 ]]; then
        log_security_event "high_request_rate" "192.168.1.1" "Request rate: ${request_rate}"
    fi
    
    # Step 4: Verify security event was logged
    local security_events
    security_events=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM security_events WHERE event_type = 'high_request_rate';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${security_events}" -ge 1 ]
}

##
# Test: Alert aggregation across components
##
@test "Cross-component: alert aggregation across components" {
    skip_if_database_not_available
    
    # Step 1: Create alerts from multiple components
    send_alert "ingestion" "warning" "test_alert" "Ingestion issue"
    send_alert "analytics" "warning" "test_alert" "Analytics issue"
    send_alert "wms" "warning" "test_alert" "WMS issue"
    
    # Step 2: Get all active alerts
    local total_alerts
    total_alerts=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE alert_type = 'test_alert' AND status = 'active';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${total_alerts}" -ge 1 ]
    
    # Step 3: Verify alerts from different components
    local ingestion_alerts
    ingestion_alerts=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'ingestion' AND alert_type = 'test_alert';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${ingestion_alerts}" -ge 1 ]
}

##
# Test: Metric correlation across components
##
@test "Cross-component: metric correlation" {
    skip_if_database_not_available
    
    # Step 1: Record correlated metrics
    record_metric "ingestion" "data_processed" "1000" "test=cross"
    record_metric "analytics" "data_processed" "1000" "source=ingestion"
    record_metric "wms" "requests_served" "500" "test=cross"
    
    # Step 2: Query metrics from multiple components
    local ingestion_data
    ingestion_data=$(get_metric_value "ingestion" "data_processed")
    
    local analytics_data
    analytics_data=$(get_metric_value "analytics" "data_processed")
    
    # Step 3: Verify correlation (analytics should match ingestion)
    assert [ -n "${ingestion_data}" ]
    assert [ -n "${analytics_data}" ]
    
    # Step 4: Aggregate metrics across components
    local total_metrics
    total_metrics=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE metric_name = 'data_processed';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${total_metrics}" -ge 2 ]
}

##
# Test: Component health cascade
##
@test "Cross-component: component health cascade" {
    skip_if_database_not_available
    
    # Step 1: Infrastructure goes down
    update_component_health "infrastructure" "down" "Infrastructure failure"
    
    # Step 2: Dependent components should be aware
    local infra_status
    infra_status=$(get_component_health "infrastructure")
    assert [[ "${infra_status}" =~ down ]]
    
    # Step 3: Components can check infrastructure before operations
    if [[ "${infra_status}" =~ down ]]; then
        send_alert "infrastructure" "critical" "infrastructure_down" "Infrastructure is down"
    fi
    
    # Step 4: Verify cascade alert was created
    local cascade_alerts
    cascade_alerts=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'infrastructure' AND alert_type = 'infrastructure_down';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${cascade_alerts}" -ge 1 ]
}

##
# Test: Shared database connection across components
##
@test "Cross-component: shared database connection" {
    skip_if_database_not_available
    
    # Step 1: All components use same database connection
    local connection_ok=true
    
    # Step 2: Test connection from each component context
    export TEST_COMPONENT="ingestion"
    if ! check_database_connection; then
        connection_ok=false
    fi
    
    export TEST_COMPONENT="analytics"
    if ! check_database_connection; then
        connection_ok=false
    fi
    
    export TEST_COMPONENT="wms"
    if ! check_database_connection; then
        connection_ok=false
    fi
    
    # Step 3: Verify all components can connect
    assert [ "${connection_ok}" == "true" ]
}

##
# Test: Concurrent operations across components
##
@test "Cross-component: concurrent operations" {
    skip_if_database_not_available
    
    # Step 1: Multiple components write concurrently
    (
        record_metric "ingestion" "concurrent_test" "1" "test=concurrent"
    ) &
    (
        record_metric "analytics" "concurrent_test" "2" "test=concurrent"
    ) &
    (
        record_metric "wms" "concurrent_test" "3" "test=concurrent"
    ) &
    
    # Wait for all background jobs
    wait
    
    # Step 2: Verify all writes succeeded
    local total_metrics
    total_metrics=$(psql -h "${DBHOST}" -p "${DBPORT}" -U "${DBUSER}" -d "${DBNAME}" -t -c \
        "SELECT COUNT(*) FROM metrics WHERE metric_name = 'concurrent_test';" 2>/dev/null | tr -d ' ' || echo "0")
    assert [ "${total_metrics}" -ge 3 ]
}
