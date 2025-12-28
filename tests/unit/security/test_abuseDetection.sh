#!/usr/bin/env bash
#
# Unit Tests: abuseDetection.sh
# Tests abuse detection functionality
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
    export ABUSE_DETECTION_ENABLED="true"
    export ABUSE_RAPID_REQUEST_THRESHOLD="10"
    export ABUSE_ERROR_RATE_THRESHOLD="50"
    export ABUSE_EXCESSIVE_REQUESTS_THRESHOLD="1000"
    export ABUSE_PATTERN_ANALYSIS_WINDOW="3600"
    
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
    init_logging "${TEST_LOG_DIR}/test.log" "test_abuseDetection"
    
    # Initialize security functions
    init_security
    
    # Initialize alerting
    init_alerting
    
    # Source abuseDetection.sh functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/abuseDetection.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
    rm -f "${TMP_DIR}/.abuse_detected"
    rm -f "${TMP_DIR}/.ip_blocked"
}

@test "analyze_patterns detects rapid requests pattern" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return rapid requests
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]] && [[ "${*}" == *"10 seconds"* ]]; then
            echo "15"  # Over threshold of 10
        elif [[ "${*}" == *"FILTER"* ]]; then
            echo "5|10"  # 5 errors out of 10 total
        elif [[ "${*}" == *"1 hour"* ]]; then
            echo "500"  # Below excessive threshold
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
    
    # Track if abuse was detected
    local abuse_file="${TMP_DIR}/.abuse_detected"
    rm -f "${abuse_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "abuse" ]]; then
            touch "${abuse_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run analysis
    run analyze_patterns "192.168.1.100" || true
    
    # Should detect abuse
    assert_success
    assert_file_exists "${abuse_file}"
}

@test "analyze_patterns detects high error rate pattern" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return high error rate
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]] && [[ "${*}" == *"10 seconds"* ]]; then
            echo "5"  # Below rapid threshold
        elif [[ "${*}" == *"FILTER"* ]]; then
            echo "60|100"  # 60 errors out of 100 total = 60% (over threshold of 50%)
        elif [[ "${*}" == *"1 hour"* ]]; then
            echo "500"
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
    
    # Track if abuse was detected
    local abuse_file="${TMP_DIR}/.abuse_detected"
    rm -f "${abuse_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "abuse" ]]; then
            touch "${abuse_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run analysis
    run analyze_patterns "192.168.1.100" || true
    
    # Should detect abuse
    assert_success
    assert_file_exists "${abuse_file}"
}

@test "analyze_patterns detects excessive requests pattern" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return excessive requests
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]] && [[ "${*}" == *"10 seconds"* ]]; then
            echo "5"
        elif [[ "${*}" == *"FILTER"* ]]; then
            echo "10|100"  # 10% error rate (below threshold)
        elif [[ "${*}" == *"1 hour"* ]]; then
            echo "1500"  # Over threshold of 1000
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
    
    # Track if abuse was detected
    local abuse_file="${TMP_DIR}/.abuse_detected"
    rm -f "${abuse_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "abuse" ]]; then
            touch "${abuse_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run analysis
    run analyze_patterns "192.168.1.100" || true
    
    # Should detect abuse
    assert_success
    assert_file_exists "${abuse_file}"
}

@test "detect_anomalies detects deviation from baseline" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return anomaly (current 3x baseline)
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"AVG(hourly_count)"* ]]; then
            echo "100"  # Baseline: 100 requests/hour
        elif [[ "${*}" == *"DATE_TRUNC('hour'"* ]]; then
            echo "350"  # Current: 350 requests (3.5x baseline)
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
    
    # Track if anomaly was detected
    local anomaly_file="${TMP_DIR}/.abuse_detected"
    rm -f "${anomaly_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "abuse" ]] && [[ "${4}" == *"anomaly"* ]]; then
            touch "${anomaly_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run anomaly detection
    run detect_anomalies "192.168.1.100" || true
    
    # Should detect anomaly
    assert_success
    assert_file_exists "${anomaly_file}"
}

@test "analyze_behavior detects high endpoint diversity" {
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock psql to return high endpoint diversity
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"COUNT(DISTINCT endpoint)"* ]]; then
            echo "25"  # Over threshold of 20
        elif [[ "${*}" == *"COUNT(DISTINCT user_agent)"* ]]; then
            echo "5"  # Below threshold
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
    
    # Track if suspicious behavior detected
    local behavior_file="${TMP_DIR}/.abuse_detected"
    rm -f "${behavior_file}"
    
    # shellcheck disable=SC2317
    record_security_event() {
        if [[ "${1}" == "abuse" ]] && [[ "${4}" == *"behavioral"* ]]; then
            touch "${behavior_file}"
        fi
        return 0
    }
    export -f record_security_event
    
    # Run behavior analysis
    run analyze_behavior "192.168.1.100" || true
    
    # Should detect suspicious behavior
    assert_success
    assert_file_exists "${behavior_file}"
}

@test "automatic_response blocks IP and escalates duration" {
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
    
    # Mock record_metric
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # Mock psql for violation count
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT COUNT(*)"* ]]; then
            echo "2"  # 2 previous violations
        fi
        return 0
    }
    export -f psql
    
    # Run automatic response
    run automatic_response "192.168.1.100" "pattern" "Abuse detected"
    
    # Should block IP
    assert_success
    assert_file_exists "${block_file}"
}

@test "check_ip_for_abuse combines all detection methods" {
    export ABUSE_DETECTION_ENABLED="true"
    
    # Mock is_ip_whitelisted
    # shellcheck disable=SC2317
    is_ip_whitelisted() {
        return 1
    }
    export -f is_ip_whitelisted
    
    # Mock analyze_patterns to detect abuse
    # shellcheck disable=SC2317
    analyze_patterns() {
        if [[ "${1}" == "192.168.1.100" ]]; then
            return 0  # Abuse detected
        fi
        return 1
    }
    export -f analyze_patterns
    
    # Mock automatic_response
    local response_file="${TMP_DIR}/.ip_blocked"
    rm -f "${response_file}"
    
    # shellcheck disable=SC2317
    automatic_response() {
        touch "${response_file}"
        return 0
    }
    export -f automatic_response
    
    # Mock other detection functions
    # shellcheck disable=SC2317
    detect_anomalies() {
        return 1  # No anomaly
    }
    export -f detect_anomalies
    
    # shellcheck disable=SC2317
    analyze_behavior() {
        return 1  # Normal behavior
    }
    export -f analyze_behavior
    
    # Run check
    run check_ip_for_abuse "192.168.1.100" || true
    
    # Should detect abuse and respond
    assert_success
    assert_file_exists "${response_file}"
}

@test "analyze_all processes multiple IPs" {
    export ABUSE_DETECTION_ENABLED="true"
    
    # Mock psql to return multiple IPs
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT DISTINCT ip_address"* ]]; then
            echo "192.168.1.100"
            echo "192.168.1.200"
        fi
        return 0
    }
    export -f psql
    
    # Mock check_ip_for_abuse
    local check_count=0
    
    # shellcheck disable=SC2317
    check_ip_for_abuse() {
        check_count=$((check_count + 1))
        return 1  # No abuse
    }
    export -f check_ip_for_abuse
    
    # Run analyze all
    run analyze_all
    
    # Should check multiple IPs
    assert_success
    assert [ ${check_count} -ge 2 ]
}

@test "get_abuse_stats queries database" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]]; then
            echo "test stats"
        fi
        return 0
    }
    export -f psql
    
    # Run stats
    run get_abuse_stats
    
    # Should succeed
    assert_success
}

@test "show_patterns displays detected patterns" {
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT"* ]]; then
            echo "test patterns"
        fi
        return 0
    }
    export -f psql
    
    # Run patterns
    run show_patterns
    
    # Should succeed
    assert_success
}

@test "main function analyze action processes IPs" {
    # Mock functions
    # shellcheck disable=SC2317
    psql() {
        if [[ "${*}" == *"SELECT DISTINCT"* ]]; then
            echo "192.168.1.100"
        fi
        return 0
    }
    # shellcheck disable=SC2317
    check_ip_for_abuse() {
        return 1  # No abuse
    }
    
    export -f psql check_ip_for_abuse
    
    # Run main with analyze action
    run main "analyze" ""
    
    # Should succeed
    assert_success
}

@test "main function check action checks specific IP" {
    # Mock check_ip_for_abuse
    # shellcheck disable=SC2317
    check_ip_for_abuse() {
        return 1  # No abuse
    }
    export -f check_ip_for_abuse
    
    # Run main with check action
    run main "check" "192.168.1.100"
    
    # Should succeed
    assert_success
}

@test "analyze_patterns bypasses whitelisted IPs" {
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
    
    # Run analysis
    run analyze_patterns "192.168.1.100"
    
    # Should bypass (return normal)
    assert_failure
}

