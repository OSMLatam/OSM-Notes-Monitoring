#!/usr/bin/env bash
#
# Setup Logrotate Configuration
# Installs logrotate configuration for OSM-Notes-Monitoring
#
# Version: 1.0.0
# Date: 2025-12-24
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
# Check if running as root
##
check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        print_message "${RED}" "Error: This script must be run as root"
        print_message "${YELLOW}" "Usage: sudo $0"
        exit 1
    fi
}

##
# Check if logrotate is installed
##
check_logrotate() {
    if ! command -v logrotate > /dev/null 2>&1; then
        print_message "${RED}" "Error: logrotate is not installed"
        print_message "${YELLOW}" "Install it with: apt-get install logrotate (Debian/Ubuntu)"
        print_message "${YELLOW}" "Or: yum install logrotate (RHEL/CentOS)"
        exit 1
    fi
}

##
# Install logrotate configuration
##
install_logrotate() {
    local source_file="${PROJECT_ROOT}/config/logrotate.conf"
    local example_file="${PROJECT_ROOT}/config/logrotate.conf.example"
    local target_file="/etc/logrotate.d/osm-notes-monitoring"
    
    # Use .conf if exists, otherwise use .example
    if [[ ! -f "${source_file}" ]]; then
        if [[ -f "${example_file}" ]]; then
            print_message "${YELLOW}" "Using example configuration file: ${example_file}"
            source_file="${example_file}"
        else
            print_message "${RED}" "Error: Configuration file not found: ${source_file}"
            print_message "${RED}" "Example file not found: ${example_file}"
            exit 1
        fi
    fi
    
    print_message "${BLUE}" "Installing logrotate configuration..."
    print_message "${BLUE}" "  Source: ${source_file}"
    print_message "${BLUE}" "  Target: ${target_file}"
    
    # Copy configuration
    cp "${source_file}" "${target_file}"
    chmod 0644 "${target_file}"
    
    print_message "${GREEN}" "✓ Logrotate configuration installed"
}

##
# Fix log file permissions
##
fix_log_permissions() {
    local log_dir="/var/log/osm-notes-monitoring"
    
    if [[ ! -d "${log_dir}" ]]; then
        print_message "${YELLOW}" "Log directory does not exist: ${log_dir}"
        return 0
    fi
    
    print_message "${BLUE}" "Fixing permissions for log files in ${log_dir}..."
    
    # Fix ownership and permissions for all log files
    chown -R notes:maptimebogota "${log_dir}"
    chmod 755 "${log_dir}"
    
    # Fix permissions for log files (readable by owner and group)
    find "${log_dir}" -type f -name "*.log" -exec chmod 0640 {} \;
    find "${log_dir}" -type f -name "*.log-*" -exec chmod 0640 {} \;
    
    print_message "${GREEN}" "✓ Log file permissions fixed"
}

##
# Test logrotate configuration
##
test_logrotate() {
    print_message "${BLUE}" "Testing logrotate configuration..."
    
    if logrotate -d /etc/logrotate.d/osm-notes-monitoring > /dev/null 2>&1; then
        print_message "${GREEN}" "✓ Configuration syntax is valid"
    else
        print_message "${YELLOW}" "⚠ Configuration test failed (this may be normal if log files don't exist yet)"
    fi
}

##
# Show usage
##
usage() {
    cat << EOF
Setup Logrotate Configuration for OSM-Notes-Monitoring

Usage: $0 [OPTIONS]

Options:
    -h, --help      Show this help message
    -t, --test      Test configuration without installing
    -d, --dry-run   Dry run (test logrotate without installing)
    -f, --fix-perms Fix log file permissions (requires root)

Examples:
    sudo $0                    # Install logrotate configuration
    sudo $0 --test            # Test configuration syntax
    logrotate -d config/logrotate.conf  # Dry run test

EOF
}

##
# Main
##
main() {
    local test_only=false
    local dry_run=false
    local fix_perms=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                exit 0
                ;;
            -t|--test)
                test_only=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -f|--fix-perms)
                fix_perms=true
                shift
                ;;
            *)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
        esac
    done
    
    print_message "${GREEN}" "OSM-Notes-Monitoring Logrotate Setup"
    echo
    
    if [[ "${fix_perms}" == true ]]; then
        # Only fix permissions
        check_root
        fix_log_permissions
        echo
        print_message "${GREEN}" "Permissions fixed!"
        exit 0
    fi
    
    check_logrotate
    
    if [[ "${test_only}" == true ]]; then
        # Test without installing
        if [[ -f "${PROJECT_ROOT}/config/logrotate.conf" ]]; then
            print_message "${BLUE}" "Testing configuration syntax..."
            if logrotate -d "${PROJECT_ROOT}/config/logrotate.conf" 2>&1; then
                print_message "${GREEN}" "✓ Configuration syntax is valid"
                exit 0
            else
                print_message "${RED}" "✗ Configuration syntax error"
                exit 1
            fi
        else
            print_message "${RED}" "Error: Configuration file not found"
            exit 1
        fi
    elif [[ "${dry_run}" == true ]]; then
        # Dry run
        if [[ -f "${PROJECT_ROOT}/config/logrotate.conf" ]]; then
            print_message "${BLUE}" "Running dry-run test..."
            logrotate -d "${PROJECT_ROOT}/config/logrotate.conf"
        else
            print_message "${RED}" "Error: Configuration file not found"
            exit 1
        fi
    else
        # Install
        check_root
        fix_log_permissions
        install_logrotate
        test_logrotate
        
        echo
        print_message "${GREEN}" "Setup complete!"
        print_message "${BLUE}" "Logrotate will run daily via cron"
        print_message "${BLUE}" "Test with: logrotate -d /etc/logrotate.d/osm-notes-monitoring"
        print_message "${BLUE}" "Force rotation: logrotate -f /etc/logrotate.d/osm-notes-monitoring"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

