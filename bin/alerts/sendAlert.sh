#!/usr/bin/env bash
#
# Enhanced Alert Sender Script
# Provides improved alert formatting and multi-channel support
#
# Version: 1.0.0
# Date: 2025-12-27
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"

# Set default LOG_DIR if not set
# In test mode, use TEST_LOG_DIR if available, otherwise use PROJECT_ROOT/logs
if [[ "${TEST_MODE:-false}" == "true" ]] && [[ -n "${TEST_LOG_DIR:-}" ]]; then
    export LOG_DIR="${TEST_LOG_DIR}"
elif [[ -z "${LOG_DIR:-}" ]]; then
    export LOG_DIR="${PROJECT_ROOT}/logs"
fi

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Initialize logging
init_logging "${LOG_DIR}/send_alert.log" "sendAlert"

# Initialize alerting
init_alerting

##
# Show usage
##
usage() {
    cat << EOF
Enhanced Alert Sender Script

Usage: ${0} [OPTIONS] COMPONENT LEVEL TYPE MESSAGE [METADATA]

Arguments:
    COMPONENT         Component name (e.g., INGESTION, ANALYTICS)
    LEVEL             Alert level (critical, warning, info)
    TYPE              Alert type (e.g., data_quality, performance)
    MESSAGE           Alert message
    METADATA          Optional JSON metadata

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --email EMAIL       Override email recipient
    --slack             Force Slack notification (even if disabled)
    --no-email          Skip email notification
    --format FORMAT     Output format (text, json, html)

Examples:
    ${0} INGESTION critical data_quality "Data quality check failed"
    ${0} ANALYTICS warning performance "Query performance degraded" '{"query_time": 5000}'
    ${0} --email admin@example.com INGESTION critical availability "Service unavailable"

EOF
}

##
# Format alert message as HTML
#
# Arguments:
#   $1 - Component
#   $2 - Alert level
#   $3 - Alert type
#   $4 - Message
#   $5 - Metadata (optional)
##
format_html() {
    local component="${1}"
    local alert_level="${2}"
    local alert_type="${3}"
    local message="${4}"
    local metadata="${5:-}"
    
    local color
    case "${alert_level}" in
        critical)
            color="#dc3545"  # Red
            ;;
        warning)
            color="#ffc107"  # Yellow
            ;;
        info)
            color="#17a2b8"  # Blue
            ;;
        *)
            color="#6c757d"  # Gray
            ;;
    esac
    
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; }
        .alert { border-left: 4px solid ${color}; padding: 10px; margin: 10px 0; }
        .header { font-weight: bold; font-size: 1.2em; }
        .metadata { font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <div class="alert">
        <div class="header">[${alert_level^^}] ${component} - ${alert_type}</div>
        <div>${message}</div>
        <div class="metadata">Timestamp: $(date -Iseconds)</div>
        ${metadata:+<div class="metadata">Metadata: ${metadata}</div>}
    </div>
</body>
</html>
EOF
}

##
# Format alert message as JSON
#
# Arguments:
#   $1 - Component
#   $2 - Alert level
#   $3 - Alert type
#   $4 - Message
#   $5 - Metadata (optional)
##
format_json() {
    local component="${1}"
    local alert_level="${2}"
    local alert_type="${3}"
    local message="${4}"
    local metadata="${5:-null}"
    
    cat << EOF
{
  "component": "${component}",
  "alert_level": "${alert_level}",
  "alert_type": "${alert_type}",
  "message": "${message}",
  "timestamp": "$(date -Iseconds)",
  "metadata": ${metadata}
}
EOF
}

##
# Enhanced send alert with improved formatting
#
# Arguments:
#   $1 - Component
#   $2 - Alert level
#   $3 - Alert type
#   $4 - Message
#   $5 - Metadata (optional)
##
enhanced_send_alert() {
    local component="${1:?Component required}"
    local alert_level="${2:?Alert level required}"
    local alert_type="${3:?Alert type required}"
    local message="${4:?Message required}"
    local metadata="${5:-null}"
    
    # Validate alert level
    case "${alert_level}" in
        critical|warning|info)
            ;;
        *)
            log_error "Invalid alert level: ${alert_level}"
            return 1
            ;;
    esac
    
    # Use base send_alert function
    send_alert "${component}" "${alert_level}" "${alert_type}" "${message}" "${metadata}"
    
    return 0
}

##
# Main function
##
main() {
    local email_override=""
    local force_slack=false
    local skip_email=false
    local format="text"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                exit 0
                ;;
            --email)
                email_override="${2}"
                shift 2
                ;;
            --slack)
                force_slack=true
                shift
                ;;
            --no-email)
                skip_email=true
                shift
                ;;
            --format)
                format="${2}"
                shift 2
                ;;
            --config|-c)
                export CONFIG_FILE="${2}"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [[ $# -lt 4 ]]; then
        echo "Error: Missing required arguments"
        usage
        exit 1
    fi
    
    local component="${1}"
    local alert_level="${2}"
    local alert_type="${3}"
    local message="${4}"
    local metadata="${5:-null}"
    
    # Override email if specified
    if [[ -n "${email_override}" ]]; then
        export ADMIN_EMAIL="${email_override}"
        export CRITICAL_ALERT_RECIPIENTS="${email_override}"
        export WARNING_ALERT_RECIPIENTS="${email_override}"
    fi
    
    # Skip email if requested
    if [[ "${skip_email}" == "true" ]]; then
        export SEND_ALERT_EMAIL="false"
    fi
    
    # Force Slack if requested
    if [[ "${force_slack}" == "true" ]]; then
        export SLACK_ENABLED="true"
    fi
    
    # Format and send based on format type
    case "${format}" in
        html)
            local html_body
            html_body=$(format_html "${component}" "${alert_level}" "${alert_type}" "${message}" "${metadata}")
            if [[ "${SEND_ALERT_EMAIL:-false}" == "true" ]] && [[ -n "${ADMIN_EMAIL:-}" ]]; then
                local subject="[${alert_level^^}] OSM-Notes-Monitoring: ${component} - ${alert_type}"
                send_email_alert "${ADMIN_EMAIL}" "${subject}" "${html_body}"
            fi
            ;;
        json)
            format_json "${component}" "${alert_level}" "${alert_type}" "${message}" "${metadata}"
            enhanced_send_alert "${component}" "${alert_level}" "${alert_type}" "${message}" "${metadata}"
            ;;
        text|*)
            enhanced_send_alert "${component}" "${alert_level}" "${alert_type}" "${message}" "${metadata}"
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

