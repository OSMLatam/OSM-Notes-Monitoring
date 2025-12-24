#!/usr/bin/env bash
#
# Run Unit Tests
# Executes all unit tests using BATS
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly TEST_DIR="${SCRIPT_DIR}/unit"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if BATS is installed
##
check_bats() {
    if ! command -v bats > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: BATS not found. Please install BATS:"
        echo "  git clone https://github.com/bats-core/bats-core.git"
        echo "  cd bats-core"
        echo "  ./install.sh /usr/local"
        exit 1
    fi
}

##
# Run unit tests
##
run_tests() {
    local test_files
    local failed_tests=0
    
    print_message "${YELLOW}" "Running unit tests..."
    echo
    
    # Find all test files
    if [[ ! -d "${TEST_DIR}" ]]; then
        print_message "${YELLOW}" "Unit test directory not found: ${TEST_DIR}"
        print_message "${YELLOW}" "Creating directory structure..."
        mkdir -p "${TEST_DIR}"
        return 0
    fi
    
    test_files=$(find "${TEST_DIR}" -name "test_*.sh" -type f)
    
    if [[ -z "${test_files}" ]]; then
        print_message "${YELLOW}" "No unit tests found in ${TEST_DIR}"
        return 0
    fi
    
    # Run tests
    while IFS= read -r test_file; do
        print_message "${GREEN}" "Running: $(basename "${test_file}")"
        
        if ! bats "${test_file}"; then
            failed_tests=$((failed_tests + 1))
        fi
        
        echo
    done <<< "${test_files}"
    
    # Summary
    echo
    if [[ ${failed_tests} -eq 0 ]]; then
        print_message "${GREEN}" "✓ All unit tests passed"
        return 0
    else
        print_message "${RED}" "✗ ${failed_tests} test suite(s) failed"
        return 1
    fi
}

##
# Main
##
main() {
    check_bats
    run_tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

