#!/usr/bin/env bash
#
# Test Database Schema Script
# Tests the database initialization script (init.sql)
#
# Version: 1.0.0
# Date: 2025-01-23
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TEST_DB="osm_notes_monitoring_test"
readonly INIT_SQL="${SCRIPT_DIR}/init.sql"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Run a test and track results
##
run_test() {
    local test_name="${1}"
    shift
    local test_command="$*"
    
    print_message "${BLUE}" "Testing: ${test_name}"
    
    if eval "${test_command}" > /dev/null 2>&1; then
        print_message "${GREEN}" "  ✓ PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_message "${RED}" "  ✗ FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Check if PostgreSQL is available
##
check_postgres() {
    if ! command -v psql > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: psql not found. Please install PostgreSQL client."
        exit 1
    fi
    
    if ! psql -lqt > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: Cannot connect to PostgreSQL. Check your connection."
        exit 1
    fi
}

##
# Setup test database
##
setup_test_database() {
    print_message "${YELLOW}" "Setting up test database: ${TEST_DB}"
    
    # Drop test database if it exists
    if psql -lqt | cut -d \| -f 1 | grep -qw "${TEST_DB}"; then
        print_message "${YELLOW}" "  Dropping existing test database..."
        dropdb "${TEST_DB}" || true
    fi
    
    # Create test database
    if createdb "${TEST_DB}"; then
        print_message "${GREEN}" "  ✓ Test database created"
    else
        print_message "${RED}" "  ✗ Failed to create test database"
        exit 1
    fi
}

##
# Initialize schema
##
initialize_schema() {
    print_message "${YELLOW}" "Initializing database schema..."
    
    if psql -d "${TEST_DB}" -f "${INIT_SQL}" > /dev/null 2>&1; then
        print_message "${GREEN}" "  ✓ Schema initialized"
        return 0
    else
        print_message "${RED}" "  ✗ Failed to initialize schema"
        print_message "${YELLOW}" "  Checking for errors..."
        psql -d "${TEST_DB}" -f "${INIT_SQL}" 2>&1 | head -20
        exit 1
    fi
}

##
# Test tables exist
##
test_tables() {
    print_message "${BLUE}" "\n=== Testing Tables ==="
    
    local tables=(
        "metrics"
        "alerts"
        "security_events"
        "ip_management"
        "component_health"
    )
    
    for table in "${tables[@]}"; do
        run_test "Table exists: ${table}" \
            "psql -d ${TEST_DB} -t -c \"SELECT 1 FROM information_schema.tables WHERE table_name = '${table}';\" | grep -q 1"
    done
}

##
# Test indexes exist
##
test_indexes() {
    print_message "${BLUE}" "\n=== Testing Indexes ==="
    
    local indexes=(
        "idx_metrics_component_timestamp"
        "idx_metrics_metric_name"
        "idx_alerts_component_status"
        "idx_security_events_ip"
        "idx_ip_management_ip_type"
    )
    
    for idx in "${indexes[@]}"; do
        run_test "Index exists: ${idx}" \
            "psql -d ${TEST_DB} -t -c \"SELECT 1 FROM pg_indexes WHERE indexname = '${idx}';\" | grep -q 1"
    done
}

##
# Test functions exist
##
test_functions() {
    print_message "${BLUE}" "\n=== Testing Functions ==="
    
    local functions=(
        "cleanup_old_metrics"
        "cleanup_old_alerts"
        "cleanup_expired_ip_blocks"
        "cleanup_old_security_events"
    )
    
    for func in "${functions[@]}"; do
        run_test "Function exists: ${func}" \
            "psql -d ${TEST_DB} -t -c \"SELECT 1 FROM pg_proc WHERE proname = '${func}';\" | grep -q 1"
    done
}

##
# Test views exist
##
test_views() {
    print_message "${BLUE}" "\n=== Testing Views ==="
    
    local views=(
        "metrics_summary"
        "active_alerts_summary"
    )
    
    for view in "${views[@]}"; do
        run_test "View exists: ${view}" \
            "psql -d ${TEST_DB} -t -c \"SELECT 1 FROM information_schema.views WHERE table_name = '${view}';\" | grep -q 1"
    done
}

##
# Test data insertion
##
test_data_insertion() {
    print_message "${BLUE}" "\n=== Testing Data Insertion ==="
    
    # Test metrics insertion
    run_test "Insert metric" \
        "psql -d ${TEST_DB} -c \"INSERT INTO metrics (component, metric_name, metric_value, metric_unit) VALUES ('ingestion', 'test_metric', 100.5, 'ms');\""
    
    # Test alert insertion
    run_test "Insert alert" \
        "psql -d ${TEST_DB} -c \"INSERT INTO alerts (component, alert_level, alert_type, message) VALUES ('ingestion', 'warning', 'test_alert', 'Test alert message');\""
    
    # Test security event insertion
    run_test "Insert security event" \
        "psql -d ${TEST_DB} -c \"INSERT INTO security_events (event_type, ip_address, endpoint) VALUES ('rate_limit', '192.168.1.100', '/api/test');\""
    
    # Test IP management insertion
    run_test "Insert IP management" \
        "psql -d ${TEST_DB} -c \"INSERT INTO ip_management (ip_address, list_type, reason) VALUES ('192.168.1.100', 'whitelist', 'Test IP');\""
}

##
# Test constraints
##
test_constraints() {
    print_message "${BLUE}" "\n=== Testing Constraints ==="
    
    # Test invalid component
    run_test "Reject invalid component in metrics" \
        "! psql -d ${TEST_DB} -c \"INSERT INTO metrics (component, metric_name, metric_value) VALUES ('invalid', 'test', 1);\" 2>&1 | grep -q 'violates check constraint'"
    
    # Test invalid alert level
    run_test "Reject invalid alert level" \
        "! psql -d ${TEST_DB} -c \"INSERT INTO alerts (component, alert_level, alert_type, message) VALUES ('ingestion', 'invalid', 'test', 'test');\" 2>&1 | grep -q 'violates check constraint'"
    
    # Test invalid IP list type
    run_test "Reject invalid IP list type" \
        "! psql -d ${TEST_DB} -c \"INSERT INTO ip_management (ip_address, list_type) VALUES ('192.168.1.101', 'invalid');\" 2>&1 | grep -q 'violates check constraint'"
}

##
# Test functions execution
##
test_functions_execution() {
    print_message "${BLUE}" "\n=== Testing Function Execution ==="
    
    # Test cleanup functions (should return 0 or count)
    run_test "Execute cleanup_old_metrics" \
        "psql -d ${TEST_DB} -t -A -c \"SELECT cleanup_old_metrics(90);\" | grep -qE '^[0-9]+$'"
    
    run_test "Execute cleanup_old_alerts" \
        "psql -d ${TEST_DB} -t -A -c \"SELECT cleanup_old_alerts(180);\" | grep -qE '^[0-9]+$'"
    
    run_test "Execute cleanup_expired_ip_blocks" \
        "psql -d ${TEST_DB} -t -A -c \"SELECT cleanup_expired_ip_blocks();\" | grep -qE '^[0-9]+$'"
    
    run_test "Execute cleanup_old_security_events" \
        "psql -d ${TEST_DB} -t -A -c \"SELECT cleanup_old_security_events(90);\" | grep -qE '^[0-9]+$'"
}

##
# Test views query
##
test_views_query() {
    print_message "${BLUE}" "\n=== Testing Views Query ==="
    
    # Test metrics_summary view
    run_test "Query metrics_summary view" \
        "psql -d ${TEST_DB} -t -c \"SELECT * FROM metrics_summary LIMIT 1;\" > /dev/null"
    
    # Test active_alerts_summary view
    run_test "Query active_alerts_summary view" \
        "psql -d ${TEST_DB} -t -c \"SELECT * FROM active_alerts_summary;\" > /dev/null"
}

##
# Test component health
##
test_component_health() {
    print_message "${BLUE}" "\n=== Testing Component Health ==="
    
    # Check all components are initialized
    local components=("ingestion" "analytics" "wms" "api" "data" "infrastructure")
    
    for component in "${components[@]}"; do
        run_test "Component health initialized: ${component}" \
            "psql -d ${TEST_DB} -t -c \"SELECT 1 FROM component_health WHERE component = '${component}';\" | grep -q 1"
    done
}

##
# Test extensions
##
test_extensions() {
    print_message "${BLUE}" "\n=== Testing Extensions ==="
    
    run_test "Extension uuid-ossp enabled" \
        "psql -d ${TEST_DB} -t -c \"SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp';\" | grep -q 1"
    
    run_test "Extension pg_trgm enabled" \
        "psql -d ${TEST_DB} -t -c \"SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm';\" | grep -q 1"
}

##
# Cleanup test database
##
cleanup() {
    print_message "${YELLOW}" "\nCleaning up test database..."
    
    if dropdb "${TEST_DB}" > /dev/null 2>&1; then
        print_message "${GREEN}" "  ✓ Test database dropped"
    else
        print_message "${YELLOW}" "  ⚠ Could not drop test database (may not exist)"
    fi
}

##
# Print summary
##
print_summary() {
    echo
    print_message "${BLUE}" "=== Test Summary ==="
    print_message "${GREEN}" "Tests passed: ${TESTS_PASSED}"
    
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        print_message "${RED}" "Tests failed: ${TESTS_FAILED}"
        echo
        return 1
    else
        print_message "${GREEN}" "Tests failed: ${TESTS_FAILED}"
        echo
        print_message "${GREEN}" "✓ All tests passed!"
        return 0
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "OSM-Notes-Monitoring Schema Test"
    echo
    
    # Trap to cleanup on exit
    trap cleanup EXIT
    
    # Check prerequisites
    check_postgres
    
    # Setup
    setup_test_database
    initialize_schema
    
    # Run tests
    test_extensions
    test_tables
    test_indexes
    test_functions
    test_views
    test_component_health
    test_data_insertion
    test_constraints
    test_functions_execution
    test_views_query
    
    # Summary
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

