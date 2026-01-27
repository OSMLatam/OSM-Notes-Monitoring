#!/usr/bin/env bash
#
# Third Unit Tests: abuseDetection.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../../.."
    
    export ABUSE_DETECTION_ENABLED="true"
    export ABUSE_RAPID_REQUEST_THRESHOLD="10"
    export ABUSE_ERROR_RATE_THRESHOLD="50"
    export ABUSE_EXCESSIVE_REQUESTS_THRESHOLD="1000"
    export ABUSE_PATTERN_ANALYSIS_WINDOW="3600"
    
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
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/securityFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/security/abuseDetection.sh"
    
    init_logging "${TEST_LOG_DIR}/test_abuseDetection_third.log" "test_abuseDetection_third"
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: analyze_patterns handles complex patterns
##
@test "analyze_patterns handles complex patterns" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100|192.168.1.1|/api/endpoint|GET"
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
    
    run analyze_patterns "192.168.1.1"
    assert_success
}

##
# Test: detect_anomalies handles statistical analysis
##
@test "detect_anomalies handles statistical analysis" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "100|50|10"  # requests, errors, patterns
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
    
    run detect_anomalies "192.168.1.1"
    assert_success
}

##
# Test: analyze_behavior handles user behavior tracking
##
@test "analyze_behavior handles user behavior tracking" {
    # Mock execute_sql_query
    # shellcheck disable=SC2317
    function execute_sql_query() {
        echo "192.168.1.1|100|50|10|5"  # IP, requests, errors, patterns, sessions
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
    
    run analyze_behavior "192.168.1.1"
    assert_success
}

##
# Test: main handles --analyze option
##
@test "main handles --analyze option" {
    # Mock analyze functions
    # shellcheck disable=SC2317
    function analyze_patterns() {
        return 0
    }
    export -f analyze_patterns
    
    # shellcheck disable=SC2317
    function detect_anomalies() {
        return 0
    }
    export -f detect_anomalies
    
    # shellcheck disable=SC2317
    function analyze_behavior() {
        return 0
    }
    export -f analyze_behavior
    
    run main analyze
    assert_success
}
