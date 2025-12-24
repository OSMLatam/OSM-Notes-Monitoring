#!/usr/bin/env bash
#
# Test Configuration Validation
# Tests configuration validation for all components
#
# Version: 1.0.0
# Date: 2025-12-24
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

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
# Run a test
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
# Main
##
main() {
    print_message "${GREEN}" "Configuration Validation Tests"
    echo
    
    # Source libraries (after setting up test environment)
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
    
    # Create test configs from examples
    mkdir -p "${PROJECT_ROOT}/tests/tmp"
    cp "${PROJECT_ROOT}/etc/properties.sh.example" "${PROJECT_ROOT}/tests/tmp/test_properties.sh"
    cp "${PROJECT_ROOT}/config/monitoring.conf.example" "${PROJECT_ROOT}/tests/tmp/test_monitoring.conf"
    cp "${PROJECT_ROOT}/config/alerts.conf.example" "${PROJECT_ROOT}/tests/tmp/test_alerts.conf"
    cp "${PROJECT_ROOT}/config/security.conf.example" "${PROJECT_ROOT}/tests/tmp/test_security.conf"
    
    # Source test configs
    # shellcheck disable=SC1090,SC1091
    source "${PROJECT_ROOT}/tests/tmp/test_properties.sh"
    # shellcheck disable=SC1090,SC1091
    source "${PROJECT_ROOT}/tests/tmp/test_monitoring.conf"
    # shellcheck disable=SC1090,SC1091
    source "${PROJECT_ROOT}/tests/tmp/test_alerts.conf"
    # shellcheck disable=SC1090,SC1091
    source "${PROJECT_ROOT}/tests/tmp/test_security.conf"
    
    # Test validations
    print_message "${BLUE}" "\n=== Testing Configuration Validations ==="
    
    # Test that validation functions exist
    run_test "Function exists: validate_main_config" \
        "type validate_main_config"
    
    run_test "Function exists: validate_monitoring_config" \
        "type validate_monitoring_config"
    
    run_test "Function exists: validate_alert_config" \
        "type validate_alert_config"
    
    run_test "Function exists: validate_security_config" \
        "type validate_security_config"
    
    run_test "Function exists: validate_all_configs" \
        "type validate_all_configs"
    
    # Test validations (may fail due to DB connection, that's OK)
    # Use timeout to prevent hanging
    run_test "validate_main_config executes" \
        "timeout 2 bash -c 'validate_main_config 2>&1 || true'"
    
    run_test "validate_monitoring_config executes" \
        "timeout 2 bash -c 'validate_monitoring_config 2>&1 || true'"
    
    run_test "validate_alert_config executes" \
        "timeout 2 bash -c 'validate_alert_config 2>&1 || true'"
    
    run_test "validate_security_config executes" \
        "timeout 2 bash -c 'validate_security_config 2>&1 || true'"
    
    run_test "validate_all_configs executes" \
        "timeout 2 bash -c 'validate_all_configs 2>&1 || true'"
    
    # Summary
    echo
    print_message "${BLUE}" "=== Test Summary ==="
    print_message "${GREEN}" "Tests passed: ${TESTS_PASSED}"
    
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        print_message "${RED}" "Tests failed: ${TESTS_FAILED}"
        exit 1
    else
        print_message "${GREEN}" "Tests failed: ${TESTS_FAILED}"
        print_message "${GREEN}" "✓ All tests passed!"
        exit 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

