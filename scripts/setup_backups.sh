#!/usr/bin/env bash
#
# Backup Configuration Script
# Configures automated backups for production
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

Configure automated backups for OSM-Notes-Monitoring.

Options:
    --install                Install backup cron job
    --remove                 Remove backup cron job
    --test                   Test backup creation
    --list                   List backup configuration
    --retention DAYS         Set retention period (default: 30)
    --schedule SCHEDULE      Set cron schedule (default: "0 3 * * *")
    -h, --help               Show this help message

Examples:
    $0 --install              # Install backup cron job
    $0 --test                 # Test backup creation
    $0 --retention 60         # Set 60-day retention

EOF
}

##
# Install backup cron job
##
install_backup_cron() {
    local project_root="${1}"
    local schedule="${2}"
    local retention="${3}"
    
    print_message "${BLUE}" "Installing backup cron job..."
    
    # Source properties to get database name
    local dbname="notes_monitoring"
    if [[ -f "${project_root}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${project_root}/etc/properties.sh"
        dbname="${DBNAME:-${dbname}}"
    fi
    
    local backup_script="${project_root}/sql/backups/backup_database.sh"
    local log_dir="/var/log/osm-notes-monitoring"
    if [[ -f "${project_root}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${project_root}/etc/properties.sh"
        log_dir="${LOG_DIR:-${log_dir}}"
    fi
    
    # Create log directory
    mkdir -p "${log_dir}" 2>/dev/null || true
    
    # Generate cron job
    local cron_job="${schedule} ${backup_script} -d ${dbname} -c -r ${retention} >> ${log_dir}/backup.log 2>&1"
    
    # Get current crontab
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    # Check if backup cron job already exists
    if echo "${current_crontab}" | grep -q "${backup_script}"; then
        print_message "${YELLOW}" "Backup cron job already exists"
        read -p "Replace existing backup cron job? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "${BLUE}" "Installation cancelled"
            return 0
        fi
        
        # Remove existing backup cron job
        current_crontab=$(echo "${current_crontab}" | grep -v "${backup_script}")
    fi
    
    # Add new cron job
    local new_crontab
    new_crontab="${current_crontab}
# OSM-Notes-Monitoring Database Backup
${cron_job}"
    
    # Install crontab
    echo "${new_crontab}" | crontab -
    
    print_message "${GREEN}" "✓ Backup cron job installed successfully"
    print_message "${BLUE}" "Schedule: ${schedule}"
    print_message "${BLUE}" "Retention: ${retention} days"
    print_message "${BLUE}" "Logs: ${log_dir}/backup.log"
}

##
# Remove backup cron job
##
remove_backup_cron() {
    print_message "${BLUE}" "Removing backup cron job..."
    
    local backup_script="${PROJECT_ROOT}/sql/backups/backup_database.sh"
    
    # Get current crontab
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if [[ -z "${current_crontab}" ]]; then
        print_message "${YELLOW}" "No crontab found"
        return 0
    fi
    
    # Remove backup cron job
    local new_crontab
    new_crontab=$(echo "${current_crontab}" | grep -v "${backup_script}" | grep -v "# OSM-Notes-Monitoring Database Backup")
    
    # Install updated crontab
    echo "${new_crontab}" | crontab -
    
    print_message "${GREEN}" "✓ Backup cron job removed successfully"
}

##
# Test backup creation
##
test_backup() {
    print_message "${BLUE}" "Testing backup creation..."
    
    local backup_script="${PROJECT_ROOT}/sql/backups/backup_database.sh"
    
    if [[ ! -f "${backup_script}" ]]; then
        print_message "${RED}" "Backup script not found: ${backup_script}"
        return 1
    fi
    
    # Source properties to get database name
    local dbname="notes_monitoring"
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/etc/properties.sh"
        dbname="${DBNAME:-${dbname}}"
    fi
    
    if "${backup_script}" -d "${dbname}" -c; then
        print_message "${GREEN}" "✓ Backup test successful"
        return 0
    else
        print_message "${RED}" "✗ Backup test failed"
        return 1
    fi
}

##
# List backup configuration
##
list_backup_config() {
    print_message "${BLUE}" "Backup configuration:"
    echo
    
    local backup_script="${PROJECT_ROOT}/sql/backups/backup_database.sh"
    
    # Get current crontab
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    # Find backup cron job
    local backup_job
    backup_job=$(echo "${current_crontab}" | grep "${backup_script}" || echo "")
    
    if [[ -z "${backup_job}" ]]; then
        print_message "${YELLOW}" "No backup cron job configured"
    else
        echo "Cron job: ${backup_job}"
    fi
    
    # Source properties
    local dbname="notes_monitoring"
    local backup_dir="${PROJECT_ROOT}/sql/backups"
    if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/etc/properties.sh"
        dbname="${DBNAME:-${dbname}}"
    fi
    
    echo "Database: ${dbname}"
    echo "Backup directory: ${backup_dir}"
    
    # List existing backups
    if [[ -d "${backup_dir}" ]]; then
        local backup_count
        backup_count=$(find "${backup_dir}" -name "${dbname}_*.sql*" -type f 2>/dev/null | wc -l)
        echo "Existing backups: ${backup_count}"
    fi
}

##
# Main
##
main() {
    local action=""
    local retention=30
    local schedule="0 3 * * *"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --install)
                action="install"
                shift
                ;;
            --remove)
                action="remove"
                shift
                ;;
            --test)
                action="test"
                shift
                ;;
            --list)
                action="list"
                shift
                ;;
            --retention)
                retention="${2}"
                shift 2
                ;;
            --schedule)
                schedule="${2}"
                shift 2
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
    
    # Default to list if no action specified
    if [[ -z "${action}" ]]; then
        action="list"
    fi
    
    # Execute action
    case "${action}" in
        install)
            install_backup_cron "${PROJECT_ROOT}" "${schedule}" "${retention}"
            ;;
        remove)
            remove_backup_cron
            ;;
        test)
            test_backup
            ;;
        list)
            list_backup_config
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
