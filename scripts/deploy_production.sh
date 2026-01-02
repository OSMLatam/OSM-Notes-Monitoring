#!/usr/bin/env bash
#
# Production Deployment Script
# Complete deployment script for production environment
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

Complete production deployment for OSM-Notes-Monitoring.

Options:
    --skip-setup             Skip production setup
    --skip-migration          Skip database migration
    --skip-security           Skip security hardening
    --skip-cron               Skip cron job setup
    --skip-backups            Skip backup configuration
    --skip-logrotate          Skip log rotation setup
    --skip-validation         Skip validation
    --validate-only           Only run validation (skip deployment)
    -h, --help                Show this help message

Examples:
    $0                        # Full deployment
    $0 --validate-only        # Only validate existing deployment
    $0 --skip-migration       # Deploy without migrations

EOF
}

##
# Run production setup
##
run_production_setup() {
    print_message "${BLUE}" "Step 1: Production Environment Setup"
    print_message "${BLUE}" "====================================="
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/production_setup.sh" ]]; then
        print_message "${RED}" "Production setup script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/production_setup.sh"; then
        print_message "${GREEN}" "✓ Production setup completed"
        return 0
    else
        print_message "${RED}" "✗ Production setup failed"
        return 1
    fi
}

##
# Run database migration
##
run_database_migration() {
    print_message "${BLUE}" "Step 2: Database Migration"
    print_message "${BLUE}" "=========================="
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/production_migration.sh" ]]; then
        print_message "${RED}" "Migration script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/production_migration.sh" -b; then
        print_message "${GREEN}" "✓ Database migration completed"
        return 0
    else
        print_message "${RED}" "✗ Database migration failed"
        return 1
    fi
}

##
# Run security hardening
##
run_security_hardening() {
    print_message "${BLUE}" "Step 3: Security Hardening"
    print_message "${BLUE}" "==========================="
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/security_hardening.sh" ]]; then
        print_message "${RED}" "Security hardening script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/security_hardening.sh" --apply; then
        print_message "${GREEN}" "✓ Security hardening completed"
        return 0
    else
        print_message "${YELLOW}" "⚠ Security hardening completed with warnings"
        return 0
    fi
}

##
# Setup cron jobs
##
setup_cron_jobs() {
    print_message "${BLUE}" "Step 4: Cron Jobs Setup"
    print_message "${BLUE}" "======================="
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/setup_cron.sh" ]]; then
        print_message "${RED}" "Cron setup script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/setup_cron.sh" --install; then
        print_message "${GREEN}" "✓ Cron jobs configured"
        return 0
    else
        print_message "${RED}" "✗ Cron jobs setup failed"
        return 1
    fi
}

##
# Setup backups
##
setup_backups() {
    print_message "${BLUE}" "Step 5: Backup Configuration"
    print_message "${BLUE}" "============================="
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/setup_backups.sh" ]]; then
        print_message "${RED}" "Backup setup script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/setup_backups.sh" --install; then
        print_message "${GREEN}" "✓ Backup configuration completed"
        return 0
    else
        print_message "${RED}" "✗ Backup configuration failed"
        return 1
    fi
}

##
# Setup log rotation
##
setup_log_rotation() {
    print_message "${BLUE}" "Step 6: Log Rotation Setup"
    print_message "${BLUE}" "==========================="
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/setup_logrotate.sh" ]]; then
        print_message "${RED}" "Log rotation setup script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/setup_logrotate.sh"; then
        print_message "${GREEN}" "✓ Log rotation configured"
        return 0
    else
        print_message "${YELLOW}" "⚠ Log rotation setup completed with warnings"
        return 0
    fi
}

##
# Run validation
##
run_validation() {
    print_message "${BLUE}" "Step 7: Production Validation"
    print_message "${BLUE}" "=============================="
    
    if [[ ! -f "${PROJECT_ROOT}/scripts/validate_production.sh" ]]; then
        print_message "${RED}" "Validation script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/scripts/validate_production.sh"; then
        print_message "${GREEN}" "✓ Production validation passed"
        return 0
    else
        print_message "${YELLOW}" "⚠ Production validation found issues"
        return 1
    fi
}

##
# Main
##
main() {
    local skip_setup=false
    local skip_migration=false
    local skip_security=false
    local skip_cron=false
    local skip_backups=false
    local skip_logrotate=false
    local skip_validation=false
    local validate_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --skip-setup)
                skip_setup=true
                shift
                ;;
            --skip-migration)
                skip_migration=true
                shift
                ;;
            --skip-security)
                skip_security=true
                shift
                ;;
            --skip-cron)
                skip_cron=true
                shift
                ;;
            --skip-backups)
                skip_backups=true
                shift
                ;;
            --skip-logrotate)
                skip_logrotate=true
                shift
                ;;
            --skip-validation)
                skip_validation=true
                shift
                ;;
            --validate-only)
                validate_only=true
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
    
    print_message "${GREEN}" "OSM-Notes-Monitoring Production Deployment"
    print_message "${BLUE}" "==========================================="
    echo
    
    # Validation only mode
    if [[ "${validate_only}" == "true" ]]; then
        run_validation
        exit $?
    fi
    
    local failed_steps=0
    
    # Step 1: Production setup
    if [[ "${skip_setup}" != "true" ]]; then
        if ! run_production_setup; then
            ((failed_steps++))
        fi
        echo
    fi
    
    # Step 2: Database migration
    if [[ "${skip_migration}" != "true" ]]; then
        if ! run_database_migration; then
            ((failed_steps++))
        fi
        echo
    fi
    
    # Step 3: Security hardening
    if [[ "${skip_security}" != "true" ]]; then
        if ! run_security_hardening; then
            ((failed_steps++))
        fi
        echo
    fi
    
    # Step 4: Cron jobs
    if [[ "${skip_cron}" != "true" ]]; then
        if ! setup_cron_jobs; then
            ((failed_steps++))
        fi
        echo
    fi
    
    # Step 5: Backups
    if [[ "${skip_backups}" != "true" ]]; then
        if ! setup_backups; then
            ((failed_steps++))
        fi
        echo
    fi
    
    # Step 6: Log rotation
    if [[ "${skip_logrotate}" != "true" ]]; then
        if ! setup_log_rotation; then
            ((failed_steps++))
        fi
        echo
    fi
    
    # Step 7: Validation
    if [[ "${skip_validation}" != "true" ]]; then
        if ! run_validation; then
            ((failed_steps++))
        fi
        echo
    fi
    
    # Summary
    echo
    print_message "${BLUE}" "Deployment Summary"
    print_message "${BLUE}" "=================="
    
    if [[ ${failed_steps} -eq 0 ]]; then
        print_message "${GREEN}" "✓ Deployment completed successfully!"
        print_message "${BLUE}" ""
        print_message "${YELLOW}" "Next steps:"
        echo "  1. Review configuration files in etc/ and config/"
        echo "  2. Configure alert delivery (email/Slack)"
        echo "  3. Test monitoring scripts manually"
        echo "  4. Monitor logs for any issues"
        exit 0
    else
        print_message "${RED}" "✗ Deployment completed with ${failed_steps} failed step(s)"
        print_message "${YELLOW}" "Review errors above and fix before proceeding"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
