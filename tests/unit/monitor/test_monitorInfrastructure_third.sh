#!/usr/bin/env bash
#
# Third Unit Tests: monitorInfrastructure.sh
# Third test file to reach 80% coverage
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    
    export INFRASTRUCTURE_ENABLED="true"
    export INFRASTRUCTURE_DISK_THRESHOLD="90"
    export INFRASTRUCTURE_CPU_THRESHOLD="80"
    export INFRASTRUCTURE_MEMORY_THRESHOLD="85"
    
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
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/monitorInfrastructure.sh"
    
    init_logging "${TEST_LOG_DIR}/test_monitorInfrastructure_third.log" "test_monitorInfrastructure_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: check_disk_usage handles low disk usage
##
@test "check_disk_usage handles low disk usage" {
    # Mock df to return low usage
    # shellcheck disable=SC2317
    function df() {
        echo "Filesystem     1K-blocks  Used Available Use% Mounted on"
        echo "/dev/sda1       1000000  100000    900000  10% /"
        return 0
    }
    export -f df
    
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
    
    # Use check_server_resources which checks disk usage
    run check_server_resources
    assert_success
}

##
# Test: check_cpu_usage handles low CPU usage
##
@test "check_cpu_usage handles low CPU usage" {
    # Mock top/uptime to return low CPU
    # shellcheck disable=SC2317
    function top() {
        echo "top - 10:00:00 up 1 day, load average: 0.10, 0.15, 0.20"
        return 0
    }
    export -f top
    
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
    
    # Use check_server_resources which checks CPU usage
    run check_server_resources
    assert_success
}

##
# Test: check_memory_usage handles low memory usage
##
@test "check_memory_usage handles low memory usage" {
    # Mock free to return low memory usage
    # shellcheck disable=SC2317
    function free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:        8000000     1000000     5000000          0     2000000     6000000"
        return 0
    }
    export -f free
    
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
    
    # Use check_server_resources which checks memory usage
    run check_server_resources
    assert_success
}

##
# Test: main handles --check option
##
@test "main handles --check option" {
    # Mock check functions
    # shellcheck disable=SC2317
    function check_disk_usage() {
        return 0
    }
    export -f check_disk_usage
    
    # shellcheck disable=SC2317
    function check_cpu_usage() {
        return 0
    }
    export -f check_cpu_usage
    
    # shellcheck disable=SC2317
    function check_memory_usage() {
        return 0
    }
    export -f check_memory_usage
    
    run main --check
    assert_success
}
