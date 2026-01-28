#!/bin/bash
#
# Script to Update All Grafana Dashboards in Production
# Uses sudo permissions configured for angoca
# This script replaces /usr/local/bin/update_grafana_dashboard.sh
#
# Version: 2.0.0
# Date: 2026-01-10
#
# Usage:
#   ./update_grafana_dashboards_prod.sh [dashboards_path]
#   Or from the server:
#   /usr/local/bin/update_grafana_dashboards_prod.sh
#

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly PROVISIONING_DIR="/etc/grafana/provisioning/dashboards"
readonly TEMP_DIR="/tmp/grafana_dashboards_$$"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Cleanup function
##
cleanup() {
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

##
# Main function
##
main() {
    local dashboards_source_dir="${1:-}"

    print_message "${GREEN}" "=========================================="
    print_message "${GREEN}" "Update Grafana Dashboards"
    print_message "${GREEN}" "=========================================="
    echo

    # Determine source directory
    if [[ -z "${dashboards_source_dir}" ]]; then
        # Try common locations
        if [[ -d "${HOME}/notes/OSM-Notes-Monitoring/dashboards/grafana" ]]; then
            dashboards_source_dir="${HOME}/notes/OSM-Notes-Monitoring/dashboards/grafana"
        elif [[ -d "${HOME}/OSM-Notes-Monitoring/dashboards/grafana" ]]; then
            dashboards_source_dir="${HOME}/OSM-Notes-Monitoring/dashboards/grafana"
        elif [[ -d "./dashboards/grafana" ]]; then
            dashboards_source_dir="./dashboards/grafana"
        elif [[ -d "/tmp" ]] && ls /tmp/*.json >/dev/null 2>&1; then
            # Use /tmp if JSON files are there (for remote deployment)
            dashboards_source_dir="/tmp"
        else
            print_message "${RED}" "Error: Dashboards directory not found"
            print_message "${YELLOW}" "Use: $0 <dashboards_path/grafana>"
            print_message "${YELLOW}" "Or copy dashboards to /tmp first"
            exit 1
        fi
    fi

    if [[ ! -d "${dashboards_source_dir}" ]]; then
        print_message "${RED}" "Error: Directory not found: ${dashboards_source_dir}"
        exit 1
    fi

    print_message "${BLUE}" "Source directory: ${dashboards_source_dir}"

    # Count dashboards
    local dashboard_count
    dashboard_count=$(find "${dashboards_source_dir}" -maxdepth 1 -name "*.json" -type f 2>/dev/null | wc -l)

    if [[ "${dashboard_count}" -eq 0 ]]; then
        print_message "${RED}" "Error: No JSON dashboards found in ${dashboards_source_dir}"
        exit 1
    fi

    print_message "${BLUE}" "Found ${dashboard_count} dashboards"
    echo

    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    print_message "${CYAN}" "Preparing dashboards..."

    # Copy all dashboards to temp directory (excluding test files)
    local copied=0
    for dashboard_file in "${dashboards_source_dir}"/*.json; do
        [[ ! -f "${dashboard_file}" ]] && continue
        [[ "${dashboard_file}" =~ test_ ]] && continue
        local dashboard_name
        dashboard_name=$(basename "${dashboard_file}")
        if cp "${dashboard_file}" "${TEMP_DIR}/${dashboard_name}" 2>/dev/null; then
            ((copied++))
            print_message "${CYAN}" "  ✓ Prepared: ${dashboard_name}"
        fi
    done

    if [[ ${copied} -eq 0 ]]; then
        print_message "${RED}" "Error: Could not copy dashboards to ${TEMP_DIR}"
        exit 1
    fi

    print_message "${CYAN}" "Total prepared: ${copied}"

    echo
    print_message "${BLUE}" "Deploying dashboards to Grafana..."

    # Copy each dashboard using sudo (with NOPASSWD permissions)
    local deployed=0
    local failed=0

    for dashboard_file in "${TEMP_DIR}"/*.json; do
        if [[ ! -f "${dashboard_file}" ]]; then
            continue
        fi

        local dashboard_name
        dashboard_name=$(basename "${dashboard_file}")

        # Use sudo with specific paths as configured in sudoers
        # The sudoers rule allows: /bin/cp /tmp/*.json /etc/grafana/provisioning/dashboards/*
        if sudo cp "${dashboard_file}" "${PROVISIONING_DIR}/${dashboard_name}" 2>/dev/null; then
            sudo chown grafana:grafana "${PROVISIONING_DIR}/${dashboard_name}" 2>/dev/null || true
            sudo chmod 644 "${PROVISIONING_DIR}/${dashboard_name}" 2>/dev/null || true
            print_message "${GREEN}" "  ✓ Deployed: ${dashboard_name}"
            ((deployed++))
        else
            print_message "${RED}" "  ✗ Error deploying: ${dashboard_name}"
            ((failed++))
        fi
    done

    echo
    print_message "${BLUE}" "Restarting Grafana..."

    # Restart Grafana
    if sudo systemctl restart grafana-server; then
        print_message "${GREEN}" "✓ Grafana restarted successfully"

        # Wait a moment for Grafana to start
        sleep 2

        # Check status
        if sudo systemctl is-active --quiet grafana-server; then
            print_message "${GREEN}" "✓ Grafana is running"
        else
            print_message "${YELLOW}" "⚠ Check Grafana status: sudo systemctl status grafana-server"
        fi
    else
        print_message "${YELLOW}" "⚠ Error restarting Grafana"
    fi

    echo
    print_message "${GREEN}" "=========================================="
    print_message "${GREEN}" "Summary"
    print_message "${GREEN}" "=========================================="
    print_message "${GREEN}" "✓ Dashboards deployed: ${deployed}"
    if [[ ${failed} -gt 0 ]]; then
        print_message "${RED}" "✗ Dashboards with errors: ${failed}"
    fi

    # Count final dashboards
    local final_count
    final_count=$(find "${PROVISIONING_DIR}" -maxdepth 1 -name "*.json" -type f 2>/dev/null | wc -l)
    print_message "${CYAN}" "Total dashboards in Grafana: ${final_count}"

    echo
    print_message "${CYAN}" "Access Grafana to view dashboards:"
    print_message "${CYAN}" "  http://192.168.0.7:3003"
    echo
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
