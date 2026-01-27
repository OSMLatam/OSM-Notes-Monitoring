#!/usr/bin/env bash
#
# ETL Metrics Collection Script
# Collects metrics from the OSM-Notes-Analytics ETL process
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

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging
init_logging "${LOG_DIR}/etl_metrics.log" "collect_etl_metrics"

# Component name
readonly COMPONENT="ANALYTICS"

# ETL log file pattern
readonly ETL_LOG_PATTERN="${ETL_LOG_PATTERN:-/tmp/ETL_*/ETL.log}"

# ETL lock file pattern
readonly ETL_LOCK_PATTERN="${ETL_LOCK_PATTERN:-/tmp/ETL_*/ETL.lock}"

# ETL recovery file pattern
readonly ETL_RECOVERY_PATTERN="${ETL_RECOVERY_PATTERN:-/tmp/ETL_*/ETL_recovery.json}"

##
# Find ETL log files
##
find_etl_log_files() {
 local log_files=()
 local found_files

 # Find all matching log files
 found_files=$(find /tmp -maxdepth 2 -type f -path "*/ETL_*/ETL.log" 2> /dev/null || true)

 if [[ -z "${found_files}" ]]; then
  log_debug "${COMPONENT}: No ETL log files found matching pattern ${ETL_LOG_PATTERN}"
  return 1
 fi

 # Convert to array
 while IFS= read -r file; do
  if [[ -f "${file}" ]] && [[ -r "${file}" ]]; then
   log_files+=("${file}")
  fi
 done <<< "${found_files}"

 # Return most recent log file
 if [[ ${#log_files[@]} -gt 0 ]]; then
  # Sort by modification time and get most recent
  local most_recent=""
  local most_recent_time=0

  for file in "${log_files[@]}"; do
   local file_time
   file_time=$(stat -c %Y "${file}" 2> /dev/null || stat -f %m "${file}" 2> /dev/null || echo "0")
   if [[ ${file_time} -gt ${most_recent_time} ]]; then
    most_recent_time=${file_time}
    most_recent="${file}"
   fi
  done

  echo "${most_recent}"
  return 0
 fi

 return 1
}

##
# Check ETL process status
##
check_etl_process_status() {
 local etl_running=0
 local etl_pid=0
 local etl_uptime=0

 # Check if ETL process is running
 if pgrep -f "ETL.sh" > /dev/null 2>&1; then
  etl_running=1
  local pids
  pids=$(pgrep -f "ETL.sh" | head -1)
  etl_pid=${pids:-0}

  # Get uptime if PID is valid
  if [[ ${etl_pid} -gt 0 ]]; then
   local etime
   etime=$(ps -o etime= -p "${etl_pid}" 2> /dev/null | tr -d '[:space:]' || echo "0:0")

   # Convert etime to seconds (format: HH:MM:SS or MM:SS)
   if [[ "${etime}" =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    local hours="${BASH_REMATCH[1]}"
    local minutes="${BASH_REMATCH[2]}"
    local seconds="${BASH_REMATCH[3]}"
    etl_uptime=$((hours * 3600 + minutes * 60 + seconds))
   elif [[ "${etime}" =~ ^([0-9]+):([0-9]+)$ ]]; then
    local minutes="${BASH_REMATCH[1]}"
    local seconds="${BASH_REMATCH[2]}"
    etl_uptime=$((minutes * 60 + seconds))
   fi
  fi
 fi

 # Record metrics
 record_metric "${COMPONENT}" "etl_up" "${etl_running}" "component=analytics,status=${etl_running}"
 record_metric "${COMPONENT}" "etl_pid" "${etl_pid}" "component=analytics"
 record_metric "${COMPONENT}" "etl_uptime_seconds" "${etl_uptime}" "component=analytics"

 log_info "${COMPONENT}: ETL process status - Running: ${etl_running}, PID: ${etl_pid}, Uptime: ${etl_uptime}s"

 return 0
}

##
# Check ETL lock files
##
check_etl_lock_files() {
 local lock_files=()
 local found_files

 # Find all matching lock files
 found_files=$(find /tmp -maxdepth 2 -type f -path "*/ETL_*/ETL.lock" 2> /dev/null || true)

 if [[ -z "${found_files}" ]]; then
  log_debug "${COMPONENT}: No ETL lock files found"
  record_metric "${COMPONENT}" "etl_lock_files_count" "0" "component=analytics"
  return 0
 fi

 # Count lock files
 local lock_count=0
 while IFS= read -r file; do
  if [[ -f "${file}" ]]; then
   lock_count=$((lock_count + 1))
   lock_files+=("${file}")
  fi
 done <<< "${found_files}"

 # Check for concurrent executions (multiple lock files)
 local concurrent_executions=0
 if [[ ${lock_count} -gt 1 ]]; then
  concurrent_executions=1
  log_warning "${COMPONENT}: Multiple ETL lock files detected (${lock_count}), possible concurrent executions"
 fi

 # Record metrics
 record_metric "${COMPONENT}" "etl_lock_files_count" "${lock_count}" "component=analytics"
 record_metric "${COMPONENT}" "etl_concurrent_executions" "${concurrent_executions}" "component=analytics"

 log_info "${COMPONENT}: ETL lock files - Count: ${lock_count}, Concurrent: ${concurrent_executions}"

 return 0
}

##
# Check ETL recovery files
##
check_etl_recovery_files() {
 local found_files

 # Find all matching recovery files
 found_files=$(find /tmp -maxdepth 2 -type f -path "*/ETL_*/ETL_recovery.json" 2> /dev/null || true)

 if [[ -z "${found_files}" ]]; then
  log_debug "${COMPONENT}: No ETL recovery files found"
  record_metric "${COMPONENT}" "etl_recovery_enabled" "0" "component=analytics"
  return 0
 fi

 # Count recovery files
 local recovery_count=0
 local recovery_enabled=0
 local last_step=""

 while IFS= read -r file; do
  if [[ -f "${file}" ]] && [[ -r "${file}" ]]; then
   recovery_count=$((recovery_count + 1))
   recovery_enabled=1

   # Try to extract last step from JSON (if jq is available)
   if command -v jq > /dev/null 2>&1; then
    local step
    step=$(jq -r '.last_step // empty' "${file}" 2> /dev/null || echo "")
    if [[ -n "${step}" ]]; then
     last_step="${step}"
    fi
   fi
  fi
 done <<< "${found_files}"

 # Record metrics
 record_metric "${COMPONENT}" "etl_recovery_enabled" "${recovery_enabled}" "component=analytics"
 record_metric "${COMPONENT}" "etl_recovery_files_count" "${recovery_count}" "component=analytics"

 if [[ -n "${last_step}" ]]; then
  log_info "${COMPONENT}: ETL recovery - Enabled: ${recovery_enabled}, Last step: ${last_step}"
 else
  log_info "${COMPONENT}: ETL recovery - Enabled: ${recovery_enabled}, Files: ${recovery_count}"
 fi

 return 0
}

##
# Parse ETL logs for execution metrics
##
parse_etl_execution_metrics() {
 local log_file="${1}"

 if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
  log_debug "${COMPONENT}: ETL log file not accessible: ${log_file}"
  return 1
 fi

 # Source ETL log parser library if available
 if [[ -f "${PROJECT_ROOT}/bin/lib/etlLogParser.sh" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/bin/lib/etlLogParser.sh"

  # Use parser functions if available
  if declare -f parse_etl_execution_time > /dev/null 2>&1; then
   parse_etl_execution_time "${log_file}"
  fi

  if declare -f parse_etl_facts_processed > /dev/null 2>&1; then
   parse_etl_facts_processed "${log_file}"
  fi

  if declare -f parse_etl_stage_timing > /dev/null 2>&1; then
   parse_etl_stage_timing "${log_file}"
  fi

  if declare -f parse_etl_validations > /dev/null 2>&1; then
   parse_etl_validations "${log_file}"
  fi

  if declare -f parse_etl_errors > /dev/null 2>&1; then
   parse_etl_errors "${log_file}"
  fi

  if declare -f detect_etl_mode > /dev/null 2>&1; then
   detect_etl_mode "${log_file}"
  fi
 else
  # Basic parsing if parser library doesn't exist yet
  log_debug "${COMPONENT}: ETL log parser library not found, using basic parsing"
  parse_etl_logs_basic "${log_file}"
 fi

 return 0
}

##
# Basic ETL log parsing (fallback when parser library doesn't exist)
##
parse_etl_logs_basic() {
 local log_file="${1}"

 # Extract last execution completion
 local last_completion
 last_completion=$(grep -E "ETL.*completed successfully|ETL.*finished successfully" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -z "${last_completion}" ]]; then
  log_debug "${COMPONENT}: No ETL completion messages found in logs"
  return 0
 fi

 # Extract execution time
 local execution_time=0
 if [[ "${last_completion}" =~ completed[[:space:]]+successfully[[:space:]]+in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
  execution_time="${BASH_REMATCH[1]}"
 elif [[ "${last_completion}" =~ finished[[:space:]]+successfully[[:space:]]+in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
  execution_time="${BASH_REMATCH[1]}"
 fi

 # Extract execution number if available
 local execution_number=0
 if [[ "${last_completion}" =~ Execution[[:space:]]+([0-9]+) ]] || [[ "${last_completion}" =~ execution[[:space:]]+([0-9]+) ]]; then
  execution_number="${BASH_REMATCH[1]}"
 fi

 # Count total executions
 local total_executions=0
 local grep_result
 grep_result=$(grep -c -E "ETL.*completed successfully|ETL.*finished successfully" "${log_file}" 2> /dev/null || echo "0")
 # Ensure grep_result is a valid number (remove any whitespace)
 grep_result=$(echo "${grep_result}" | tr -d '[:space:]' || echo "0")
 grep_result="${grep_result:-0}"
 total_executions=$((grep_result + 0))

 # Count successful vs failed executions
 local successful_executions=0
 local failed_executions=0
 grep_result=$(grep -c -E "ETL.*completed successfully|ETL.*finished successfully" "${log_file}" 2> /dev/null || echo "0")
 grep_result=$(echo "${grep_result}" | tr -d '[:space:]' || echo "0")
 grep_result="${grep_result:-0}"
 successful_executions=$((grep_result + 0))
 grep_result=$(grep -c -E "ETL.*failed|ETL.*error|ETL.*FATAL" "${log_file}" 2> /dev/null || echo "0")
 grep_result=$(echo "${grep_result}" | tr -d '[:space:]' || echo "0")
 grep_result="${grep_result:-0}"
 failed_executions=$((grep_result + 0))

 # Calculate success rate
 local success_rate=100
 local total_attempts=$((successful_executions + failed_executions))
 if [[ ${total_attempts} -gt 0 ]]; then
  success_rate=$((successful_executions * 100 / total_attempts))
 fi

 # Record basic metrics
 record_metric "${COMPONENT}" "etl_execution_duration_seconds" "${execution_time}" "component=analytics"
 record_metric "${COMPONENT}" "etl_execution_number" "${execution_number}" "component=analytics"
 record_metric "${COMPONENT}" "etl_executions_total" "${total_executions}" "component=analytics"
 record_metric "${COMPONENT}" "etl_execution_success_rate" "${success_rate}" "component=analytics"
 record_metric "${COMPONENT}" "etl_executions_successful_count" "${successful_executions}" "component=analytics"
 record_metric "${COMPONENT}" "etl_executions_failed_count" "${failed_executions}" "component=analytics"

 log_info "${COMPONENT}: ETL execution metrics - Duration: ${execution_time}s, Total: ${total_executions}, Success rate: ${success_rate}%"

 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting ETL metrics collection"

 # Check ETL process status
 check_etl_process_status

 # Check ETL lock files
 check_etl_lock_files

 # Check ETL recovery files
 check_etl_recovery_files

 # Find and parse ETL log files
 local etl_log_file
 if etl_log_file=$(find_etl_log_files); then
  log_info "${COMPONENT}: Found ETL log file: ${etl_log_file}"
  parse_etl_execution_metrics "${etl_log_file}"
 else
  log_debug "${COMPONENT}: No ETL log files found, skipping log parsing"
 fi

 log_info "${COMPONENT}: ETL metrics collection completed"

 return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
