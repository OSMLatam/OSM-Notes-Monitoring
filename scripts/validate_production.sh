#!/usr/bin/env bash
#
# Production Validation Script
# Validates that production deployment is working correctly
#
# Version: 1.0.0
# Date: 2026-01-01
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

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNINGS=0

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Test result
##
test_result() {
    local status="${1}"
    local message="${2}"
    
    case "${status}" in
        PASS)
            print_message "${GREEN}" "  ✓ ${message}"
            ((TESTS_PASSED++))
            ;;
        FAIL)
            print_message "${RED}" "  ✗ ${message}"
            ((TESTS_FAILED++))
            ;;
        WARN)
            print_message "${YELLOW}" "  ⚠ ${message}"
            ((TESTS_WARNINGS++))
            ;;
    esac
}

##
# Validate database connection
##
validate_database() {
    print_message "${BLUE}" "Validating database connection..."
    
    # Source properties
    local dbname="notes_monitoring"
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/etc/properties.sh"
        dbname="${DBNAME:-${dbname}}"
    fi
    
    if psql -d "${dbname}" -c "SELECT 1;" > /dev/null 2>&1; then
        test_result "PASS" "Database connection successful"
        
        # Check schema
        local table_count
        table_count=$(psql -d "${dbname}" -t -A -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
        if [[ "${table_count}" -gt 0 ]]; then
            test_result "PASS" "Database schema exists (${table_count} tables)"
        else
            test_result "FAIL" "Database schema not initialized"
        fi
    else
        test_result "FAIL" "Database connection failed"
    fi
}

##
# Validate configuration
##
validate_configuration() {
    print_message "${BLUE}" "Validating configuration files..."
    
    local config_files=(
        "etc/properties.sh"
        "config/monitoring.conf"
        "config/alerts.conf"
        "config/security.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        local full_path="${PROJECT_ROOT}/${config_file}"
        if [[ -f "${full_path}" ]]; then
            test_result "PASS" "Configuration file exists: ${config_file}"
            
            # Check for default values
            if grep -q "example.com\|changeme\|password" "${full_path}" 2>/dev/null; then
                test_result "WARN" "Default values found in ${config_file}"
            fi
        else
            test_result "FAIL" "Configuration file missing: ${config_file}"
        fi
    done
    
    # Run config validation script if available
    if [[ -f "${PROJECT_ROOT}/scripts/test_config_validation.sh" ]]; then
        if "${PROJECT_ROOT}/scripts/test_config_validation.sh" > /dev/null 2>&1; then
            test_result "PASS" "Configuration validation passed"
        else
            test_result "WARN" "Configuration validation found issues"
        fi
    fi
}

##
# Validate monitoring scripts
##
validate_monitoring_scripts() {
    print_message "${BLUE}" "Validating monitoring scripts..."
    
    local scripts=(
        "bin/monitor/monitorIngestion.sh"
        "bin/monitor/monitorAnalytics.sh"
        "bin/monitor/monitorWMS.sh"
        "bin/monitor/monitorAPI.sh"
        "bin/monitor/monitorData.sh"
        "bin/monitor/monitorInfrastructure.sh"
    )
    
    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        if [[ -f "${full_path}" && -x "${full_path}" ]]; then
            test_result "PASS" "Monitoring script exists and is executable: ${script}"
        else
            test_result "FAIL" "Monitoring script missing or not executable: ${script}"
        fi
    done
}

##
# Validate alert delivery
##
validate_alert_delivery() {
    print_message "${BLUE}" "Validating alert delivery..."
    
    # Check alert scripts
    if [[ -f "${PROJECT_ROOT}/bin/alerts/sendAlert.sh" ]]; then
        test_result "PASS" "Alert sending script exists"
    else
        test_result "FAIL" "Alert sending script missing"
    fi
    
    # Check alert configuration
    if [[ -f "${PROJECT_ROOT}/config/alerts.conf" ]]; then
        # Source to check if email is configured
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/config/alerts.conf" 2>/dev/null || true
        if [[ "${SEND_ALERT_EMAIL:-false}" == "true" ]]; then
            if command -v mutt > /dev/null 2>&1; then
                test_result "PASS" "Email alerts configured and mutt available"
            else
                test_result "WARN" "Email alerts configured but mutt not found"
            fi
        else
            test_result "WARN" "Email alerts not configured"
        fi
        
        if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
            test_result "PASS" "Slack webhook configured"
        else
            test_result "WARN" "Slack webhook not configured"
        fi
    fi
}

##
# Validate dashboards
##
validate_dashboards() {
    print_message "${BLUE}" "Validating dashboards..."
    
    # Check HTML dashboards
    local html_dashboards=(
        "dashboards/html/overview.html"
        "dashboards/html/component_status.html"
        "dashboards/html/health_check.html"
    )
    
    for dashboard in "${html_dashboards[@]}"; do
        local full_path="${PROJECT_ROOT}/${dashboard}"
        if [[ -f "${full_path}" ]]; then
            test_result "PASS" "HTML dashboard exists: ${dashboard}"
        else
            test_result "WARN" "HTML dashboard missing: ${dashboard}"
        fi
    done
    
    # Check Grafana dashboards
    if [[ -d "${PROJECT_ROOT}/dashboards/grafana" ]]; then
        local grafana_count
        grafana_count=$(find "${PROJECT_ROOT}/dashboards/grafana" -name "*.json" -type f 2>/dev/null | wc -l)
        if [[ "${grafana_count}" -gt 0 ]]; then
            test_result "PASS" "Grafana dashboards found (${grafana_count} files)"
        else
            test_result "WARN" "No Grafana dashboards found"
        fi
    fi
}

##
# Validate system health
##
validate_system_health() {
    print_message "${BLUE}" "Validating system health..."
    
    # Check disk space
    local available_space
    available_space=$(df -BG "${PROJECT_ROOT}" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ "${available_space}" -lt 1 ]]; then
        test_result "WARN" "Low disk space: ${available_space}GB available"
    else
        test_result "PASS" "Disk space OK: ${available_space}GB available"
    fi
    
    # Check log directory
    local log_dir="/var/log/osm-notes-monitoring"
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/etc/properties.sh"
        log_dir="${LOG_DIR:-${log_dir}}"
    fi
    
    if [[ -d "${log_dir}" && -w "${log_dir}" ]]; then
        test_result "PASS" "Log directory exists and is writable: ${log_dir}"
    else
        test_result "WARN" "Log directory missing or not writable: ${log_dir}"
    fi
    
    # Check required commands
    local required_commands=("bash" "psql" "curl")
    for cmd in "${required_commands[@]}"; do
        if command -v "${cmd}" > /dev/null 2>&1; then
            test_result "PASS" "Required command available: ${cmd}"
        else
            test_result "FAIL" "Required command missing: ${cmd}"
        fi
    done
}

##
# Validate cron jobs
##
validate_cron_jobs() {
    print_message "${BLUE}" "Validating cron jobs..."
    
    local crontab_content
    crontab_content=$(crontab -l 2>/dev/null || echo "")
    
    if echo "${crontab_content}" | grep -q "OSM-Notes-Monitoring"; then
        local job_count
        job_count=$(echo "${crontab_content}" | grep -c "OSM-Notes-Monitoring" || echo "0")
        test_result "PASS" "Cron jobs configured (${job_count} jobs)"
    else
        test_result "WARN" "No cron jobs configured"
    fi
}

##
# Generate summary
##
generate_summary() {
    echo
    print_message "${BLUE}" "Validation Summary"
    print_message "${BLUE}" "=================="
    echo
    print_message "${GREEN}" "Passed: ${TESTS_PASSED}"
    print_message "${YELLOW}" "Warnings: ${TESTS_WARNINGS}"
    print_message "${RED}" "Failed: ${TESTS_FAILED}"
    echo
    
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        if [[ ${TESTS_WARNINGS} -eq 0 ]]; then
            print_message "${GREEN}" "✓ All validations passed!"
            return 0
        else
            print_message "${YELLOW}" "⚠ Validations passed with warnings"
            return 0
        fi
    else
        print_message "${RED}" "✗ Validation failed - review issues above"
        return 1
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Production Validation for OSM-Notes-Monitoring"
    print_message "${BLUE}" "================================================"
    echo
    
    validate_database
    echo
    
    validate_configuration
    echo
    
    validate_monitoring_scripts
    echo
    
    validate_alert_delivery
    echo
    
    validate_dashboards
    echo
    
    validate_system_health
    echo
    
    validate_cron_jobs
    echo
    
    generate_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
