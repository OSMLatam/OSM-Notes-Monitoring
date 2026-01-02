#!/usr/bin/env bash
#
# Production Environment Setup Script
# Sets up the production environment for OSM-Notes-Monitoring
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

Production environment setup for OSM-Notes-Monitoring.

Options:
    --skip-checks          Skip environment validation checks
    --skip-database        Skip database setup
    --skip-config          Skip configuration setup
    --skip-security        Skip security hardening
    --force                Force setup even if already configured
    -h, --help             Show this help message

Examples:
    $0                     # Full production setup
    $0 --skip-database     # Setup without database
    $0 --force             # Force re-setup

EOF
}

##
# Check if command exists
##
command_exists() {
    command -v "${1}" > /dev/null 2>&1
}

##
# Validate production environment
##
validate_environment() {
    print_message "${BLUE}" "Validating production environment..."
    
    local errors=0
    local warnings=0
    
    # Check required commands
    local required_commands=(
        "bash"
        "psql"
        "curl"
        "gzip"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "${cmd}"; then
            print_message "${RED}" "  ✗ Missing required command: ${cmd}"
            ((errors++))
        else
            print_message "${GREEN}" "  ✓ Found: ${cmd}"
        fi
    done
    
    # Check PostgreSQL version (should be 12+)
    if command_exists psql; then
        local pg_version
        pg_version=$(psql --version | grep -oE '[0-9]+' | head -1)
        if [[ "${pg_version}" -lt 12 ]]; then
            print_message "${YELLOW}" "  ⚠ PostgreSQL version ${pg_version} is below recommended (12+)"
            ((warnings++))
        else
            print_message "${GREEN}" "  ✓ PostgreSQL version ${pg_version}"
        fi
    fi
    
    # Check disk space (should have at least 1GB free)
    local available_space
    available_space=$(df -BG "${PROJECT_ROOT}" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ "${available_space}" -lt 1 ]]; then
        print_message "${YELLOW}" "  ⚠ Low disk space: ${available_space}GB available (recommended: 1GB+)"
        ((warnings++))
    else
        print_message "${GREEN}" "  ✓ Disk space: ${available_space}GB available"
    fi
    
    # Check write permissions
    if [[ ! -w "${PROJECT_ROOT}" ]]; then
        print_message "${RED}" "  ✗ No write permission on project directory"
        ((errors++))
    else
        print_message "${GREEN}" "  ✓ Write permissions OK"
    fi
    
    # Check if running as root (not recommended)
    if [[ "${EUID}" -eq 0 ]]; then
        print_message "${YELLOW}" "  ⚠ Running as root - consider using a dedicated user"
        ((warnings++))
    fi
    
    echo
    if [[ ${errors} -gt 0 ]]; then
        print_message "${RED}" "Environment validation failed with ${errors} error(s)"
        return 1
    elif [[ ${warnings} -gt 0 ]]; then
        print_message "${YELLOW}" "Environment validation passed with ${warnings} warning(s)"
        return 0
    else
        print_message "${GREEN}" "Environment validation passed"
        return 0
    fi
}

##
# Setup production database
##
setup_production_database() {
    print_message "${BLUE}" "Setting up production database..."
    
    # Source properties to get database name
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/etc/properties.sh"
    fi
    
    local dbname="${DBNAME:-notes_monitoring}"
    local init_sql="${PROJECT_ROOT}/sql/init.sql"
    
    # Check if database exists
    if psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "${dbname}"; then
        print_message "${YELLOW}" "  Database ${dbname} already exists"
        if [[ "${FORCE:-false}" != "true" ]]; then
            read -p "  Reinitialize database? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_message "${BLUE}" "  Skipping database setup"
                return 0
            fi
        fi
        
        # Backup existing database
        print_message "${YELLOW}" "  Creating backup before reinitialization..."
        "${PROJECT_ROOT}/sql/backups/backup_database.sh" -d "${dbname}" -c || true
    fi
    
    # Create database if it doesn't exist
    if ! psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "${dbname}"; then
        if createdb "${dbname}" 2>/dev/null; then
            print_message "${GREEN}" "  ✓ Created database: ${dbname}"
        else
            print_message "${RED}" "  ✗ Failed to create database"
            return 1
        fi
    fi
    
    # Initialize schema
    if [[ -f "${init_sql}" ]]; then
        print_message "${BLUE}" "  Initializing database schema..."
        if psql -d "${dbname}" -f "${init_sql}" > /dev/null 2>&1; then
            print_message "${GREEN}" "  ✓ Initialized database schema"
        else
            print_message "${RED}" "  ✗ Failed to initialize schema"
            return 1
        fi
        
        # Apply query optimizations
        local optimize_sql="${PROJECT_ROOT}/sql/optimize_queries.sql"
        if [[ -f "${optimize_sql}" ]]; then
            print_message "${BLUE}" "  Applying query optimizations..."
            if psql -d "${dbname}" -f "${optimize_sql}" > /dev/null 2>&1; then
                print_message "${GREEN}" "  ✓ Applied query optimizations"
            else
                print_message "${YELLOW}" "  ⚠ Failed to apply optimizations (non-critical)"
            fi
        fi
    else
        print_message "${RED}" "  ✗ SQL init file not found: ${init_sql}"
        return 1
    fi
    
    # Run migrations
    print_message "${BLUE}" "  Running database migrations..."
    if "${PROJECT_ROOT}/sql/migrations/run_migrations.sh" -d "${dbname}" > /dev/null 2>&1; then
        print_message "${GREEN}" "  ✓ Database migrations completed"
    else
        print_message "${YELLOW}" "  ⚠ Some migrations may have failed (check logs)"
    fi
}

##
# Setup production configuration
##
setup_production_config() {
    print_message "${BLUE}" "Setting up production configuration..."
    
    local config_files=(
        "etc/properties.sh"
        "config/monitoring.conf"
        "config/alerts.conf"
        "config/security.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        local example_file="${config_file}.example"
        local full_path="${PROJECT_ROOT}/${config_file}"
        local example_path="${PROJECT_ROOT}/${example_file}"
        
        if [[ ! -f "${full_path}" ]]; then
            if [[ -f "${example_path}" ]]; then
                cp "${example_path}" "${full_path}"
                print_message "${YELLOW}" "  Created ${config_file} from example"
                print_message "${YELLOW}" "  ⚠ IMPORTANT: Edit ${config_file} with production values"
                
                # Set secure permissions
                chmod 640 "${full_path}"
            else
                print_message "${RED}" "  ✗ Example file not found: ${example_file}"
            fi
        else
            if [[ "${FORCE:-false}" == "true" ]]; then
                print_message "${YELLOW}" "  ⚠ ${config_file} already exists (use --force to overwrite)"
            else
                print_message "${GREEN}" "  ✓ ${config_file} already exists"
            fi
        fi
    done
    
    # Verify configuration
    print_message "${BLUE}" "  Validating configuration..."
    if [[ -f "${PROJECT_ROOT}/scripts/test_config_validation.sh" ]]; then
        if "${PROJECT_ROOT}/scripts/test_config_validation.sh" > /dev/null 2>&1; then
            print_message "${GREEN}" "  ✓ Configuration validation passed"
        else
            print_message "${YELLOW}" "  ⚠ Configuration validation found issues (check output)"
        fi
    fi
}

##
# Setup production directories
##
setup_production_directories() {
    print_message "${BLUE}" "Setting up production directories..."
    
    # Source properties to get directory paths
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/etc/properties.sh"
    fi
    
    local directories=(
        "${LOG_DIR:-/var/log/osm-notes-monitoring}"
        "${TMP_DIR:-/var/tmp/osm-notes-monitoring}"
        "${LOCK_DIR:-/var/run/osm-notes-monitoring}"
        "${PROJECT_ROOT}/logs"
        "${PROJECT_ROOT}/metrics"
        "${PROJECT_ROOT}/reports"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            if mkdir -p "${dir}" 2>/dev/null; then
                print_message "${GREEN}" "  ✓ Created directory: ${dir}"
            else
                print_message "${YELLOW}" "  ⚠ Failed to create directory: ${dir} (may need sudo)"
            fi
        else
            print_message "${GREEN}" "  ✓ Directory exists: ${dir}"
        fi
        
        # Set appropriate permissions
        if [[ -w "${dir}" ]]; then
            chmod 755 "${dir}" 2>/dev/null || true
        fi
    done
}

##
# Setup security hardening
##
setup_security_hardening() {
    print_message "${BLUE}" "Setting up security hardening..."
    
    local issues=0
    
    # Set secure file permissions
    print_message "${BLUE}" "  Setting file permissions..."
    
    # Scripts should be executable
    find "${PROJECT_ROOT}/bin" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    
    # Config files should not be world-readable
    find "${PROJECT_ROOT}/etc" -type f -name "*.sh" ! -name "*.example" -exec chmod 640 {} \; 2>/dev/null || true
    find "${PROJECT_ROOT}/config" -type f ! -name "*.example" -exec chmod 640 {} \; 2>/dev/null || true
    
    # Log files should have restricted permissions
    if [[ -d "${PROJECT_ROOT}/logs" ]]; then
        find "${PROJECT_ROOT}/logs" -type f -exec chmod 640 {} \; 2>/dev/null || true
    fi
    
    print_message "${GREEN}" "  ✓ File permissions set"
    
    # Run security audit
    print_message "${BLUE}" "  Running security audit..."
    if [[ -f "${PROJECT_ROOT}/scripts/security_audit.sh" ]]; then
        if "${PROJECT_ROOT}/scripts/security_audit.sh" > /dev/null 2>&1; then
            print_message "${GREEN}" "  ✓ Security audit passed"
        else
            print_message "${YELLOW}" "  ⚠ Security audit found issues (check reports/)"
            ((issues++))
        fi
    fi
    
    # Check for hardcoded credentials
    print_message "${BLUE}" "  Checking for hardcoded credentials..."
    if grep -r "password.*=.*['\"].*[^example|test|dummy]" "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/config" --exclude="*.example" 2>/dev/null | grep -v "example\|test\|dummy" > /dev/null; then
        print_message "${YELLOW}" "  ⚠ Potential hardcoded credentials found (review manually)"
        ((issues++))
    else
        print_message "${GREEN}" "  ✓ No obvious hardcoded credentials"
    fi
    
    if [[ ${issues} -eq 0 ]]; then
        print_message "${GREEN}" "  ✓ Security hardening completed"
    else
        print_message "${YELLOW}" "  ⚠ Security hardening completed with ${issues} issue(s)"
    fi
}

##
# Main
##
main() {
    local skip_checks=false
    local skip_database=false
    local skip_config=false
    local skip_security=false
    FORCE=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --skip-checks)
                skip_checks=true
                shift
                ;;
            --skip-database)
                skip_database=true
                shift
                ;;
            --skip-config)
                skip_config=true
                shift
                ;;
            --skip-security)
                skip_security=true
                shift
                ;;
            --force)
                FORCE=true
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
    
    print_message "${GREEN}" "OSM-Notes-Monitoring Production Setup"
    print_message "${BLUE}" "========================================"
    echo
    
    # Validate environment
    if [[ "${skip_checks}" != "true" ]]; then
        if ! validate_environment; then
            print_message "${RED}" "Environment validation failed. Use --skip-checks to continue anyway."
            exit 1
        fi
        echo
    fi
    
    # Setup directories
    setup_production_directories
    echo
    
    # Setup configuration
    if [[ "${skip_config}" != "true" ]]; then
        setup_production_config
        echo
    fi
    
    # Setup database
    if [[ "${skip_database}" != "true" ]]; then
        setup_production_database
        echo
    fi
    
    # Security hardening
    if [[ "${skip_security}" != "true" ]]; then
        setup_security_hardening
        echo
    fi
    
    print_message "${GREEN}" "Production setup complete!"
    echo
    print_message "${YELLOW}" "Next steps:"
    echo "  1. Review and update configuration files in etc/ and config/"
    echo "  2. Configure alert delivery (email/Slack) in config/alerts.conf"
    echo "  3. Set up cron jobs: ./scripts/setup_cron.sh"
    echo "  4. Configure log rotation: ./scripts/setup_logrotate.sh"
    echo "  5. Set up backups: ./scripts/setup_backups.sh"
    echo "  6. Run validation: ./scripts/validate_production.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
