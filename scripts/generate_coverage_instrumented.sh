#!/usr/bin/env bash
#
# Generate Instrumented Test Coverage Report
# Uses kcov or bashcov to measure actual code coverage
#
# Version: 1.0.0
# Date: 2025-12-31
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
COVERAGE_TOOL="${COVERAGE_TOOL:-auto}"  # auto, kcov, bashcov

# Output directories
readonly COVERAGE_DIR="${PROJECT_ROOT}/coverage"
readonly KCOV_OUTPUT="${COVERAGE_DIR}/kcov"
readonly BASHCOV_OUTPUT="${COVERAGE_DIR}/bashcov"
readonly COVERAGE_REPORT="${COVERAGE_DIR}/coverage_report_instrumented.txt"

# Database configuration (use environment variables or defaults)
# These will be exported to child processes (tests) when running kcov/bashcov
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
export DBNAME="${DBNAME:-${TEST_DB_NAME}}"
export DBHOST="${DBHOST:-${PGHOST:-localhost}}"
export DBPORT="${DBPORT:-${PGPORT:-5432}}"
export DBUSER="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
# Don't export PGPASSWORD if not set - let psql use .pgpass or peer auth
if [[ -n "${PGPASSWORD:-}" ]]; then
    export PGPASSWORD
fi

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if kcov is available
##
check_kcov() {
    if command -v kcov >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
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
# Detect available coverage tool
##
detect_coverage_tool() {
    if [[ "${COVERAGE_TOOL}" == "kcov" ]]; then
        if check_kcov; then
            echo "kcov"
            return 0
        else
            print_message "${RED}" "Error: kcov not found. Install with: sudo apt-get install kcov"
            return 1
        fi
    elif [[ "${COVERAGE_TOOL}" == "bashcov" ]]; then
        if check_bashcov; then
            echo "bashcov"
            return 0
        else
            print_message "${RED}" "Error: bashcov not found. Install with: gem install bashcov"
            return 1
        fi
    else
        # Auto-detect
        if check_kcov; then
            echo "kcov"
            return 0
        elif check_bashcov; then
            echo "bashcov"
            return 0
        else
            print_message "${RED}" "Error: No coverage tool found."
            print_message "${YELLOW}" "Install kcov: sudo apt-get install kcov"
            print_message "${YELLOW}" "Or install bashcov: gem install bashcov"
            return 1
        fi
    fi
}

##
# Install kcov (if possible)
##
install_kcov() {
    print_message "${BLUE}" "Attempting to install kcov..."
    
    if command -v apt-get >/dev/null 2>&1; then
        print_message "${YELLOW}" "Run: sudo apt-get install kcov"
        return 1
    elif command -v dnf >/dev/null 2>&1; then
        print_message "${YELLOW}" "Run: sudo dnf install kcov"
        return 1
    elif command -v brew >/dev/null 2>&1; then
        print_message "${YELLOW}" "Run: brew install kcov"
        return 1
    else
        print_message "${YELLOW}" "Please install kcov manually from: https://github.com/SimonKagstrom/kcov"
        return 1
    fi
}

##
# Run tests with kcov
##
run_kcov_coverage() {
    local test_file="${1}"
    local script_under_test="${2}"
    
    # Create output directory for this script
    local script_name
    script_name=$(basename "${script_under_test}" .sh)
    local output_dir="${KCOV_OUTPUT}/${script_name}"
    mkdir -p "${output_dir}"
    
    # Set up database environment variables for tests
    # Use DB* variables if set, otherwise fall back to PG* or system defaults
    local db_env=""
    db_env="DBNAME=\"${DBNAME:-${TEST_DB_NAME:-osm_notes_monitoring_test}}\" "
    db_env+="DBHOST=\"${DBHOST:-${PGHOST:-localhost}}\" "
    db_env+="DBPORT=\"${DBPORT:-${PGPORT:-5432}}\" "
    db_env+="DBUSER=\"${DBUSER:-${PGUSER:-${USER:-postgres}}}\" "
    
    # Only set PGPASSWORD if it's actually configured
    if [[ -n "${PGPASSWORD:-}" ]]; then
        db_env+="PGPASSWORD=\"${PGPASSWORD}\" "
    fi
    
    # Run kcov on the test file with proper environment
    # kcov will instrument the scripts sourced by the test
    eval "${db_env}" kcov \
        --include-path="${PROJECT_ROOT}/bin" \
        --exclude-path="${PROJECT_ROOT}/tests" \
        --exclude-path="${PROJECT_ROOT}/tmp" \
        --exclude-path="${PROJECT_ROOT}/coverage" \
        "${output_dir}" \
        bats "${test_file}" >/dev/null 2>&1 || true
    
    # Extract coverage percentage from kcov report
    if [[ -f "${output_dir}/index.html" ]]; then
        # kcov stores coverage in index.json
        if [[ -f "${output_dir}/index.json" ]]; then
            # Parse JSON to get coverage percentage
            local coverage
            coverage=$(python3 -c "
import json
import sys
try:
    with open('${output_dir}/index.json', 'r') as f:
        data = json.load(f)
        if 'merged' in data and 'percent_covered' in data['merged']:
            print(int(data['merged']['percent_covered']))
        else:
            print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
            echo "${coverage}"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

##
# Run tests with bashcov
##
run_bashcov_coverage() {
    local test_file="${1}"
    local script_under_test="${2}"
    
    # Create output directory
    local script_name
    script_name=$(basename "${script_under_test}" .sh)
    local output_dir="${BASHCOV_OUTPUT}/${script_name}"
    mkdir -p "${output_dir}"
    
    # Set up database environment variables for tests
    # Use DB* variables if set, otherwise fall back to PG* or system defaults
    local db_env=""
    db_env="DBNAME=\"${DBNAME:-${TEST_DB_NAME:-osm_notes_monitoring_test}}\" "
    db_env+="DBHOST=\"${DBHOST:-${PGHOST:-localhost}}\" "
    db_env+="DBPORT=\"${DBPORT:-${PGPORT:-5432}}\" "
    db_env+="DBUSER=\"${DBUSER:-${PGUSER:-${USER:-postgres}}}\" "
    
    # Only set PGPASSWORD if it's actually configured
    if [[ -n "${PGPASSWORD:-}" ]]; then
        db_env+="PGPASSWORD=\"${PGPASSWORD}\" "
    fi
    
    # Run bashcov on the test file with proper environment
    # bashcov will instrument bash scripts during execution
    eval "${db_env}" BASHCOV_OUTPUT_DIR="${output_dir}" \
    bashcov \
        --root "${PROJECT_ROOT}" \
        --skip-uncovered \
        bats "${test_file}" >/dev/null 2>&1 || true
    
    # Extract coverage from bashcov report
    if [[ -f "${output_dir}/coverage.json" ]]; then
        local coverage
        coverage=$(python3 -c "
import json
import sys
try:
    with open('${output_dir}/coverage.json', 'r') as f:
        data = json.load(f)
        if 'percent_covered' in data:
            print(int(data['percent_covered']))
        else:
            print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
        echo "${coverage}"
    else
        echo "0"
    fi
}

##
# Generate coverage report for a script
##
analyze_script_coverage() {
    local script_path="${1}"
    local tool="${2}"
    local script_name
    script_name=$(basename "${script_path}" .sh)
    
    # Find test files for this script
    local test_files=()
    while IFS= read -r -d '' test_file; do
        test_files+=("${test_file}")
    done < <(find "${PROJECT_ROOT}/tests" -name "*${script_name}*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "${script_name}|0|0|No tests"
        return 0
    fi
    
    # Run coverage for each test file and aggregate
    local total_coverage=0
    local coverage_count=0
    
    for test_file in "${test_files[@]}"; do
        local coverage=0
        if [[ "${tool}" == "kcov" ]]; then
            coverage=$(run_kcov_coverage "${test_file}" "${script_path}")
        elif [[ "${tool}" == "bashcov" ]]; then
            coverage=$(run_bashcov_coverage "${test_file}" "${script_path}")
        fi
        
        if [[ "${coverage}" =~ ^[0-9]+$ ]] && [[ ${coverage} -gt 0 ]]; then
            total_coverage=$((total_coverage + coverage))
            coverage_count=$((coverage_count + 1))
        fi
    done
    
    # Calculate average coverage
    local avg_coverage=0
    if [[ ${coverage_count} -gt 0 ]]; then
        avg_coverage=$((total_coverage / coverage_count))
    fi
    
    echo "${script_name}|${#test_files[@]}|${avg_coverage}|${tool}"
}

##
# Generate comprehensive coverage report
##
generate_instrumented_report() {
    local tool="${1}"
    
    print_message "${BLUE}" "Generating instrumented coverage report using ${tool}..."
    
    # Create coverage directories
    mkdir -p "${COVERAGE_DIR}"
    mkdir -p "${KCOV_OUTPUT}"
    mkdir -p "${BASHCOV_OUTPUT}"
    
    # Find all scripts
    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("${script}")
    done < <(find "${PROJECT_ROOT}/bin" -name "*.sh" -type f -print0 | sort -z)
    
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
            local result
            result=$(analyze_script_coverage "${script}" "${tool}")
            
            local script_name
            script_name=$(echo "${result}" | cut -d'|' -f1)
            local test_count
            test_count=$(echo "${result}" | cut -d'|' -f2)
            local coverage
            coverage=$(echo "${result}" | cut -d'|' -f3)
            
            if [[ ${test_count} -gt 0 ]]; then
                scripts_with_tests=$((scripts_with_tests + 1))
                
                if [[ "${coverage}" =~ ^[0-9]+$ ]]; then
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
                printf "%-50s %10s %10s %s\n" "${script_name}" "${test_count}" "${coverage}" "✗"
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
        echo "Detailed HTML reports available in:"
        if [[ "${tool}" == "kcov" ]]; then
            echo "  ${KCOV_OUTPUT}/"
        else
            echo "  ${BASHCOV_OUTPUT}/"
        fi
    } > "${COVERAGE_REPORT}"
    
    print_message "${GREEN}" "✓ Instrumented coverage report generated: ${COVERAGE_REPORT}"
    
    # Display summary
    tail -20 "${COVERAGE_REPORT}"
}

##
# Main
##
main() {
    print_message "${GREEN}" "Instrumented Test Coverage Report Generator"
    echo
    
    # Detect coverage tool
    local tool
    if ! tool=$(detect_coverage_tool); then
        print_message "${RED}" "Failed to detect coverage tool"
        exit 1
    fi
    
    print_message "${BLUE}" "Using coverage tool: ${tool}"
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
    if [[ "${tool}" == "kcov" ]]; then
        echo "  HTML: ${KCOV_OUTPUT}/<script_name>/index.html"
    else
        echo "  HTML: ${BASHCOV_OUTPUT}/<script_name>/index.html"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
