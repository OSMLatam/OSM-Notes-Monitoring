#!/usr/bin/env bash
#
# Generate Metrics Script
# Generates metrics data for dashboards
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
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Only initialize logging if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 # Initialize logging
 init_logging "${LOG_DIR}/generate_metrics.log" "generateMetrics"
fi

##
# Show usage
##
usage() {
 cat << EOF
Generate Metrics Script

Usage: ${0} [OPTIONS] [COMPONENT] [OUTPUT_FORMAT]

Arguments:
    COMPONENT         Component name (INGESTION, ANALYTICS, WMS, API, INFRASTRUCTURE, or 'all')
    OUTPUT_FORMAT     Output format (json, csv, or 'dashboard') (default: json)

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    -o, --output FILE   Output file (default: stdout)
    --time-range HOURS  Time range in hours (default: 24)
    --component COMP    Filter by component

Examples:
    ${0} all json                    # Generate all metrics as JSON
    ${0} INGESTION dashboard         # Generate ingestion metrics for dashboard
    ${0} --time-range 168 all json  # Generate metrics for last 7 days
    ${0} -o metrics.json all json  # Save to file

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
 export METRICS_TIME_RANGE_HOURS="${METRICS_TIME_RANGE_HOURS:-24}"
 export METRICS_OUTPUT_DIR="${METRICS_OUTPUT_DIR:-${PROJECT_ROOT}/metrics}"
}

##
# Generate metrics for a component
#
# Arguments:
#   $1 - Component name
#   $2 - Time range in hours
#   $3 - Output format
##
generate_component_metrics() {
 local component="${1:?Component required}"
 local time_range_hours="${2:-24}"
 local output_format="${3:-json}"
 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 # Convert component to lowercase for database constraint
 local component_lower
 component_lower=$(echo "${component}" | tr '[:upper:]' '[:lower:]')

 local query="SELECT 
                   metric_name,
                   metric_value,
                   metadata,
                   timestamp
                 FROM metrics
                 WHERE component = '${component_lower}'
                   AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${time_range_hours} hours'
                 ORDER BY timestamp DESC;"

 case "${output_format}" in
 json)
  generate_json_metrics "${component}" "${query}" "${dbname}" "${dbhost}" "${dbport}" "${dbuser}"
  ;;
 csv)
  generate_csv_metrics "${component}" "${query}" "${dbname}" "${dbhost}" "${dbport}" "${dbuser}"
  ;;
 dashboard)
  generate_dashboard_metrics "${component}" "${query}" "${dbname}" "${dbhost}" "${dbport}" "${dbuser}"
  ;;
 *)
  log_error "Unknown output format: ${output_format}"
  return 1
  ;;
 esac
}

##
# Generate JSON metrics
##
generate_json_metrics() {
 local component="${1}"
 local query="${2}"
 local dbname="${3}"
 local dbhost="${4}"
 local dbport="${5}"
 local dbuser="${6}"

 # Use psql with JSON output
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "SELECT json_agg(row_to_json(t)) FROM (${query}) t;" 2> /dev/null || echo "[]"
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "SELECT json_agg(row_to_json(t)) FROM (${query}) t;" 2> /dev/null || echo "[]"
 fi
}

##
# Generate CSV metrics
##
generate_csv_metrics() {
 local component="${1}"
 local query="${2}"
 local dbname="${3}"
 local dbhost="${4}"
 local dbport="${5}"
 local dbuser="${6}"

 # Header
 echo "metric_name,metric_value,metadata,timestamp"

 # Data
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -F "," \
   -c "${query}" 2> /dev/null || true
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -F "," \
   -c "${query}" 2> /dev/null || true
 fi
}

##
# Generate dashboard-formatted metrics
##
generate_dashboard_metrics() {
 local component="${1}"
 local query="${2}"
 local dbname="${3}"
 local dbhost="${4}"
 local dbport="${5}"
 local dbuser="${6}"

 # Convert component to lowercase for database constraint
 local component_lower
 component_lower=$(echo "${component}" | tr '[:upper:]' '[:lower:]')

 # Aggregate metrics by name for dashboard
 local dashboard_query="SELECT 
                            metric_name,
                            COUNT(*) as count,
                            AVG(metric_value::numeric) as avg_value,
                            MIN(metric_value::numeric) as min_value,
                            MAX(metric_value::numeric) as max_value,
                            MAX(timestamp) as last_update
                          FROM metrics
                          WHERE component = '${component_lower}'
                            AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
                          GROUP BY metric_name
                          ORDER BY metric_name;"

 # Output as JSON for dashboard consumption
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "SELECT json_agg(row_to_json(t)) FROM (${dashboard_query}) t;" 2> /dev/null || echo "[]"
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "SELECT json_agg(row_to_json(t)) FROM (${dashboard_query}) t;" 2> /dev/null || echo "[]"
 fi
}

##
# Generate all component metrics
##
generate_all_metrics() {
 local time_range_hours="${1:-24}"
 local output_format="${2:-json}"

 local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
 local output="{"
 local first=true

 for component in "${components[@]}"; do
  if [[ "${first}" == "true" ]]; then
   first=false
  else
   output="${output},"
  fi

  local component_metrics
  component_metrics=$(generate_component_metrics "${component}" "${time_range_hours}" "${output_format}" 2> /dev/null || echo "[]")

  output="${output}\"${component}\": ${component_metrics}"
 done

 output="${output}}"
 echo "${output}"
}

##
# Main function
##
main() {
 local component="${1:-all}"
 local output_format="${2:-json}"
 local output_file="${3:-}"
 local time_range_hours="${4:-24}"

 # Load configuration
 load_config "${CONFIG_FILE:-}"

 # Override time range if provided
 if [[ -n "${4:-}" ]]; then
  time_range_hours="${4}"
 fi

 # Generate metrics
 local metrics_output
 if [[ "${component}" == "all" ]]; then
  metrics_output=$(generate_all_metrics "${time_range_hours}" "${output_format}")
 else
  metrics_output=$(generate_component_metrics "${component}" "${time_range_hours}" "${output_format}")
 fi

 # Output to file or stdout
 if [[ -n "${output_file}" ]]; then
  echo "${metrics_output}" > "${output_file}"
  log_info "Metrics written to ${output_file}"
 else
  echo "${metrics_output}"
 fi
}

# Parse command line arguments only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 OUTPUT_FILE=""
 TIME_RANGE=""
 COMPONENT=""
 OUTPUT_FORMAT="" # Initialize as empty, set default after parsing

 while [[ $# -gt 0 ]]; do
  case "${1}" in
  -h | --help)
   usage
   exit 0
   ;;
  -v | --verbose)
   export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
   shift
   ;;
  -q | --quiet)
   export LOG_LEVEL="${LOG_LEVEL_ERROR}"
   shift
   ;;
  -c | --config)
   export CONFIG_FILE="${2}"
   shift 2
   ;;
  -o | --output)
   OUTPUT_FILE="${2}"
   shift 2
   ;;
  --time-range)
   TIME_RANGE="${2}"
   shift 2
   ;;
  --component)
   COMPONENT="${2}"
   shift 2
   ;;
  --*)
   # Unknown option starting with --
   echo "ERROR: Unknown option: ${1}" >&2
   usage
   exit 1
   ;;
  *)
   # If --component was already set, treat remaining positional args as format/output
   if [[ -z "${COMPONENT}" ]]; then
    COMPONENT="${1}"
   elif [[ -z "${OUTPUT_FORMAT}" ]]; then
    OUTPUT_FORMAT="${1}"
   elif [[ -z "${OUTPUT_FILE}" ]]; then
    OUTPUT_FILE="${1}"
   fi
   shift
   ;;
  esac
 done

 # Set default OUTPUT_FORMAT if not provided
 OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"

 # If --component was specified, use it; otherwise use positional argument or default to "all"
 FINAL_COMPONENT="${COMPONENT:-${1:-all}}"
 # If COMPONENT was set via --component, skip first positional arg (it's the component)
 if [[ -n "${COMPONENT}" ]] && [[ $# -gt 0 ]]; then
  shift # Skip first positional arg since we're using --component value
 fi
 # Get output format from remaining args or default
 FINAL_FORMAT="${OUTPUT_FORMAT:-${1:-json}}"
 main "${FINAL_COMPONENT}" "${FINAL_FORMAT}" "${OUTPUT_FILE}" "${TIME_RANGE:-24}"
fi
