#!/usr/bin/env bash
#
# Update Dashboard Script
# Updates dashboard data from metrics database
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

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Only initialize logging if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Initialize logging
    init_logging "${LOG_DIR}/update_dashboard.log" "updateDashboard"
fi

##
# Show usage
##
usage() {
    cat << EOF
Update Dashboard Script

Usage: ${0} [OPTIONS] [DASHBOARD_TYPE]

Arguments:
    DASHBOARD_TYPE    Dashboard type (grafana, html, or 'all') (default: all)

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    -d, --dashboard DIR Dashboard directory (default: dashboards/)
    --force             Force update even if data is recent
    --component COMP    Update specific component only

Examples:
    ${0} grafana                    # Update Grafana dashboards
    ${0} html                      # Update HTML dashboards
    ${0} all                       # Update all dashboards
    ${0} --component ingestion all # Update ingestion component only

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
    
    # Set defaults
    export DASHBOARD_UPDATE_INTERVAL="${DASHBOARD_UPDATE_INTERVAL:-300}"  # 5 minutes
    export DASHBOARD_OUTPUT_DIR="${DASHBOARD_OUTPUT_DIR:-${PROJECT_ROOT}/dashboards}"
}

##
# Check if dashboard needs update
#
# Arguments:
#   $1 - Dashboard file path
#   $2 - Update interval in seconds
##
needs_update() {
    local dashboard_file="${1:?Dashboard file required}"
    local update_interval="${2:-300}"
    
    if [[ ! -f "${dashboard_file}" ]]; then
        return 0  # File doesn't exist, needs update
    fi
    
    local file_age
    file_age=$(($(date +%s) - $(stat -c %Y "${dashboard_file}" 2>/dev/null || echo "0")))
    
    if [[ "${file_age}" -gt "${update_interval}" ]]; then
        return 0  # File is older than interval, needs update
    fi
    
    return 1  # File is recent, no update needed
}

##
# Update Grafana dashboard data
#
# Arguments:
#   $1 - Component name (optional)
##
update_grafana_dashboard() {
    local component="${1:-}"
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/grafana"
    local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
    
    mkdir -p "${dashboard_dir}"
    
    if [[ -n "${component}" ]]; then
        log_info "Updating Grafana dashboard for component: ${component}"
        "${metrics_script}" "${component}" dashboard > "${dashboard_dir}/${component}_metrics.json" 2>/dev/null || true
    else
        log_info "Updating all Grafana dashboards"
        local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
        
        for comp in "${components[@]}"; do
            log_info "Updating Grafana dashboard for component: ${comp}"
            "${metrics_script}" "${comp}" dashboard > "${dashboard_dir}/${comp}_metrics.json" 2>/dev/null || true
        done
    fi
    
    log_info "Grafana dashboards updated"
}

##
# Execute SQL query and return JSON result
#
# Arguments:
#   $1 - SQL query to execute
#   $2 - Database name (optional)
#
# Returns:
#   JSON result via stdout
##
execute_json_query() {
    local query="${1:?SQL query required}"
    local dbname="${2:-${DBNAME:-osm_notes_monitoring}}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    local result
    
    # Build psql command (same logic as execute_sql_query)
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
    
    # Execute query with JSON output format (-t removes headers, -A aligns, but we need raw JSON)
    # Use -t to remove headers, but keep the JSON intact
    if result=$(eval "${psql_cmd} -d ${dbname} -t -A -c \"${query}\"" 2>&1); then
        # Trim whitespace
        result=$(echo "${result}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "${result}"
        return 0
    else
        echo "Error: ${result}" >&2
        return 1
    fi
}

##
# Generate component health JSON file
##
generate_component_health_json() {
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/html"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    
    log_info "Generating component_health.json"
    
    mkdir -p "${dashboard_dir}"
    
    # Query to get component health as JSON
    local query="SELECT COALESCE(json_object_agg(component, json_build_object('status', status, 'last_check', last_check, 'last_success', last_success, 'error_count', error_count)), '{}'::json) FROM component_health;"
    
    # Execute query and get JSON result
    local result
    if result=$(execute_json_query "${query}" "${dbname}" 2>/dev/null); then
        # If result is empty, null, or {}, create default structure
        if [[ -z "${result}" ]] || [[ "${result}" == "null" ]] || [[ "${result}" == "{}" ]]; then
            result='{"ingestion":{"status":"unknown","last_check":null,"last_success":null,"error_count":0},"analytics":{"status":"unknown","last_check":null,"last_success":null,"error_count":0},"wms":{"status":"unknown","last_check":null,"last_success":null,"error_count":0},"api":{"status":"unknown","last_check":null,"last_success":null,"error_count":0},"data":{"status":"unknown","last_check":null,"last_success":null,"error_count":0},"infrastructure":{"status":"unknown","last_check":null,"last_success":null,"error_count":0}}'
        fi
        echo "${result}" > "${dashboard_dir}/component_health.json"
        log_info "✓ Generated component_health.json"
    else
        log_warning "Failed to generate component_health.json, creating default"
        # Create default structure if query fails
        cat > "${dashboard_dir}/component_health.json" <<'EOF'
{
  "ingestion": {"status": "unknown", "last_check": null, "last_success": null, "error_count": 0},
  "analytics": {"status": "unknown", "last_check": null, "last_success": null, "error_count": 0},
  "wms": {"status": "unknown", "last_check": null, "last_success": null, "error_count": 0},
  "api": {"status": "unknown", "last_check": null, "last_success": null, "error_count": 0},
  "data": {"status": "unknown", "last_check": null, "last_success": null, "error_count": 0},
  "infrastructure": {"status": "unknown", "last_check": null, "last_success": null, "error_count": 0}
}
EOF
    fi
}

##
# Generate recent alerts JSON file
##
generate_recent_alerts_json() {
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/html"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    
    log_info "Generating recent_alerts.json"
    
    mkdir -p "${dashboard_dir}"
    
    # Query to get recent alerts as JSON array
    local query="SELECT COALESCE(json_agg(json_build_object('id', id, 'component', component, 'severity', severity, 'message', message, 'timestamp', timestamp, 'resolved', resolved) ORDER BY timestamp DESC), '[]'::json) FROM alerts WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours' LIMIT 50;"
    
    # Execute query and get JSON result
    local result
    if result=$(execute_json_query "${query}" "${dbname}" 2>/dev/null); then
        # If result is empty or null, use empty array
        if [[ -z "${result}" ]] || [[ "${result}" == "null" ]]; then
            result="[]"
        fi
        echo "${result}" > "${dashboard_dir}/recent_alerts.json"
        log_info "✓ Generated recent_alerts.json"
    else
        log_warning "Failed to generate recent_alerts.json, creating empty array"
        echo "[]" > "${dashboard_dir}/recent_alerts.json"
    fi
}

##
# Update HTML dashboard data
#
# Arguments:
#   $1 - Component name (optional)
##
update_html_dashboard() {
    local component="${1:-}"
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/html"
    local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
    
    mkdir -p "${dashboard_dir}"
    
    if [[ -n "${component}" ]]; then
        log_info "Updating HTML dashboard for component: ${component}"
        "${metrics_script}" "${component}" json > "${dashboard_dir}/${component}_data.json" 2>/dev/null || true
    else
        log_info "Updating all HTML dashboards"
        local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
        
        for comp in "${components[@]}"; do
            log_info "Updating HTML dashboard for component: ${comp}"
            "${metrics_script}" "${comp}" json > "${dashboard_dir}/${comp}_data.json" 2>/dev/null || true
        done
        
        # Generate overview data
        log_info "Generating overview data"
        "${metrics_script}" all json > "${dashboard_dir}/overview_data.json" 2>/dev/null || true
        
        # Generate component health JSON
        generate_component_health_json
        
        # Generate recent alerts JSON
        generate_recent_alerts_json
    fi
    
    log_info "HTML dashboards updated"
}

##
# Update component health status
##
update_component_health() {
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    log_info "Updating component health status"
    
    local query="
        WITH latest_metrics AS (
            SELECT DISTINCT ON (component)
                component,
                timestamp,
                CASE 
                    WHEN COUNT(*) FILTER (WHERE metric_name LIKE '%error%' OR metric_name LIKE '%failure%') > 0 THEN 'degraded'
                    WHEN COUNT(*) FILTER (WHERE metric_name LIKE '%availability%' AND metric_value::numeric < 1) > 0 THEN 'down'
                    WHEN MAX(timestamp) < CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 'unknown'
                    ELSE 'healthy'
                END as status
            FROM metrics
            WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
            GROUP BY component, timestamp
            ORDER BY component, timestamp DESC
        )
        INSERT INTO component_health (component, status, last_check, last_success)
        SELECT 
            component,
            status,
            CURRENT_TIMESTAMP,
            CASE WHEN status = 'healthy' THEN CURRENT_TIMESTAMP ELSE last_success END
        FROM latest_metrics
        ON CONFLICT (component) DO UPDATE SET
            status = EXCLUDED.status,
            last_check = EXCLUDED.last_check,
            last_success = EXCLUDED.last_success,
            error_count = CASE 
                WHEN EXCLUDED.status != 'healthy' THEN component_health.error_count + 1
                ELSE 0
            END;
    "
    
    # Use PGPASSWORD only if set, otherwise let psql use default authentication
    if [[ -n "${PGPASSWORD:-}" ]]; then
        PGPASSWORD="${PGPASSWORD}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "${query}" > /dev/null 2>&1 || log_warning "Failed to update component health"
    else
        psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1 || log_warning "Failed to update component health"
    fi
}

##
# Main function
##
main() {
    local dashboard_type="${1:-all}"
    local component="${2:-}"
    local force_update="${3:-false}"
    
    # Load configuration
    load_config "${CONFIG_FILE:-}"
    
    # Update component health
    update_component_health
    
    # Update dashboards based on type
    case "${dashboard_type}" in
        grafana)
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/grafana/overview_metrics.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_grafana_dashboard "${component}"
            else
                log_info "Grafana dashboards are up to date"
            fi
            ;;
        html)
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/html/overview_data.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_html_dashboard "${component}"
            else
                log_info "HTML dashboards are up to date"
            fi
            ;;
        all)
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/html/overview_data.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_html_dashboard "${component}"
            fi
            if [[ "${force_update}" == "true" ]] || needs_update "${DASHBOARD_OUTPUT_DIR}/grafana/overview_metrics.json" "${DASHBOARD_UPDATE_INTERVAL}"; then
                update_grafana_dashboard "${component}"
            fi
            if [[ "${force_update}" != "true" ]]; then
                log_info "Dashboards are up to date"
            fi
            ;;
        *)
            log_error "Unknown dashboard type: ${dashboard_type}"
            usage
            exit 1
            ;;
    esac
    
    log_info "Dashboard update completed"
}

# Parse command line arguments
DASHBOARD_TYPE="all"
COMPONENT=""
FORCE_UPDATE="false"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
            shift
            ;;
        -q|--quiet)
            export LOG_LEVEL="${LOG_LEVEL_ERROR}"
            shift
            ;;
        -c|--config)
            export CONFIG_FILE="${2}"
            shift 2
            ;;
        -d|--dashboard)
            export DASHBOARD_OUTPUT_DIR="${2}"
            shift 2
            ;;
        --force)
            FORCE_UPDATE="true"
            shift
            ;;
        --component)
            COMPONENT="${2}"
            shift 2
            ;;
        *)
            DASHBOARD_TYPE="${1}"
            shift
            ;;
    esac
done

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "${DASHBOARD_TYPE}" "${COMPONENT}" "${FORCE_UPDATE}"
fi
