#!/usr/bin/env bash
#
# Generate Instrumented Test Coverage Report (Optimized)
# Uses bashcov to measure actual code coverage
# Optimized version: runs coverage tool once on all tests
#
# Version: 2.1.0
# Date: 2026-01-02
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

# Coverage tool selection
COVERAGE_TOOL="${COVERAGE_TOOL:-bashcov}"  # bashcov only

# Output directories
readonly COVERAGE_DIR="${PROJECT_ROOT}/coverage"
readonly BASHCOV_OUTPUT="${COVERAGE_DIR}/bashcov"
readonly COVERAGE_REPORT="${COVERAGE_DIR}/coverage_report_instrumented.txt"

# Database configuration (use environment variables or defaults)
# For bashcov, we want to avoid password prompts, so we'll use empty password
# Tests should use mocks, but if they don't, psql will fail silently
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
export DBNAME="${DBNAME:-${TEST_DB_NAME}}"
export DBHOST="${DBHOST:-${PGHOST:-localhost}}"
export DBPORT="${DBPORT:-${PGPORT:-5432}}"
export DBUSER="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
# Set PGPASSWORD to empty to avoid password prompts (tests should use mocks)
export PGPASSWORD="${PGPASSWORD:-}"
# Also set PGOPTIONS to avoid interactive prompts
export PGOPTIONS="-c statement_timeout=1s"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if bashcov is available
##
check_bashcov() {
    if command -v bashcov >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

##
# Detect available coverage tool (bashcov only)
##
detect_coverage_tool() {
    if check_bashcov; then
        echo "bashcov"
        return 0
    else
        print_message "${RED}" "Error: bashcov not found. Install with: gem install bashcov"
        return 1
    fi
}

##
# Run all tests with bashcov (single execution)
##
run_all_tests_with_bashcov() {
    local output_dir="${BASHCOV_OUTPUT}/all"
    mkdir -p "${output_dir}"
    
    print_message "${BLUE}" "Running all tests with bashcov (this may take a while)..."
    
    # bashcov generates coverage.json in current directory
    # Run from project root so coverage.json is generated there
    cd "${PROJECT_ROOT}" || return 1
    
    # Find all test files and execute them with bats
    # bashcov needs explicit test files, not directories
    # Execute tests in batches to avoid command line length issues
    local test_files=()
    while IFS= read -r -d '' test_file; do
        test_files+=("${test_file}")
    done < <(find "${PROJECT_ROOT}/tests" -name "*.sh" -type f -print0 2>/dev/null | sort -z)
    
    # Run bashcov on test files
    # Note: bashcov works best when executing bats directly on individual files
    # We'll execute them one by one and bashcov will merge the results
    if [[ ${#test_files[@]} -gt 0 ]]; then
        local count=0
        for test_file in "${test_files[@]}"; do
            # Run each test file individually - bashcov will accumulate coverage
            # Redirect stdin to /dev/null to prevent psql password prompts
            bashcov \
                --root "${PROJECT_ROOT}" \
                --skip-uncovered \
                bats "${test_file}" </dev/null >/dev/null 2>&1 || true
            count=$((count + 1))
            # Show progress every 10 tests
            if [[ $((count % 10)) -eq 0 ]]; then
                print_message "${BLUE}" "  Processed ${count}/${#test_files[@]} test files..."
            fi
        done
    fi
    
    # Move coverage.json to output directory if it exists
    if [[ -f "${PROJECT_ROOT}/coverage.json" ]]; then
        mv "${PROJECT_ROOT}/coverage.json" "${output_dir}/coverage.json" 2>/dev/null || true
    fi
    
    print_message "${GREEN}" "✓ Tests executed with bashcov"
}

##
# Extract coverage for a specific script from bashcov report
##
get_script_coverage_from_bashcov() {
    local script_path="${1}"
    local resultset_file="${COVERAGE_DIR}/.resultset.json"
    
    # bashcov uses SimpleCov format: .resultset.json
    if [[ -f "${resultset_file}" ]]; then
        local coverage
        coverage=$(python3 -c "
import json
import sys
import os

try:
    script_path = '${script_path}'
    script_basename = os.path.basename(script_path)
    script_abs_path = os.path.abspath(script_path)
    
    with open('${resultset_file}', 'r') as f:
        data = json.load(f)
    
    # SimpleCov structure: { 'command': { 'coverage': { 'file_path': [coverage_array] } } }
    for cmd_name, cmd_data in data.items():
        if 'coverage' in cmd_data:
            files = cmd_data['coverage']
            for file_path, coverage_data in files.items():
                # Check if this file matches our script
                file_basename = os.path.basename(file_path)
                if (script_path in file_path or 
                    script_abs_path in file_path or 
                    script_basename == file_basename):
                    # Calculate coverage percentage from array
                    if isinstance(coverage_data, list):
                        covered = sum(1 for x in coverage_data if x is not None and x > 0)
                        total = len([x for x in coverage_data if x is not None])
                        if total > 0:
                            percent = int((covered / total) * 100)
                            print(percent)
                            sys.exit(0)
    
    # If not found, return 0
    print(0)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")
        echo "${coverage}"
    else
        echo "0"
    fi
}

##
# Count test files for a script
##
count_test_files_for_script() {
    local script_path="${1}"
    local script_name
    script_name=$(basename "${script_path}" .sh)
    
    local test_count=0
    # shellcheck disable=SC2034
    # test_file is used in the loop to count files
    while IFS= read -r -d '' test_file; do
        test_count=$((test_count + 1))
    done < <(find "${PROJECT_ROOT}/tests" -name "*${script_name}*.sh" -type f -print0 2>/dev/null || true)
    
    echo "${test_count}"
}

##
# Generate comprehensive coverage report
##
generate_instrumented_report() {
    local tool="${1}"
    
    print_message "${BLUE}" "Generating instrumented coverage report using ${tool}..."
    
    # Create coverage directories
    mkdir -p "${COVERAGE_DIR}"
    mkdir -p "${BASHCOV_OUTPUT}"
    
    # Run all tests with bashcov
    run_all_tests_with_bashcov
    
    # Find all scripts
    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("${script}")
    done < <(find "${PROJECT_ROOT}/bin" -name "*.sh" -type f -print0 | sort -z)
    
    print_message "${BLUE}" "Analyzing coverage for ${#scripts[@]} scripts..."
    
    # Generate report
    {
        echo "OSM Notes Monitoring - Instrumented Test Coverage Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Tool: ${tool}"
        echo "=========================================="
        echo ""
        echo "Coverage Target: >80%"
        echo ""
        echo "Script Coverage:"
        echo "----------------------------------------"
        printf "%-50s %10s %10s %10s\n" "Script" "Tests" "Coverage" "Status"
        echo "----------------------------------------"
        
        local scripts_with_tests=0
        local scripts_above_threshold=0
        local total_coverage=0
        local coverage_count=0
        
        for script in "${scripts[@]}"; do
            local script_name
            script_name=$(basename "${script}" .sh)
            local test_count
            test_count=$(count_test_files_for_script "${script}")
            
            local coverage=0
            if [[ ${test_count} -gt 0 ]]; then
                coverage=$(get_script_coverage_from_bashcov "${script}")
                
                scripts_with_tests=$((scripts_with_tests + 1))
                
                if [[ "${coverage}" =~ ^[0-9]+$ ]] && [[ ${coverage} -gt 0 ]]; then
                    total_coverage=$((total_coverage + coverage))
                    coverage_count=$((coverage_count + 1))
                    
                    if [[ ${coverage} -ge 80 ]]; then
                        scripts_above_threshold=$((scripts_above_threshold + 1))
                    fi
                fi
            fi
            
            local status=""
            if [[ "${coverage}" =~ ^[0-9]+$ ]]; then
                if [[ ${coverage} -ge 80 ]]; then
                    status="✓"
                elif [[ ${coverage} -ge 50 ]]; then
                    status="⚠"
                else
                    status="✗"
                fi
                printf "%-50s %10s %9s%% %s\n" "${script_name}" "${test_count}" "${coverage}" "${status}"
            else
                printf "%-50s %10s %10s %s\n" "${script_name}" "${test_count}" "N/A" "✗"
            fi
        done
        
        echo "----------------------------------------"
        echo ""
        echo "Summary:"
        echo "  Total scripts: ${#scripts[@]}"
        echo "  Scripts with tests: ${scripts_with_tests}"
        echo "  Scripts above 80% coverage: ${scripts_above_threshold}"
        
        # Calculate overall coverage
        local overall_coverage=0
        if [[ ${coverage_count} -gt 0 ]]; then
            overall_coverage=$((total_coverage / coverage_count))
        fi
        
        echo "  Average coverage: ${overall_coverage}%"
        echo ""
        
        if [[ ${overall_coverage} -ge 80 ]]; then
            echo "Status: ✓ Coverage target met!"
        elif [[ ${overall_coverage} -ge 50 ]]; then
            echo "Status: ⚠ Coverage below target, improvement needed"
        else
            echo "Status: ✗ Coverage significantly below target"
        fi
        
        echo ""
        echo "Detailed reports available in:"
        echo "  ${BASHCOV_OUTPUT}/all/"
    } > "${COVERAGE_REPORT}"
    
    print_message "${GREEN}" "✓ Instrumented coverage report generated: ${COVERAGE_REPORT}"
    
    # Display summary
    tail -20 "${COVERAGE_REPORT}"
}

##
# Main
##
main() {
    print_message "${GREEN}" "Instrumented Test Coverage Report Generator (Optimized)"
    echo
    
    # Detect coverage tool
    local tool
    if ! tool=$(detect_coverage_tool); then
        print_message "${RED}" "Failed to detect coverage tool"
        exit 1
    fi
    
    print_message "${BLUE}" "Using coverage tool: ${tool}"
    print_message "${YELLOW}" "Note: This will run all tests once with ${tool} (more memory efficient)"
    echo
    
    # Generate report
    if ! generate_instrumented_report "${tool}"; then
        print_message "${RED}" "Failed to generate instrumented coverage report"
        exit 1
    fi
    
    print_message "${GREEN}" ""
    print_message "${GREEN}" "Coverage report generated successfully!"
    print_message "${YELLOW}" "View reports:"
    echo "  Text: ${COVERAGE_REPORT}"
    echo "  JSON: ${BASHCOV_OUTPUT}/all/coverage.json"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
