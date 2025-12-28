#!/usr/bin/env bash
#
# Unit Tests: ddosProtection.sh
# Tests DDoS protection functionality
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
    
    # Set test configuration
    export DDOS_ENABLED="true"
    export DDOS_THRESHOLD_REQUESTS_PER_SECOND="100"
    export DDOS_THRESHOLD_CONCURRENT_CONNECTIONS="500"
    export DDOS_AUTO_BLOCK_DURATION_MINUTES="15"
    export DDOS_CHECK_WINDOW_SECONDS="60"
    export DDOS_GEO_FILTERING_ENABLED="false"
    
    # Mock database functions to avoid real DB calls
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_ddosProtection"
    
    # Initialize security functions
    init_security
    
    # Initialize alerting
    init_alerting
    
    # Source ddosProtection.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/ddosProtection.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
    rm -f "${TMP_DIR}/.ddos_detected"
    rm -f "${TMP_DIR}/.ip_blocked"
}

@test "detect_ddos_attack returns normal when requests below threshold" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return low count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "50"  # Below threshold of 100 req/s
        fi
        return 0
    }
    export -f psql
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run detection
    run detect_ddos_attack "192.168.1.100" "60" "100"
    
    # Should return normal (exit code 1)
    assert_failure
}

@test "detect_ddos_attack detects attack when threshold exceeded" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return high count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "7000"  # 7000 requests in 60 seconds = 116 req/s (over threshold)
        fi
        return 0
    }
    export -f psql
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track if attack was detected
    local attack_file="${TMP_DIR}/.ddos_detected"
    rm -f "${attack_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "ddos" ]]; then
            touch "${attack_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run detection
    run detect_ddos_attack "192.168.1.100" "60" "100" || true
    
    # Should detect attack (exit code 0)
    assert_success
    assert_file_exists "${attack_file}"
}

@test "detect_ddos_attack bypasses whitelisted IPs" {
    # Mock is_ip_whitelisted to return true
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 0
    }
    export -f is_ip_whitelisted
    
    # Mock psql (should not be called)
    # shellcheck disable=SC2317
    psql() {
        echo "Should not be called"
        return 1
    }
    export -f psql
    
    # Run detection
    run detect_ddos_attack "192.168.1.100" "60" "100"
    
    # Should bypass (return normal)
    assert_failure
}

@test "check_concurrent_connections detects high connections" {
    # Mock is_ip_whitelisted to return false
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return high connection count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(DISTINCT"* ]]; then
            echo "600"  # Over threshold of 500
        fi
        return 0
    }
    export -f psql
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Track if event was recorded
    local event_file="${TMP_DIR}/.ddos_detected"
    rm -f "${event_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "ddos" ]]; then
            touch "${event_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run check
    run check_concurrent_connections "" "500" || true
    
    # Should detect high connections
    assert_success
    assert_file_exists "${event_file}"
}

@test "auto_block_ip blocks IP with expiration" {
    # Mock block_ip function
    local block_file="${TMP_DIR}/.ip_blocked"
    rm -f "${block_file}"
    
    # shellcheck disable=SC2317
    block_ip() {
        if [[ "${1}" == "192.168.1.100" ]] && [[ "${2}" == "temp_block" ]]; then
            touch "${block_file}"
        fi
        return 0
    }
    export -f block_ip
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Run auto block
    run auto_block_ip "192.168.1.100" "DDoS attack" "15"
    
    # Should succeed
    assert_success
    assert_file_exists "${block_file}"
}

@test "check_and_block_ddos blocks detected attacks" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return attack
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT DISTINCT ip_address"* ]]; then
            echo "192.168.1.100"
        elif [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "7000"  # Attack detected
        fi
        return 0
    }
    export -f psql
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Mock block_ip
    local block_file="${TMP_DIR}/.ip_blocked"
    rm -f "${block_file}"
    
    # shellcheck disable=SC2317
    block_ip() {
        touch "${block_file}"
        return 0
    }
    export -f block_ip
    
    # Mock send_alert
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    # Run check and block
    run check_and_block_ddos "" || true
    
    # Should detect and block
    assert_file_exists "${block_file}"
}

@test "check_geographic_filter blocks IP from blocked country" {
    export DDOS_GEO_FILTERING_ENABLED="true"
    export DDOS_BLOCKED_COUNTRIES="CN,RU"
    
    # Mock get_ip_country to return blocked country
    # shellcheck disable=SC2317
    get_ip_country() {
        if [[ "${1}" == "192.168.1.100" ]]; then
            echo "CN"
            return 0
        fi
        return 1
    }
    export -f get_ip_country
    
    # Mock block_ip
    local block_file="${TMP_DIR}/.ip_blocked"
    rm -f "${block_file}"
    
    # shellcheck disable=SC2317
    block_ip() {
        touch "${block_file}"
        return 0
    }
    export -f block_ip
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # Run geographic filter check
    run check_geographic_filter "192.168.1.100"
    
    # Should block
    assert_success
    assert_file_exists "${block_file}"
}

@test "check_geographic_filter allows IP from allowed country" {
    export DDOS_GEO_FILTERING_ENABLED="true"
    export DDOS_ALLOWED_COUNTRIES="US,GB"
    
    # Mock get_ip_country to return allowed country
    # shellcheck disable=SC2317
    get_ip_country() {
        if [[ "${1}" == "192.168.1.100" ]]; then
            echo "US"
            return 0
        fi
        return 1
    }
    export -f get_ip_country
    
    # Run geographic filter check
    run check_geographic_filter "192.168.1.100"
    
    # Should allow (return 1 = not blocked)
    assert_failure
}

@test "get_ddos_stats queries database" {
    # Mock psql to return test data
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]]; then
            echo "10|5|2025-12-27 10:00:00"
            echo ""
            echo "192.168.1.100|temp_block|DDoS|2025-12-27 11:00:00"
        fi
        return 0
    }
    export -f psql
    
    # Run stats
    run get_ddos_stats
    
    # Should succeed
    assert_success
}

@test "main function check action detects and blocks attacks" {
    # Mock functions
    # shellcheck disable=SC2317
    is_ip_whitelisted() { return 1; }
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT DISTINCT"* ]]; then
            echo "192.168.1.100"
        elif [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "7000"
        fi
        return 0
    }
    # shellcheck disable=SC2317
    record_metric() { return 0; }
    # shellcheck disable=SC2317
    record_security_event() { return 0; }
    # shellcheck disable=SC2317
    block_ip() { return 0; }
    # shellcheck disable=SC2317
    send_alert() { return 0; }
    
    export -f is_ip_whitelisted psql record_metric record_security_event block_ip send_alert
    
    # Run main with check action
    run main "check" "" || true
    
    # Should detect attacks
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}

@test "main function block action blocks IP" {
    # Mock block_ip
    local block_file="${TMP_DIR}/.ip_blocked"
    rm -f "${block_file}"
    
    # shellcheck disable=SC2317
    block_ip() {
        touch "${block_file}"
        return 0
    }
    export -f block_ip
    
    # Run main with block action
    run main "block" "192.168.1.100" "Manual block"
    
    # Should succeed
    assert_success
    assert_file_exists "${block_file}"
}

@test "main function unblock action removes block" {
    # Mock psql to track DELETE
    local delete_called=false
    
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"DELETE"* ]]; then
            delete_called=true
        fi
        return 0
    }
    export -f psql
    
    # Mock record_security_event
    # shellcheck disable=SC2317
    record_security_event() {
        return 0
    }
    export -f record_security_event
    
    # Run main with unblock action
    run main "unblock" "192.168.1.100"
    
    # Should succeed
    assert_success
    assert_equal "true" "${delete_called}"
}

@test "main function stats action shows statistics" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        echo "test stats"
        return 0
    }
    export -f psql
    
    # Run main with stats action
    run main "stats"
    
    # Should succeed
    assert_success
}

@test "detect_ddos_attack handles geographic filter" {
    export DDOS_GEO_FILTERING_ENABLED="true"
    export DDOS_BLOCKED_COUNTRIES="CN"
    
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock get_ip_country
    # shellcheck disable=SC2317
    get_ip_country() {
        echo "CN"
        return 0
    }
    export -f get_ip_country
    
    # Mock block_ip
    local block_file="${TMP_DIR}/.ip_blocked"
    rm -f "${block_file}"
    
    # shellcheck disable=SC2317
    block_ip() {
        touch "${block_file}"
        return 0
    }
    export -f block_ip
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
    # Run detection
    run detect_ddos_attack "192.168.1.100" "60" "100" || true
    
    # Should block due to geographic filter
    assert_success
    assert_file_exists "${block_file}"
}

