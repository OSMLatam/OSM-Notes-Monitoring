#!/usr/bin/env bash
#
# Metrics Functions Library
# Provides metrics collection and aggregation utilities
#
# Version: 1.0.0
# Date: 2025-01-23
#

# Source logging functions
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh"
fi

# Source monitoring functions for database access
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/monitoringFunctions.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/monitoringFunctions.sh"
fi

##
# Initialize metrics functions
##
init_metrics() {
    # Metrics are initialized through monitoringFunctions
    return 0
}

##
# Get metrics summary for a component
#
# Arguments:
#   $1 - Component name
#   $2 - Hours back (default: 24)
#
# Returns:
#   Metrics summary via stdout (JSON format)
##
get_metrics_summary() {
    local component="${1:?Component required}"
    local hours_back="${2:-24}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    query="SELECT 
               metric_name,
               AVG(metric_value) as avg_value,
               MIN(metric_value) as min_value,
               MAX(metric_value) as max_value,
               COUNT(*) as sample_count
           FROM metrics
           WHERE component = '${component}'
             AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${hours_back} hours'
           GROUP BY metric_name
           ORDER BY metric_name;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -F '|' \
        -c "${query}" 2>/dev/null
}

##
# Clean up old metrics
#
# Arguments:
#   $1 - Retention days (default: 90)
#
# Returns:
#   0 on success, 1 on failure
##
cleanup_old_metrics() {
    local retention_days="${1:-90}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    log_info "Cleaning up metrics older than ${retention_days} days"
    
    # Use the cleanup function from init.sql
    local query
    query="SELECT cleanup_old_metrics(${retention_days});"
    
    local deleted_count
    deleted_count=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null)
    
    if [[ -n "${deleted_count}" ]]; then
        log_info "Cleaned up ${deleted_count} old metric records"
        return 0
    else
        log_error "Failed to cleanup old metrics"
        return 1
    fi
}

##
# Get metric value for a specific metric
#
# Arguments:
#   $1 - Component name
#   $2 - Metric name
#   $3 - Hours back (default: 1)
#
# Returns:
#   Latest metric value via stdout
##
get_latest_metric_value() {
    local component="${1:?Component required}"
    local metric_name="${2:?Metric name required}"
    local hours_back="${3:-1}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    query="SELECT metric_value
           FROM metrics
           WHERE component = '${component}'
             AND metric_name = '${metric_name}'
             AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${hours_back} hours'
           ORDER BY timestamp DESC
           LIMIT 1;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null
}

##
# Aggregate metrics by time period
#
# Arguments:
#   $1 - Component name
#   $2 - Metric name
#   $3 - Period (hour, day, week)
#
# Returns:
#   Aggregated metrics via stdout
##
aggregate_metrics() {
    local component="${1:?Component required}"
    local metric_name="${2:?Metric name required}"
    local period="${3:-hour}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    # Determine time grouping based on period
    local time_group
    case "${period}" in
        hour)
            time_group="DATE_TRUNC('hour', timestamp)"
            ;;
        day)
            time_group="DATE_TRUNC('day', timestamp)"
            ;;
        week)
            time_group="DATE_TRUNC('week', timestamp)"
            ;;
        *)
            log_error "Invalid period: ${period}"
            return 1
            ;;
    esac
    
    local query
    query="SELECT 
               ${time_group} as period,
               AVG(metric_value) as avg_value,
               MIN(metric_value) as min_value,
               MAX(metric_value) as max_value,
               COUNT(*) as sample_count
           FROM metrics
           WHERE component = '${component}'
             AND metric_name = '${metric_name}'
           GROUP BY ${time_group}
           ORDER BY period DESC;"
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -F '|' \
        -c "${query}" 2>/dev/null
}

# Initialize on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_metrics
fi

