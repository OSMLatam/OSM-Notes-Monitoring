#!/usr/bin/env bash
#
# Metrics Functions Library
# Provides metrics collection and aggregation utilities
#
# Version: 1.0.0
# Date: 2025-12-24
#

# Source logging functions
# shellcheck disable=SC1091
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh" ]]; then
 source "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh"
fi

# Source monitoring functions for database access
# shellcheck disable=SC1091
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

 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -F '|' \
   -c "${query}" 2> /dev/null
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -F '|' \
   -c "${query}" 2> /dev/null
 fi
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
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  deleted_count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null)
 else
  deleted_count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null)
 fi

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

 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null
 fi
}

##
# Get metric value (alias for get_latest_metric_value for compatibility)
#
# Arguments:
#   $1 - Component name
#   $2 - Metric name
#   $3 - Hours back (default: 1)
#
# Returns:
#   Latest metric value via stdout
##
get_metric_value() {
 get_latest_metric_value "$@"
}

##
# Get all metrics for a component
#
# Arguments:
#   $1 - Component name
#   $2 - Hours back (default: 24)
#
# Returns:
#   Metrics via stdout (metric_name|metric_value|timestamp format)
##
get_metrics_by_component() {
 local component="${1:?Component required}"
 local hours_back="${2:-24}"
 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 local query
 query="SELECT metric_name, metric_value, timestamp
           FROM metrics
           WHERE component = '${component}'
             AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${hours_back} hours'
           ORDER BY timestamp DESC, metric_name;"

 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -F '|' \
   -c "${query}" 2> /dev/null
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -F '|' \
   -c "${query}" 2> /dev/null
 fi
}

##
# Record a metric (wrapper for store_metric with automatic unit detection)
#
# Arguments:
#   $1 - Component name
#   $2 - Metric name
#   $3 - Metric value
#   $4 - Metadata string (key=value pairs, comma-separated)
#
# Returns:
#   0 on success, 1 on failure
##
record_metric() {
 local component="${1:?Component required}"
 local metric_name="${2:?Metric name required}"
 local metric_value="${3:?Metric value required}"
 local metadata_string="${4:-}"

 # Determine unit from metric name suffix
 local metric_unit=""
 case "${metric_name}" in
 *_percent)
  metric_unit="percent"
  ;;
 *_ms)
  metric_unit="milliseconds"
  ;;
 *_seconds | *_duration)
  metric_unit="seconds"
  ;;
 *_hours)
  metric_unit="hours"
  ;;
 *_count | *_total | *_found | *_executable | *_running | *_errors | *_warnings | *_passes | *_failures)
  metric_unit="count"
  ;;
 *_bytes)
  metric_unit="bytes"
  ;;
 *_status | *_score)
  # Boolean or percentage status metrics
  if [[ "${metric_value}" == "0" ]] || [[ "${metric_value}" == "1" ]]; then
   metric_unit="boolean"
  else
   metric_unit="percent"
  fi
  ;;
 *)
  # Default: no unit
  metric_unit=""
  ;;
 esac

 # Convert metadata string to JSON
 local metadata_json="null"
 if [[ -n "${metadata_string}" ]]; then
  # Parse key=value pairs and convert to JSON
  local json_pairs=()
  IFS=',' read -ra pairs <<< "${metadata_string}"
  for pair in "${pairs[@]}"; do
   local key="${pair%%=*}"
   local value="${pair#*=}"
   # Trim whitespace
   key="${key#"${key%%[![:space:]]*}"}"
   key="${key%"${key##*[![:space:]]}"}"
   value="${value#"${value%%[![:space:]]*}"}"
   value="${value%"${value##*[![:space:]]}"}"
   # Escape quotes and backslashes in value for JSON
   value="${value//\\/\\\\}"
   value="${value//\"/\\\"}"
   json_pairs+=("\"${key}\":\"${value}\"")
  done
  metadata_json="{$(
   IFS=','
   echo "${json_pairs[*]}"
  )}"
 fi

 # Normalize component name (convert to lowercase)
 local component_lower
 component_lower=$(echo "${component}" | tr '[:upper:]' '[:lower:]')

 # Call store_metric
 if ! store_metric "${component_lower}" "${metric_name}" "${metric_value}" "${metric_unit}" "${metadata_json}"; then
  log_error "Failed to record metric: ${component}/${metric_name}"
  return 1
 fi

 return 0
}

##
# Aggregate metrics by time period
#
# Arguments:
#   $1 - Component name
#   $2 - Metric name
#   $3 - Aggregation type (avg, max, min, sum) or period (hour, day, week) for backward compatibility
#   $4 - Time period string (e.g., "24 hours") or period for backward compatibility
#
# Returns:
#   Aggregated metric value via stdout
##
aggregate_metrics() {
 local component="${1:?Component required}"
 local metric_name="${2:?Metric name required}"
 local aggregation_type="${3:-avg}"
 local time_period="${4:-24 hours}"
 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 # Check if third argument is a period (backward compatibility)
 if [[ "${aggregation_type}" =~ ^(hour|day|week)$ ]]; then
  # Old signature: aggregate_metrics component metric_name period
  local period="${aggregation_type}"
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

  # Use PGPASSWORD only if set, otherwise let psql use default authentication
  if [[ -n "${PGPASSWORD:-}" ]]; then
   PGPASSWORD="${PGPASSWORD}" psql \
    -h "${dbhost}" \
    -p "${dbport}" \
    -U "${dbuser}" \
    -d "${dbname}" \
    -t -A \
    -F '|' \
    -c "${query}" 2> /dev/null
  else
   psql \
    -h "${dbhost}" \
    -p "${dbport}" \
    -U "${dbuser}" \
    -d "${dbname}" \
    -t -A \
    -F '|' \
    -c "${query}" 2> /dev/null
  fi
  return 0
 fi

 # New signature: aggregate_metrics component metric_name aggregation_type time_period
 # Parse time period (e.g., "24 hours" -> INTERVAL '24 hours')
 local interval_expr
 if [[ "${time_period}" =~ ^([0-9]+)[[:space:]]+(hour|hours|day|days|week|weeks)$ ]]; then
  interval_expr="INTERVAL '${time_period}'"
 else
  interval_expr="INTERVAL '${time_period}'"
 fi

 # Determine aggregation function
 local agg_func
 case "${aggregation_type}" in
 avg | average)
  agg_func="AVG(metric_value)"
  ;;
 max | maximum)
  agg_func="MAX(metric_value)"
  ;;
 min | minimum)
  agg_func="MIN(metric_value)"
  ;;
 sum)
  agg_func="SUM(metric_value)"
  ;;
 *)
  log_error "Invalid aggregation type: ${aggregation_type}"
  return 1
  ;;
 esac

 local query
 query="SELECT ${agg_func}
           FROM metrics
           WHERE component = '${component}'
             AND metric_name = '${metric_name}'
             AND timestamp > CURRENT_TIMESTAMP - ${interval_expr};"

 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null
 fi
}

# Initialize on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
 init_metrics
fi
