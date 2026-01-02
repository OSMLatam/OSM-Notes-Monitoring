#!/usr/bin/env bash
#
# Security Hardening Script
# Applies security hardening checklist for production
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

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Print usage
##
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Apply security hardening checklist for production.

Options:
    --check                  Run security checks only (no changes)
    --apply                  Apply security hardening
    --report                 Generate security report
    -h, --help               Show this help message

Examples:
    $0 --check               # Check security status
    $0 --apply                # Apply security hardening
    $0 --report               # Generate security report

EOF
}

##
# Check file permissions
##
check_file_permissions() {
    print_message "${BLUE}" "Checking file permissions..."
    
    local issues=0
    
    # Check for world-writable files
    local world_writable
    world_writable=$(find "${PROJECT_ROOT}/bin" -type f -perm -002 2>/dev/null | wc -l)
    if [[ "${world_writable}" -gt 0 ]]; then
        print_message "${RED}" "  ✗ Found ${world_writable} world-writable files"
        ((issues++))
    else
        print_message "${GREEN}" "  ✓ No world-writable files"
    fi
    
    # Check config file permissions
    local config_files
    config_files=$(find "${PROJECT_ROOT}/etc" "${PROJECT_ROOT}/config" -type f ! -name "*.example" 2>/dev/null | wc -l)
    if [[ "${config_files}" -gt 0 ]]; then
        local world_readable
        world_readable=$(find "${PROJECT_ROOT}/etc" "${PROJECT_ROOT}/config" -type f ! -name "*.example" -perm -004 2>/dev/null | wc -l)
        if [[ "${world_readable}" -gt 0 ]]; then
            print_message "${YELLOW}" "  ⚠ Found ${world_readable} world-readable config files"
            ((issues++))
        else
            print_message "${GREEN}" "  ✓ Config files have restricted permissions"
        fi
    fi
    
    return ${issues}
}

##
# Apply file permissions
##
apply_file_permissions() {
    print_message "${BLUE}" "Applying secure file permissions..."
    
    # Scripts should be executable
    find "${PROJECT_ROOT}/bin" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    
    # Config files should not be world-readable
    find "${PROJECT_ROOT}/etc" -type f -name "*.sh" ! -name "*.example" -exec chmod 640 {} \; 2>/dev/null || true
    find "${PROJECT_ROOT}/config" -type f ! -name "*.example" -exec chmod 640 {} \; 2>/dev/null || true
    
    # Log files should have restricted permissions
    if [[ -d "${PROJECT_ROOT}/logs" ]]; then
        find "${PROJECT_ROOT}/logs" -type f -exec chmod 640 {} \; 2>/dev/null || true
    fi
    
    print_message "${GREEN}" "✓ File permissions applied"
}

##
# Check for hardcoded credentials
##
check_hardcoded_credentials() {
    print_message "${BLUE}" "Checking for hardcoded credentials..."
    
    local issues=0
    
    # Check for password patterns
    if grep -r "password.*=.*['\"].*[^example|test|dummy|changeme]" "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/config" --exclude="*.example" 2>/dev/null | grep -v "example\|test\|dummy\|changeme" > /dev/null; then
        print_message "${YELLOW}" "  ⚠ Potential hardcoded credentials found"
        print_message "${YELLOW}" "  Review manually: grep -r 'password.*=' bin/ config/"
        ((issues++))
    else
        print_message "${GREEN}" "  ✓ No obvious hardcoded credentials"
    fi
    
    # Check for API keys
    if grep -r "api.*key.*=.*['\"].*[^example|test|dummy]" "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/config" --exclude="*.example" 2>/dev/null | grep -v "example\|test\|dummy" > /dev/null; then
        print_message "${YELLOW}" "  ⚠ Potential hardcoded API keys found"
        ((issues++))
    fi
    
    return ${issues}
}

##
# Check security configuration
##
check_security_config() {
    print_message "${BLUE}" "Checking security configuration..."
    
    local issues=0
    
    # Check if security.conf exists
    if [[ ! -f "${PROJECT_ROOT}/config/security.conf" ]]; then
        print_message "${YELLOW}" "  ⚠ Security configuration file not found"
        print_message "${YELLOW}" "  Copy from config/security.conf.example"
        ((issues++))
    else
        print_message "${GREEN}" "  ✓ Security configuration file exists"
    fi
    
    # Check for default passwords
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        if grep -q "admin@example.com\|changeme\|password" "${PROJECT_ROOT}/etc/properties.sh" 2>/dev/null; then
            print_message "${YELLOW}" "  ⚠ Default values found in properties.sh"
            print_message "${YELLOW}" "  Review and update with production values"
            ((issues++))
        fi
    fi
    
    return ${issues}
}

##
# Run security audit
##
run_security_audit() {
    print_message "${BLUE}" "Running security audit..."
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/security_audit.sh" ]]; then
        print_message "${YELLOW}" "  ⚠ Security audit script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/security_audit.sh" > /dev/null 2>&1; then
        print_message "${GREEN}" "  ✓ Security audit passed"
        return 0
    else
        print_message "${YELLOW}" "  ⚠ Security audit found issues (check reports/)"
        return 1
    fi
}

##
# Generate security report
##
generate_security_report() {
    local report_file
    report_file="${PROJECT_ROOT}/reports/security_hardening_$(date +%Y%m%d_%H%M%S).txt"
    
    print_message "${BLUE}" "Generating security report..."
    
    mkdir -p "$(dirname "${report_file}")" 2>/dev/null || true
    
    {
        echo "Security Hardening Report"
        echo "Generated: $(date)"
        echo "Project: ${PROJECT_ROOT}"
        echo "=========================================="
        echo ""
        
        echo "File Permissions:"
        check_file_permissions || true
        echo ""
        
        echo "Hardcoded Credentials:"
        check_hardcoded_credentials || true
        echo ""
        
        echo "Security Configuration:"
        check_security_config || true
        echo ""
        
        echo "Security Audit:"
        run_security_audit || true
        echo ""
        
    } | tee "${report_file}"
    
    print_message "${GREEN}" "✓ Report saved to: ${report_file}"
}

##
# Main
##
main() {
    local action="check"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --check)
                action="check"
                shift
                ;;
            --apply)
                action="apply"
                shift
                ;;
            --report)
                action="report"
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
    
    print_message "${GREEN}" "Security Hardening for OSM-Notes-Monitoring"
    print_message "${BLUE}" "============================================="
    echo
    
    case "${action}" in
        check)
            local total_issues=0
            check_file_permissions || total_issues=$((total_issues + $?))
            check_hardcoded_credentials || total_issues=$((total_issues + $?))
            check_security_config || total_issues=$((total_issues + $?))
            run_security_audit || total_issues=$((total_issues + $?))
            
            echo
            if [[ ${total_issues} -eq 0 ]]; then
                print_message "${GREEN}" "✓ All security checks passed"
            else
                print_message "${YELLOW}" "⚠ Found ${total_issues} issue(s) - review above"
            fi
            ;;
        apply)
            apply_file_permissions
            echo
            print_message "${GREEN}" "Security hardening applied"
            print_message "${YELLOW}" "Run --check to verify"
            ;;
        report)
            generate_security_report
            ;;
        *)
            print_message "${RED}" "Unknown action: ${action}"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
