#!/usr/bin/env bash
#
# Datamart Metrics Collection Script
# Collects metrics from the OSM-Notes-Analytics datamart processes
#
# Version: 1.0.0
# Date: 2026-01-09
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
# Set TEST_MODE temporarily to prevent COMPONENT from being readonly
original_test_mode="${TEST_MODE:-false}"
export TEST_MODE="true"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/datamartLogParser.sh"

# Restore TEST_MODE and set COMPONENT to lowercase
export TEST_MODE="${original_test_mode}"
COMPONENT="analytics"
export COMPONENT

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging only if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 init_logging "${LOG_DIR}/datamart_metrics.log" "collectDatamartMetrics"
fi

# Datamart log file patterns (allow override in test mode)
if [[ "${TEST_MODE:-false}" != "true" ]]; then
 readonly DATAMART_COUNTRIES_PATTERN="${DATAMART_COUNTRIES_PATTERN:-/tmp/datamartCountries_*/datamartCountries.log}"
 readonly DATAMART_USERS_PATTERN="${DATAMART_USERS_PATTERN:-/tmp/datamartUsers_*/datamartUsers.log}"
 readonly DATAMART_GLOBAL_PATTERN="${DATAMART_GLOBAL_PATTERN:-/tmp/datamartGlobal_*/datamartGlobal.log}"
else
 DATAMART_COUNTRIES_PATTERN="${DATAMART_COUNTRIES_PATTERN:-/tmp/datamartCountries_*/datamartCountries.log}"
 DATAMART_USERS_PATTERN="${DATAMART_USERS_PATTERN:-/tmp/datamartUsers_*/datamartUsers.log}"
 DATAMART_GLOBAL_PATTERN="${DATAMART_GLOBAL_PATTERN:-/tmp/datamartGlobal_*/datamartGlobal.log}"
fi

##
# Show usage
##
usage() {
 cat << EOF
Datamart Metrics Collection Script

Collects metrics from the OSM-Notes-Analytics datamart processes.

Usage: $0 [OPTIONS]

Options:
    -h, --help            Show this help message

Examples:
    # Collect all datamart metrics
    $0
EOF
}

##
# Check datamart process status
##
check_datamart_process_status() {
 local datamart_name="${1:?Datamart name required}"
 local process_running=0
 local process_pid=0

 # Check if datamart process is running
 if pgrep -f "datamart${datamart_name^}.sh" > /dev/null 2>&1; then
  process_running=1
  process_pid=$(pgrep -f "datamart${datamart_name^}.sh" | head -1 || echo "0")
 fi

 record_metric "${COMPONENT}" "datamart_process_running" "${process_running}" "component=analytics,datamart=\"${datamart_name}\""
 if [[ ${process_running} -eq 1 ]]; then
  record_metric "${COMPONENT}" "datamart_process_pid" "${process_pid}" "component=analytics,datamart=\"${datamart_name}\""
  log_info "${COMPONENT}: Datamart ${datamart_name} process is running (PID: ${process_pid})"
 else
  log_info "${COMPONENT}: Datamart ${datamart_name} process is not running"
 fi

 return 0
}

##
# Collect datamart log metrics
##
collect_datamart_log_metrics() {
 log_info "${COMPONENT}: Starting datamart log analysis"

 # Parse all datamart logs using the parser library
 if parse_all_datamart_logs; then
  log_info "${COMPONENT}: Datamart log analysis completed"
  return 0
 else
  log_warning "${COMPONENT}: Datamart log analysis failed or no logs found"
  return 1
 fi
}

##
# Check datamart freshness from database and logs
##
check_datamart_freshness() {
 log_info "${COMPONENT}: Checking datamart freshness from database and logs"

 # Check database connection first
 if command -v check_database_connection > /dev/null 2>&1; then
  if ! check_database_connection; then
   log_error "${COMPONENT}: Database connection failed, skipping freshness check"
   return 1
  fi
 fi

 # Map datamart names to table names and log patterns
 local datamart_config=(
  "countries:datamartcountries:${DATAMART_COUNTRIES_PATTERN}"
  "users:datamartusers:${DATAMART_USERS_PATTERN}"
  "global:datamartglobal:${DATAMART_GLOBAL_PATTERN}"
 )

 for config in "${datamart_config[@]}"; do
  IFS=':' read -r datamart_name table_name _ <<< "${config}"
  # Third field (log_pattern) is not used, we use find directly

  # Check freshness from log file modification time
  local freshness_seconds=0
  local log_file
  # Find the most recent log file matching the pattern
  log_file=$(find /tmp -maxdepth 2 -path "*/datamart${datamart_name^}*/datamart${datamart_name^}.log" -type f -printf '%T@ %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2- || echo "")

  if [[ -n "${log_file}" && -f "${log_file}" ]]; then
   local log_mtime
   log_mtime=$(stat -c %Y "${log_file}" 2> /dev/null || echo "0")
   local current_time
   current_time=$(date +%s)
   freshness_seconds=$((current_time - log_mtime))
  fi

  # Also get row count from database
  local row_count=0
  # Use ANALYTICS_DBNAME if available, otherwise default to notes_dwh
  local analytics_dbname="${ANALYTICS_DBNAME:-notes_dwh}"
  local analytics_dbuser="${ANALYTICS_DBUSER:-osm_notes_analytics_user}"

  # Try to get row count, but don't fail if database is not accessible
  local query="SELECT COUNT(*)::bigint FROM dwh.${table_name};"
  local result=""

  # Temporarily override DBUSER for this query
  local original_dbuser="${DBUSER:-}"
  export DBUSER="${analytics_dbuser}"
  result=$(execute_sql_query "${query}" "${analytics_dbname}" 2> /dev/null || echo "")
  export DBUSER="${original_dbuser}"

  if [[ -n "${result}" ]]; then
   row_count=$(echo "${result}" | tr -d '[:space:]' || echo "0")
  fi

  # Record freshness metric
  if [[ "${freshness_seconds}" =~ ^[0-9]+$ ]]; then
   record_metric "${COMPONENT}" "datamart_freshness_seconds" "${freshness_seconds}" "component=analytics,datamart=\"${datamart_name}\""
   log_info "${COMPONENT}: Datamart ${datamart_name} freshness: ${freshness_seconds} seconds (rows: ${row_count})"
  fi

  # Record row count metric
  if [[ "${row_count}" =~ ^[0-9]+$ ]] && [[ ${row_count} -gt 0 ]]; then
   record_metric "${COMPONENT}" "datamart_records_total" "${row_count}" "component=analytics,datamart=\"${datamart_name}\""
  fi
 done

 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting datamart metrics collection"

 # Ensure HOME is set (important for .pgpass)
 if [[ -z "${HOME:-}" ]]; then
  local home_dir
  home_dir=$(getent passwd "${USER:-$(whoami)}" | cut -d: -f6 2> /dev/null || echo "/home/${USER:-$(whoami)}")
  export HOME="${home_dir}"
 fi

 # Ensure PGPASSFILE is set if .pgpass exists
 if [[ -z "${PGPASSFILE:-}" ]] && [[ -f "${HOME}/.pgpass" ]]; then
  export PGPASSFILE="${HOME}/.pgpass"
 fi

 # Load configuration
 if ! load_monitoring_config; then
  log_error "${COMPONENT}: Failed to load monitoring configuration"
  exit 1
 fi

 # Check process status for each datamart
 check_datamart_process_status "countries"
 check_datamart_process_status "users"
 check_datamart_process_status "global"

 # Collect log metrics
 collect_datamart_log_metrics

 # Check freshness from database
 check_datamart_freshness

 log_info "${COMPONENT}: Datamart metrics collection completed"
 return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
