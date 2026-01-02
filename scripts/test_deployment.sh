#!/usr/bin/env bash
#
# Test Deployment Script
# Tests deployment in a safe, non-destructive way
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

# Test database name
TEST_DBNAME="${TEST_DBNAME:-osm_notes_monitoring_test}"

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

Test deployment in a safe, non-destructive way.

Options:
    --full                  Run full test suite
    --quick                 Run quick validation only
    --database              Test database operations only
    --scripts               Test scripts only
    --config                Test configuration only
    --cleanup               Clean up test database after test
    -h, --help              Show this help message

Examples:
    $0 --full               # Run full test suite
    $0 --quick              # Quick validation
    $0 --database           # Test database only

EOF
}

##
# Check prerequisites
##
check_prerequisites() {
    print_message "${BLUE}" "Checking prerequisites..."
    
    local missing=()
    
    # Check required commands
    local required_commands=("bash" "psql" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" > /dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "${RED}" "  ✗ Missing required commands: ${missing[*]}"
        return 1
    fi
    
    print_message "${GREEN}" "  ✓ All prerequisites met"
    return 0
}

##
# Test database setup
##
test_database_setup() {
    print_message "${BLUE}" "Testing database setup..."
    
    # Create test database
    if createdb "${TEST_DBNAME}" 2>/dev/null; then
        print_message "${GREEN}" "  ✓ Test database created: ${TEST_DBNAME}"
    else
        # Database might already exist
        if psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "${TEST_DBNAME}"; then
            print_message "${YELLOW}" "  ⚠ Test database already exists: ${TEST_DBNAME}"
            read -p "  Drop and recreate? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                dropdb "${TEST_DBNAME}" 2>/dev/null || true
                createdb "${TEST_DBNAME}"
                print_message "${GREEN}" "  ✓ Test database recreated"
            fi
        else
            print_message "${RED}" "  ✗ Failed to create test database"
            return 1
        fi
    fi
    
    # Initialize schema
    if [[ -f "${PROJECT_ROOT}/sql/init.sql" ]]; then
        if psql -d "${TEST_DBNAME}" -f "${PROJECT_ROOT}/sql/init.sql" > /dev/null 2>&1; then
            print_message "${GREEN}" "  ✓ Database schema initialized"
        else
            print_message "${RED}" "  ✗ Failed to initialize schema"
            return 1
        fi
    fi
    
    # Test migrations
    if [[ -f "${PROJECT_ROOT}/sql/migrations/run_migrations.sh" ]]; then
        if "${PROJECT_ROOT}/sql/migrations/run_migrations.sh" -d "${TEST_DBNAME}" > /dev/null 2>&1; then
            print_message "${GREEN}" "  ✓ Migrations completed"
        else
            print_message "${YELLOW}" "  ⚠ Some migrations may have failed (non-critical)"
        fi
    fi
    
    return 0
}

##
# Test configuration
##
test_configuration() {
    print_message "${BLUE}" "Testing configuration..."
    
    # Check if config files exist
    local config_files=(
        "etc/properties.sh.example"
        "config/monitoring.conf.example"
        "config/alerts.conf.example"
        "config/security.conf.example"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${config_file}" ]]; then
            print_message "${GREEN}" "  ✓ ${config_file} exists"
        else
            print_message "${RED}" "  ✗ ${config_file} missing"
        fi
    done
    
    # Test config generation
    if [[ -f "${PROJECT_ROOT}/scripts/generate_config.sh" ]]; then
        print_message "${GREEN}" "  ✓ Config generation script exists"
    fi
    
    # Test config validation
    if [[ -f "${PROJECT_ROOT}/scripts/test_config_validation.sh" ]]; then
        print_message "${GREEN}" "  ✓ Config validation script exists"
    fi
}

##
# Test scripts
##
test_scripts() {
    print_message "${BLUE}" "Testing scripts..."
    
    local scripts=(
        "scripts/production_setup.sh"
        "scripts/production_migration.sh"
        "scripts/deploy_production.sh"
        "scripts/validate_production.sh"
        "scripts/security_hardening.sh"
        "scripts/setup_cron.sh"
        "scripts/setup_backups.sh"
    )
    
    local passed=0
    local failed=0
    
    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        if [[ -f "${full_path}" && -x "${full_path}" ]]; then
            # Test syntax
            if bash -n "${full_path}" > /dev/null 2>&1; then
                print_message "${GREEN}" "  ✓ ${script} (syntax OK)"
                ((passed++))
            else
                print_message "${RED}" "  ✗ ${script} (syntax error)"
                ((failed++))
            fi
        else
            print_message "${RED}" "  ✗ ${script} (missing or not executable)"
            ((failed++))
        fi
    done
    
    echo
    print_message "${BLUE}" "  Scripts tested: $((passed + failed))"
    print_message "${GREEN}" "  Passed: ${passed}"
    if [[ ${failed} -gt 0 ]]; then
        print_message "${RED}" "  Failed: ${failed}"
        return 1
    fi
    
    return 0
}

##
# Test monitoring scripts
##
test_monitoring_scripts() {
    print_message "${BLUE}" "Testing monitoring scripts..."
    
    local scripts=(
        "bin/monitor/monitorIngestion.sh"
        "bin/monitor/monitorAnalytics.sh"
        "bin/monitor/monitorInfrastructure.sh"
    )
    
    for script in "${scripts[@]}"; do
        local full_path="${PROJECT_ROOT}/${script}"
        if [[ -f "${full_path}" && -x "${full_path}" ]]; then
            # Test syntax only (don't run, might fail without proper config)
            if bash -n "${full_path}" > /dev/null 2>&1; then
                print_message "${GREEN}" "  ✓ ${script} (syntax OK)"
            else
                print_message "${RED}" "  ✗ ${script} (syntax error)"
            fi
        else
            print_message "${YELLOW}" "  ⚠ ${script} (missing or not executable)"
        fi
    done
}

##
# Test backup/restore
##
test_backup_restore() {
    print_message "${BLUE}" "Testing backup/restore..."
    
    if [[ ! -f "${PROJECT_ROOT}/sql/backups/backup_database.sh" ]]; then
        print_message "${YELLOW}" "  ⚠ Backup script not found"
        return 0
    fi
    
    # Create backup
    if "${PROJECT_ROOT}/sql/backups/backup_database.sh" -d "${TEST_DBNAME}" -c > /dev/null 2>&1; then
        print_message "${GREEN}" "  ✓ Backup created successfully"
        
        # List backups
        local backup_count
        backup_count=$("${PROJECT_ROOT}/sql/backups/backup_database.sh" -d "${TEST_DBNAME}" -l 2>/dev/null | grep -c "${TEST_DBNAME}" || echo "0")
        if [[ "${backup_count}" -gt 0 ]]; then
            print_message "${GREEN}" "  ✓ Backup listed successfully (${backup_count} backup(s))"
        fi
    else
        print_message "${YELLOW}" "  ⚠ Backup test failed (may need proper configuration)"
    fi
}

##
# Cleanup test database
##
cleanup_test_database() {
    print_message "${BLUE}" "Cleaning up test database..."
    
    if psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "${TEST_DBNAME}"; then
        read -p "Drop test database ${TEST_DBNAME}? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if dropdb "${TEST_DBNAME}" 2>/dev/null; then
                print_message "${GREEN}" "  ✓ Test database dropped"
            else
                print_message "${YELLOW}" "  ⚠ Failed to drop test database"
            fi
        fi
    fi
}

##
# Quick validation
##
quick_validation() {
    print_message "${BLUE}" "Running quick validation..."
    
    check_prerequisites
    echo
    
    test_configuration
    echo
    
    test_scripts
    echo
    
    print_message "${GREEN}" "Quick validation completed"
}

##
# Full test suite
##
full_test_suite() {
    print_message "${GREEN}" "Running Full Test Suite"
    print_message "${BLUE}" "========================"
    echo
    
    if ! check_prerequisites; then
        exit 1
    fi
    echo
    
    test_configuration
    echo
    
    test_scripts
    echo
    
    test_monitoring_scripts
    echo
    
    test_database_setup
    echo
    
    test_backup_restore
    echo
    
    print_message "${GREEN}" "Full test suite completed"
}

##
# Main
##
main() {
    local test_mode="full"
    local cleanup=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --full)
                test_mode="full"
                shift
                ;;
            --quick)
                test_mode="quick"
                shift
                ;;
            --database)
                test_mode="database"
                shift
                ;;
            --scripts)
                test_mode="scripts"
                shift
                ;;
            --config)
                test_mode="config"
                shift
                ;;
            --cleanup)
                cleanup=true
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
    
    case "${test_mode}" in
        full)
            full_test_suite
            ;;
        quick)
            quick_validation
            ;;
        database)
            check_prerequisites
            echo
            test_database_setup
            ;;
        scripts)
            test_scripts
            ;;
        config)
            test_configuration
            ;;
    esac
    
    if [[ "${cleanup}" == "true" ]]; then
        echo
        cleanup_test_database
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
