#!/usr/bin/env bash
#
# Database Backup Script
# Creates a backup of the OSM-Notes-Monitoring database
#
# Version: 1.0.0
# Date: 2025-12-24
#

set -euo pipefail

# Ensure PATH includes standard binary directories for pg_dump, gzip, etc.
# This is important when script runs from cron or with limited PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin:${PATH:-}"

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default values - try to get from properties.sh if available
if [[ -f "${SCRIPT_DIR}/../../etc/properties.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/../../etc/properties.sh"
fi
DBNAME="${DBNAME:-notes_monitoring}"
BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

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

Create a backup of the OSM-Notes-Monitoring database.

Options:
    -d, --database DATABASE    Database name (default: osm_notes_monitoring)
    -o, --output DIR           Output directory (default: sql/backups)
    -r, --retention DAYS        Keep backups for N days (default: 30)
    -c, --compress              Compress backup with gzip
    -v, --verbose               Verbose output
    -h, --help                  Show this help message

Examples:
    $0                          # Backup to default location
    $0 -d osm_notes_monitoring_test  # Backup test database
    $0 -o /backups -c            # Backup to /backups with compression
    $0 -r 7                      # Keep backups for 7 days

EOF
}

##
# Check prerequisites
##
check_prerequisites() {
    if ! command -v pg_dump > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: pg_dump not found. Please install PostgreSQL client tools."
        exit 1
    fi
    
    if ! psql -lqt > /dev/null 2>&1; then
        print_message "${RED}" "ERROR: Cannot connect to PostgreSQL. Check your connection."
        exit 1
    fi
}

##
# Create backup directory if it doesn't exist
##
ensure_backup_dir() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        mkdir -p "${BACKUP_DIR}"
        print_message "${BLUE}" "Created backup directory: ${BACKUP_DIR}"
    fi
}

##
# Generate backup filename
##
generate_backup_filename() {
    local compress="${1:-false}"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local extension="sql"
    
    if [[ "${compress}" == "true" ]]; then
        extension="sql.gz"
    fi
    
    echo "${BACKUP_DIR}/${DBNAME}_${timestamp}.${extension}"
}

##
# Create backup
##
create_backup() {
    local backup_file="${1}"
    local compress="${2:-false}"
    local verbose="${3:-false}"
    
    print_message "${BLUE}" "Creating backup of database: ${DBNAME}"
    print_message "${BLUE}" "Backup file: ${backup_file}"
    
    local pg_dump_opts=(
        "--dbname=${DBNAME}"
        "--format=plain"
        "--no-owner"
        "--no-acl"
        "--clean"
        "--if-exists"
    )
    
    if [[ "${verbose}" == "true" ]]; then
        pg_dump_opts+=("--verbose")
    fi
    
    if [[ "${compress}" == "true" ]]; then
        if pg_dump "${pg_dump_opts[@]}" | gzip > "${backup_file}"; then
            print_message "${GREEN}" "✓ Backup created successfully (compressed)"
            return 0
        else
            print_message "${RED}" "✗ Backup failed"
            return 1
        fi
    else
        if pg_dump "${pg_dump_opts[@]}" > "${backup_file}"; then
            print_message "${GREEN}" "✓ Backup created successfully"
            return 0
        else
            print_message "${RED}" "✗ Backup failed"
            return 1
        fi
    fi
}

##
# Clean up old backups
##
cleanup_old_backups() {
    local retention_days="${1}"
    
    print_message "${BLUE}" "Cleaning up backups older than ${retention_days} days..."
    
    local deleted_count
    deleted_count=$(find "${BACKUP_DIR}" -name "${DBNAME}_*.sql" -o -name "${DBNAME}_*.sql.gz" \
        -type f -mtime +"${retention_days}" -delete -print | wc -l)
    
    if [[ ${deleted_count} -gt 0 ]]; then
        print_message "${GREEN}" "✓ Deleted ${deleted_count} old backup(s)"
    else
        print_message "${BLUE}" "  No old backups to delete"
    fi
}

##
# List existing backups
##
list_backups() {
    print_message "${BLUE}" "Existing backups:"
    
    local backups
    backups=$(find "${BACKUP_DIR}" -name "${DBNAME}_*.sql" -o -name "${DBNAME}_*.sql.gz" \
        -type f | sort -r)
    
    if [[ -z "${backups}" ]]; then
        print_message "${BLUE}" "  No backups found"
        return 0
    fi
    
    while IFS= read -r backup; do
        local size
        size=$(du -h "${backup}" | cut -f1)
        local date
        date=$(stat -c "%y" "${backup}" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  - $(basename "${backup}") (${size}, ${date})"
    done <<< "${backups}"
}

##
# Main
##
main() {
    local compress=false
    local verbose=false
    local list_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -d|--database)
                DBNAME="${2}"
                shift 2
                ;;
            -o|--output)
                BACKUP_DIR="${2}"
                shift 2
                ;;
            -r|--retention)
                RETENTION_DAYS="${2}"
                shift 2
                ;;
            -c|--compress)
                compress=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
            *)
                print_message "${RED}" "Unexpected argument: ${1}"
                usage
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    check_prerequisites
    
    # Ensure backup directory exists
    ensure_backup_dir
    
    # List only mode
    if [[ "${list_only}" == "true" ]]; then
        list_backups
        exit 0
    fi
    
    # Generate backup filename
    local backup_file
    backup_file=$(generate_backup_filename "${compress}")
    
    # Create backup
    if create_backup "${backup_file}" "${compress}" "${verbose}"; then
        # Show backup info
        local size
        size=$(du -h "${backup_file}" | cut -f1)
        print_message "${GREEN}" "Backup size: ${size}"
        
        # Cleanup old backups
        cleanup_old_backups "${RETENTION_DAYS}"
        
        # List backups
        echo
        list_backups
        
        exit 0
    else
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

