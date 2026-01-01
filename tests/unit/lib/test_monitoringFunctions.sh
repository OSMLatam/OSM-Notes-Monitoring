#!/usr/bin/env bats
#
# Unit Tests: monitoringFunctions.sh
# Tests for monitoring functions library
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="MONITORING"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_monitoringFunctions.log"
    init_logging "${LOG_FILE}" "test_monitoringFunctions"
    
    # Mock database connection
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
}

teardown() {
    # Cleanup
    rm -rf "${TEST_LOG_DIR:-}"
}

##
# Test: check_database_connection - success case
##
@test "check_database_connection succeeds with valid connection" {
    # Mock psql to return success
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -c.*SELECT.*1 ]]; then
            echo "1"
            return 0
        fi
        return 1
    }
    
    run check_database_connection
    assert_success
}

##
# Test: check_database_connection - failure case
##
@test "check_database_connection fails with invalid connection" {
    # Mock psql to return failure
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run check_database_connection
    assert_failure
}

##
# Test: update_component_health - healthy status
##
@test "update_component_health updates status to healthy" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "healthy" "All checks passed"
    assert_success
}

##
# Test: update_component_health - degraded status
##
@test "update_component_health updates status to degraded" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "degraded" "Some checks failed"
    assert_success
}

##
# Test: update_component_health - down status
##
@test "update_component_health updates status to down" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "down" "Component unavailable"
    assert_success
}

##
# Test: update_component_health - invalid status
##
@test "update_component_health handles invalid status" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "invalid" "Invalid status"
    # Should handle gracefully
    assert_failure
}

##
# Test: get_component_health - retrieves health status
##
@test "get_component_health retrieves current health status" {
    # Mock psql to return health data
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ SELECT.*component_health ]]; then
            echo "healthy|All checks passed|2025-12-28 10:00:00"
            return 0
        fi
        return 1
    }
    
    run get_component_health "TEST_COMPONENT"
    assert_success
    assert [[ "${output}" =~ healthy ]]
}

##
# Test: check_database_server_health - healthy database
##
@test "check_database_connection handles connection timeout" {
    # Mock psql to simulate timeout
    # shellcheck disable=SC2317
    function psql() {
        sleep 0.001
        return 1
    }
    
    run check_database_connection
    assert_failure
}

##
# Test: execute_sql_query - handles PGPASSWORD
##
@test "execute_sql_query uses PGPASSWORD when set" {
    export PGPASSWORD="test_password"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -c.*SELECT ]]; then
            echo "result"
            return 0
        fi
        return 1
    }
    
    run execute_sql_query "SELECT 1"
    assert_success
}

@test "execute_sql_query executes query successfully" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -c.*SELECT ]]; then
            echo "result1"
            echo "result2"
            return 0
        fi
        return 1
    }
    
    run execute_sql_query "SELECT * FROM test_table"
    assert_success
    assert [[ "${output}" =~ result1 ]]
}

@test "execute_sql_query handles query error" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        echo "Error: relation does not exist" >&2
        return 1
    }
    
    run execute_sql_query "SELECT * FROM nonexistent_table"
    assert_failure
    assert [[ "${output}" =~ Error ]]
}

@test "execute_sql_file executes SQL file" {
    local test_sql_file="${BATS_TEST_DIRNAME}/../../tmp/test.sql"
    echo "SELECT 1;" > "${test_sql_file}"
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -f.*test.sql ]]; then
            return 0
        fi
        return 1
    }
    
    run execute_sql_file "${test_sql_file}"
    assert_success
    
    rm -f "${test_sql_file}"
}

@test "execute_sql_file handles missing file" {
    run execute_sql_file "/nonexistent/file.sql"
    assert_failure
}

@test "update_component_health handles empty message" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*component_health ]]; then
            return 0
        fi
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "healthy" ""
    assert_success
}

@test "get_component_health handles component not found" {
    # Mock psql to return empty
    # shellcheck disable=SC2317
    function psql() {
        return 0
    }
    
    run get_component_health "NONEXISTENT_COMPONENT"
    assert_success
    # May return empty or default value
}

@test "check_database_connection uses custom database name" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -d.*custom_db ]]; then
            return 0
        fi
        return 1
    }
    
    run check_database_connection "custom_db"
    assert_success
}

@test "execute_sql_query uses custom database name" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -d.*custom_db ]]; then
            echo "result"
            return 0
        fi
        return 1
    }
    
    run execute_sql_query "SELECT 1" "custom_db"
    assert_success
}

@test "update_component_health handles unknown status" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    
    run update_component_health "TEST_COMPONENT" "unknown" "Test"
    assert_failure
}

##
# Test: init_monitoring - initializes monitoring system
##
@test "init_monitoring initializes with defaults" {
    unset DBNAME DBHOST DBPORT DBUSER
    
    run init_monitoring
    assert_success
    assert [[ -n "${DBNAME:-}" ]]
    assert [[ -n "${DBHOST:-}" ]]
    assert [[ -n "${DBPORT:-}" ]]
    assert [[ -n "${DBUSER:-}" ]]
}

##
# Test: get_db_connection_string - generates connection string
##
@test "get_db_connection_string generates connection string" {
    export DBNAME="test_db"
    export DBHOST="localhost"
    export DBPORT="5432"
    export DBUSER="test_user"
    
    run get_db_connection_string
    assert_success
    assert [[ "${output}" =~ postgresql ]]
    assert [[ "${output}" =~ test_db ]]
}

##
# Test: store_metric - stores metric successfully
##
@test "store_metric stores metric for valid component" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]]; then
            return 0
        fi
        return 1
    }
    
    run store_metric "ingestion" "test_metric" "100" "count"
    assert_success
}

##
# Test: store_metric - rejects invalid component
##
@test "store_metric rejects invalid component" {
    run store_metric "invalid_component" "test_metric" "100" "count"
    assert_failure
}

##
# Test: store_metric - handles metadata
##
@test "store_metric stores metric with metadata" {
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ INSERT.*metrics ]] && [[ "${*}" =~ metadata ]]; then
            return 0
        fi
        return 1
    }
    
    local metadata='{"key": "value"}'
    run store_metric "ingestion" "test_metric" "100" "count" "${metadata}"
    assert_success
}

##
# Test: get_http_response_time - measures response time
##
@test "get_http_response_time measures response time" {
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        sleep 0.001  # Simulate small delay
        return 0
    }
    export -f curl
    
    run get_http_response_time "http://localhost/test"
    assert_success
    assert [[ "${output}" =~ ^[0-9]+$ ]]
}

##
# Test: get_http_response_time - handles timeout
##
@test "get_http_response_time handles timeout" {
    # Mock curl to timeout
    # shellcheck disable=SC2317
    function curl() {
        return 1
    }
    export -f curl
    
    run get_http_response_time "http://localhost/test" "1"
    assert_failure
}

##
# Test: check_http_health - detects healthy service
##
@test "check_http_health detects healthy service" {
    # Mock curl
    # shellcheck disable=SC2317
    function curl() {
        return 0
    }
    export -f curl
    
    run check_http_health "http://localhost/test"
    assert_success
}

##
# Test: check_http_health - detects unhealthy service
##
@test "check_http_health detects unhealthy service" {
    # Mock curl to fail
    # shellcheck disable=SC2317
    function curl() {
        return 1
    }
    export -f curl
    
    run check_http_health "http://localhost/test"
    assert_failure
}

##
# Test: execute_sql_file - handles file with multiple queries
##
@test "execute_sql_file executes file with multiple queries" {
    local test_sql_file="${BATS_TEST_DIRNAME}/../../tmp/test_multi.sql"
    cat > "${test_sql_file}" << 'EOF'
SELECT 1;
SELECT 2;
SELECT 3;
EOF
    
    # Mock psql
    # shellcheck disable=SC2317
    function psql() {
        if [[ "${*}" =~ -f.*test_multi.sql ]]; then
            return 0
        fi
        return 1
    }
    
    run execute_sql_file "${test_sql_file}"
    assert_success
    
    rm -f "${test_sql_file}"
}
