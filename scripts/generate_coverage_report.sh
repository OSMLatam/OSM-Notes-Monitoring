#!/usr/bin/env bash
#
# Generate Test Coverage Report
# Analyzes test coverage for OSM Notes Monitoring scripts
#
# Version: 1.0.0
# Date: 2025-12-28
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

# Output directory
readonly COVERAGE_DIR="${PROJECT_ROOT}/coverage"
readonly COVERAGE_REPORT="${COVERAGE_DIR}/coverage_report.txt"
readonly COVERAGE_HTML="${COVERAGE_DIR}/coverage_report.html"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Count lines in a file
##
count_lines() {
    local file="${1}"
    if [[ -f "${file}" ]]; then
        wc -l < "${file}" | tr -d ' '
    else
        echo "0"
    fi
}

##
# Count test files for a script
##
count_test_files() {
    local script_path="${1}"
    local script_name
    script_name=$(basename "${script_path}" .sh)
    
    # Search for test files
    local test_count=0
    
    # Check unit tests
    if find "${PROJECT_ROOT}/tests/unit" -name "test_${script_name}.sh" -o -name "*${script_name}*.sh" 2>/dev/null | grep -q .; then
        test_count=$(find "${PROJECT_ROOT}/tests/unit" -name "*${script_name}*.sh" 2>/dev/null | wc -l | tr -d ' ')
    fi
    
    # Check integration tests
    if find "${PROJECT_ROOT}/tests/integration" -name "*${script_name}*.sh" 2>/dev/null | grep -q .; then
        test_count=$((test_count + $(find "${PROJECT_ROOT}/tests/integration" -name "*${script_name}*.sh" 2>/dev/null | wc -l | tr -d ' ')))
    fi
    
    echo "${test_count}"
}

##
# Calculate coverage percentage (simplified)
##
calculate_coverage() {
    local script_path="${1}"
    local script_lines
    script_lines=$(count_lines "${script_path}")
    local test_count
    test_count=$(count_test_files "${script_path}")
    
    # Simple heuristic: if script has tests, assume some coverage
    # This is a simplified approach - real coverage would require code instrumentation
    if [[ ${test_count} -gt 0 ]]; then
        # Base coverage: 50% if tests exist, plus 10% per test file (max 90%)
        local base_coverage=50
        local additional=$((test_count * 10))
        local coverage=$((base_coverage + additional))
        
        if [[ ${coverage} -gt 90 ]]; then
            coverage=90
        fi
        
        echo "${coverage}"
    else
        echo "0"
    fi
}

##
# Analyze script coverage
##
analyze_script() {
    local script_path="${1}"
    local script_name
    script_name=$(basename "${script_path}")
    local script_lines
    script_lines=$(count_lines "${script_path}")
    local test_count
    test_count=$(count_test_files "${script_path}")
    local coverage
    coverage=$(calculate_coverage "${script_path}")
    
    echo "${script_name}|${script_lines}|${test_count}|${coverage}"
}

##
# Generate coverage report
##
generate_report() {
    print_message "${BLUE}" "Generating test coverage report..."
    
    # Create coverage directory
    mkdir -p "${COVERAGE_DIR}"
    
    # Find all scripts
    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("${script}")
    done < <(find "${PROJECT_ROOT}/bin" -name "*.sh" -type f -print0 | sort -z)
    
    # Generate report
    {
        echo "OSM Notes Monitoring - Test Coverage Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo ""
        echo "Coverage Target: >80%"
        echo ""
        echo "Script Coverage:"
        echo "----------------------------------------"
        printf "%-50s %10s %10s %10s\n" "Script" "Lines" "Tests" "Coverage"
        echo "----------------------------------------"
        
        local total_lines=0
        local total_tests=0
        local scripts_with_tests=0
        local scripts_above_threshold=0
        
        for script in "${scripts[@]}"; do
            local script_name
            script_name=$(basename "${script}")
            local script_lines
            script_lines=$(count_lines "${script}")
            local test_count
            test_count=$(count_test_files "${script}")
            local coverage
            coverage=$(calculate_coverage "${script}")
            
            total_lines=$((total_lines + script_lines))
            total_tests=$((total_tests + test_count))
            
            if [[ ${test_count} -gt 0 ]]; then
                scripts_with_tests=$((scripts_with_tests + 1))
            fi
            
            if [[ ${coverage} -ge 80 ]]; then
                scripts_above_threshold=$((scripts_above_threshold + 1))
            fi
            
            local status=""
            if [[ ${coverage} -ge 80 ]]; then
                status="✓"
            elif [[ ${coverage} -ge 50 ]]; then
                status="⚠"
            else
                status="✗"
            fi
            
            printf "%-50s %10s %10s %9s%% %s\n" "${script_name}" "${script_lines}" "${test_count}" "${coverage}" "${status}"
        done
        
        echo "----------------------------------------"
        echo ""
        echo "Summary:"
        echo "  Total scripts: ${#scripts[@]}"
        echo "  Scripts with tests: ${scripts_with_tests}"
        echo "  Scripts above 80% coverage: ${scripts_above_threshold}"
        echo "  Total lines of code: ${total_lines}"
        echo "  Total test files: ${total_tests}"
        echo ""
        
        # Calculate overall coverage estimate
        local overall_coverage=0
        if [[ ${#scripts[@]} -gt 0 ]]; then
            overall_coverage=$((scripts_above_threshold * 100 / ${#scripts[@]}))
        fi
        
        echo "Overall Coverage Estimate: ${overall_coverage}%"
        echo ""
        
        if [[ ${overall_coverage} -ge 80 ]]; then
            echo "Status: ✓ Coverage target met!"
        elif [[ ${overall_coverage} -ge 50 ]]; then
            echo "Status: ⚠ Coverage below target, improvement needed"
        else
            echo "Status: ✗ Coverage significantly below target"
        fi
        
        echo ""
        echo "Note: This is an estimated coverage based on test file presence."
        echo "For accurate coverage, use code instrumentation tools like kcov or bashcov."
    } > "${COVERAGE_REPORT}"
    
    print_message "${GREEN}" "✓ Coverage report generated: ${COVERAGE_REPORT}"
    
    # Display summary
    tail -20 "${COVERAGE_REPORT}"
}

##
# Generate HTML report
##
generate_html_report() {
    print_message "${BLUE}" "Generating HTML coverage report..."
    
    {
        cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>OSM Notes Monitoring - Coverage Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { color: green; font-weight: bold; }
        .warn { color: orange; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .summary { background-color: #e7f3ff; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>OSM Notes Monitoring - Test Coverage Report</h1>
    <p>Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <pre>$(tail -15 "${COVERAGE_REPORT}")</pre>
    </div>
    
    <h2>Detailed Coverage</h2>
    <table>
        <tr>
            <th>Script</th>
            <th>Lines</th>
            <th>Tests</th>
            <th>Coverage</th>
            <th>Status</th>
        </tr>
EOF
        
        # Add script rows
        while IFS= read -r -d '' script; do
            local script_name
            script_name=$(basename "${script}")
            local script_lines
            script_lines=$(count_lines "${script}")
            local test_count
            test_count=$(count_test_files "${script}")
            local coverage
            coverage=$(calculate_coverage "${script}")
            
            local status_class="fail"
            local status_text="✗"
            if [[ ${coverage} -ge 80 ]]; then
                status_class="pass"
                status_text="✓ Pass"
            elif [[ ${coverage} -ge 50 ]]; then
                status_class="warn"
                status_text="⚠ Warning"
            else
                status_text="✗ Fail"
            fi
            
            echo "        <tr>"
            echo "            <td>${script_name}</td>"
            echo "            <td>${script_lines}</td>"
            echo "            <td>${test_count}</td>"
            echo "            <td>${coverage}%</td>"
            echo "            <td class=\"${status_class}\">${status_text}</td>"
            echo "        </tr>"
        done < <(find "${PROJECT_ROOT}/bin" -name "*.sh" -type f -print0 | sort -z)
        
        cat <<EOF
    </table>
</body>
</html>
EOF
    } > "${COVERAGE_HTML}"
    
    print_message "${GREEN}" "✓ HTML report generated: ${COVERAGE_HTML}"
}

##
# Main
##
main() {
    print_message "${GREEN}" "Test Coverage Report Generator"
    echo
    
    if ! generate_report; then
        print_message "${RED}" "Failed to generate coverage report"
        exit 1
    fi
    
    echo
    if generate_html_report; then
        print_message "${GREEN}" ""
        print_message "${GREEN}" "Coverage reports generated successfully!"
        print_message "${YELLOW}" "View reports:"
        echo "  Text: ${COVERAGE_REPORT}"
        echo "  HTML: ${COVERAGE_HTML}"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
