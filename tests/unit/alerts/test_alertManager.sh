#!/usr/bin/env bash
#
# Unit Tests: Alert Manager
# Tests alert manager functionality
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

# Set TEST_MODE and LOG_DIR before loading anything to avoid permission issues
export TEST_MODE=true
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
mkdir -p "${TEST_LOG_DIR}"
# Export TEST_LOG_DIR and LOG_DIR with absolute path to ensure it's used
# shellcheck disable=SC2155
TEST_LOG_DIR="$(cd "${BATS_TEST_DIRNAME}/../../tmp/logs" && pwd)"
export TEST_LOG_DIR
export LOG_DIR="${TEST_LOG_DIR}"
export LOG_FILE="${LOG_DIR}/test_alertManager.log"

# Set PROJECT_ROOT to avoid issues when alertManager.sh calculates it
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../../.."

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

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
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertManager.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Ensure LOG_DIR is set
    export LOG_DIR="${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alertManager.log"
    
    # Mock psql for database operations
    # Track alert states for more realistic behavior
    # Use a file to persist state across function calls
    export MOCK_STATUS_FILE="${TEST_LOG_DIR}/.mock_alert_status"
    echo "active" > "${MOCK_STATUS_FILE}"
    
    # shellcheck disable=SC2317
    function psql() {
        local args=("$@")
        local query=""
        local is_tab_format=false
        local all_args="${*}"
        
        # Extract query from arguments
        # psql can be called as: psql -h host -p port -U user -d db -c "query"
        # or: psql -t -A -c "query" (for execute_sql_query)
        local i=0
        while [[ $i -lt ${#args[@]} ]]; do
            case "${args[$i]}" in
                -c)
                    if [[ $((i+1)) -lt ${#args[@]} ]]; then
                        query="${args[$((i+1))]}"
                        break
                    fi
                    ;;
                -t|-A)
                    is_tab_format=true
                    ;;
            esac
            ((i++))
        done
        
        # If no -c found, treat all args as query (for backward compatibility)
        # This handles cases where psql is called without -c flag
        if [[ -z "${query}" ]]; then
            query="${all_args}"
        fi
        
        # Handle INSERT operations (for store_alert)
        if [[ "${query}" =~ INSERT.*alerts ]]; then
            echo "INSERT 0 1"
            return 0
        fi
        
        # Handle SELECT operations
        if [[ "${query}" =~ SELECT.*FROM.alerts ]]; then
            # Read current mock status from file
            local current_status
            current_status=$(cat "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}" 2>/dev/null || echo "active")
            
            # is_tab_format is already set from argument parsing above
            
            # IMPORTANT: Check for component filter FIRST (more specific)
            # This must come before the generic SELECT id queries
            # SELECT queries for list_alerts or show_history with component filter
            # list_alerts uses: SELECT id, component, alert_level, alert_type, message, status, created_at, resolved_at FROM alerts WHERE 1=1 AND component = 'INGESTION'...
            # show_history uses: SELECT id, alert_level, alert_type, message, status, created_at, resolved_at FROM alerts WHERE component = 'INGESTION'...
            # Check if query contains component filter for INGESTION (handle various formats)
            # Normalize query for matching (case insensitive)
            local query_lower
            query_lower=$(echo "${query}" | tr '[:upper:]' '[:lower:]')
            
            # Debug: log query to file
            echo "DEBUG: Query: ${query}" >> "${TEST_LOG_DIR}/psql_debug.log" 2>&1 || true
            echo "DEBUG: Query lower: ${query_lower}" >> "${TEST_LOG_DIR}/psql_debug.log" 2>&1 || true
            
            if echo "${query_lower}" | grep -q "component.*=.*ingestion" || echo "${query}" | grep -q "component.*=.*INGESTION" || echo "${query}" | grep -q "component.*=.*['\"]INGESTION"; then
                echo "DEBUG: Matched component filter" >> "${TEST_LOG_DIR}/psql_debug.log" 2>&1 || true
                # Check if it's show_history (no component column in SELECT)
                if [[ "${query}" =~ SELECT.*id.*alert_level.*alert_type.*message.*status ]] && [[ ! "${query}" =~ SELECT.*component ]]; then
                    # show_history format (no component column)
                    if [[ "${is_tab_format}" == "true" ]]; then
                        echo "00000000-0000-0000-0000-000000000001|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                    else
                        echo " id | alert_level | alert_type | message | status | created_at | resolved_at"
                        echo "----+-------------+------------+---------+--------+------------+-------------"
                        echo " 00000000-0000-0000-0000-000000000001 | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                    fi
                else
                    # list_alerts format (with component column)
                    if [[ "${is_tab_format}" == "true" ]]; then
                        echo "00000000-0000-0000-0000-000000000001|INGESTION|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                    else
                        echo " id | component | alert_level | alert_type | message | status | created_at | resolved_at"
                        echo "----+-----------+-------------+------------+---------+--------+------------+-------------"
                        echo " 00000000-0000-0000-0000-000000000001 | INGESTION | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                    fi
                fi
                return 0
            fi
            
            # SELECT status queries (for checking alert status)
            if [[ "${query}" =~ SELECT.*status.*WHERE.*id ]]; then
                # Return current mock status
                echo "${current_status}"
                return 0
            fi
            
            # SELECT id queries (for get_alert_id helper) - must come AFTER component filter check
            if [[ "${query}" =~ SELECT.*id.*WHERE.*component ]]; then
                echo "00000000-0000-0000-0000-000000000001"
                return 0
            fi
            
            # Check for non-existent alert ID
            if [[ "${query}" =~ WHERE.*id.*=.*00000000-0000-0000-0000-000000000000 ]]; then
                # Non-existent alert ID
                return 0  # Return empty
            fi
            # Check for single alert query (show_alert - WHERE id=)
            if [[ "${query}" =~ WHERE.*id.*= ]]; then
                if [[ "${is_tab_format}" == "true" ]]; then
                    # Return tab-separated format
                    echo "00000000-0000-0000-0000-000000000001|INGESTION|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                else
                    # Return formatted table
                    echo " id | component | alert_level | alert_type | message | status | created_at | resolved_at"
                    echo "----+-----------+-------------+------------+---------+--------+------------+-------------"
                    echo " 00000000-0000-0000-0000-000000000001 | INGESTION | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                fi
                return 0
            fi
            # Default list query - return formatted table
            if [[ "${is_tab_format}" == "true" ]]; then
                echo "00000000-0000-0000-0000-000000000001|INGESTION|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                echo "00000000-0000-0000-0000-000000000002|ANALYTICS|critical|test_type|Test message 2|active|2025-12-28 10:00:00|"
            else
                echo " id | component | alert_level | alert_type | message | status | created_at | resolved_at"
                echo "----+-----------+-------------+------------+---------+--------+------------+-------------"
                echo " 00000000-0000-0000-0000-000000000001 | INGESTION | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                echo " 00000000-0000-0000-0000-000000000002 | ANALYTICS | critical | test_type | Test message 2 | active | 2025-12-28 10:00:00 |"
            fi
            return 0
        fi
        
        # Handle UPDATE operations (for acknowledge/resolve)
        if [[ "${query}" =~ UPDATE.*alerts ]]; then
            # Read current mock status from file
            local current_status
            current_status=$(cat "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}" 2>/dev/null || echo "active")
            
            # Check if it's a valid UUID
            if [[ "${query}" =~ 00000000-0000-0000-0000-000000000000 ]] || [[ "${query}" =~ invalid-uuid ]]; then
                # Invalid UUID - return empty (no rows updated)
                return 0
            fi
            # Check if updating to acknowledged
            if [[ "${query}" =~ status.*=.*acknowledged ]]; then
                # acknowledge_alert only updates if status = 'active'
                # Check if alert is already acknowledged or resolved
                if [[ "${current_status}" == "acknowledged" ]] || [[ "${current_status}" == "resolved" ]]; then
                    # Already acknowledged/resolved - return empty (no rows updated)
                    return 0
                fi
                # Update mock status in file
                echo "acknowledged" > "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}"
                # Return alert ID (RETURNING id) - check for -t -A format in args or all_args
                if [[ "${is_tab_format}" == "true" ]] || [[ "${all_args}" =~ -t.*-A ]] || [[ "${all_args}" =~ -A.*-t ]] || [[ "${*}" =~ -t.*-A ]] || [[ "${*}" =~ -A.*-t ]]; then
                    echo "00000000-0000-0000-0000-000000000001"
                fi
                return 0
            fi
            # Check if updating to resolved
            if [[ "${query}" =~ status.*=.*resolved ]]; then
                # resolve_alert only updates if status IN ('active', 'acknowledged')
                # Check if alert is already resolved
                if [[ "${current_status}" == "resolved" ]]; then
                    # Already resolved - return empty (no rows updated)
                    if [[ "${is_tab_format}" == "true" ]] || [[ "${all_args}" =~ -t.*-A ]] || [[ "${all_args}" =~ -A.*-t ]] || [[ "${*}" =~ -t.*-A ]] || [[ "${*}" =~ -A.*-t ]]; then
                        echo ""  # Return empty string for -t -A format
                    fi
                    return 0
                fi
                # Update mock status in file BEFORE returning result
                echo "resolved" > "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}"
                # Return alert ID (RETURNING id) - check for -t -A format in args or all_args
                if [[ "${is_tab_format}" == "true" ]] || [[ "${all_args}" =~ -t.*-A ]] || [[ "${all_args}" =~ -A.*-t ]] || [[ "${*}" =~ -t.*-A ]] || [[ "${*}" =~ -A.*-t ]]; then
                    echo "00000000-0000-0000-0000-000000000001"
                fi
                return 0
            fi
            # Other UPDATE - return success
            echo "UPDATE 1"
            return 0
        fi
        
        # Handle DELETE operations (for cleanup)
        if [[ "${query}" =~ DELETE.*alerts ]]; then
            echo "DELETE 1"
            return 0
        fi
        
        # Handle TRUNCATE (for clean_test_database)
        if [[ "${query}" =~ TRUNCATE ]]; then
            # Reset mock status file if it exists, otherwise just return success
            if [[ -n "${MOCK_STATUS_FILE:-}" ]] && [[ -n "${TEST_LOG_DIR:-}" ]]; then
                echo "active" > "${MOCK_STATUS_FILE}" 2>/dev/null || true
            fi
            return 0
        fi
        
        # Handle COUNT queries (for stats, aggregation)
        if [[ "${query}" =~ SELECT.*COUNT ]]; then
            echo "2"
            return 0
        fi
        
        # Default: return success
        return 0
    }
    export -f psql
    
    # Initialize alerting
    init_alerting
    
    # Clean test database
    clean_test_database
}

teardown() {
    # Ensure TEST_LOG_DIR is set for clean_test_database
    export TEST_LOG_DIR="${TEST_LOG_DIR:-${BATS_TEST_DIRNAME}/../../tmp/logs}"
    
    # Clean up test alerts
    clean_test_database
    
    # Clean up test log files
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: List alerts returns active alerts
##
@test "List alerts returns active alerts" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # List alerts
    run list_alerts "" "active"
    assert_success
    assert_output --partial "INGESTION"
    assert_output --partial "warning"
}

##
# Test: List alerts filters by component
##
@test "List alerts filters by component" {
    # Create test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message 1"
    send_alert "ANALYTICS" "critical" "test_type" "Test message 2"
    
    # List alerts for INGESTION
    run list_alerts "INGESTION" "active"
    assert_success
    assert_output --partial "INGESTION"
    assert_output --partial "warning"
    refute_output --partial "ANALYTICS"
}

##
# Test: Show alert displays alert details
##
@test "Show alert displays alert details" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Get alert ID
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        run show_alert "${alert_id}"
        assert_success
        assert_output --partial "INGESTION"
        assert_output --partial "warning"
        assert_output --partial "Test message"
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Acknowledge alert updates status
##
@test "Acknowledge alert updates status" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Get alert ID
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        # Acknowledge alert
        run acknowledge_alert "${alert_id}" "test_user"
        assert_success
        
        # Verify status
        local status_query="SELECT status FROM alerts WHERE id = '${alert_id}'::uuid;"
        local status
        # Use PGPASSWORD only if set, otherwise let psql use default authentication
        if [[ -n "${PGPASSWORD:-}" ]]; then
            status=$(PGPASSWORD="${PGPASSWORD}" psql \
                -h "${DBHOST:-localhost}" \
                -p "${DBPORT:-5432}" \
                -U "${DBUSER:-postgres}" \
                -d "${TEST_DB_NAME}" \
                -t -A \
                -c "${status_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        else
            status=$(psql \
                -h "${DBHOST:-localhost}" \
                -p "${DBPORT:-5432}" \
                -U "${DBUSER:-postgres}" \
                -d "${TEST_DB_NAME}" \
                -t -A \
                -c "${status_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        fi
        
        assert [ "${status}" = "acknowledged" ]
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Resolve alert updates status
##
@test "Resolve alert updates status" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Get alert ID
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        # Resolve alert
        run resolve_alert "${alert_id}" "test_user"
        assert_success
        
        # Verify status
        local status_query="SELECT status FROM alerts WHERE id = '${alert_id}'::uuid;"
        local status
        # Use PGPASSWORD only if set, otherwise let psql use default authentication
        if [[ -n "${PGPASSWORD:-}" ]]; then
            status=$(PGPASSWORD="${PGPASSWORD}" psql \
                -h "${DBHOST:-localhost}" \
                -p "${DBPORT:-5432}" \
                -U "${DBUSER:-postgres}" \
                -d "${TEST_DB_NAME}" \
                -t -A \
                -c "${status_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        else
            status=$(psql \
                -h "${DBHOST:-localhost}" \
                -p "${DBPORT:-5432}" \
                -U "${DBUSER:-postgres}" \
                -d "${TEST_DB_NAME}" \
                -t -A \
                -c "${status_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        fi
        
        assert [ "${status}" = "resolved" ]
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Aggregate alerts groups by component and type
##
@test "Aggregate alerts groups by component and type" {
    # Create multiple test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message 1"
    send_alert "INGESTION" "warning" "test_type" "Test message 2"
    send_alert "INGESTION" "critical" "test_type" "Test message 3"
    
    # Aggregate alerts
    run aggregate_alerts "INGESTION" "60"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Show history returns alert history
##
@test "Show history returns alert history" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Show history
    run show_history "INGESTION" "7"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Show stats returns alert statistics
##
@test "Show stats returns alert statistics" {
    # Create test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message 1"
    send_alert "INGESTION" "critical" "test_type" "Test message 2"
    
    # Show stats
    run show_stats ""
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Cleanup alerts removes old resolved alerts
##
@test "Cleanup alerts removes old resolved alerts" {
    # Create and resolve test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        resolve_alert "${alert_id}" "test_user"
        
        # Cleanup (with short retention for testing)
        run cleanup_alerts "0"
        assert_success
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Helper function to get alert ID
##
get_alert_id() {
    local component="${1}"
    local alert_type="${2}"
    local message="${3}"
    
    local query="SELECT id FROM alerts 
                 WHERE component = '${component}' 
                   AND alert_type = '${alert_type}' 
                   AND message = '${message}'
                 ORDER BY created_at DESC 
                 LIMIT 1;"
    
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        PGPASSWORD="${PGPASSWORD}" psql \
            -h "${DBHOST:-localhost}" \
            -p "${DBPORT:-5432}" \
            -U "${DBUSER:-postgres}" \
            -d "${TEST_DB_NAME}" \
            -t -A \
            -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo ""
    else
        psql \
            -h "${DBHOST:-localhost}" \
            -p "${DBPORT:-5432}" \
            -U "${DBUSER:-postgres}" \
            -d "${TEST_DB_NAME}" \
            -t -A \
            -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo ""
    fi
}

##
# Test: List alerts handles empty result set
##
@test "List alerts handles empty result set gracefully" {
    # List alerts when none exist
    run list_alerts "" "active"
    assert_success
    # Should not error, just return empty result
}

##
# Test: Show alert handles non-existent alert ID
##
@test "Show alert handles non-existent alert ID gracefully" {
    # Try to show non-existent alert
    run show_alert "00000000-0000-0000-0000-000000000000"
    assert_success  # Should not error, just return empty
}

##
# Test: Acknowledge alert handles already acknowledged alert
##
@test "Acknowledge alert handles already acknowledged alert" {
    # Create and acknowledge test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        acknowledge_alert "${alert_id}" "test_user"
        
        # Try to acknowledge again
        run acknowledge_alert "${alert_id}" "test_user"
        assert_failure  # Should fail as already acknowledged
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Resolve alert handles already resolved alert
##
@test "Resolve alert handles already resolved alert" {
    # Create and resolve test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        resolve_alert "${alert_id}" "test_user"
        
        # Try to resolve again
        run resolve_alert "${alert_id}" "test_user"
        assert_failure  # Should fail as already resolved
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Aggregate alerts handles empty component
##
@test "Aggregate alerts handles empty component" {
    # Aggregate with empty component
    run aggregate_alerts "" "60"
    assert_success
}

##
# Test: Show history handles invalid component
##
@test "Show history handles invalid component gracefully" {
    # Show history for non-existent component
    run show_history "NONEXISTENT_COMPONENT" "7"
    assert_success  # Should not error, just return empty
}

##
# Test: Show stats handles empty database
##
@test "Show stats handles empty database gracefully" {
    # Clean database first
    clean_test_database
    
    # Show stats
    run show_stats ""
    assert_success  # Should not error, just return empty stats
}

##
# Test: Cleanup alerts handles zero days gracefully
##
@test "Cleanup alerts handles zero days gracefully" {
    # Cleanup with zero days
    run cleanup_alerts "0"
    assert_success
}

##
# Test: List alerts handles invalid status
##
@test "List alerts handles invalid status gracefully" {
    # List with invalid status
    run list_alerts "" "invalid_status"
    assert_success  # Should handle gracefully
}

##
# Test: Show alert handles invalid UUID format
##
@test "Show alert handles invalid UUID format gracefully" {
    # Try to show alert with invalid UUID
    run show_alert "invalid-uuid"
    assert_success  # Should handle gracefully (may fail SQL but not crash)
}

##
# Test: Acknowledge alert handles database error
##
@test "Acknowledge alert handles database error gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run acknowledge_alert "00000000-0000-0000-0000-000000000000" "test_user"
    assert_failure
}

##
# Test: Resolve alert handles database error
##
@test "Resolve alert handles database error gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run resolve_alert "00000000-0000-0000-0000-000000000000" "test_user"
    assert_failure
}

##
# Test: Aggregate alerts handles very large window
##
@test "Aggregate alerts handles very large window gracefully" {
    # Aggregate with very large window (1 year)
    run aggregate_alerts "INGESTION" "525600"  # 365 days in minutes
    assert_success
}

##
# Test: Show history handles very large days parameter
##
@test "Show history handles very large days parameter gracefully" {
    # Show history with very large days
    run show_history "INGESTION" "3650"  # 10 years
    assert_success
}

##
# Test: Main function handles unknown action
##
@test "Main function handles unknown action gracefully" {
    run main "unknown_action"
    assert_failure
    assert_output --partial "Unknown action"
}

##
# Test: Main function handles missing action
##
@test "Main function handles missing action gracefully" {
    run main ""
    assert_failure
    assert_output --partial "Action required"
}

##
# Test: Main function handles missing alert ID for show
##
@test "Main function handles missing alert ID for show" {
    run main "show"
    assert_failure
    assert_output --partial "Alert ID required"
}

##
# Test: Main function handles missing alert ID for acknowledge
##
@test "Main function handles missing alert ID for acknowledge" {
    run main "acknowledge"
    assert_failure
    assert_output --partial "Alert ID required"
}

##
# Test: Main function handles missing component for history
##
@test "Main function handles missing component for history" {
    run main "history"
    assert_failure
    assert_output --partial "Component required"
}

##
# Test: load_config loads custom config file
##
@test "load_config loads custom config file" {
    local test_config="${BATS_TEST_DIRNAME}/../../tmp/test_config.conf"
    mkdir -p "$(dirname "${test_config}")"
    cat > "${test_config}" << 'EOF'
ALERT_DEDUPLICATION_ENABLED="false"
ALERT_RETENTION_DAYS="90"
EOF
    
    run load_config "${test_config}"
    assert_success
    
    rm -f "${test_config}"
}

##
# Test: load_config handles missing config file gracefully
##
@test "load_config handles missing config file gracefully" {
    run load_config "/nonexistent/config.conf"
    assert_success  # Should not fail, just use defaults
}

##
# Test: usage displays help message
##
@test "usage displays help message" {
    run usage
    assert_success
    assert_output --partial "Alert Manager Script"
    assert_output --partial "Usage:"
    assert_output --partial "list"
    assert_output --partial "show"
}

##
# Test: Main function handles help option
##
@test "Main function handles help option" {
    run main "--help"
    assert_success
    assert_output --partial "Alert Manager Script"
}

##
# Test: Main function handles -h option
##
@test "Main function handles -h option" {
    run main "-h"
    assert_success
    assert_output --partial "Alert Manager Script"
}

##
# Test: list_alerts handles different status values
##
@test "list_alerts handles resolved status" {
    # Create and resolve test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        resolve_alert "${alert_id}" "test_user"
        
        # List resolved alerts
        run list_alerts "" "resolved"
        assert_success
        assert_output --partial "INGESTION"
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: list_alerts handles acknowledged status
##
@test "list_alerts handles acknowledged status" {
    # Create and acknowledge test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        acknowledge_alert "${alert_id}" "test_user"
        
        # List acknowledged alerts
        run list_alerts "" "acknowledged"
        assert_success
        assert_output --partial "INGESTION"
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: aggregate_alerts uses default window when not specified
##
@test "aggregate_alerts uses default window when not specified" {
    # Create test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Aggregate without specifying window
    run aggregate_alerts "INGESTION"
    assert_success
}

##
# Test: show_history uses default days when not specified
##
@test "show_history uses default days when not specified" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Show history without specifying days
    run show_history "INGESTION"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: cleanup_alerts uses default retention when not specified
##
@test "cleanup_alerts uses default retention when not specified" {
    # Create and resolve test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        resolve_alert "${alert_id}" "test_user"
        
        # Cleanup without specifying days (should use default)
        run cleanup_alerts
        assert_success
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: Main function handles list action
##
@test "Main function handles list action" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    run main "list"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Main function handles list action with component
##
@test "Main function handles list action with component" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    # Mock psql to return formatted table for main function
    # Save reference to original mock from setup
    export MOCK_STATUS_FILE="${TEST_LOG_DIR}/.mock_alert_status"
    
    # shellcheck disable=SC2317
    function psql() {
        local query="${*}"
        
        # Handle the specific query for list_alerts with component filter
        if [[ "${query}" =~ SELECT.*FROM.alerts ]] && [[ "${query}" =~ WHERE.*component.*=.*INGESTION ]]; then
            echo " id | component | alert_level | alert_type | message | status | created_at | resolved_at"
            echo "----+-----------+-------------+------------+---------+--------+------------+-------------"
            echo " 00000000-0000-0000-0000-000000000001 | INGESTION | warning | test_type | Test message | active | 2025-12-28 10:00:00 |"
            return 0
        fi
        
        # Handle INSERT operations (for store_alert)
        if [[ "${query}" =~ INSERT.*alerts ]]; then
            echo "INSERT 0 1"
            return 0
        fi
        
        # Handle SELECT operations
        if [[ "${query}" =~ SELECT.*FROM.alerts ]]; then
            local current_status
            current_status=$(cat "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}" 2>/dev/null || echo "active")
            local is_tab_format=false
            if [[ "${*}" =~ -t.*-A ]] || [[ "${*}" =~ -A.*-t ]]; then
                is_tab_format=true
            fi
            
            if [[ "${query}" =~ SELECT.*status.*WHERE.*id ]]; then
                echo "${current_status}"
                return 0
            fi
            if [[ "${query}" =~ SELECT.*id.*WHERE.*component ]]; then
                echo "00000000-0000-0000-0000-000000000001"
                return 0
            fi
            if [[ "${query}" =~ WHERE.*component.*=.*INGESTION ]] || [[ "${query}" =~ component.*=.*INGESTION ]]; then
                if [[ "${is_tab_format}" == "true" ]]; then
                    if [[ "${query}" =~ SELECT.*id.*alert_level.*alert_type.*message.*status ]]; then
                        echo "00000000-0000-0000-0000-000000000001|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                    else
                        echo "00000000-0000-0000-0000-000000000001|INGESTION|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                    fi
                else
                    if [[ "${query}" =~ SELECT.*id.*alert_level.*alert_type.*message.*status ]]; then
                        echo " id | alert_level | alert_type | message | status | created_at | resolved_at"
                        echo "----+-------------+------------+---------+--------+------------+-------------"
                        echo " 00000000-0000-0000-0000-000000000001 | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                    else
                        echo " id | component | alert_level | alert_type | message | status | created_at | resolved_at"
                        echo "----+-----------+-------------+------------+---------+--------+------------+-------------"
                        echo " 00000000-0000-0000-0000-000000000001 | INGESTION | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                    fi
                fi
                return 0
            fi
            if [[ "${query}" =~ WHERE.*id.*=.*00000000-0000-0000-0000-000000000000 ]]; then
                return 0
            fi
            if [[ "${query}" =~ WHERE.*id.*= ]]; then
                if [[ "${is_tab_format}" == "true" ]]; then
                    echo "00000000-0000-0000-0000-000000000001|INGESTION|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                else
                    echo " id | component | alert_level | alert_type | message | status | created_at | resolved_at"
                    echo "----+-----------+-------------+------------+---------+--------+------------+-------------"
                    echo " 00000000-0000-0000-0000-000000000001 | INGESTION | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                fi
                return 0
            fi
            if [[ "${is_tab_format}" == "true" ]]; then
                echo "00000000-0000-0000-0000-000000000001|INGESTION|warning|test_type|Test message|${current_status}|2025-12-28 10:00:00|"
                echo "00000000-0000-0000-0000-000000000002|ANALYTICS|critical|test_type|Test message 2|active|2025-12-28 10:00:00|"
            else
                echo " id | component | alert_level | alert_type | message | status | created_at | resolved_at"
                echo "----+-----------+-------------+------------+---------+--------+------------+-------------"
                echo " 00000000-0000-0000-0000-000000000001 | INGESTION | warning | test_type | Test message | ${current_status} | 2025-12-28 10:00:00 |"
                echo " 00000000-0000-0000-0000-000000000002 | ANALYTICS | critical | test_type | Test message 2 | active | 2025-12-28 10:00:00 |"
            fi
            return 0
        fi
        
        # Handle UPDATE operations
        if [[ "${query}" =~ UPDATE.*alerts ]]; then
            local current_status
            current_status=$(cat "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}" 2>/dev/null || echo "active")
            if [[ "${query}" =~ 00000000-0000-0000-0000-000000000000 ]] || [[ "${query}" =~ invalid-uuid ]]; then
                return 0
            fi
            if [[ "${query}" =~ status.*=.*acknowledged ]]; then
                if [[ "${current_status}" == "acknowledged" ]] || [[ "${current_status}" == "resolved" ]]; then
                    return 0
                fi
                echo "acknowledged" > "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}"
                if [[ "${*}" =~ -t.*-A ]] || [[ "${*}" =~ -A.*-t ]]; then
                    echo "00000000-0000-0000-0000-000000000001"
                fi
                return 0
            fi
            if [[ "${query}" =~ status.*=.*resolved ]]; then
                if [[ "${current_status}" == "resolved" ]]; then
                    return 0
                fi
                echo "resolved" > "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}"
                if [[ "${*}" =~ -t.*-A ]] || [[ "${*}" =~ -A.*-t ]]; then
                    echo "00000000-0000-0000-0000-000000000001"
                fi
                return 0
            fi
            echo "UPDATE 1"
            return 0
        fi
        
        # Handle DELETE operations
        if [[ "${query}" =~ DELETE.*alerts ]]; then
            echo "DELETE 1"
            return 0
        fi
        
        # Handle TRUNCATE
        if [[ "${query}" =~ TRUNCATE ]]; then
            echo "active" > "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}"
            return 0
        fi
        
        # Handle COUNT queries
        if [[ "${query}" =~ SELECT.*COUNT ]]; then
            echo "2"
            return 0
        fi
        
        return 0
    }
    export -f psql
    
    run main "list" "INGESTION" "active"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: Main function handles stats action
##
@test "Main function handles stats action" {
    # Create test alerts
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    run main "stats"
    assert_success
}

##
# Test: Main function handles aggregate action
##
@test "Main function handles aggregate action" {
    # Create test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    run main "aggregate" "INGESTION" "60"
    assert_success
}

##
# Test: Main function handles cleanup action
##
@test "Main function handles cleanup action" {
    run main "cleanup" "0"
    assert_success
}

##
# Test: resolve_alert handles already resolved alert from acknowledged state
##
@test "resolve_alert resolves acknowledged alert" {
    # Create, acknowledge, then resolve test alert
    send_alert "INGESTION" "warning" "test_type" "Test message"
    
    local alert_id
    alert_id=$(get_alert_id "INGESTION" "test_type" "Test message")
    
    if [[ -n "${alert_id}" ]]; then
        # Reset mock status to active
        echo "active" > "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}"
        
        # Acknowledge alert
        run acknowledge_alert "${alert_id}" "test_user"
        assert_success
        
        # Verify status is acknowledged (read from file)
        local mock_status
        mock_status=$(cat "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}" 2>/dev/null || echo "active")
        assert [ "${mock_status}" = "acknowledged" ]
        
        # Resolve from acknowledged state
        run resolve_alert "${alert_id}" "test_user"
        assert_success
        
        # Verify status is resolved (read from file)
        mock_status=$(cat "${MOCK_STATUS_FILE:-${TEST_LOG_DIR}/.mock_alert_status}" 2>/dev/null || echo "active")
        assert [ "${mock_status}" = "resolved" ]
    else
        skip "Could not retrieve alert ID"
    fi
}

##
# Test: acknowledge_alert handles invalid UUID gracefully
##
@test "acknowledge_alert handles invalid UUID gracefully" {
    run acknowledge_alert "invalid-uuid" "test_user"
    assert_failure
}

##
# Test: resolve_alert handles invalid UUID gracefully
##
@test "resolve_alert handles invalid UUID gracefully" {
    run resolve_alert "invalid-uuid" "test_user"
    assert_failure
}

##
# Test: show_stats filters by component
##
@test "show_stats filters by component" {
    # Create test alerts for different components
    send_alert "INGESTION" "warning" "test_type" "Test message 1"
    send_alert "ANALYTICS" "critical" "test_type" "Test message 2"
    
    # Show stats for INGESTION only
    run show_stats "INGESTION"
    assert_success
    assert_output --partial "INGESTION"
}

##
# Test: aggregate_alerts handles empty result gracefully
##
@test "aggregate_alerts handles empty result gracefully" {
    # Clean database
    clean_test_database
    
    # Aggregate with no alerts
    run aggregate_alerts "INGESTION" "60"
    assert_success  # Should not error
}

##
# Test: show_history handles zero days parameter
##
@test "show_history handles zero days parameter gracefully" {
    run show_history "INGESTION" "0"
    assert_success
}

##
# Test: cleanup_alerts handles negative days parameter
##
@test "cleanup_alerts handles negative days parameter gracefully" {
    run cleanup_alerts "-1"
    assert_success  # Should handle gracefully
}


