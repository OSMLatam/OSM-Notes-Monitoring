#!/usr/bin/env bash
#
# Production Configuration Script
# Interactive configuration setup for production
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

Interactive production configuration setup.

Options:
    --main                  Configure main properties only
    --monitoring            Configure monitoring thresholds only
    --alerts                Configure alerts only
    --security              Configure security only
    --all                   Configure all (default)
    --review                Review current configuration
    -h, --help              Show this help message

Examples:
    $0                      # Interactive configuration of all
    $0 --main               # Configure main properties only
    $0 --review             # Review current configuration

EOF
}

##
# Configure main properties
##
configure_main_properties() {
    print_message "${BLUE}" "Configuring Main Properties (etc/properties.sh)"
    print_message "${BLUE}" "================================================"
    echo
    
    local config_file="${PROJECT_ROOT}/etc/properties.sh"
    local example_file="${PROJECT_ROOT}/etc/properties.sh.example"
    
    # Copy from example if doesn't exist
    if [[ ! -f "${config_file}" && -f "${example_file}" ]]; then
        cp "${example_file}" "${config_file}"
        print_message "${YELLOW}" "Created ${config_file} from example"
    fi
    
    if [[ ! -f "${config_file}" ]]; then
        print_message "${RED}" "Configuration file not found: ${config_file}"
        return 1
    fi
    
    print_message "${YELLOW}" "Current configuration:"
    echo
    grep -E "^[A-Z_]+=" "${config_file}" | head -20
    echo
    
    read -p "Edit configuration file? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} "${config_file}"
        print_message "${GREEN}" "✓ Configuration updated"
    else
        print_message "${BLUE}" "Skipped"
    fi
    
    echo
    print_message "${BLUE}" "Key settings to configure:"
    echo "  - DBNAME: Monitoring database name (default: notes_monitoring)"
    echo "  - DBHOST: Database host (default: localhost)"
    echo "  - DBPORT: Database port (default: 5432)"
    echo "  - DBUSER: Database user (default: postgres)"
    echo "  - ADMIN_EMAIL: Admin email for alerts"
    echo "  - INGESTION_REPO_PATH: Path to OSM-Notes-Ingestion"
    echo "  - ANALYTICS_REPO_PATH: Path to OSM-Notes-Analytics"
    echo "  - WMS_REPO_PATH: Path to OSM-Notes-WMS"
    echo "  - DATA_REPO_PATH: Path to OSM-Notes-Data"
}

##
# Configure monitoring thresholds
##
configure_monitoring() {
    print_message "${BLUE}" "Configuring Monitoring Thresholds (config/monitoring.conf)"
    print_message "${BLUE}" "========================================================"
    echo
    
    local config_file="${PROJECT_ROOT}/config/monitoring.conf"
    local example_file="${PROJECT_ROOT}/config/monitoring.conf.example"
    
    # Copy from example if doesn't exist
    if [[ ! -f "${config_file}" && -f "${example_file}" ]]; then
        cp "${example_file}" "${config_file}"
        print_message "${YELLOW}" "Created ${config_file} from example"
    fi
    
    if [[ ! -f "${config_file}" ]]; then
        print_message "${RED}" "Configuration file not found: ${config_file}"
        return 1
    fi
    
    print_message "${YELLOW}" "Current thresholds:"
    echo
    grep -E "THRESHOLD|INTERVAL" "${config_file}" | head -15
    echo
    
    read -p "Edit monitoring configuration? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} "${config_file}"
        print_message "${GREEN}" "✓ Monitoring configuration updated"
    else
        print_message "${BLUE}" "Skipped"
    fi
    
    echo
    print_message "${BLUE}" "Key thresholds to review:"
    echo "  - Ingestion thresholds (data freshness, error rates)"
    echo "  - Analytics thresholds (ETL duration, query performance)"
    echo "  - WMS thresholds (response time, error rate)"
    echo "  - Infrastructure thresholds (CPU, memory, disk)"
    echo "  - Monitoring intervals (how often to check)"
}

##
# Configure alerts
##
configure_alerts() {
    print_message "${BLUE}" "Configuring Alerts (config/alerts.conf)"
    print_message "${BLUE}" "======================================="
    echo
    
    local config_file="${PROJECT_ROOT}/config/alerts.conf"
    local example_file="${PROJECT_ROOT}/config/alerts.conf.example"
    
    # Copy from example if doesn't exist
    if [[ ! -f "${config_file}" && -f "${example_file}" ]]; then
        cp "${example_file}" "${config_file}"
        print_message "${YELLOW}" "Created ${config_file} from example"
    fi
    
    if [[ ! -f "${config_file}" ]]; then
        print_message "${RED}" "Configuration file not found: ${config_file}"
        return 1
    fi
    
    print_message "${YELLOW}" "Current alert configuration:"
    echo
    grep -E "EMAIL|SLACK|SEND" "${config_file}" | head -10
    echo
    
    read -p "Edit alert configuration? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} "${config_file}"
        print_message "${GREEN}" "✓ Alert configuration updated"
    else
        print_message "${BLUE}" "Skipped"
    fi
    
    echo
    print_message "${BLUE}" "Key settings to configure:"
    echo "  - ADMIN_EMAIL: Email address for alerts"
    echo "  - SEND_ALERT_EMAIL: Enable/disable email alerts (true/false)"
    echo "  - SLACK_WEBHOOK_URL: Slack webhook URL (optional)"
    echo "  - SEND_ALERT_SLACK: Enable/disable Slack alerts (true/false)"
    echo "  - Alert routing and escalation rules"
}

##
# Configure security
##
configure_security() {
    print_message "${BLUE}" "Configuring Security (config/security.conf)"
    print_message "${BLUE}" "==========================================="
    echo
    
    local config_file="${PROJECT_ROOT}/config/security.conf"
    local example_file="${PROJECT_ROOT}/config/security.conf.example"
    
    # Copy from example if doesn't exist
    if [[ ! -f "${config_file}" && -f "${example_file}" ]]; then
        cp "${example_file}" "${config_file}"
        print_message "${YELLOW}" "Created ${config_file} from example"
    fi
    
    if [[ ! -f "${config_file}" ]]; then
        print_message "${RED}" "Configuration file not found: ${config_file}"
        return 1
    fi
    
    print_message "${YELLOW}" "Current security configuration:"
    echo
    grep -E "RATE_LIMIT|DDoS|BLOCK" "${config_file}" | head -10
    echo
    
    read -p "Edit security configuration? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} "${config_file}"
        print_message "${GREEN}" "✓ Security configuration updated"
    else
        print_message "${BLUE}" "Skipped"
    fi
    
    echo
    print_message "${BLUE}" "Key settings to configure:"
    echo "  - RATE_LIMIT_PER_IP_PER_MINUTE: Rate limiting per IP"
    echo "  - RATE_LIMIT_PER_IP_PER_HOUR: Hourly rate limit"
    echo "  - DDoS protection thresholds"
    echo "  - IP blocking rules"
}

##
# Review current configuration
##
review_configuration() {
    print_message "${BLUE}" "Reviewing Current Configuration"
    print_message "${BLUE}" "==============================="
    echo
    
    local config_files=(
        "etc/properties.sh"
        "config/monitoring.conf"
        "config/alerts.conf"
        "config/security.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        local full_path="${PROJECT_ROOT}/${config_file}"
        
        echo
        print_message "${YELLOW}" "=== ${config_file} ==="
        
        if [[ -f "${full_path}" ]]; then
            # Check for default values
            local defaults_found=0
            
            if grep -q "example.com\|changeme\|password\|/path/to" "${full_path}" 2>/dev/null; then
                print_message "${RED}" "⚠ Default values found:"
                grep -E "example.com|changeme|password|/path/to" "${full_path}" | head -5
                defaults_found=1
            fi
            
            # Show key settings
            print_message "${BLUE}" "Key settings:"
            case "${config_file}" in
                "etc/properties.sh")
                    grep -E "^DBNAME=|^DBHOST=|^ADMIN_EMAIL=|^INGESTION_REPO_PATH=" "${full_path}" 2>/dev/null | head -10
                    ;;
                "config/monitoring.conf")
                    grep -E "THRESHOLD|INTERVAL" "${full_path}" 2>/dev/null | head -10
                    ;;
                "config/alerts.conf")
                    grep -E "EMAIL|SLACK|SEND" "${full_path}" 2>/dev/null | head -10
                    ;;
                "config/security.conf")
                    grep -E "RATE_LIMIT|DDoS" "${full_path}" 2>/dev/null | head -10
                    ;;
            esac
            
            if [[ ${defaults_found} -eq 0 ]]; then
                print_message "${GREEN}" "✓ No obvious default values"
            fi
        else
            print_message "${RED}" "✗ File not found (using defaults)"
        fi
    done
    
    echo
    print_message "${BLUE}" "Validation:"
    if [[ -f "${PROJECT_ROOT}/scripts/test_config_validation.sh" ]]; then
        "${PROJECT_ROOT}/scripts/test_config_validation.sh" 2>&1 | tail -10
    fi
}

##
# Validate configuration
##
validate_configuration() {
    print_message "${BLUE}" "Validating configuration..."
    
    if [[ -f "${PROJECT_ROOT}/scripts/test_config_validation.sh" ]]; then
        if "${PROJECT_ROOT}/scripts/test_config_validation.sh" > /dev/null 2>&1; then
            print_message "${GREEN}" "✓ Configuration validation passed"
            return 0
        else
            print_message "${YELLOW}" "⚠ Configuration validation found issues"
            print_message "${BLUE}" "Run for details: ./scripts/test_config_validation.sh"
            return 1
        fi
    else
        print_message "${YELLOW}" "⚠ Validation script not found"
        return 1
    fi
}

##
# Main
##
main() {
    local config_mode="all"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --main)
                config_mode="main"
                shift
                ;;
            --monitoring)
                config_mode="monitoring"
                shift
                ;;
            --alerts)
                config_mode="alerts"
                shift
                ;;
            --security)
                config_mode="security"
                shift
                ;;
            --all)
                config_mode="all"
                shift
                ;;
            --review)
                config_mode="review"
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
    
    print_message "${GREEN}" "Production Configuration Setup"
    print_message "${BLUE}" "==============================="
    echo
    
    case "${config_mode}" in
        main)
            configure_main_properties
            echo
            validate_configuration
            ;;
        monitoring)
            configure_monitoring
            echo
            validate_configuration
            ;;
        alerts)
            configure_alerts
            echo
            validate_configuration
            ;;
        security)
            configure_security
            echo
            validate_configuration
            ;;
        review)
            review_configuration
            ;;
        all)
            configure_main_properties
            echo
            configure_monitoring
            echo
            configure_alerts
            echo
            configure_security
            echo
            validate_configuration
            ;;
    esac
    
    echo
    print_message "${GREEN}" "Configuration complete!"
    print_message "${BLUE}" "Next steps:"
    echo "  1. Review configuration: $0 --review"
    echo "  2. Validate: ./scripts/test_config_validation.sh"
    echo "  3. Test deployment: ./scripts/test_deployment.sh --quick"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
