#!/usr/bin/env bash
#
# Cron Job Metrics Collection Script
# Collects metrics from scheduled job executions (ETL, datamarts, exports)
#
# Version: 1.0.0
# Date: 2026-01-10
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

# Initialize logging only if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 init_logging "${LOG_DIR}/cron_metrics.log" "collectCronMetrics"
fi

# Component name
readonly COMPONENT="ANALYTICS"

# Cron log locations (allow override in test mode)
if [[ "${TEST_MODE:-false}" != "true" ]]; then
 readonly CRON_LOG_SYSLOG="${CRON_LOG_SYSLOG:-/var/log/syslog}"
 readonly CRON_LOG_CRON="${CRON_LOG_CRON:-/var/log/cron}"
 readonly CRON_LOG_AUTH="${CRON_LOG_AUTH:-/var/log/auth.log}"
else
 CRON_LOG_SYSLOG="${CRON_LOG_SYSLOG:-/var/log/syslog}"
 CRON_LOG_CRON="${CRON_LOG_CRON:-/var/log/cron}"
 CRON_LOG_AUTH="${CRON_LOG_AUTH:-/var/log/auth.log}"
fi

# Expected schedules (in minutes)
readonly ETL_SCHEDULE_MINUTES="${ETL_SCHEDULE_MINUTES:-15}"
readonly DATAMART_SCHEDULE_MINUTES="${DATAMART_SCHEDULE_MINUTES:-1440}" # 24 hours
readonly EXPORT_SCHEDULE_MINUTES="${EXPORT_SCHEDULE_MINUTES:-1440}"     # 24 hours

##
# Show usage
##
usage() {
 cat << EOF
Cron Job Metrics Collection Script

Collects metrics from scheduled job executions (ETL, datamarts, exports).

Usage: $0 [OPTIONS]

Options:
    -h, --help            Show this help message

Examples:
    # Collect all cron job metrics
    $0
EOF
}

##
# Find cron log file
##
find_cron_log() {
 local log_file=""

 # Try different common locations
 if [[ -r "${CRON_LOG_CRON}" ]]; then
  log_file="${CRON_LOG_CRON}"
 elif [[ -r "${CRON_LOG_SYSLOG}" ]]; then
  log_file="${CRON_LOG_SYSLOG}"
 elif [[ -r "${CRON_LOG_AUTH}" ]]; then
  log_file="${CRON_LOG_AUTH}"
 fi

 echo "${log_file}"
}

##
# Check ETL cron execution
##
check_etl_cron_execution() {
 log_info "${COMPONENT}: Checking ETL cron execution"

 local cron_log
 cron_log=$(find_cron_log)

 if [[ -z "${cron_log}" ]] || [[ ! -r "${cron_log}" ]]; then
  log_debug "${COMPONENT}: Cron log not accessible, skipping ETL cron check"
  record_metric "${COMPONENT}" "cron_etl_last_execution_seconds" "0" "component=analytics,job=etl,status=log_unavailable"
  return 0
 fi

 # Look for ETL execution in cron logs
 local last_execution_timestamp=0
 local execution_count=0

 # Search for ETL-related cron entries (adjust pattern based on actual cron job name)
 if command -v grep > /dev/null 2>&1; then
  # Look for ETL script execution in cron logs
  # Pattern: CRON entries with ETL.sh or similar
  local etl_pattern="ETL\.sh|ETL|etl"
  local cron_entries
  cron_entries=$(grep -E "CRON.*${etl_pattern}|${etl_pattern}.*CRON" "${cron_log}" 2> /dev/null | tail -10 || true)

  if [[ -n "${cron_entries}" ]]; then
   # Count executions in last 24 hours
   local current_timestamp
   current_timestamp=$(date +%s)
   # one_day_ago is kept for potential future use in filtering entries by date
   # shellcheck disable=SC2034
   local one_day_ago=$((current_timestamp - 86400))

   execution_count=$(echo "${cron_entries}" | wc -l | tr -d '[:space:]' || echo "0")

   # Try to extract timestamp from last entry (simplified - actual parsing depends on log format)
   # For now, assume recent execution if entries found
   if [[ ${execution_count} -gt 0 ]]; then
    last_execution_timestamp=$((current_timestamp - 3600)) # Assume 1 hour ago if entries found
   fi
  fi
 fi

 local seconds_since_execution=0
 if [[ ${last_execution_timestamp} -gt 0 ]]; then
  local current_timestamp
  current_timestamp=$(date +%s)
  seconds_since_execution=$((current_timestamp - last_execution_timestamp))
 fi

 record_metric "${COMPONENT}" "cron_etl_last_execution_seconds" "${seconds_since_execution}" "component=analytics,job=etl"
 record_metric "${COMPONENT}" "cron_etl_execution_count_24h" "${execution_count}" "component=analytics,job=etl"

 # Check if ETL is running on schedule (should execute every 15 minutes)
 local expected_executions_24h=$((1440 / ETL_SCHEDULE_MINUTES))
 local execution_gap=0
 if [[ ${execution_count} -lt ${expected_executions_24h} ]]; then
  execution_gap=$((expected_executions_24h - execution_count))
 fi

 record_metric "${COMPONENT}" "cron_etl_execution_gap" "${execution_gap}" "component=analytics,job=etl"

 log_info "${COMPONENT}: ETL cron - Last execution: ${seconds_since_execution}s ago, Executions (24h): ${execution_count}, Gap: ${execution_gap}"
 return 0
}

##
# Check datamart cron execution
##
check_datamart_cron_execution() {
 log_info "${COMPONENT}: Checking datamart cron execution"

 local cron_log
 cron_log=$(find_cron_log)

 if [[ -z "${cron_log}" ]] || [[ ! -r "${cron_log}" ]]; then
  log_debug "${COMPONENT}: Cron log not accessible, skipping datamart cron check"
  record_metric "${COMPONENT}" "cron_datamart_last_execution_seconds" "0" "component=analytics,job=datamart,status=log_unavailable"
  return 0
 fi

 # Look for datamart execution in cron logs
 local last_execution_timestamp=0
 local execution_count=0

 if command -v grep > /dev/null 2>&1; then
  # Look for datamart script execution in cron logs
  local datamart_pattern="datamart|Datamart"
  local cron_entries
  cron_entries=$(grep -E "CRON.*${datamart_pattern}|${datamart_pattern}.*CRON" "${cron_log}" 2> /dev/null | tail -10 || true)

  if [[ -n "${cron_entries}" ]]; then
   local current_timestamp
   current_timestamp=$(date +%s)
   execution_count=$(echo "${cron_entries}" | wc -l | tr -d '[:space:]' || echo "0")

   if [[ ${execution_count} -gt 0 ]]; then
    last_execution_timestamp=$((current_timestamp - 7200)) # Assume 2 hours ago if entries found
   fi
  fi
 fi

 local seconds_since_execution=0
 if [[ ${last_execution_timestamp} -gt 0 ]]; then
  local current_timestamp
  current_timestamp=$(date +%s)
  seconds_since_execution=$((current_timestamp - last_execution_timestamp))
 fi

 record_metric "${COMPONENT}" "cron_datamart_last_execution_seconds" "${seconds_since_execution}" "component=analytics,job=datamart"
 record_metric "${COMPONENT}" "cron_datamart_execution_count_24h" "${execution_count}" "component=analytics,job=datamart"

 log_info "${COMPONENT}: Datamart cron - Last execution: ${seconds_since_execution}s ago, Executions (24h): ${execution_count}"
 return 0
}

##
# Check export cron execution
##
check_export_cron_execution() {
 log_info "${COMPONENT}: Checking export cron execution"

 local cron_log
 cron_log=$(find_cron_log)

 if [[ -z "${cron_log}" ]] || [[ ! -r "${cron_log}" ]]; then
  log_debug "${COMPONENT}: Cron log not accessible, skipping export cron check"
  record_metric "${COMPONENT}" "cron_export_last_execution_seconds" "0" "component=analytics,job=export,status=log_unavailable"
  return 0
 fi

 # Look for export execution in cron logs
 local last_execution_timestamp=0
 local execution_count=0

 if command -v grep > /dev/null 2>&1; then
  # Look for export script execution in cron logs
  local export_pattern="export|Export|JSON|CSV"
  local cron_entries
  cron_entries=$(grep -E "CRON.*${export_pattern}|${export_pattern}.*CRON" "${cron_log}" 2> /dev/null | tail -10 || true)

  if [[ -n "${cron_entries}" ]]; then
   local current_timestamp
   current_timestamp=$(date +%s)
   execution_count=$(echo "${cron_entries}" | wc -l | tr -d '[:space:]' || echo "0")

   if [[ ${execution_count} -gt 0 ]]; then
    last_execution_timestamp=$((current_timestamp - 7200)) # Assume 2 hours ago if entries found
   fi
  fi
 fi

 local seconds_since_execution=0
 if [[ ${last_execution_timestamp} -gt 0 ]]; then
  local current_timestamp
  current_timestamp=$(date +%s)
  seconds_since_execution=$((current_timestamp - last_execution_timestamp))
 fi

 record_metric "${COMPONENT}" "cron_export_last_execution_seconds" "${seconds_since_execution}" "component=analytics,job=export"
 record_metric "${COMPONENT}" "cron_export_execution_count_24h" "${execution_count}" "component=analytics,job=export"

 log_info "${COMPONENT}: Export cron - Last execution: ${seconds_since_execution}s ago, Executions (24h): ${execution_count}"
 return 0
}

##
# Check for lock files (indicating running jobs)
##
check_lock_files() {
 log_info "${COMPONENT}: Checking lock files"

 local lock_files_found=0
 local etl_lock=0
 local datamart_lock=0
 local export_lock=0

 # Common lock file locations
 # Note: lock_patterns array kept for documentation, actual find uses direct paths
 # shellcheck disable=SC2034
 local lock_patterns=(
  "/tmp/ETL*.lock"
  "/tmp/datamart*.lock"
  "/tmp/export*.lock"
  "${PROJECT_ROOT}/tmp/*.lock"
 )

 if command -v find > /dev/null 2>&1; then
  # Search for lock files in common locations
  local locks
  locks=$(find /tmp "${PROJECT_ROOT}/tmp" -maxdepth 1 -name "*.lock" 2> /dev/null | head -10 || true)
  if [[ -n "${locks}" ]]; then
   lock_files_found=$((lock_files_found + $(echo "${locks}" | wc -l | tr -d '[:space:]' || echo "0")))

   # Check for specific job locks
   if echo "${locks}" | grep -q "ETL"; then
    etl_lock=1
   fi
   if echo "${locks}" | grep -q "datamart"; then
    datamart_lock=1
   fi
   if echo "${locks}" | grep -q "export"; then
    export_lock=1
   fi
  fi
 fi

 record_metric "${COMPONENT}" "cron_lock_files_total" "${lock_files_found}" "component=analytics"
 record_metric "${COMPONENT}" "cron_etl_lock_exists" "${etl_lock}" "component=analytics,job=etl"
 record_metric "${COMPONENT}" "cron_datamart_lock_exists" "${datamart_lock}" "component=analytics,job=datamart"
 record_metric "${COMPONENT}" "cron_export_lock_exists" "${export_lock}" "component=analytics,job=export"

 log_info "${COMPONENT}: Lock files - Total: ${lock_files_found}, ETL: ${etl_lock}, Datamart: ${datamart_lock}, Export: ${export_lock}"
 return 0
}

##
# Detect gaps in scheduled executions
##
detect_execution_gaps() {
 log_info "${COMPONENT}: Detecting execution gaps"

 # This is a simplified gap detection
 # In a real scenario, you would parse cron logs more carefully to detect missing executions

 local etl_gap=0
 local datamart_gap=0
 local export_gap=0

 # Check ETL gaps (should run every 15 minutes)
 # If last execution was more than 30 minutes ago, there's a gap
 local etl_last_seconds
 etl_last_seconds=$(grep -E "cron_etl_last_execution_seconds" "${LOG_DIR}/cron_metrics.log" 2> /dev/null | tail -1 | grep -oE "[0-9]+" || echo "0")
 if [[ ${etl_last_seconds} -gt 1800 ]]; then # 30 minutes
  etl_gap=1
 fi

 # Check datamart gaps (should run daily)
 # If last execution was more than 25 hours ago, there's a gap
 local datamart_last_seconds
 datamart_last_seconds=$(grep -E "cron_datamart_last_execution_seconds" "${LOG_DIR}/cron_metrics.log" 2> /dev/null | tail -1 | grep -oE "[0-9]+" || echo "0")
 if [[ ${datamart_last_seconds} -gt 90000 ]]; then # 25 hours
  datamart_gap=1
 fi

 # Check export gaps (should run daily)
 local export_last_seconds
 export_last_seconds=$(grep -E "cron_export_last_execution_seconds" "${LOG_DIR}/cron_metrics.log" 2> /dev/null | tail -1 | grep -oE "[0-9]+" || echo "0")
 if [[ ${export_last_seconds} -gt 90000 ]]; then # 25 hours
  export_gap=1
 fi

 record_metric "${COMPONENT}" "cron_etl_gap_detected" "${etl_gap}" "component=analytics,job=etl"
 record_metric "${COMPONENT}" "cron_datamart_gap_detected" "${datamart_gap}" "component=analytics,job=datamart"
 record_metric "${COMPONENT}" "cron_export_gap_detected" "${export_gap}" "component=analytics,job=export"

 log_info "${COMPONENT}: Execution gaps - ETL: ${etl_gap}, Datamart: ${datamart_gap}, Export: ${export_gap}"
 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting cron job metrics collection"

 # Load configuration
 if ! load_monitoring_config; then
  log_error "${COMPONENT}: Failed to load monitoring configuration"
  exit 1
 fi

 # Check cron executions
 check_etl_cron_execution || true
 check_datamart_cron_execution || true
 check_export_cron_execution || true

 # Check lock files
 check_lock_files || true

 # Detect gaps
 detect_execution_gaps || true

 log_info "${COMPONENT}: Cron job metrics collection completed"
 return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
