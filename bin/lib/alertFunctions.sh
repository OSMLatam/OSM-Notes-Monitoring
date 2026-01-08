#!/usr/bin/env bash
#
# Alert Functions Library
# Provides alerting utilities for OSM-Notes-Monitoring
#
# Version: 1.0.0
# Date: 2025-12-24
#

# Source logging functions
# shellcheck disable=SC1091
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh"
fi

# Alert levels (exported for external use)
# Only define if not already set to allow multiple sourcing
if [[ -z "${ALERT_LEVEL_CRITICAL:-}" ]]; then
readonly ALERT_LEVEL_CRITICAL="critical"
fi
if [[ -z "${ALERT_LEVEL_WARNING:-}" ]]; then
readonly ALERT_LEVEL_WARNING="warning"
fi
if [[ -z "${ALERT_LEVEL_INFO:-}" ]]; then
readonly ALERT_LEVEL_INFO="info"
fi
export ALERT_LEVEL_CRITICAL ALERT_LEVEL_WARNING ALERT_LEVEL_INFO

##
# Initialize alerting
# Sources alert configuration
##
init_alerting() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root
    project_root="$(dirname "$(dirname "${script_dir}")")"
    
    # Source alert configuration if available
    # shellcheck disable=SC1091
    if [[ -f "${project_root}/config/alerts.conf" ]]; then
        source "${project_root}/config/alerts.conf"
    fi
    
    # Set defaults
    export ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
    export SEND_ALERT_EMAIL="${SEND_ALERT_EMAIL:-false}"
    export SLACK_ENABLED="${SLACK_ENABLED:-false}"
    export SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
}

##
# Store alert in database
#
# Arguments:
#   $1 - Component name
#   $2 - Alert level (critical, warning, info)
#   $3 - Alert type
#   $4 - Message
#   $5 - Metadata JSON (optional)
#
# Returns:
#   0 on success, 1 on failure
##
store_alert() {
    local component="${1:?Component required}"
    local alert_level="${2:?Alert level required}"
    local alert_type="${3:?Alert type required}"
    local message="${4:?Message required}"
    local metadata="${5:-null}"
    
    # Normalize alert level to lowercase
    alert_level=$(echo "${alert_level}" | tr '[:upper:]' '[:lower:]')
    
    # Map ERROR to critical (since ERROR is not a valid level)
    if [[ "${alert_level}" == "error" ]]; then
        alert_level="critical"
    fi
    
    # Validate alert level
    case "${alert_level}" in
        critical|warning|info)
            ;;
        *)
            log_error "Invalid alert level: ${alert_level}"
            return 1
            ;;
    esac
    
    # Check deduplication if enabled
    if [[ "${ALERT_DEDUPLICATION_ENABLED:-true}" == "true" ]]; then
        if is_alert_duplicate "${component}" "${alert_type}" "${message}"; then
            log_debug "Alert deduplicated: ${component}/${alert_type}"
            return 0
        fi
    fi
    
    # Get database connection info
    local dbname="${DBNAME:-notes_monitoring}"
    
    # Insert alert - escape single quotes in message and metadata
    local message_escaped="${message//\'/\'\'}"
    local metadata_escaped="${metadata}"
    metadata_escaped="${metadata_escaped//\'/\'\'}"
    
    # Build query
    local query
    if [[ "${metadata}" == "null" || -z "${metadata}" ]]; then
        query="INSERT INTO alerts (component, alert_level, alert_type, message) VALUES ('${component}', '${alert_level}', '${alert_type}', '${message_escaped}');"
    else
        query="INSERT INTO alerts (component, alert_level, alert_type, message, metadata) VALUES ('${component}', '${alert_level}', '${alert_type}', '${message_escaped}', E'${metadata_escaped}'::jsonb);"
    fi
    
    # Use execute_sql_query if available, otherwise fall back to direct psql
    if command -v execute_sql_query > /dev/null 2>&1; then
        if execute_sql_query "${query}" "${dbname}" > /dev/null 2>&1; then
            log_info "Alert stored: ${component}/${alert_type}"
            return 0
        else
            log_error "Failed to store alert in database"
            return 1
        fi
    else
        # Fallback: use psql directly (same logic as execute_sql_query)
        local dbhost="${DBHOST:-localhost}"
        local dbport="${DBPORT:-5432}"
        local dbuser="${DBUSER:-notes}"
        local psql_cmd="psql"
        local current_user="${USER:-$(whoami)}"
        
        if [[ "${dbuser}" == "${current_user}" ]] && [[ "${dbhost}" == "localhost" || "${dbhost}" == "127.0.0.1" || -z "${dbhost}" ]]; then
            if [[ -n "${dbport}" && "${dbport}" != "5432" ]]; then
                psql_cmd="${psql_cmd} -p ${dbport}"
            fi
        else
            psql_cmd="${psql_cmd} -U ${dbuser}"
            if [[ -n "${dbhost}" && "${dbhost}" != "localhost" && "${dbhost}" != "127.0.0.1" ]]; then
                psql_cmd="${psql_cmd} -h ${dbhost}"
            fi
            if [[ -n "${dbport}" && "${dbport}" != "5432" ]]; then
                psql_cmd="${psql_cmd} -p ${dbport}"
            fi
            if [[ -n "${PGPASSWORD:-}" ]]; then
                psql_cmd="PGPASSWORD=\"${PGPASSWORD}\" ${psql_cmd}"
            fi
        fi
        
        local query_escaped
        query_escaped=$(printf '%q' "${query}")
        
        if eval "${psql_cmd} -d ${dbname} -c ${query_escaped}" > /dev/null 2>&1; then
            log_info "Alert stored: ${component}/${alert_type}"
            return 0
        else
            log_error "Failed to store alert in database"
            return 1
        fi
    fi
}

##
# Check if alert is duplicate
#
# Arguments:
#   $1 - Component name
#   $2 - Alert type
#   $3 - Message
#
# Returns:
#   0 if duplicate, 1 if not
##
is_alert_duplicate() {
    local component="${1}"
    local alert_type="${2}"
    local message="${3}"
    local window_minutes="${ALERT_DEDUPLICATION_WINDOW_MINUTES:-60}"
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    query="SELECT COUNT(*) FROM alerts
           WHERE component = '${component}'
             AND alert_type = '${alert_type}'
             AND message = '${message}'
             AND status = 'active'
             AND created_at > CURRENT_TIMESTAMP - INTERVAL '${window_minutes} minutes';"
    
    local count
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        count=$(PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${query}" 2>/dev/null)
    else
        count=$(psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null)
    fi
    
    if [[ "${count:-0}" -gt 0 ]]; then
        return 0  # Duplicate
    else
        return 1  # Not duplicate
    fi
}

##
# Send email alert
#
# Arguments:
#   $1 - Recipient email
#   $2 - Subject
#   $3 - Message body
#
# Returns:
#   0 on success, 1 on failure
##
send_email_alert() {
    local recipient="${1:?Recipient required}"
    local subject="${2:?Subject required}"
    local body="${3:?Message body required}"
    
    if [[ "${SEND_ALERT_EMAIL:-false}" != "true" ]]; then
        log_debug "Email alerts disabled, skipping"
        return 0
    fi
    
    # Check if mutt is available
    if ! command -v mutt > /dev/null 2>&1; then
        log_error "mutt not found, cannot send email"
        return 1
    fi
    
    # Send email
    if echo "${body}" | mutt -s "${subject}" "${recipient}" 2>/dev/null; then
        log_info "Email alert sent to ${recipient}"
        return 0
    else
        log_error "Failed to send email alert to ${recipient}"
        return 1
    fi
}

##
# Send alert via multiple channels
#
# Arguments:
#   $1 - Component name
#   $2 - Alert level (critical, warning, info)
#   $3 - Alert type
#   $4 - Message
#   $5 - Metadata JSON (optional)
#
# Returns:
#   0 on success, 1 on failure
##
send_alert() {
    local component="${1:?Component required}"
    local alert_level="${2:?Alert level required}"
    local alert_type="${3:?Alert type required}"
    local message="${4:?Message required}"
    local metadata="${5:-null}"
    
    # Store alert in database (normalization happens in store_alert)
    if ! store_alert "${component}" "${alert_level}" "${alert_type}" "${message}" "${metadata}"; then
        log_error "Failed to store alert, aborting send_alert"
        return 1
    fi
    
    # Determine recipients based on alert level
    local recipients
    case "${alert_level}" in
        critical)
            recipients="${CRITICAL_ALERT_RECIPIENTS:-${ADMIN_EMAIL}}"
            ;;
        warning)
            recipients="${WARNING_ALERT_RECIPIENTS:-${ADMIN_EMAIL}}"
            ;;
        info)
            recipients="${INFO_ALERT_RECIPIENTS:-}"
            ;;
    esac
    
    # Skip if no recipients for info alerts
    if [[ -z "${recipients}" && "${alert_level}" == "info" ]]; then
        return 0
    fi
    
    # Format subject
    local subject
    subject="[${alert_level^^}] OSM-Notes-Monitoring: ${component} - ${alert_type}"
    
    # Format message body
    local body
    body="Component: ${component}
Alert Level: ${alert_level}
Alert Type: ${alert_type}
Message: ${message}
Timestamp: $(date -Iseconds)

This is an automated alert from OSM-Notes-Monitoring."
    
    # Send email
    if [[ -n "${recipients}" ]]; then
        send_email_alert "${recipients}" "${subject}" "${body}"
    fi
    
    # Send Slack notification if enabled
    if [[ "${SLACK_ENABLED:-false}" == "true" && -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        send_slack_alert "${component}" "${alert_level}" "${alert_type}" "${message}"
    fi
    
    return 0
}

##
# Send Slack alert
#
# Arguments:
#   $1 - Component name
#   $2 - Alert level
#   $3 - Alert type
#   $4 - Message
#
# Returns:
#   0 on success, 1 on failure
##
send_slack_alert() {
    local component="${1}"
    local alert_level="${2}"
    local alert_type="${3}"
    local message="${4}"
    
    # Check if Slack is enabled
    if [[ "${SLACK_ENABLED:-false}" != "true" ]]; then
        log_debug "Slack notifications disabled, skipping"
        return 0
    fi
    
    # Check if webhook URL is configured
    if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        log_debug "Slack webhook URL not configured, skipping"
        return 0
    fi
    
    # Check if curl is available
    if ! command -v curl > /dev/null 2>&1; then
        log_error "curl not found, cannot send Slack notification"
        return 1
    fi
    
    # Determine color based on alert level
    local color
    case "${alert_level}" in
        critical)
            color="danger"
            ;;
        warning)
            color="warning"
            ;;
        info)
            color="good"
            ;;
        *)
            color="#36a64f"
            ;;
    esac
    
    # Create JSON payload
    local payload
    payload=$(cat <<EOF
{
  "channel": "${SLACK_CHANNEL:-#monitoring}",
  "username": "OSM-Notes-Monitoring",
  "icon_emoji": ":warning:",
  "attachments": [{
    "color": "${color}",
    "title": "${alert_level^^}: ${component} - ${alert_type}",
    "text": "${message}",
    "footer": "OSM-Notes-Monitoring",
    "ts": $(date +%s)
  }]
}
EOF
)
    
    # Send to Slack
    if curl -X POST -H 'Content-type: application/json' \
        --data "${payload}" \
        "${SLACK_WEBHOOK_URL}" > /dev/null 2>&1; then
        log_info "Slack alert sent"
        return 0
    else
        log_error "Failed to send Slack alert"
        return 1
    fi
}

# Initialize on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_alerting
fi

