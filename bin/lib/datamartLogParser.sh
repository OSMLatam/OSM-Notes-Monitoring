#!/usr/bin/env bash
#
# Datamart Log Parser
# Parses datamart logs from OSM-Notes-Analytics and extracts detailed structured metrics
#
# Version: 1.0.0
# Date: 2026-01-09
#
set -euo pipefail

# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]]; then
 COMPONENT="ANALYTICS"
fi
# Only make readonly if not in test mode
if [[ "${TEST_MODE:-false}" != "true" ]]; then
 readonly COMPONENT
fi

# Source logging and metrics functions (assuming they are in the same lib directory or sourced by caller)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/metricsFunctions.sh"

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
# Find most recent datamart log file
#
# Arguments:
#   $1 - Pattern to search for
#
# Returns:
#   Path to most recent log file via stdout, or empty if not found
##
find_datamart_log_file() {
 local pattern="${1:?Pattern required}"
 local found_files
 local most_recent=""
 local most_recent_time=0

 # Find all matching log files
 found_files=$(find /tmp -maxdepth 2 -type f -path "${pattern}" 2> /dev/null || true)

 if [[ -z "${found_files}" ]]; then
  log_debug "${COMPONENT}: No datamart log files found matching pattern ${pattern}"
  return 1
 fi

 # Find most recent file
 while IFS= read -r file; do
  if [[ -f "${file}" ]] && [[ -r "${file}" ]]; then
   local file_time
   file_time=$(stat -c %Y "${file}" 2> /dev/null || stat -f %m "${file}" 2> /dev/null || echo "0")
   if [[ ${file_time} -gt ${most_recent_time} ]]; then
    most_recent_time=${file_time}
    most_recent="${file}"
   fi
  fi
 done <<< "${found_files}"

 if [[ -n "${most_recent}" ]]; then
  echo "${most_recent}"
  return 0
 fi

 return 1
}

##
# Parse datamart execution metrics
#
# Arguments:
#   $1 - Log file path
#   $2 - Datamart name (countries, users, global)
#
# Returns:
#   0 on success, 1 on failure
##
parse_datamart_execution() {
 local log_file="${1:?Log file required}"
 local datamart_name="${2:?Datamart name required}"

 if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
  log_warning "${COMPONENT}: Cannot read datamart log file: ${log_file}"
  return 1
 fi

 local execution_duration=0
 local last_success_time=0
 local execution_count=0
 local success_count=0

 # Extract execution duration (look for patterns like "completed in X seconds" or "took X seconds")
 local duration_line
 duration_line=$(grep -E "(completed|finished|took).*[0-9]+.*second" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${duration_line}" ]]; then
  # Extract duration in seconds
  local duration_match
  duration_match=$(echo "${duration_line}" | grep -oE "[0-9]+" | head -1 || echo "0")
  execution_duration=$((duration_match + 0))
 fi

 # Extract last successful execution timestamp
 local success_lines
 success_lines=$(grep -E "(completed successfully|finished successfully|execution completed)" "${log_file}" 2> /dev/null || echo "")

 if [[ -n "${success_lines}" ]]; then
  # Get last line and extract timestamp
  local last_success_line
  last_success_line=$(echo "${success_lines}" | tail -1)
  # Try to extract timestamp (format: YYYY-MM-DD HH:MM:SS)
  local timestamp_match
  timestamp_match=$(echo "${last_success_line}" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1 || echo "")

  if [[ -n "${timestamp_match}" ]]; then
   # Convert to Unix timestamp
   if command -v date > /dev/null 2>&1; then
    last_success_time=$(date -d "${timestamp_match}" +%s 2> /dev/null || echo "0")
   fi
  fi
 fi

 # Count executions
 execution_count=$(grep -c -E "(started|execution|running)" "${log_file}" 2> /dev/null || echo "0")
 execution_count=$((execution_count + 0))

 # Count successful executions
 success_count=$(grep -c -E "(completed successfully|finished successfully)" "${log_file}" 2> /dev/null || echo "0")
 success_count=$((success_count + 0))

 # Record metrics
 record_metric "${COMPONENT}" "datamart_execution_duration_seconds" "${execution_duration}" "component=analytics,datamart=\"${datamart_name}\""
 record_metric "${COMPONENT}" "datamart_last_success_timestamp" "${last_success_time}" "component=analytics,datamart=\"${datamart_name}\""
 record_metric "${COMPONENT}" "datamart_execution_count_total" "${execution_count}" "component=analytics,datamart=\"${datamart_name}\""
 record_metric "${COMPONENT}" "datamart_success_count_total" "${success_count}" "component=analytics,datamart=\"${datamart_name}\""

 # Calculate success rate
 local success_rate=0
 if [[ ${execution_count} -gt 0 ]]; then
  success_rate=$((success_count * 100 / execution_count))
 fi
 record_metric "${COMPONENT}" "datamart_success_rate_percent" "${success_rate}" "component=analytics,datamart=\"${datamart_name}\""

 log_info "${COMPONENT}: Datamart ${datamart_name} - Duration: ${execution_duration}s, Executions: ${execution_count}, Success: ${success_count}, Rate: ${success_rate}%"

 return 0
}

##
# Parse datamartCountries specific metrics
#
# Arguments:
#   $1 - Log file path
#
# Returns:
#   0 on success, 1 on failure
##
parse_datamart_countries_metrics() {
 local log_file="${1:?Log file required}"

 if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
  log_warning "${COMPONENT}: Cannot read datamartCountries log file: ${log_file}"
  return 1
 fi

 local countries_processed=0
 local parallel_processing=0

 # Extract countries processed count
 local countries_line
 countries_line=$(grep -E "(countries|countries processed|processed.*countries)" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${countries_line}" ]]; then
  local countries_match
  countries_match=$(echo "${countries_line}" | grep -oE "[0-9]+" | head -1 || echo "0")
  countries_processed=$((countries_match + 0))
 fi

 # Extract parallel processing information
 local parallel_line
 parallel_line=$(grep -E "(parallel|threads|concurrent)" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${parallel_line}" ]]; then
  local parallel_match
  parallel_match=$(echo "${parallel_line}" | grep -oE "[0-9]+" | head -1 || echo "0")
  parallel_processing=$((parallel_match + 0))
 fi

 # Record metrics
 record_metric "${COMPONENT}" "datamart_countries_processed_total" "${countries_processed}" "component=analytics,datamart=countries"
 record_metric "${COMPONENT}" "datamart_parallel_processing_count" "${parallel_processing}" "component=analytics,datamart=countries"

 log_info "${COMPONENT}: DatamartCountries - Countries processed: ${countries_processed}, Parallel: ${parallel_processing}"

 return 0
}

##
# Parse datamartUsers specific metrics
#
# Arguments:
#   $1 - Log file path
#
# Returns:
#   0 on success, 1 on failure
##
parse_datamart_users_metrics() {
 local log_file="${1:?Log file required}"

 if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
  log_warning "${COMPONENT}: Cannot read datamartUsers log file: ${log_file}"
  return 1
 fi

 local users_processed=0
 local users_pending=0
 local initial_load_progress=0

 # Extract users processed count
 local users_line
 users_line=$(grep -E "(users|users processed|processed.*users)" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${users_line}" ]]; then
  local users_match
  users_match=$(echo "${users_line}" | grep -oE "[0-9]+" | head -1 || echo "0")
  users_processed=$((users_match + 0))
 fi

 # Extract pending users (if mentioned)
 local pending_line
 pending_line=$(grep -E "(pending|remaining|to process)" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${pending_line}" ]]; then
  local pending_match
  pending_match=$(echo "${pending_line}" | grep -oE "[0-9]+" | head -1 || echo "0")
  users_pending=$((pending_match + 0))
 fi

 # Extract initial load progress (percentage)
 local progress_line
 progress_line=$(grep -E "(progress|complete|percent)" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${progress_line}" ]]; then
  local progress_match
  progress_match=$(echo "${progress_line}" | grep -oE "[0-9]+" | head -1 || echo "0")
  initial_load_progress=$((progress_match + 0))
 fi

 # Record metrics
 record_metric "${COMPONENT}" "datamart_users_processed_total" "${users_processed}" "component=analytics,datamart=users"
 record_metric "${COMPONENT}" "datamart_users_pending_total" "${users_pending}" "component=analytics,datamart=users"
 record_metric "${COMPONENT}" "datamart_initial_load_progress_percent" "${initial_load_progress}" "component=analytics,datamart=users"

 log_info "${COMPONENT}: DatamartUsers - Processed: ${users_processed}, Pending: ${users_pending}, Progress: ${initial_load_progress}%"

 return 0
}

##
# Parse datamartGlobal specific metrics
#
# Arguments:
#   $1 - Log file path
#
# Returns:
#   0 on success, 1 on failure
##
parse_datamart_global_metrics() {
 local log_file="${1:?Log file required}"

 if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
  log_warning "${COMPONENT}: Cannot read datamartGlobal log file: ${log_file}"
  return 1
 fi

 local last_update_time=0
 local records_count=0

 # Extract last update timestamp
 local update_line
 update_line=$(grep -E "(updated|last update|refreshed)" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${update_line}" ]]; then
  # Try to extract timestamp
  local timestamp_match
  timestamp_match=$(echo "${update_line}" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1 || echo "")

  if [[ -n "${timestamp_match}" ]]; then
   if command -v date > /dev/null 2>&1; then
    last_update_time=$(date -d "${timestamp_match}" +%s 2> /dev/null || echo "0")
   fi
  fi
 fi

 # Extract records count
 local records_line
 records_line=$(grep -E "(records|rows|entries)" "${log_file}" 2> /dev/null | tail -1 || echo "")

 if [[ -n "${records_line}" ]]; then
  local records_match
  records_match=$(echo "${records_line}" | grep -oE "[0-9]+" | head -1 || echo "0")
  records_count=$((records_match + 0))
 fi

 # Record metrics
 record_metric "${COMPONENT}" "datamart_global_last_update_timestamp" "${last_update_time}" "component=analytics,datamart=global"
 record_metric "${COMPONENT}" "datamart_global_records_total" "${records_count}" "component=analytics,datamart=global"

 log_info "${COMPONENT}: DatamartGlobal - Last update: ${last_update_time}, Records: ${records_count}"

 return 0
}

##
# Parse all datamart logs
#
# Returns:
#   0 on success, 1 on failure
##
parse_all_datamart_logs() {
 local success_count=0
 local total_count=0

 # Parse datamartCountries
 local countries_log
 if countries_log=$(find_datamart_log_file "${DATAMART_COUNTRIES_PATTERN}"); then
  total_count=$((total_count + 1))
  if parse_datamart_execution "${countries_log}" "countries"; then
   success_count=$((success_count + 1))
   parse_datamart_countries_metrics "${countries_log}" || true
  fi
 fi

 # Parse datamartUsers
 local users_log
 if users_log=$(find_datamart_log_file "${DATAMART_USERS_PATTERN}"); then
  total_count=$((total_count + 1))
  if parse_datamart_execution "${users_log}" "users"; then
   success_count=$((success_count + 1))
   parse_datamart_users_metrics "${users_log}" || true
  fi
 fi

 # Parse datamartGlobal
 local global_log
 if global_log=$(find_datamart_log_file "${DATAMART_GLOBAL_PATTERN}"); then
  total_count=$((total_count + 1))
  if parse_datamart_execution "${global_log}" "global"; then
   success_count=$((success_count + 1))
   parse_datamart_global_metrics "${global_log}" || true
  fi
 fi

 log_info "${COMPONENT}: Parsed ${success_count}/${total_count} datamart logs"

 return 0
}
