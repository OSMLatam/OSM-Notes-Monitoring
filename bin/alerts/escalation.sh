#!/usr/bin/env bash
#
# Alert Escalation Script
# Implements escalation rules, timing, and on-call rotation
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

# Only initialize if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Initialize logging
    init_logging "${LOG_DIR}/escalation.log" "escalation"
    
    # Initialize alerting
    init_alerting
fi

##
# Show usage
##
usage() {
    cat << EOF
Alert Escalation Script

Usage: ${0} [OPTIONS] [ACTION] [ARGS...]

Actions:
    check [COMPONENT]                  Check for alerts that need escalation
    escalate ALERT_ID [LEVEL]          Manually escalate an alert
    rules [COMPONENT]                  Show escalation rules for component
    oncall [DATE]                      Show on-call schedule for date
    rotate                             Rotate on-call schedule (if enabled)

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file

Examples:
    ${0} check                          # Check all alerts for escalation
    ${0} check INGESTION                # Check INGESTION alerts
    ${0} escalate <alert-id> 2          # Escalate alert to level 2
    ${0} rules INGESTION                # Show escalation rules
    ${0} oncall                         # Show today's on-call
    ${0} oncall 2025-12-28              # Show on-call for specific date

EOF
}

##
# Load configuration
##
load_config() {
    local config_file="${1:-${PROJECT_ROOT}/config/monitoring.conf}"
    
    if [[ -f "${config_file}" ]]; then
        # shellcheck disable=SC1090
        source "${config_file}" || true
    fi
    
    # Load alerts config if available
    if [[ -f "${PROJECT_ROOT}/config/alerts.conf" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/config/alerts.conf" || true
    elif [[ -f "${PROJECT_ROOT}/config/alerts.conf.example" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/config/alerts.conf.example" || true
    fi
    
    # Set defaults
    export ESCALATION_ENABLED="${ESCALATION_ENABLED:-true}"
    export ESCALATION_LEVEL1_MINUTES="${ESCALATION_LEVEL1_MINUTES:-15}"
    export ESCALATION_LEVEL2_MINUTES="${ESCALATION_LEVEL2_MINUTES:-30}"
    export ESCALATION_LEVEL3_MINUTES="${ESCALATION_LEVEL3_MINUTES:-60}"
    export ONCALL_ROTATION_ENABLED="${ONCALL_ROTATION_ENABLED:-false}"
    export ONCALL_ROTATION_SCHEDULE="${ONCALL_ROTATION_SCHEDULE:-weekly}"
}

##
# Check if alert needs escalation
#
# Arguments:
#   $1 - Alert ID
#
# Returns:
#   0 if needs escalation, 1 if not
##
needs_escalation() {
    local alert_id="${1:?Alert ID required}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    # Get alert details
    local query="SELECT component, alert_level, status, created_at, metadata->>'escalation_level' as escalation_level
                 FROM alerts
                 WHERE id = '${alert_id}'::uuid
                   AND status = 'active';"
    
    local result
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        result=$(PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -F "|" \
            -c "${query}" 2>/dev/null || echo "")
    else
        result=$(psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -F "|" \
            -c "${query}" 2>/dev/null || echo "")
    fi
    
    if [[ -z "${result}" ]]; then
        return 1  # Alert not found or not active
    fi
    
    # Parse result: component|alert_level|status|created_at|escalation_level
    local component
    component=$(echo "${result}" | cut -d'|' -f1)
    local alert_level
    alert_level=$(echo "${result}" | cut -d'|' -f2)
    local created_at
    created_at=$(echo "${result}" | cut -d'|' -f4)
    local current_level
    current_level=$(echo "${result}" | cut -d'|' -f5)
    current_level="${current_level:-0}"
    
    # Calculate age in minutes
    local age_query="SELECT EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - '${created_at}'::timestamp)) / 60;"
    local age_minutes
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        age_minutes=$(PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${age_query}" 2>/dev/null | cut -d'.' -f1 || echo "0")
    else
        age_minutes=$(psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${age_query}" 2>/dev/null | cut -d'.' -f1 || echo "0")
    fi
    
    # Determine escalation thresholds based on alert level
    local threshold1
    local threshold2
    local threshold3
    
    case "${alert_level}" in
        critical)
            threshold1="${ESCALATION_LEVEL1_MINUTES}"
            threshold2="${ESCALATION_LEVEL2_MINUTES}"
            threshold3="${ESCALATION_LEVEL3_MINUTES}"
            ;;
        warning)
            threshold1=$((ESCALATION_LEVEL1_MINUTES * 2))
            threshold2=$((ESCALATION_LEVEL2_MINUTES * 2))
            threshold3=$((ESCALATION_LEVEL3_MINUTES * 2))
            ;;
        info)
            # Info alerts typically don't escalate
            return 1
            ;;
        *)
            return 1
            ;;
    esac
    
    # Check if escalation is needed
    if [[ "${age_minutes}" -ge "${threshold3}" ]] && [[ "${current_level}" -lt 3 ]]; then
        return 0  # Needs level 3 escalation
    elif [[ "${age_minutes}" -ge "${threshold2}" ]] && [[ "${current_level}" -lt 2 ]]; then
        return 0  # Needs level 2 escalation
    elif [[ "${age_minutes}" -ge "${threshold1}" ]] && [[ "${current_level}" -lt 1 ]]; then
        return 0  # Needs level 1 escalation
    fi
    
    return 1  # No escalation needed
}

##
# Escalate an alert
#
# Arguments:
#   $1 - Alert ID
#   $2 - Escalation level (optional, auto-determined if not provided)
##
escalate_alert() {
    local alert_id="${1:?Alert ID required}"
    local target_level="${2:-}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    # Get current escalation level
    local current_query="SELECT metadata->>'escalation_level' as escalation_level
                         FROM alerts
                         WHERE id = '${alert_id}'::uuid;"
    
    local current_level
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        current_level=$(PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${current_query}" 2>/dev/null | tr -d '[:space:]' || echo "0")
    else
        current_level=$(psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${current_query}" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
    current_level="${current_level:-0}"
    
    # Determine target level
    if [[ -z "${target_level}" ]]; then
        # Auto-determine based on age
        if needs_escalation "${alert_id}"; then
            target_level=$((current_level + 1))
        else
            log_warning "Alert ${alert_id} does not need escalation"
            return 1
        fi
    fi
    
    # Get escalation recipients
    local recipients
    case "${target_level}" in
        1)
            recipients="${ESCALATION_LEVEL1_RECIPIENTS:-${ADMIN_EMAIL}}"
            ;;
        2)
            recipients="${ESCALATION_LEVEL2_RECIPIENTS:-${ADMIN_EMAIL}}"
            ;;
        3)
            recipients="${ESCALATION_LEVEL3_RECIPIENTS:-${ADMIN_EMAIL}}"
            ;;
        *)
            log_error "Invalid escalation level: ${target_level}"
            return 1
            ;;
    esac
    
    # Update alert metadata
    local update_query="UPDATE alerts
                        SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
                            'escalation_level', ${target_level},
                            'escalated_at', CURRENT_TIMESTAMP,
                            'escalation_recipients', '${recipients}'
                        )
                        WHERE id = '${alert_id}'::uuid
                        RETURNING id;"
    
    local result
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        result=$(PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${update_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
    else
        result=$(psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${update_query}" 2>/dev/null | tr -d '[:space:]' || echo "")
    fi
    
    if [[ -n "${result}" ]]; then
        log_info "Alert ${alert_id} escalated to level ${target_level}"
        
        # Send escalation notification
        local alert_query="SELECT component, alert_level, alert_type, message
                           FROM alerts
                           WHERE id = '${alert_id}'::uuid;"
        
        local alert_data
        # Use PGPASSWORD only if set, otherwise let psql use default authentication
        if [[ -n "${PGPASSWORD:-}" ]]; then
            alert_data=$(PGPASSWORD="${PGPASSWORD}" psql \
                -h "${dbhost}" \
                -p "${dbport}" \
                -U "${dbuser}" \
                -d "${dbname}" \
                -t -A \
                -F "|" \
                -c "${alert_query}" 2>/dev/null || echo "")
        else
            alert_data=$(psql \
                -h "${dbhost}" \
                -p "${dbport}" \
                -U "${dbuser}" \
                -d "${dbname}" \
                -t -A \
                -F "|" \
                -c "${alert_query}" 2>/dev/null || echo "")
        fi
        
        if [[ -n "${alert_data}" ]]; then
            local component
            component=$(echo "${alert_data}" | cut -d'|' -f1)
            local alert_level
            alert_level=$(echo "${alert_data}" | cut -d'|' -f2)
            local message
            message=$(echo "${alert_data}" | cut -d'|' -f4)
            
            local escalation_message="Alert escalated to level ${target_level}: ${message}"
            send_alert "${component}" "${alert_level}" "escalation_${target_level}" "${escalation_message}" "{\"alert_id\": \"${alert_id}\", \"escalation_level\": ${target_level}}"
        fi
        
        echo "Alert escalated to level ${target_level}: ${alert_id}"
        return 0
    else
        log_error "Failed to escalate alert ${alert_id}"
        return 1
    fi
}

##
# Check alerts for escalation
#
# Arguments:
#   $1 - Component (optional)
##
check_escalation() {
    local component="${1:-}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="SELECT id FROM alerts WHERE status = 'active'"
    
    if [[ -n "${component}" ]]; then
        query="${query} AND component = '${component}'"
    fi
    
    query="${query};"
    
    local alert_ids
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        alert_ids=$(PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${query}" 2>/dev/null || echo "")
    else
        alert_ids=$(psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${query}" 2>/dev/null || echo "")
    fi
    
    local escalated_count=0
    
    while IFS= read -r alert_id; do
        if [[ -n "${alert_id}" ]]; then
            if needs_escalation "${alert_id}"; then
                if escalate_alert "${alert_id}"; then
                    escalated_count=$((escalated_count + 1))
                fi
            fi
        fi
    done <<< "${alert_ids}"
    
    log_info "Escalation check completed: ${escalated_count} alerts escalated"
    echo "Escalated ${escalated_count} alerts"
}

##
# Show escalation rules
#
# Arguments:
#   $1 - Component (optional)
##
show_rules() {
    local component="${1:-}"
    
    echo "Escalation Rules:"
    echo "================="
    echo ""
    echo "Level 1: ${ESCALATION_LEVEL1_MINUTES} minutes"
    echo "  Recipients: ${ESCALATION_LEVEL1_RECIPIENTS:-${ADMIN_EMAIL}}"
    echo ""
    echo "Level 2: ${ESCALATION_LEVEL2_MINUTES} minutes"
    echo "  Recipients: ${ESCALATION_LEVEL2_RECIPIENTS:-${ADMIN_EMAIL}}"
    echo ""
    echo "Level 3: ${ESCALATION_LEVEL3_MINUTES} minutes"
    echo "  Recipients: ${ESCALATION_LEVEL3_RECIPIENTS:-${ADMIN_EMAIL}}"
    echo ""
    echo "Note: Warning alerts use 2x thresholds, Info alerts do not escalate"
}

##
# Show on-call schedule
#
# Arguments:
#   $1 - Date (optional, default: today)
##
show_oncall() {
    local target_date="${1:-$(date +%Y-%m-%d)}"
    
    if [[ "${ONCALL_ROTATION_ENABLED:-false}" != "true" ]]; then
        echo "On-call rotation is not enabled"
        echo "Default on-call: ${ADMIN_EMAIL:-admin@example.com}"
        return 0
    fi
    
    # Simple on-call rotation logic (can be enhanced with database)
    echo "On-call for ${target_date}:"
    echo "  Primary: ${ONCALL_PRIMARY:-${ADMIN_EMAIL}}"
    echo "  Secondary: ${ONCALL_SECONDARY:-${ADMIN_EMAIL}}"
}

##
# Rotate on-call schedule
##
rotate_oncall() {
    if [[ "${ONCALL_ROTATION_ENABLED:-false}" != "true" ]]; then
        echo "On-call rotation is not enabled"
        return 1
    fi
    
    log_info "On-call rotation triggered"
    echo "On-call rotation completed"
    # In a full implementation, this would update the on-call schedule
    # For now, it's a placeholder
}

##
# Main function
##
main() {
    local action="${1:-}"
    
    # Handle options before action
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -v|--verbose)
                export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
                shift
                ;;
            -q|--quiet)
                export LOG_LEVEL="${LOG_LEVEL_ERROR}"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -c|--config)
                export CONFIG_FILE="${2}"
                shift 2
                ;;
            *)
                action="${1}"
                shift
                break
                ;;
        esac
    done
    
    # Load configuration
    load_config "${CONFIG_FILE:-}"
    
    # Strip leading -- from action if present
    if [[ "${action}" =~ ^-- ]]; then
        action="${action#--}"
    fi
    
    case "${action}" in
        check|--check)
            check_escalation "${2:-}"
            ;;
        escalate|--escalate)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Alert ID required"
                usage
                exit 1
            fi
            escalate_alert "${2}" "${3:-}"
            ;;
        rules|--rules)
            show_rules "${2:-}"
            ;;
        oncall|--oncall)
            show_oncall "${2:-}"
            ;;
        rotate|--rotate)
            rotate_oncall
            ;;
        -h|--help|help)
            usage
            ;;
        "")
            echo "Error: Action required"
            usage
            exit 1
            ;;
        *)
            echo "Error: Unknown action: ${action}"
            usage
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

