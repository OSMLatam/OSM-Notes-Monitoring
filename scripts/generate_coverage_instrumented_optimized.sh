#!/usr/bin/env bash
#
# Generate Instrumented Test Coverage Report (Optimized)
# Uses kcov or bashcov to measure actual code coverage
# Optimized version: runs coverage tool once on all tests
#
# Version: 2.0.0
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
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"
export DBNAME="${DBNAME:-${TEST_DB_NAME}}"
export DBHOST="${DBHOST:-${PGHOST:-localhost}}"
export DBPORT="${DBPORT:-${PGPORT:-5432}}"
export DBUSER="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
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
# Run all tests with kcov (single execution)
##
run_all_tests_with_kcov() {
    local output_dir="${KCOV_OUTPUT}/all"
    mkdir -p "${output_dir}"
    
    print_message "${BLUE}" "Running all tests with kcov (this may take a while)..."
    
    # Run kcov on all tests at once
    kcov \
        --include-path="${PROJECT_ROOT}/bin" \
        --exclude-path="${PROJECT_ROOT}/tests" \
        --exclude-path="${PROJECT_ROOT}/tmp" \
        --exclude-path="${PROJECT_ROOT}/coverage" \
        --exclude-path="${PROJECT_ROOT}/scripts" \
        "${output_dir}" \
        bats "${PROJECT_ROOT}/tests" >/dev/null 2>&1 || true
    
    print_message "${GREEN}" "✓ Tests executed with kcov"
}

##
# Extract coverage for a specific script from kcov report
##
get_script_coverage_from_kcov() {
    local script_path="${1}"
    local output_dir="${KCOV_OUTPUT}/all"
    
    # Get relative path from PROJECT_ROOT
    local rel_path="${script_path#${PROJECT_ROOT}/}"
    
    # kcov stores file coverage in index.json
    if [[ -f "${output_dir}/index.json" ]]; then
        local coverage
        coverage=$(python3 -c "
import json
import sys
import os

try:
    script_path = '${rel_path}'
    with open('${output_dir}/index.json', 'r') as f:
        data = json.load(f)
        
    # kcov stores files by their absolute path in the 'files' dict
    # We need to find the file that matches our script
    if 'files' in data:
        for file_path, file_data in data['files'].items():
            # Check if this file matches our script
            if script_path in file_path or os.path.basename(script_path) in file_path:
                if 'percent_covered' in file_data:
                    print(int(file_data['percent_covered']))
                    sys.exit(0)
    
    # If not found in files, try merged data
    if 'merged' in data and 'percent_covered' in data['merged']:
        print(int(data['merged']['percent_covered']))
    else:
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
# Run all tests with bashcov (single execution)
##
run_all_tests_with_bashcov() {
    local output_dir="${BASHCOV_OUTPUT}/all"
    mkdir -p "${output_dir}"
    
    print_message "${BLUE}" "Running all tests with bashcov (this may take a while)..."
    
    # Run bashcov on all tests at once
    BASHCOV_OUTPUT_DIR="${output_dir}" \
    bashcov \
        --root "${PROJECT_ROOT}" \
        --skip-uncovered \
        bats "${PROJECT_ROOT}/tests" >/dev/null 2>&1 || true
    
    print_message "${GREEN}" "✓ Tests executed with bashcov"
}

##
# Extract coverage for a specific script from bashcov report
##
get_script_coverage_from_bashcov() {
    local script_path="${1}"
    local output_dir="${BASHCOV_OUTPUT}/all"
    
    # bashcov stores coverage in coverage.json
    if [[ -f "${output_dir}/coverage.json" ]]; then
        local coverage
        coverage=$(python3 -c "
import json
import sys
import os

try:
    script_path = '${script_path}'
    script_basename = os.path.basename(script_path)
    
    with open('${output_dir}/coverage.json', 'r') as f:
        data = json.load(f)
    
    # bashcov stores files in a dict with file paths as keys
    if 'files' in data:
        for file_path, file_data in data['files'].items():
            if script_path in file_path or script_basename in file_path:
                if 'percent_covered' in file_data:
                    print(int(file_data['percent_covered']))
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
    mkdir -p "${KCOV_OUTPUT}"
    mkdir -p "${BASHCOV_OUTPUT}"
    
    # Run all tests with coverage tool (single execution)
    if [[ "${tool}" == "kcov" ]]; then
        run_all_tests_with_kcov
    elif [[ "${tool}" == "bashcov" ]]; then
        run_all_tests_with_bashcov
    fi
    
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
                if [[ "${tool}" == "kcov" ]]; then
                    coverage=$(get_script_coverage_from_kcov "${script}")
                elif [[ "${tool}" == "bashcov" ]]; then
                    coverage=$(get_script_coverage_from_bashcov "${script}")
                fi
                
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
        echo "Detailed HTML reports available in:"
        if [[ "${tool}" == "kcov" ]]; then
            echo "  ${KCOV_OUTPUT}/all/index.html"
        else
            echo "  ${BASHCOV_OUTPUT}/all/"
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
    if [[ "${tool}" == "kcov" ]]; then
        echo "  HTML: ${KCOV_OUTPUT}/all/index.html"
    else
        echo "  HTML: ${BASHCOV_OUTPUT}/all/"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
