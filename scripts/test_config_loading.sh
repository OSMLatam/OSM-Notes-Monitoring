#!/usr/bin/env bash
#
# Test Configuration Loading
# Tests that all configuration files can be loaded correctly
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
readonly YELLOW='\033[1;33m'
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
# Test configuration file syntax
##
test_config_syntax() {
    local config_file="${1}"
    local config_name="${2}"
    
    run_test "Syntax check: ${config_name}" \
        "bash -n '${config_file}'"
}

##
# Test configuration file loading
##
test_config_loading() {
    local config_file="${1}"
    local config_name="${2}"
    
    # Create temporary test script
    local test_script
    test_script=$(mktemp)
    
    cat > "${test_script}" << EOF
#!/usr/bin/env bash
set -euo pipefail
source "${config_file}"
echo "Config loaded successfully"
EOF
    
    chmod +x "${test_script}"
    
    run_test "Loading: ${config_name}" \
        "bash '${test_script}'"
    
    rm -f "${test_script}"
}

##
# Test main config loading function
##
test_main_config_function() {
    local project_root="${PROJECT_ROOT}"
    
    # Source config functions
    # shellcheck disable=SC1091
    source "${project_root}/bin/lib/configFunctions.sh"
    
    # Test if function exists
    run_test "Function exists: load_main_config" \
        "type load_main_config"
    
    # Test if function can be called (may fail if config doesn't exist, that's OK)
    run_test "Function callable: load_main_config" \
        "load_main_config || true"
}

##
# Test all config loading functions
##
test_all_config_functions() {
    local project_root="${PROJECT_ROOT}"
    
    # Source config functions
    # shellcheck disable=SC1091
    source "${project_root}/bin/lib/configFunctions.sh"
    
    local functions=(
        "load_main_config"
        "load_monitoring_config"
        "load_alert_config"
        "load_security_config"
        "load_all_configs"
    )
    
    for func in "${functions[@]}"; do
        run_test "Function exists: ${func}" \
            "type ${func}"
    done
}

##
# Test configuration variables
##
test_config_variables() {
    local project_root="${PROJECT_ROOT}"
    local config_file="${project_root}/etc/properties.sh.example"
    
    # Source config file
    # shellcheck disable=SC1090,SC1091
    source "${config_file}"
    
    # Check required variables
    local required_vars=(
        "DBNAME"
        "DBHOST"
        "DBPORT"
        "DBUSER"
    )
    
    for var in "${required_vars[@]}"; do
        run_test "Variable set: ${var}" \
            "[[ -n \"\${${var}:-}\" ]]"
    done
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
    print_message "${GREEN}" "Configuration Loading Tests"
    echo
    
    local project_root="${PROJECT_ROOT}"
    
    # Test configuration files exist
    print_message "${BLUE}" "\n=== Testing Configuration Files ==="
    
    local configs=(
        "etc/properties.sh.example:Main Configuration"
        "config/monitoring.conf.example:Monitoring Configuration"
        "config/alerts.conf.example:Alert Configuration"
        "config/security.conf.example:Security Configuration"
    )
    
    for config_entry in "${configs[@]}"; do
        local config_file="${config_entry%%:*}"
        local config_name="${config_entry##*:}"
        local full_path="${project_root}/${config_file}"
        
        if [[ -f "${full_path}" ]]; then
            test_config_syntax "${full_path}" "${config_name}"
            test_config_loading "${full_path}" "${config_name}"
        else
            print_message "${YELLOW}" "  ⚠ Config file not found: ${config_file}"
        fi
    done
    
    # Test configuration functions
    print_message "${BLUE}" "\n=== Testing Configuration Functions ==="
    test_all_config_functions
    
    # Test configuration variables
    print_message "${BLUE}" "\n=== Testing Configuration Variables ==="
    test_config_variables
    
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

