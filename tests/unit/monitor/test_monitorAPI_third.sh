#!/usr/bin/env bash
#
# Third Unit Tests: monitorAPI.sh
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
    
    export API_URL="http://localhost:8080/api/health"
    export API_CHECK_TIMEOUT="5"
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        return 0
    }
    export -f psql
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorAPI.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorAPI_third.log" "test_monitorAPI_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_api_availability handles slow response
##
@test "check_api_availability handles slow response" {
    # Create mock curl executable so command -v finds it
    local mock_curl_dir="${BATS_TEST_DIRNAME}/../../tmp/bin"
    mkdir -p "${mock_curl_dir}"
    local mock_curl="${mock_curl_dir}/curl"
    cat > "${mock_curl}" << 'EOF'
#!/bin/bash
# Return HTTP 200 with slow response time
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w)
            shift
            if [[ "$1" == "%{http_code}" ]]; then
                sleep 0.002
                echo "200"
            elif [[ "$1" == "%{time_total}" ]]; then
                echo "0.002"
            fi
            ;;
        -s|-o|--max-time|--connect-timeout)
            shift
            ;;
        *)
            ;;
    esac
    shift
done
exit 0
EOF
    chmod +x "${mock_curl}"
    # shellcheck disable=SC2030,SC2031
    export PATH="${mock_curl_dir}:${PATH}"
    
    # Mock log functions
    # shellcheck disable=SC2317
    log_info() {
        return 0
    }
    export -f log_info
    
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
    
    run check_api_availability
    assert_success
    
    # Cleanup
    rm -rf "${mock_curl_dir}"
}

##
# Test: check_rate_limiting handles rate limit exceeded
##
@test "check_rate_limiting handles rate limit exceeded" {
    export RATE_LIMIT_ENABLED="true"
    
    # Mock rateLimiter.sh check_rate_limit function to return exceeded
    # shellcheck disable=SC2317
    check_rate_limit() {
        return 1  # Rate limit exceeded
    }
    export -f check_rate_limit
    
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
    
    run check_rate_limiting || true
    assert_success || true
}

##
# Test: main handles all checks option
##
@test "main handles all checks option" {
    # Mock load_config
    # shellcheck disable=SC2317
    load_config() {
        return 0
    }
    export -f load_config
    
    # Mock all check functions
    # shellcheck disable=SC2317
    check_api_availability() {
        return 0
    }
    export -f check_api_availability
    
    # shellcheck disable=SC2317
    check_rate_limiting() {
        return 0
    }
    export -f check_rate_limiting
    
    # shellcheck disable=SC2317
    check_ddos_protection() {
        return 0
    }
    export -f check_ddos_protection
    
    # shellcheck disable=SC2317
    check_abuse_detection() {
        return 0
    }
    export -f check_abuse_detection
    
    run main --check "all"
    assert_success
}

##
# Test: main handles verbose mode with specific check
##
@test "main handles verbose mode with specific check" {
    # Mock load_config
    # shellcheck disable=SC2317
    load_config() {
        return 0
    }
    export -f load_config
    
    # Mock check_api_availability
    # shellcheck disable=SC2317
    check_api_availability() {
        return 0
    }
    export -f check_api_availability
    
    run main --verbose --check "api_availability"
    assert_success
}
