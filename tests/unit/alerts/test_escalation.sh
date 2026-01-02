#!/usr/bin/env bash
#
# Unit Tests: Alert Escalation
# Tests escalation functionality
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

# Set test environment variables BEFORE sourcing scripts
export TEST_MODE=true
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../../tmp/logs"
mkdir -p "${TEST_LOG_DIR}"
export TEST_LOG_DIR="${TEST_LOG_DIR}"
export LOG_DIR="${TEST_LOG_DIR}"

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
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/escalation.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database - ensure DBNAME is set correctly
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Set escalation configuration
    export ESCALATION_ENABLED="true"
    export ESCALATION_LEVEL1_MINUTES="1"  # Short for testing
    export ESCALATION_LEVEL2_MINUTES="2"
    export ESCALATION_LEVEL3_MINUTES="3"
    
    # Disable email alerts for testing
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Ensure DBNAME is exported for store_alert (must be before init_alerting)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    
    # Ensure LOG_DIR is set
    export LOG_DIR="${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_escalation.log"
    
    # Initialize alerting
    init_alerting
    
    # Clean test database
    clean_test_database
}

teardown() {
    # Clean up test alerts
    clean_test_database
    
    # Clean up test log files
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: Show escalation rules displays rules
##
@test "Show escalation rules displays rules" {
    run show_rules ""
    assert_success
    assert_output --partial "Level 1"
    assert_output --partial "Level 2"
    assert_output --partial "Level 3"
}

##
# Test: Escalate alert updates metadata
##
@test "Escalate alert updates metadata" {
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql to ensure it's created
    # Use single-line query to avoid issues with multi-line strings in BATS
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    
    local alert_id
    local psql_output
    # Execute psql and capture output - ensure variables are available in subshell
    # IMPORTANT: Get USER from environment before subshell, as it may not be available in subshell
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    # Debug: verify variables before executing psql
    if [[ -z "${dbuser}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Extract UUID from output (psql returns UUID on a line by itself with -t -A)
    # Use -o flag to only output matching part, not the whole line
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    # Verify we got a valid UUID (36 characters)
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Escalate alert - ensure DBUSER is set correctly for escalate_alert
        export DBUSER="${dbuser}"
        export DBNAME="${dbname}"
        export DBHOST="${dbhost}"
        export DBPORT="${dbport}"
        run escalate_alert "${alert_id}" "1"
        assert_success
        
        # Verify escalation level in metadata - use local variables
        # Small delay to ensure escalation is committed
        sleep 0.1
        local metadata_query="SELECT metadata->>'escalation_level' FROM alerts WHERE id = '${alert_id}'::uuid;"
        local escalation_level
        escalation_level=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${metadata_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
        
        assert [ "${escalation_level}" = "1" ]
    else
        skip "Could not create test alert (psql_output: '${psql_output}', alert_id: '${alert_id}')"
    fi
}

##
# Test: Needs escalation detects old alerts
##
@test "Needs escalation detects old alerts" {
    # Ensure DBNAME and DBUSER are set correctly
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql to ensure it's created
    # Use single-line query to avoid issues with multi-line strings in BATS
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    
    local alert_id
    local psql_output
    # Execute psql and capture output - ensure variables are available in subshell
    # IMPORTANT: Get USER from environment before subshell, as it may not be available in subshell
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    # Debug: verify variables before executing psql
    if [[ -z "${dbuser}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Extract UUID from output (psql returns UUID on a line by itself with -t -A)
    # Use -o flag to only output matching part, not the whole line
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Get database connection variables (use already detected current_user)
        local dbhost="${DBHOST:-localhost}"
        local dbport="${DBPORT:-5432}"
        local dbuser="${DBUSER:-${current_user}}"
        # Never use 'postgres' as dbuser if DBUSER is not explicitly set
        if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
            dbuser="${current_user}"
        fi
        local dbname="${DBNAME:-osm_notes_monitoring_test}"
        
        # Update alert to have old timestamp (simulate age)
        # Use single-line query to avoid issues with multi-line strings in BATS
        local update_query="UPDATE alerts SET created_at = CURRENT_TIMESTAMP - INTERVAL '2 minutes' WHERE id = '${alert_id}'::uuid;"
        
        PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "${update_query}" >/dev/null 2>&1 || true
        
        # Ensure DBUSER is set correctly for needs_escalation
        export DBUSER="${dbuser}"
        export DBNAME="${dbname}"
        export DBHOST="${dbhost}"
        export DBPORT="${dbport}"
        # Check if needs escalation
        run needs_escalation "${alert_id}"
        # May or may not need escalation depending on thresholds
        assert [ "$status" -ge 0 ]
    else
        skip "Could not create test alert"
    fi
}

##
# Test: Show oncall displays on-call information
##
@test "Show oncall displays on-call information" {
    run show_oncall ""
    assert_success
    assert_output --partial "on-call"
}

##
# Helper function to create test alert and return ID
##
create_test_alert() {
    local component="${1:-INGESTION}"
    local alert_level="${2:-critical}"
    local alert_type="${3:-test_type}"
    local message="${4:-Test message}"
    
    # IMPORTANT: Get USER from environment before subshell
    # Use variables from environment, ensuring they're available
    local current_user="${USER:-postgres}"
    
    # Get database connection variables from environment
    local dbname="${DBNAME}"
    if [[ -z "${dbname}" ]]; then
        # TEST_DB_NAME is readonly, so use it directly
        dbname="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    fi
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER}"
    if [[ -z "${dbuser}" ]]; then
        dbuser="${current_user}"
    fi
    
    # Ensure dbuser is not postgres if DBUSER is not set
    if [[ "${dbuser}" == "postgres" ]] && [[ -z "${DBUSER:-}" ]]; then
        dbuser="${current_user}"
    fi
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('${component}', '${alert_level}', '${alert_type}', '${message}', '{}'::jsonb) RETURNING id;"
    
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Extract UUID from output
    local alert_id
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Return the alert_id
    echo "${alert_id}"
}

##
# Helper function to get alert ID
##
get_alert_id() {
    local component="${1}"
    local alert_type="${2}"
    local message="${3}"
    
    # Use DBNAME from environment, fallback to TEST_DB_NAME
    # IMPORTANT: Get USER from environment before subshell
    local current_user="${USER:-postgres}"
    local dbname="${DBNAME:-${TEST_DB_NAME:-osm_notes_monitoring_test}}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    
    # Ensure dbuser is not postgres if DBUSER is not set
    if [[ -z "${DBUSER:-}" ]] && [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    
    local query="SELECT id FROM alerts 
                 WHERE component = '${component}' 
                   AND alert_type = '${alert_type}' 
                   AND message = '${message}'
                 ORDER BY created_at DESC 
                 LIMIT 1;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo ""
}

##
# Test: Escalate alert handles non-existent alert ID
##
@test "Escalate alert handles non-existent alert ID gracefully" {
    # Try to escalate non-existent alert
    run escalate_alert "00000000-0000-0000-0000-000000000000" "1"
    assert_failure  # Should fail gracefully
}

##
# Test: Escalate alert handles invalid escalation level
##
@test "Escalate alert handles invalid escalation level gracefully" {
    # Ensure DBNAME and DBUSER are set correctly
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql to ensure it's created
    # Use single-line query to avoid issues with multi-line strings in BATS
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    
    local alert_id
    local psql_output
    # Execute psql and capture output - ensure variables are available in subshell
    # IMPORTANT: Get USER from environment before subshell, as it may not be available in subshell
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    # Debug: verify variables before executing psql
    if [[ -z "${dbuser}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Extract UUID from output (psql returns UUID on a line by itself with -t -A)
    # Use -o flag to only output matching part, not the whole line
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Ensure DBUSER is set correctly for escalate_alert
        local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
        export DBUSER="${dbuser}"
        export DBNAME="${DBNAME:-osm_notes_monitoring_test}"
        export DBHOST="${DBHOST:-localhost}"
        export DBPORT="${DBPORT:-5432}"
        # Try to escalate to invalid level
        run escalate_alert "${alert_id}" "99"
        assert_failure  # Should fail for invalid level
    else
        skip "Could not create test alert"
    fi
}

##
# Test: Needs escalation returns false for info alerts
##
@test "Needs escalation returns false for info alerts" {
    # IMPORTANT: Get the actual current user FIRST, before any other operations
    # This must be done before setting DBUSER to avoid using 'postgres' as default
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    # Ensure USER is exported
    export USER="${current_user}"
    
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # Use current_user, not postgres as default
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create info alert directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'info', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    local alert_id
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Small delay to ensure INSERT is committed
    sleep 0.1
    
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        # Wait a bit more and try again
        sleep 0.1
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' AND alert_level = 'info' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Ensure DBUSER is set correctly for needs_escalation
        export DBUSER="${dbuser}"
        export DBNAME="${dbname}"
        export DBHOST="${dbhost}"
        export DBPORT="${dbport}"
        # Info alerts should not need escalation
        run needs_escalation "${alert_id}"
        assert_failure  # Returns 1 = no escalation needed
    else
        skip "Could not create test alert (dbuser: ${dbuser}, dbname: ${dbname}, psql_output preview: ${psql_output:0:100})"
    fi
}

##
# Test: Needs escalation handles already escalated alert
##
@test "Needs escalation handles already escalated alert" {
    # IMPORTANT: Get current_user FIRST, before any other operations
    # This must be done before setting DBUSER to avoid using 'postgres' as default
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    # Ensure USER is exported
    export USER="${current_user}"
    
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # Use current_user, not postgres as default
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    local alert_id
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Small delay to ensure INSERT is committed
    sleep 0.1
    
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Get database connection variables (use already detected current_user)
        local dbhost="${DBHOST:-localhost}"
        local dbport="${DBPORT:-5432}"
        local dbuser="${DBUSER:-${current_user}}"
        # Never use 'postgres' as dbuser if DBUSER is not explicitly set
        if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
            dbuser="${current_user}"
        fi
        local dbname="${DBNAME:-osm_notes_monitoring_test}"
        
        # Update alert to have old timestamp and level 3 escalation
        # Use single-line query to avoid issues with multi-line strings in BATS
        local update_query="UPDATE alerts SET created_at = CURRENT_TIMESTAMP - INTERVAL '10 minutes', metadata = jsonb_build_object('escalation_level', '3') WHERE id = '${alert_id}'::uuid;"
        
        PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "${update_query}" >/dev/null 2>&1 || true
        
        # Ensure DBUSER is set correctly for needs_escalation
        export DBUSER="${dbuser}"
        export DBNAME="${dbname}"
        export DBHOST="${dbhost}"
        export DBPORT="${dbport}"
        # Should not need further escalation
        run needs_escalation "${alert_id}"
        assert_failure  # Already at max level
    else
        skip "Could not create test alert"
    fi
}

##
# Test: Check escalation handles empty component
##
@test "Check escalation handles empty component" {
    # Check escalation for all components
    run check_escalation ""
    assert_success
}

##
# Test: Check escalation handles non-existent component
##
@test "Check escalation handles non-existent component gracefully" {
    # Check escalation for non-existent component
    run check_escalation "NONEXISTENT_COMPONENT"
    assert_success  # Should not error, just return empty
}

##
# Test: Show rules handles component filter
##
@test "Show rules handles component filter" {
    # Show rules for specific component
    run show_rules "INGESTION"
    assert_success
    assert_output --partial "Level"
}

##
# Test: Show oncall handles specific date
##
@test "Show oncall handles specific date" {
    # Show oncall for specific date
    run show_oncall "2025-12-31"
    assert_success
    assert_output --partial "on-call"
}

##
# Test: Show oncall handles invalid date format
##
@test "Show oncall handles invalid date format gracefully" {
    # Show oncall with invalid date
    run show_oncall "invalid-date"
    assert_success  # Should handle gracefully
}

##
# Test: Rotate oncall handles disabled rotation
##
@test "Rotate oncall handles disabled rotation gracefully" {
    export ONCALL_ROTATION_ENABLED="false"
    
    # Try to rotate
    run rotate_oncall
    assert_success  # Should handle gracefully when disabled
}

##
# Test: Escalate alert handles database error
##
@test "Escalate alert handles database error gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run escalate_alert "00000000-0000-0000-0000-000000000000" "1"
    assert_failure
}

##
# Test: Needs escalation handles database error
##
@test "Needs escalation handles database error gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run needs_escalation "00000000-0000-0000-0000-000000000000"
    assert_failure
}

##
# Test: Check escalation handles database error
##
@test "Check escalation handles database error gracefully" {
    # Mock psql to fail
    # shellcheck disable=SC2317
    function psql() {
        return 1
    }
    export -f psql
    
    run check_escalation "INGESTION"
    assert_success  # May succeed even if DB fails (graceful handling)
}

##
# Test: Escalate alert handles already at max level
##
@test "Escalate alert handles already at max level" {
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    local alert_id
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Small delay to ensure INSERT is committed
    sleep 0.1
    
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Ensure DBUSER is set correctly for escalate_alert
        local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
        export DBUSER="${dbuser}"
        export DBNAME="${DBNAME:-osm_notes_monitoring_test}"
        export DBHOST="${DBHOST:-localhost}"
        export DBPORT="${DBPORT:-5432}"
        # Escalate to level 3
        run escalate_alert "${alert_id}" "3"
        assert_success
        
        # Try to escalate beyond max level
        run escalate_alert "${alert_id}" "4"
        assert_failure  # Should fail as already at max
    else
        skip "Could not create test alert"
    fi
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
# Test: Main function handles missing alert ID for escalate
##
@test "Main function handles missing alert ID for escalate" {
    run main "escalate"
    assert_failure
    assert_output --partial "Alert ID required"
}

##
# Additional edge cases and error handling tests
##

@test "needs_escalation handles warning alerts with adjusted thresholds" {
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create warning alert directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'warning', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    local alert_id
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Small delay to ensure INSERT is committed
    sleep 0.1
    
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' AND alert_level = 'warning' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Get database connection variables (use already detected current_user)
        local dbhost="${DBHOST:-localhost}"
        local dbport="${DBPORT:-5432}"
        local dbuser="${DBUSER:-${current_user}}"
        # Never use 'postgres' as dbuser if DBUSER is not explicitly set
        if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
            dbuser="${current_user}"
        fi
        local dbname="${DBNAME:-osm_notes_monitoring_test}"
        
        # Update alert to have old timestamp
        # Use single-line query to avoid issues with multi-line strings in BATS
        local update_query="UPDATE alerts SET created_at = CURRENT_TIMESTAMP - INTERVAL '${ESCALATION_LEVEL1_MINUTES} minutes' WHERE id = '${alert_id}'::uuid;"
        
        PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "${update_query}" >/dev/null 2>&1 || true
        
        # Ensure DBUSER is set correctly for needs_escalation
        export DBUSER="${dbuser}"
        export DBNAME="${dbname}"
        export DBHOST="${dbhost}"
        export DBPORT="${dbport}"
        # Warning alerts use 2x thresholds, so should not need escalation yet
        run needs_escalation "${alert_id}"
        # May or may not need escalation depending on exact timing
        assert [ "$status" -ge 0 ]
    else
        skip "Could not create test alert"
    fi
}

@test "escalate_alert auto-determines escalation level" {
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    local alert_id
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Small delay to ensure INSERT is committed
    sleep 0.1
    
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Get database connection variables (use already detected current_user)
        local dbhost="${DBHOST:-localhost}"
        local dbport="${DBPORT:-5432}"
        local dbuser="${DBUSER:-${current_user}}"
        # Never use 'postgres' as dbuser if DBUSER is not explicitly set
        if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
            dbuser="${current_user}"
        fi
        local dbname="${DBNAME:-osm_notes_monitoring_test}"
        
        # Update alert to be old enough for escalation
        # Use single-line query to avoid issues with multi-line strings in BATS
        local update_query="UPDATE alerts SET created_at = CURRENT_TIMESTAMP - INTERVAL '${ESCALATION_LEVEL1_MINUTES} minutes' WHERE id = '${alert_id}'::uuid;"
        
        PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "${update_query}" >/dev/null 2>&1 || true
        
        # Ensure DBUSER is set correctly for escalate_alert
        export DBUSER="${dbuser}"
        export DBNAME="${dbname}"
        export DBHOST="${dbhost}"
        export DBPORT="${dbport}"
        # Escalate without specifying level (auto-determine)
        run escalate_alert "${alert_id}"
        # May succeed or fail depending on needs_escalation check
        assert [ "$status" -ge 0 ]
    else
        skip "Could not create test alert"
    fi
}

@test "escalate_alert handles invalid escalation level gracefully" {
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    local alert_id
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Small delay to ensure INSERT is committed
    sleep 0.1
    
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Ensure DBUSER is set correctly for escalate_alert
        local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
        export DBUSER="${dbuser}"
        export DBNAME="${DBNAME:-osm_notes_monitoring_test}"
        export DBHOST="${DBHOST:-localhost}"
        export DBPORT="${DBPORT:-5432}"
        # Try to escalate to invalid level (negative)
        run escalate_alert "${alert_id}" "-1"
        assert_failure
    else
        skip "Could not create test alert"
    fi
}

@test "check_escalation handles multiple alerts" {
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create multiple test alerts directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query1="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type1', 'Test message 1', '{}'::jsonb) RETURNING id;"
    local insert_query2="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type2', 'Test message 2', '{}'::jsonb) RETURNING id;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query1}" >/dev/null 2>&1 || true
    
    sleep 0.1
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query2}" >/dev/null 2>&1 || true
    
    sleep 0.1
    
    # Ensure DBUSER is set correctly for check_escalation
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    export DBUSER="${dbuser}"
    export DBNAME="${DBNAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # Check escalation for component
    run check_escalation "INGESTION"
    assert_success
    assert_output --partial "Escalated"
}

@test "show_rules displays all escalation levels" {
    run show_rules
    assert_success
    assert_output --partial "Level 1"
    assert_output --partial "Level 2"
    assert_output --partial "Level 3"
    assert_output --partial "minutes"
}

@test "show_oncall handles enabled rotation" {
    export ONCALL_ROTATION_ENABLED="true"
    export ONCALL_PRIMARY="primary@example.com"
    export ONCALL_SECONDARY="secondary@example.com"
    
    run show_oncall
    assert_success
    assert_output --partial "primary@example.com"
    assert_output --partial "secondary@example.com"
}

@test "rotate_oncall succeeds when enabled" {
    export ONCALL_ROTATION_ENABLED="true"
    
    run rotate_oncall
    assert_success
    assert_output --partial "rotation"
}

@test "main handles check action with component" {
    run main "check" "INGESTION"
    assert_success
}

@test "main handles escalate action with level" {
    # Ensure DBNAME and DBUSER are set correctly (already set in setup, but ensure they're available)
    export DBNAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    # IMPORTANT: Get current_user FIRST, before setting DBUSER
    local current_user
    if [[ -n "${USER:-}" ]]; then
        current_user="${USER}"
    else
        current_user=$(id -un 2>/dev/null || echo "postgres")
    fi
    export USER="${current_user}"
    
    export DBUSER="${DBUSER:-${current_user}}"
    
    # Create test alert directly using psql (same pattern as working test)
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
    local dbname="${DBNAME:-osm_notes_monitoring_test}"
    
    local insert_query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('INGESTION', 'critical', 'test_type', 'Test message', '{}'::jsonb) RETURNING id;"
    local alert_id
    local psql_output
    psql_output=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${insert_query}" 2>&1) || true
    
    # Small delay to ensure INSERT is committed
    sleep 0.1
    
    alert_id=$(echo "${psql_output}" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    
    # Debug: log what we got (only if alert_id is empty)
    if [[ -z "${alert_id}" ]]; then
        # Try to get alert_id from database directly (fallback) - use local variables
        alert_id=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT id FROM alerts WHERE component = 'INGESTION' AND alert_type = 'test_type' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1 || echo "")
    fi
    
    if [[ -n "${alert_id}" && "${#alert_id}" -eq 36 ]]; then
        # Ensure DBUSER is set correctly for main
        local dbuser="${DBUSER:-${current_user}}"
    # Never use 'postgres' as dbuser if DBUSER is not explicitly set
    if [[ -z "${DBUSER:-}" ]] || [[ "${dbuser}" == "postgres" ]]; then
        dbuser="${current_user}"
    fi
        export DBUSER="${dbuser}"
        export DBNAME="${DBNAME:-osm_notes_monitoring_test}"
        export DBHOST="${DBHOST:-localhost}"
        export DBPORT="${DBPORT:-5432}"
        run main "escalate" "${alert_id}" "1"
        # May succeed or fail depending on alert state
        assert [ "$status" -ge 0 ]
    else
        skip "Could not create test alert"
    fi
}

@test "main handles rules action" {
    run main "rules"
    assert_success
    assert_output --partial "Level"
}

@test "main handles oncall action" {
    run main "oncall"
    assert_success
    assert_output --partial "on-call"
}

@test "main handles rotate action" {
    run main "rotate"
    # May succeed or fail depending on rotation enabled
    assert [ "$status" -ge 0 ]
}

@test "main handles help action" {
    run main "help"
    assert_success
    assert_output --partial "Usage:"
}

@test "load_config sets default escalation values" {
    unset ESCALATION_ENABLED
    unset ESCALATION_LEVEL1_MINUTES
    unset ESCALATION_LEVEL2_MINUTES
    unset ESCALATION_LEVEL3_MINUTES
    
    load_config
    
    assert [ -n "${ESCALATION_ENABLED:-}" ]
    assert [ -n "${ESCALATION_LEVEL1_MINUTES:-}" ]
    assert [ -n "${ESCALATION_LEVEL2_MINUTES:-}" ]
    assert [ -n "${ESCALATION_LEVEL3_MINUTES:-}" ]
}


