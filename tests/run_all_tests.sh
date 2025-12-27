#!/usr/bin/env bash
#
# Run All Tests
# Executes all test suites: unit, integration, e2e, SQL queries, and script tests
#
# Version: 1.0.0
# Date: 2025-12-27
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
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Print section header
##
print_section() {
    echo
    print_message "${BLUE}" "═══════════════════════════════════════════════════════════"
    print_message "${BLUE}" "${1}"
    print_message "${BLUE}" "═══════════════════════════════════════════════════════════"
    echo
}

##
# Check if BATS is installed
##
check_bats() {
    if ! command -v bats > /dev/null 2>&1; then
        print_message "${YELLOW}" "Warning: BATS not found. Unit, integration, and e2e tests will be skipped."
        print_message "${YELLOW}" "Install BATS: git clone https://github.com/bats-core/bats-core.git && cd bats-core && ./install.sh /usr/local"
        return 1
    fi
    return 0
}

##
# Run unit tests
##
run_unit_tests() {
    print_section "UNIT TESTS"
    
    if ! check_bats; then
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local unit_test_dir="${SCRIPT_DIR}/unit"
    if [[ ! -d "${unit_test_dir}" ]]; then
        print_message "${YELLOW}" "Unit test directory not found: ${unit_test_dir}"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local test_files
    test_files=$(find "${unit_test_dir}" -name "test_*.sh" -type f 2>/dev/null || true)
    
    if [[ -z "${test_files}" ]]; then
        print_message "${YELLOW}" "No unit tests found"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local failed=0
    while IFS= read -r test_file; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        print_message "${GREEN}" "Running: $(basename "${test_file}")"
        
        if bats "${test_file}" 2>&1; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            failed=$((failed + 1))
        fi
        echo
    done <<< "${test_files}"
    
    if [[ ${failed} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All unit tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed} unit test suite(s) failed"
        return 1
    fi
}

##
# Run integration tests
##
run_integration_tests() {
    print_section "INTEGRATION TESTS"
    
    if ! check_bats; then
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local integration_test_dir="${SCRIPT_DIR}/integration"
    if [[ ! -d "${integration_test_dir}" ]]; then
        print_message "${YELLOW}" "Integration test directory not found: ${integration_test_dir}"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local test_files
    test_files=$(find "${integration_test_dir}" -name "test_*.sh" -type f 2>/dev/null || true)
    
    if [[ -z "${test_files}" ]]; then
        print_message "${YELLOW}" "No integration tests found"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local failed=0
    while IFS= read -r test_file; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        print_message "${GREEN}" "Running: $(basename "${test_file}")"
        
        if bats "${test_file}" 2>&1; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            failed=$((failed + 1))
        fi
        echo
    done <<< "${test_files}"
    
    if [[ ${failed} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All integration tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed} integration test suite(s) failed"
        return 1
    fi
}

##
# Run end-to-end tests
##
run_e2e_tests() {
    print_section "END-TO-END TESTS"
    
    if ! check_bats; then
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local e2e_test_dir="${SCRIPT_DIR}/e2e"
    if [[ ! -d "${e2e_test_dir}" ]]; then
        print_message "${YELLOW}" "E2E test directory not found: ${e2e_test_dir}"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local test_files
    test_files=$(find "${e2e_test_dir}" -name "test_*.sh" -type f 2>/dev/null || true)
    
    if [[ -z "${test_files}" ]]; then
        print_message "${YELLOW}" "No e2e tests found"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local failed=0
    while IFS= read -r test_file; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        print_message "${GREEN}" "Running: $(basename "${test_file}")"
        
        if bats "${test_file}" 2>&1; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            failed=$((failed + 1))
        fi
        echo
    done <<< "${test_files}"
    
    if [[ ${failed} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All e2e tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed} e2e test suite(s) failed"
        return 1
    fi
}

##
# Run SQL query tests
##
run_sql_tests() {
    print_section "SQL QUERY TESTS"
    
    local sql_test_scripts=(
        "${PROJECT_ROOT}/sql/ingestion/test_queries.sh"
        "${PROJECT_ROOT}/sql/analytics/test_queries.sh"
    )
    
    local failed=0
    for test_script in "${sql_test_scripts[@]}"; do
        if [[ ! -f "${test_script}" ]]; then
            print_message "${YELLOW}" "SQL test script not found: ${test_script}"
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            continue
        fi
        
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        print_message "${GREEN}" "Running: $(basename "${test_script}")"
        
        if bash "${test_script}" --syntax-only 2>&1; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            failed=$((failed + 1))
        fi
        echo
    done
    
    if [[ ${failed} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All SQL query tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed} SQL test script(s) failed"
        return 1
    fi
}

##
# Run script tests (in scripts/ directory)
##
run_script_tests() {
    print_section "SCRIPT TESTS"
    
    local scripts_dir="${PROJECT_ROOT}/scripts"
    if [[ ! -d "${scripts_dir}" ]]; then
        print_message "${YELLOW}" "Scripts directory not found: ${scripts_dir}"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local test_scripts
    test_scripts=$(find "${scripts_dir}" -name "test_*.sh" -type f 2>/dev/null || true)
    
    if [[ -z "${test_scripts}" ]]; then
        print_message "${YELLOW}" "No script tests found"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local failed=0
    while IFS= read -r test_script; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        print_message "${GREEN}" "Running: $(basename "${test_script}")"
        
        if bash "${test_script}" 2>&1; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            failed=$((failed + 1))
        fi
        echo
    done <<< "${test_scripts}"
    
    if [[ ${failed} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All script tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed} script test(s) failed"
        return 1
    fi
}

##
# Run performance tests
##
run_performance_tests() {
    print_section "PERFORMANCE TESTS"
    
    if ! check_bats; then
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local perf_test_dir="${SCRIPT_DIR}/performance"
    if [[ ! -d "${perf_test_dir}" ]]; then
        print_message "${YELLOW}" "Performance test directory not found: ${perf_test_dir}"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local test_files
    test_files=$(find "${perf_test_dir}" -name "test_*.sh" -type f 2>/dev/null || true)
    
    if [[ -z "${test_files}" ]]; then
        print_message "${YELLOW}" "No performance tests found"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi
    
    local failed=0
    while IFS= read -r test_file; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        print_message "${GREEN}" "Running: $(basename "${test_file}")"
        
        if bats "${test_file}" 2>&1; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            FAILED_TESTS=$((FAILED_TESTS + 1))
            failed=$((failed + 1))
        fi
        echo
    done <<< "${test_files}"
    
    if [[ ${failed} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All performance tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed} performance test suite(s) failed"
        return 1
    fi
}

##
# Print summary
##
print_summary() {
    echo
    print_section "TEST SUMMARY"
    
    print_message "${BLUE}" "Total test suites: ${TOTAL_TESTS}"
    print_message "${GREEN}" "Passed: ${PASSED_TESTS}"
    
    if [[ ${FAILED_TESTS} -gt 0 ]]; then
        print_message "${RED}" "Failed: ${FAILED_TESTS}"
    else
        print_message "${GREEN}" "Failed: ${FAILED_TESTS}"
    fi
    
    if [[ ${SKIPPED_TESTS} -gt 0 ]]; then
        print_message "${YELLOW}" "Skipped: ${SKIPPED_TESTS}"
    fi
    
    echo
    
    if [[ ${FAILED_TESTS} -eq 0 ]]; then
        print_message "${GREEN}" "═══════════════════════════════════════════════════════════"
        print_message "${GREEN}" "✓ ALL TESTS PASSED!"
        print_message "${GREEN}" "═══════════════════════════════════════════════════════════"
        return 0
    else
        print_message "${RED}" "═══════════════════════════════════════════════════════════"
        print_message "${RED}" "✗ SOME TESTS FAILED"
        print_message "${RED}" "═══════════════════════════════════════════════════════════"
        return 1
    fi
}

##
# Show usage
##
usage() {
    cat << EOF
Run All Tests

Executes all test suites: unit, integration, e2e, SQL queries, and script tests.

Usage: $0 [OPTIONS]

Options:
    -u, --unit-only          Run only unit tests
    -i, --integration-only  Run only integration tests
    -e, --e2e-only          Run only e2e tests
    -s, --sql-only          Run only SQL query tests
    -p, --scripts-only      Run only script tests
    -f, --performance-only  Run only performance tests
    -h, --help              Show this help message

Examples:
    # Run all tests
    $0

    # Run only unit tests
    $0 --unit-only

    # Run only SQL tests
    $0 --sql-only

EOF
}

##
# Main
##
main() {
    local unit_only=false
    local integration_only=false
    local e2e_only=false
    local sql_only=false
    local scripts_only=false
    local performance_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -u|--unit-only)
                unit_only=true
                shift
                ;;
            -i|--integration-only)
                integration_only=true
                shift
                ;;
            -e|--e2e-only)
                e2e_only=true
                shift
                ;;
            -s|--sql-only)
                sql_only=true
                shift
                ;;
            -p|--scripts-only)
                scripts_only=true
                shift
                ;;
            -f|--performance-only)
                performance_only=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
        esac
    done
    
    print_message "${GREEN}" "═══════════════════════════════════════════════════════════"
    print_message "${GREEN}" "  OSM Notes Monitoring - Test Suite Runner"
    print_message "${GREEN}" "═══════════════════════════════════════════════════════════"
    
    local overall_result=0
    
    # Run tests based on options
    if [[ "${unit_only}" == "true" ]]; then
        run_unit_tests || overall_result=1
    elif [[ "${integration_only}" == "true" ]]; then
        run_integration_tests || overall_result=1
    elif [[ "${e2e_only}" == "true" ]]; then
        run_e2e_tests || overall_result=1
    elif [[ "${sql_only}" == "true" ]]; then
        run_sql_tests || overall_result=1
    elif [[ "${scripts_only}" == "true" ]]; then
        run_script_tests || overall_result=1
    elif [[ "${performance_only}" == "true" ]]; then
        run_performance_tests || overall_result=1
    else
        # Run all tests
        run_unit_tests || overall_result=1
        run_integration_tests || overall_result=1
        run_e2e_tests || overall_result=1
        run_sql_tests || overall_result=1
        run_script_tests || overall_result=1
        run_performance_tests || overall_result=1
    fi
    
    # Print summary
    print_summary
    
    # Exit with appropriate code based on overall result
    if [[ ${overall_result} -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

