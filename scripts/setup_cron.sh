#!/usr/bin/env bash
#
# Cron Jobs Setup Script
# Configures cron jobs for monitoring scripts
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

Setup cron jobs for OSM-Notes-Monitoring.

Options:
    --install                Install cron jobs
    --remove                 Remove cron jobs
    --list                   List current cron jobs
    --user USER              User to install cron jobs for (default: current user)
    -h, --help               Show this help message

Examples:
    $0 --install              # Install cron jobs
    $0 --remove               # Remove cron jobs
    $0 --list                 # List cron jobs

EOF
}

##
# Generate cron jobs
##
generate_cron_jobs() {
    local project_root="${1}"
    local log_dir="${2}"
    
    cat << EOF
# OSM-Notes-Monitoring Cron Jobs
# Generated: $(date +"%Y-%m-%d %H:%M:%S")
# Project: ${project_root}

# Ingestion monitoring (every 5 minutes)
*/5 * * * * ${project_root}/bin/monitor/monitorIngestion.sh >> ${log_dir}/ingestion.log 2>&1

# Analytics monitoring (every 15 minutes)
*/15 * * * * ${project_root}/bin/monitor/monitorAnalytics.sh >> ${log_dir}/analytics.log 2>&1

# WMS monitoring (every 5 minutes)
*/5 * * * * ${project_root}/bin/monitor/monitorWMS.sh >> ${log_dir}/wms.log 2>&1

# API/Security monitoring (every minute)
* * * * * ${project_root}/bin/monitor/monitorAPI.sh >> ${log_dir}/api.log 2>&1

# Data freshness monitoring (every hour)
0 * * * * ${project_root}/bin/monitor/monitorData.sh >> ${log_dir}/data.log 2>&1

# Infrastructure monitoring (every 5 minutes)
*/5 * * * * ${project_root}/bin/monitor/monitorInfrastructure.sh >> ${log_dir}/infrastructure.log 2>&1

# Dashboard updates (every 15 minutes)
*/15 * * * * ${project_root}/bin/dashboard/updateDashboard.sh html >> ${log_dir}/dashboard.log 2>&1

# Metrics generation (every 15 minutes)
*/15 * * * * ${project_root}/bin/dashboard/generateMetrics.sh >> ${log_dir}/metrics.log 2>&1

# Database cleanup (daily at 2 AM)
0 2 * * * psql -d notes_monitoring -c "SELECT cleanup_old_metrics(); SELECT cleanup_old_alerts();" >> ${log_dir}/cleanup.log 2>&1

# Database backup (daily at 3 AM)
0 3 * * * ${project_root}/sql/backups/backup_database.sh -c -r 30 >> ${log_dir}/backup.log 2>&1

EOF
}

##
# Install cron jobs
##
install_cron_jobs() {
    local user="${1}"
    local project_root="${2}"
    
    print_message "${BLUE}" "Installing cron jobs for user: ${user}"
    
    # Source properties to get log directory
    local log_dir="/var/log/osm-notes-monitoring"
    if [[ -f "${project_root}/etc/properties.sh" ]]; then
        # shellcheck source=/dev/null
        source "${project_root}/etc/properties.sh"
        log_dir="${LOG_DIR:-${log_dir}}"
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "${log_dir}" 2>/dev/null || true
    
    # Generate cron jobs
    local cron_jobs
    cron_jobs=$(generate_cron_jobs "${project_root}" "${log_dir}")
    
    # Get current crontab
    local current_crontab
    current_crontab=$(crontab -u "${user}" -l 2>/dev/null || echo "")
    
    # Check if cron jobs already exist
    if echo "${current_crontab}" | grep -q "OSM-Notes-Monitoring"; then
        print_message "${YELLOW}" "Cron jobs already exist for this project"
        read -p "Replace existing cron jobs? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "${BLUE}" "Installation cancelled"
            return 0
        fi
        
        # Remove existing cron jobs
        current_crontab=$(echo "${current_crontab}" | grep -v "OSM-Notes-Monitoring" | grep -v "# Generated:" | grep -v "# Project:")
    fi
    
    # Add new cron jobs
    local new_crontab
    new_crontab="${current_crontab}
${cron_jobs}"
    
    # Install crontab
    echo "${new_crontab}" | crontab -u "${user}" -
    
    print_message "${GREEN}" "✓ Cron jobs installed successfully"
    print_message "${BLUE}" "Logs will be written to: ${log_dir}"
}

##
# Remove cron jobs
##
remove_cron_jobs() {
    local user="${1}"
    
    print_message "${BLUE}" "Removing cron jobs for user: ${user}"
    
    # Get current crontab
    local current_crontab
    current_crontab=$(crontab -u "${user}" -l 2>/dev/null || echo "")
    
    if [[ -z "${current_crontab}" ]]; then
        print_message "${YELLOW}" "No crontab found for user: ${user}"
        return 0
    fi
    
    # Remove OSM-Notes-Monitoring cron jobs
    local new_crontab
    new_crontab=$(echo "${current_crontab}" | grep -v "OSM-Notes-Monitoring" | grep -v "# Generated:" | grep -v "# Project:")
    
    # Install updated crontab
    echo "${new_crontab}" | crontab -u "${user}" -
    
    print_message "${GREEN}" "✓ Cron jobs removed successfully"
}

##
# List cron jobs
##
list_cron_jobs() {
    local user="${1}"
    
    print_message "${BLUE}" "Cron jobs for user: ${user}"
    echo
    
    # Get current crontab
    local current_crontab
    current_crontab=$(crontab -u "${user}" -l 2>/dev/null || echo "")
    
    if [[ -z "${current_crontab}" ]]; then
        print_message "${YELLOW}" "No crontab found for user: ${user}"
        return 0
    fi
    
    # Filter OSM-Notes-Monitoring cron jobs
    local monitoring_jobs
    monitoring_jobs=$(echo "${current_crontab}" | grep -A 1 "OSM-Notes-Monitoring" || echo "")
    
    if [[ -z "${monitoring_jobs}" ]]; then
        print_message "${YELLOW}" "No OSM-Notes-Monitoring cron jobs found"
    else
        echo "${monitoring_jobs}"
    fi
}

##
# Main
##
main() {
    local action=""
    local user="${USER}"
    
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
            --list)
                action="list"
                shift
                ;;
            --user)
                user="${2}"
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
    
    # Default to install if no action specified
    if [[ -z "${action}" ]]; then
        action="install"
    fi
    
    # Check if running as root for other users
    if [[ "${user}" != "${USER}" && "${EUID}" -ne 0 ]]; then
        print_message "${RED}" "ERROR: Must run as root to install cron jobs for other users"
        exit 1
    fi
    
    # Execute action
    case "${action}" in
        install)
            install_cron_jobs "${user}" "${PROJECT_ROOT}"
            ;;
        remove)
            remove_cron_jobs "${user}"
            ;;
        list)
            list_cron_jobs "${user}"
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
