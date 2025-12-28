#!/usr/bin/env bash
#
# Alert Manager Script
# Manages alerts: deduplication, aggregation, history, acknowledgment
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
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging
init_logging "${LOG_DIR}/alert_manager.log" "alertManager"

# Initialize alerting
init_alerting

##
# Show usage
##
usage() {
    cat << EOF
Alert Manager Script

Usage: ${0} [OPTIONS] [ACTION] [ARGS...]

Actions:
    list [COMPONENT] [STATUS]           List alerts (optionally filtered)
    show ALERT_ID                       Show alert details
    acknowledge ALERT_ID [USER]         Acknowledge an alert
    resolve ALERT_ID [USER]             Resolve an alert
    aggregate [COMPONENT] [WINDOW]      Aggregate alerts by component/type
    history COMPONENT [DAYS]            Show alert history for component
    stats [COMPONENT]                   Show alert statistics
    cleanup [DAYS]                      Cleanup old resolved alerts

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --json              Output in JSON format

Examples:
    ${0} list                          # List all active alerts
    ${0} list INGESTION active         # List active alerts for INGESTION
    ${0} show <alert-id>               # Show alert details
    ${0} acknowledge <alert-id> admin  # Acknowledge alert
    ${0} resolve <alert-id> admin     # Resolve alert
    ${0} aggregate INGESTION 60        # Aggregate alerts for INGESTION in last 60 min
    ${0} history INGESTION 7           # Show 7-day history for INGESTION
    ${0} stats                         # Show alert statistics
    ${0} cleanup 180                   # Cleanup alerts older than 180 days

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
    export ALERT_DEDUPLICATION_ENABLED="${ALERT_DEDUPLICATION_ENABLED:-true}"
    export ALERT_DEDUPLICATION_WINDOW_MINUTES="${ALERT_DEDUPLICATION_WINDOW_MINUTES:-60}"
    export ALERT_AGGREGATION_ENABLED="${ALERT_AGGREGATION_ENABLED:-true}"
    export ALERT_AGGREGATION_WINDOW_MINUTES="${ALERT_AGGREGATION_WINDOW_MINUTES:-15}"
    export ALERT_RETENTION_DAYS="${ALERT_RETENTION_DAYS:-180}"
}

##
# List alerts
#
# Arguments:
#   $1 - Component (optional)
#   $2 - Status (optional: active, resolved, acknowledged)
##
list_alerts() {
    local component="${1:-}"
    local status="${2:-active}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="SELECT id, component, alert_level, alert_type, message, status, created_at, resolved_at
                 FROM alerts
                 WHERE 1=1"
    
    if [[ -n "${component}" ]]; then
        query="${query} AND component = '${component}'"
    fi
    
    if [[ -n "${status}" ]]; then
        query="${query} AND status = '${status}'"
    fi
    
    query="${query} ORDER BY created_at DESC LIMIT 100;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Show alert details
#
# Arguments:
#   $1 - Alert ID
##
show_alert() {
    local alert_id="${1:?Alert ID required}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="SELECT * FROM alerts WHERE id = '${alert_id}'::uuid;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Acknowledge an alert
#
# Arguments:
#   $1 - Alert ID
#   $2 - User (optional)
##
acknowledge_alert() {
    local alert_id="${1:?Alert ID required}"
    local user="${2:-system}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="UPDATE alerts
                 SET status = 'acknowledged',
                     metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('acknowledged_by', '${user}', 'acknowledged_at', CURRENT_TIMESTAMP)
                 WHERE id = '${alert_id}'::uuid
                   AND status = 'active'
                 RETURNING id;"
    
    local result
    result=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo "")
    
    if [[ -n "${result}" ]]; then
        log_info "Alert ${alert_id} acknowledged by ${user}"
        echo "Alert acknowledged: ${alert_id}"
        return 0
    else
        log_warning "Failed to acknowledge alert ${alert_id} (not found or already resolved)"
        echo "Failed to acknowledge alert: ${alert_id}"
        return 1
    fi
}

##
# Resolve an alert
#
# Arguments:
#   $1 - Alert ID
#   $2 - User (optional)
##
resolve_alert() {
    local alert_id="${1:?Alert ID required}"
    local user="${2:-system}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="UPDATE alerts
                 SET status = 'resolved',
                     resolved_at = CURRENT_TIMESTAMP,
                     metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('resolved_by', '${user}', 'resolved_at', CURRENT_TIMESTAMP)
                 WHERE id = '${alert_id}'::uuid
                   AND status IN ('active', 'acknowledged')
                 RETURNING id;"
    
    local result
    result=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo "")
    
    if [[ -n "${result}" ]]; then
        log_info "Alert ${alert_id} resolved by ${user}"
        echo "Alert resolved: ${alert_id}"
        return 0
    else
        log_warning "Failed to resolve alert ${alert_id} (not found or already resolved)"
        echo "Failed to resolve alert: ${alert_id}"
        return 1
    fi
}

##
# Aggregate alerts by component and type
#
# Arguments:
#   $1 - Component (optional)
#   $2 - Window in minutes (optional, default: 15)
##
aggregate_alerts() {
    local component="${1:-}"
    local window_minutes="${2:-${ALERT_AGGREGATION_WINDOW_MINUTES}}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="SELECT component, alert_level, alert_type, COUNT(*) as count, MAX(created_at) as latest
                 FROM alerts
                 WHERE status = 'active'
                   AND created_at > CURRENT_TIMESTAMP - INTERVAL '${window_minutes} minutes'"
    
    if [[ -n "${component}" ]]; then
        query="${query} AND component = '${component}'"
    fi
    
    query="${query} GROUP BY component, alert_level, alert_type
                 ORDER BY count DESC, latest DESC;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Show alert history for a component
#
# Arguments:
#   $1 - Component
#   $2 - Days (optional, default: 7)
##
show_history() {
    local component="${1:?Component required}"
    local days="${2:-7}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="SELECT id, alert_level, alert_type, message, status, created_at, resolved_at
                 FROM alerts
                 WHERE component = '${component}'
                   AND created_at > CURRENT_TIMESTAMP - INTERVAL '${days} days'
                 ORDER BY created_at DESC
                 LIMIT 100;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Show alert statistics
#
# Arguments:
#   $1 - Component (optional)
##
show_stats() {
    local component="${1:-}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="SELECT 
                   component,
                   alert_level,
                   status,
                   COUNT(*) as count,
                   MIN(created_at) as first_alert,
                   MAX(created_at) as last_alert
                 FROM alerts"
    
    if [[ -n "${component}" ]]; then
        query="${query} WHERE component = '${component}'"
    fi
    
    query="${query} GROUP BY component, alert_level, status
                 ORDER BY component, alert_level, status;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Cleanup old resolved alerts
#
# Arguments:
#   $1 - Retention days (optional, default: 180)
##
cleanup_alerts() {
    local retention_days="${1:-${ALERT_RETENTION_DAYS}}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="SELECT cleanup_old_alerts(${retention_days});"
    
    local result
    result=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    log_info "Cleaned up ${result} old alerts (retention: ${retention_days} days)"
    echo "Cleaned up ${result} old alerts"
}

##
# Main function
##
main() {
    local action="${1:-}"
    
    # Load configuration
    load_config "${CONFIG_FILE:-}"
    
    case "${action}" in
        list)
            list_alerts "${2:-}" "${3:-}"
            ;;
        show)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Alert ID required"
                usage
                exit 1
            fi
            show_alert "${2}"
            ;;
        acknowledge|ack)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Alert ID required"
                usage
                exit 1
            fi
            acknowledge_alert "${2}" "${3:-}"
            ;;
        resolve)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Alert ID required"
                usage
                exit 1
            fi
            resolve_alert "${2}" "${3:-}"
            ;;
        aggregate)
            aggregate_alerts "${2:-}" "${3:-}"
            ;;
        history)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Component required"
                usage
                exit 1
            fi
            show_history "${2}" "${3:-}"
            ;;
        stats)
            show_stats "${2:-}"
            ;;
        cleanup)
            cleanup_alerts "${2:-}"
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

