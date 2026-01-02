#!/usr/bin/env bash
#
# Production Database Migration Script
# Runs database migrations with rollback support for production
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

# Default database name
DBNAME="${DBNAME:-notes_monitoring}"

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

Production database migration with rollback support.

Options:
    -d, --database DATABASE    Database name (default: notes_monitoring)
    -b, --backup               Create backup before migration
    -r, --rollback FILE        Rollback from backup file
    -l, --list                 List pending migrations
    -v, --verbose              Verbose output
    -h, --help                 Show this help message

Examples:
    $0 -b                       # Migrate with backup
    $0 -r backup.sql.gz         # Rollback from backup
    $0 -l                       # List pending migrations

EOF
}

##
# Create backup before migration
##
create_backup() {
    local dbname="${1}"
    
    print_message "${BLUE}" "Creating backup before migration..."
    
    if [[ ! -f "${PROJECT_ROOT}/sql/backups/backup_database.sh" ]]; then
        print_message "${RED}" "Backup script not found"
        return 1
    fi
    
    if "${PROJECT_ROOT}/sql/backups/backup_database.sh" -d "${dbname}" -c; then
        print_message "${GREEN}" "✓ Backup created successfully"
        return 0
    else
        print_message "${RED}" "✗ Backup failed"
        return 1
    fi
}

##
# Rollback from backup
##
rollback_from_backup() {
    local backup_file="${1}"
    local dbname="${2}"
    
    print_message "${BLUE}" "Rolling back from backup: ${backup_file}"
    
    if [[ ! -f "${backup_file}" ]]; then
        print_message "${RED}" "Backup file not found: ${backup_file}"
        return 1
    fi
    
    if [[ ! -f "${PROJECT_ROOT}/sql/backups/restore_database.sh" ]]; then
        print_message "${RED}" "Restore script not found"
        return 1
    fi
    
    print_message "${YELLOW}" "WARNING: This will overwrite the database!"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "${BLUE}" "Rollback cancelled"
        return 1
    fi
    
    if "${PROJECT_ROOT}/sql/backups/restore_database.sh" -d "${dbname}" -f "${backup_file}"; then
        print_message "${GREEN}" "✓ Rollback completed successfully"
        return 0
    else
        print_message "${RED}" "✗ Rollback failed"
        return 1
    fi
}

##
# Run migrations
##
run_migrations() {
    local dbname="${1}"
    local verbose="${2:-false}"
    
    print_message "${BLUE}" "Running database migrations..."
    
    if [[ ! -f "${PROJECT_ROOT}/sql/migrations/run_migrations.sh" ]]; then
        print_message "${RED}" "Migration script not found"
        return 1
    fi
    
    local args=("-d" "${dbname}")
    if [[ "${verbose}" == "true" ]]; then
        args+=("-v")
    fi
    
    if "${PROJECT_ROOT}/sql/migrations/run_migrations.sh" "${args[@]}"; then
        print_message "${GREEN}" "✓ Migrations completed successfully"
        return 0
    else
        print_message "${RED}" "✗ Migrations failed"
        return 1
    fi
}

##
# Main
##
main() {
    local create_backup_flag=false
    local rollback_file=""
    local list_only=false
    local verbose=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -d|--database)
                DBNAME="${2}"
                shift 2
                ;;
            -b|--backup)
                create_backup_flag=true
                shift
                ;;
            -r|--rollback)
                rollback_file="${2}"
                shift 2
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
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
    
    # Check database connection
    if ! psql -d "${DBNAME}" -c "SELECT 1;" > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: Cannot connect to database: ${DBNAME}"
        exit 1
    fi
    
    # Rollback mode
    if [[ -n "${rollback_file}" ]]; then
        if rollback_from_backup "${rollback_file}" "${DBNAME}"; then
            exit 0
        else
            exit 1
        fi
    fi
    
    # List mode
    if [[ "${list_only}" == "true" ]]; then
        "${PROJECT_ROOT}/sql/migrations/run_migrations.sh" -d "${DBNAME}" -l
        exit 0
    fi
    
    # Create backup if requested
    if [[ "${create_backup_flag}" == "true" ]]; then
        if ! create_backup "${DBNAME}"; then
            print_message "${RED}" "Backup failed - aborting migration"
            exit 1
        fi
        echo
    fi
    
    # Run migrations
    if run_migrations "${DBNAME}" "${verbose}"; then
        print_message "${GREEN}" "Migration process completed successfully"
        exit 0
    else
        print_message "${RED}" "Migration process failed"
        if [[ "${create_backup_flag}" == "true" ]]; then
            print_message "${YELLOW}" "Backup was created - use -r to rollback if needed"
        fi
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
