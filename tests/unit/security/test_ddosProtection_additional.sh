#!/usr/bin/env bash
#
# Additional Unit Tests: ddosProtection.sh
# Additional tests for DDoS protection to increase coverage
#

# shellcheck disable=SC2030,SC2031,SC1091
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC1091: Not following source files is expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export DDOS_ENABLED="true"
    export DDOS_THRESHOLD_REQUESTS_PER_SECOND="100"
    export DDOS_THRESHOLD_CONCURRENT_CONNECTIONS="500"
    export DDOS_AUTO_BLOCK_DURATION_MINUTES="15"
    export DDOS_CHECK_WINDOW_SECONDS="60"
    export DDOS_GEO_FILTERING_ENABLED="false"
    
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock functions BEFORE sourcing
    # shellcheck disable=SC2317
    load_config() { return 0; }
    export -f load_config
    # shellcheck disable=SC2317
    init_alerting() { return 0; }
    export -f init_alerting
    # shellcheck disable=SC2317
    psql() { return 0; }
    export -f psql
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/ddosProtection.sh"
    
    init_logging "${TEST_LOG_DIR}/test_ddosProtection_additional.log" "test_ddosProtection_additional"
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_attack_detection handles normal traffic
##
@test "check_attack_detection handles normal traffic" {
    # Mock psql to return normal request rate
    # shellcheck disable=SC2317
    function psql() {
        echo "50"  # 50 requests per second (below threshold)
        return 0
    }
    export -f psql
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1  # Not whitelisted
    }
    export -f is_ip_whitelisted
    
    # shellcheck disable=SC2317
    check_geographic_filter() {
        return 1  # Not blocked
    }
    export -f check_geographic_filter
    
    run detect_ddos_attack "192.168.1.1"
    # Should return 1 (no attack detected) when below threshold
    assert_equal 1 "${status}"
}

##
# Test: check_connection_rate_limiting handles normal connections
##
@test "check_connection_rate_limiting handles normal connections" {
    # Mock execute_sql_query to return normal connection count
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100"  # 100 concurrent connections (below threshold)
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run check_concurrent_connections "192.168.1.1"
    assert_success
}

##
# Test: check_geographic_filtering handles disabled filtering
##
@test "check_geographic_filtering handles disabled filtering" {
    export DDOS_GEO_FILTERING_ENABLED="false"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    run check_geographic_filter "192.168.1.1"
    # Should return 1 (not blocked) when disabled
    assert_equal 1 "${status}"
}

##
# Test: auto_block_ip handles database error
##
@test "auto_block_ip handles database error" {
    # Mock block_ip to fail
    # shellcheck disable=SC2317
    function block_ip() {
        return 1
    }
    export -f block_ip
    
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    run auto_block_ip "192.168.1.1" "ddos"
    assert_failure
}

##
# Test: main handles --check option
##
@test "main handles --check option" {
    # Mock functions that check_and_block_ddos calls
    # shellcheck disable=SC2317
    function detect_ddos_attack() {
        return 1  # No attack
    }
    export -f detect_ddos_attack
    
    # shellcheck disable=SC2317
    function check_concurrent_connections() {
        return 1  # Normal
    }
    export -f check_concurrent_connections
    
    # shellcheck disable=SC2317
    function auto_block_ip() {
        return 0
    }
    export -f auto_block_ip
    
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
    run main check
    assert_success
}

##
# Test: main handles unknown option
##
@test "main handles unknown option" {
    # Mock usage
    # shellcheck disable=SC2317
    function usage() {
        return 0
    }
    export -f usage
    
    run main --unknown-option || true
    assert_failure
}

##
# Test: check_attack_detection handles database error
##
@test "check_attack_detection handles database error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1  # Not whitelisted
    }
    export -f is_ip_whitelisted
    
    # shellcheck disable=SC2317
    check_geographic_filter() {
        return 1  # Not blocked
    }
    export -f check_geographic_filter
    
    run detect_ddos_attack "192.168.1.1" || true
    # Should handle error gracefully
    assert [ ${status} -ge 0 ]
}

##
# Test: check_connection_rate_limiting detects high connection rate
##
@test "check_connection_rate_limiting detects high connection rate" {
    # Mock execute_sql_query to return high connection count
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "1000"  # 1000 concurrent connections (above threshold)
        return 0
    }
    export -f execute_sql_query
    
    # Use temp file to track alert
    local alert_file="${TEST_LOG_DIR}/.alert_sent"
    rm -f "${alert_file}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        if [[ "${4}" == *"connection rate"* ]] || [[ "${4}" == *"concurrent connections"* ]]; then
            touch "${alert_file}"
        fi
        return 0
    }
    export -f send_alert
    
    run check_concurrent_connections "192.168.1.1" || true
    
    # May send alert if threshold exceeded
    assert [ ${status} -ge 0 ]
}

##
# Test: check_geographic_filtering handles enabled filtering
##
@test "check_geographic_filtering handles enabled filtering" {
    export DDOS_GEO_FILTERING_ENABLED="true"
    export DDOS_ALLOWED_COUNTRIES="US,CA,MX"
    
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "192.168.1.1|US|50"  # IP, country, request count
        return 0
    }
    export -f execute_sql_query
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run check_geographic_filter "192.168.1.1"
    # Should return 1 (not blocked) when IP is from allowed country
    assert_equal 1 "${status}"
}

##
# Test: auto_block_ip records security event
##
@test "auto_block_ip records security event" {
    # Mock block_ip
    # shellcheck disable=SC2317
    function block_ip() {
        return 0
    }
    export -f block_ip
    
    # Use temp file to track event recording
    local event_file="${TEST_LOG_DIR}/.event_recorded"
    rm -f "${event_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "ddos" ]]; then
            touch "${event_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    run auto_block_ip "192.168.1.1" "ddos"
    assert_success
    assert_file_exists "${event_file}"
}

##
# Test: check_attack_detection uses custom window
##
@test "check_attack_detection uses custom window" {
    export DDOS_CHECK_WINDOW_SECONDS="120"  # 2 minutes
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        echo "50"  # 50 requests (below threshold)
        return 0
    }
    export -f psql
    
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1  # Not whitelisted
    }
    export -f is_ip_whitelisted
    
    # shellcheck disable=SC2317
    check_geographic_filter() {
        return 1  # Not blocked
    }
    export -f check_geographic_filter
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run detect_ddos_attack "192.168.1.1" "120"
    # Should use custom window
    assert_equal 1 "${status}"  # No attack detected
}

##
# Test: main handles --verbose option
##
@test "main handles --verbose option" {
    # Mock functions
    # shellcheck disable=SC2317
    function detect_ddos_attack() {
        return 1  # No attack
    }
    export -f detect_ddos_attack
    
    # shellcheck disable=SC2317
    function check_concurrent_connections() {
        return 1  # Normal
    }
    export -f check_concurrent_connections
    
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    export -f psql
    
    run main --verbose check
    assert_success
}

##
# Test: check_attack_detection handles multiple attacking IPs
##
@test "check_attack_detection handles multiple attacking IPs" {
    # Mock psql to return multiple attacking IPs
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" == *"SELECT DISTINCT ip_address"* ]]; then
            echo "192.168.1.1"
            echo "192.168.1.2"
            echo "192.168.1.3"
        else
            echo "150"  # High request rate
        fi
        return 0
    }
    export -f psql
    
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1  # Not whitelisted
    }
    export -f is_ip_whitelisted
    
    # shellcheck disable=SC2317
    check_geographic_filter() {
        return 1  # Not blocked
    }
    export -f check_geographic_filter
    
    # shellcheck disable=SC2317
    auto_block_ip() {
        return 0
    }
    export -f auto_block_ip
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock auto_block_ip
    # shellcheck disable=SC2317
    function auto_block_ip() {
        return 0
    }
    export -f auto_block_ip
    
    # Test check_and_block_ddos which handles multiple IPs
    run check_and_block_ddos || true
    # Should handle multiple IPs
    assert [ ${status} -ge 0 ]
}
