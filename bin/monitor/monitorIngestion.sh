#!/usr/bin/env bash
#
# Ingestion Monitoring Script
# Monitors the OSM-Notes-Ingestion component health and performance
#
# Version: 1.0.0
# Date: 2025-12-24
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
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/parseApiLogs.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/parseStructuredLogs.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging only if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 init_logging "${LOG_DIR}/ingestion.log" "monitorIngestion"
fi

# Component name
# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]] || [[ "${TEST_MODE:-false}" == "true" ]]; then
 COMPONENT="${COMPONENT:-INGESTION}"
fi
readonly COMPONENT

##
# Show usage
##
usage() {
 cat << EOF
Ingestion Monitoring Script

Monitors the OSM-Notes-Ingestion component for health, performance, and data quality.

Usage: $0 [OPTIONS]

Options:
    -c, --check TYPE      Run specific check (health, performance, data-quality, all)
    -v, --verbose         Enable verbose output
    -d, --dry-run         Dry run (don't write to database)
    -h, --help            Show this help message

Check Types:
    health          Check component health status
    performance     Check performance metrics
    data-quality    Check data quality metrics
    execution-status Check script execution status
    latency         Check processing latency
    error-rate      Check error rate from logs
    disk-space      Check disk space usage
    api-download    Check API download status
    api-advanced    Check advanced API metrics
    daemon          Check daemon process metrics
    boundary        Check boundary processing metrics
    log-analysis    Check structured log analysis metrics
    all             Run all checks (default)

Examples:
    # Run all checks
    $0

    # Run only health check
    $0 --check health

    # Dry run (no database writes)
    $0 --dry-run

EOF
}

##
# Check script execution status
##
check_script_execution_status() {
 log_info "${COMPONENT}: Starting script execution status check"

 # Define scripts with their subdirectories
 # Note: processAPINotesDaemon.sh is the daemon wrapper, but we check for processAPINotes.sh
 # as it may be invoked by the daemon or run directly
 # Note: analyzeDatabasePerformance.sh is part of the ingestion repository as it's specific
 # to that component's database schema and queries
 local scripts_to_check=(
  "process/processAPINotes.sh"
  "process/processAPINotesDaemon.sh"
  "process/processPlanetNotes.sh"
  "process/updateCountries.sh"
  "monitor/notesCheckVerifier.sh"
  "monitor/processCheckPlanetNotes.sh"
  "monitor/analyzeDatabasePerformance.sh"
 )

 local scripts_dir="${INGESTION_REPO_PATH}/bin"
 local scripts_found=0
 local scripts_executable=0
 local scripts_running=0

 for script_rel_path in "${scripts_to_check[@]}"; do
  local script_path="${scripts_dir}/${script_rel_path}"
  local script_name
  script_name=$(basename "${script_rel_path}")

  # Check if script exists
  if [[ ! -f "${script_path}" ]]; then
   log_debug "${COMPONENT}: Script not found: ${script_rel_path}"
   continue
  fi

  scripts_found=$((scripts_found + 1))

  # Check if script is executable
  if [[ -x "${script_path}" ]]; then
   scripts_executable=$((scripts_executable + 1))
  else
   log_warning "${COMPONENT}: Script exists but not executable: ${script_name}"
  fi

  # Check if script process is running
  local script_basename
  script_basename=$(basename "${script_path}")

  # Try multiple pgrep strategies to find running processes
  local pid_found=""
  # First try: exact match with -f (full command line)
  pid_found=$(pgrep -f "${script_basename}" 2> /dev/null | head -1)

  # If not found, try matching just the basename (in case script is invoked differently)
  if [[ -z "${pid_found}" ]]; then
   pid_found=$(pgrep "${script_basename}" 2> /dev/null | head -1)
  fi

  # If still not found, try matching without .sh extension (for daemon processes)
  if [[ -z "${pid_found}" ]] && [[ "${script_basename}" == *.sh ]]; then
   local script_name_noext="${script_basename%.sh}"
   pid_found=$(pgrep -f "${script_name_noext}" 2> /dev/null | head -1)
  fi

  if [[ -n "${pid_found}" ]]; then
   scripts_running=$((scripts_running + 1))
   log_info "${COMPONENT}: Script is running: ${script_name} (PID: ${pid_found})"

   # Get process info
   local runtime
   runtime=$(ps -o etime= -p "${pid_found}" 2> /dev/null | tr -d ' ' || echo "unknown")
   log_debug "${COMPONENT}: Script ${script_name} PID: ${pid_found}, Runtime: ${runtime}"
  else
   log_debug "${COMPONENT}: Script not running: ${script_name} (checked: ${script_basename})"
  fi
 done

 # Record metrics
 record_metric "${COMPONENT}" "scripts_found" "${scripts_found}" "component=ingestion"
 record_metric "${COMPONENT}" "scripts_executable" "${scripts_executable}" "component=ingestion"
 record_metric "${COMPONENT}" "scripts_running" "${scripts_running}" "component=ingestion"

 log_info "${COMPONENT}: Script execution status - Found: ${scripts_found}, Executable: ${scripts_executable}, Running: ${scripts_running}"

 # Check against thresholds
 # Expected: 7 scripts (processAPINotes.sh, processAPINotesDaemon.sh, processPlanetNotes.sh,
 # updateCountries.sh, notesCheckVerifier.sh, processCheckPlanetNotes.sh, analyzeDatabasePerformance.sh)
 local expected_scripts_count="${INGESTION_SCRIPTS_FOUND_THRESHOLD:-7}"

 # Check if scripts found matches expected count
 if [[ ${scripts_found} -ne ${expected_scripts_count} ]]; then
  if [[ ${scripts_found} -lt ${expected_scripts_count} ]]; then
   log_warning "${COMPONENT}: Scripts found (${scripts_found}) below expected (${expected_scripts_count})"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "script_execution_status" "Low number of scripts found: ${scripts_found} (expected: ${expected_scripts_count})" || true
   fi
  else
   log_warning "${COMPONENT}: More scripts found (${scripts_found}) than expected (${expected_scripts_count})"
  fi
fi

# Check if all found scripts are executable
if [[ ${scripts_executable} -lt ${scripts_found} ]]; then
 log_warning "${COMPONENT}: Some scripts are not executable (${scripts_executable}/${scripts_found})"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "WARNING" "script_execution_status" "Scripts executable count (${scripts_executable}) is less than scripts found (${scripts_found})" || true
 fi
fi

# Critical check: scripts_executable must equal expected count
if [[ ${scripts_executable} -ne ${expected_scripts_count} ]]; then
 log_warning "${COMPONENT}: Scripts executable (${scripts_executable}) does not match expected count (${expected_scripts_count})"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "WARNING" "script_execution_status" "Scripts executable count (${scripts_executable}) does not match expected (${expected_scripts_count}). All scripts must be executable." || true
 fi
fi

 # Check last execution time from log files
 check_last_execution_time

 return 0
}

##
# Check error rate from log files
##
check_error_rate() {
 log_info "${COMPONENT}: Starting error rate check"

 local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"

 if [[ ! -d "${ingestion_log_dir}" ]]; then
  log_warning "${COMPONENT}: Log directory not found: ${ingestion_log_dir}"
  return 0
 fi

 # Find recent log files (last 24 hours)
 # In test mode, find all .log files without time restriction
 local log_files
 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  mapfile -t log_files < <(find "${ingestion_log_dir}" -name "*.log" -type f 2> /dev/null | head -10)
 else
  mapfile -t log_files < <(find "${ingestion_log_dir}" -name "*.log" -type f -mtime -1 2> /dev/null | head -10)
 fi

 if [[ ${#log_files[@]} -eq 0 ]]; then
  log_warning "${COMPONENT}: No recent log files found for error rate analysis"
  return 0
 fi

 local total_lines=0
 local error_lines=0
 local warning_lines=0
 local info_lines=0

 # Parse log files for error patterns
 for log_file in "${log_files[@]}"; do
  # Count lines by log level
  local file_errors
  file_errors=$(grep -cE "\[ERROR\]|ERROR|error|failed|failure" "${log_file}" 2> /dev/null || echo "0")
  # Ensure numeric value (remove any whitespace and non-numeric characters)
  file_errors=$(echo "${file_errors}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
  file_errors=$((file_errors + 0))

  local file_warnings
  file_warnings=$(grep -cE "\[WARNING\]|WARNING|warning" "${log_file}" 2> /dev/null || echo "0")
  # Ensure numeric value (remove any whitespace and non-numeric characters)
  file_warnings=$(echo "${file_warnings}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
  file_warnings=$((file_warnings + 0))

  local file_info
  file_info=$(grep -cE "\[INFO\]|INFO|info" "${log_file}" 2> /dev/null || echo "0")
  # Ensure numeric value (remove any whitespace and non-numeric characters)
  file_info=$(echo "${file_info}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
  file_info=$((file_info + 0))

  local file_total
  file_total=$(wc -l < "${log_file}" 2> /dev/null || echo "0")
  # Ensure numeric value (remove any whitespace and non-numeric characters)
  file_total=$(echo "${file_total}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
  file_total=$((file_total + 0))

  error_lines=$((error_lines + file_errors))
  warning_lines=$((warning_lines + file_warnings))
  info_lines=$((info_lines + file_info))
  total_lines=$((total_lines + file_total))
 done

 if [[ ${total_lines} -eq 0 ]]; then
  log_info "${COMPONENT}: No log lines found for error rate analysis"
  return 0
 fi

 # Calculate error rate percentage
 local error_rate=0
 if [[ ${total_lines} -gt 0 ]]; then
  error_rate=$((error_lines * 100 / total_lines))
 fi

 local warning_rate=0
 if [[ ${total_lines} -gt 0 ]]; then
  warning_rate=$((warning_lines * 100 / total_lines))
 fi

 log_info "${COMPONENT}: Error rate analysis - Total: ${total_lines}, Errors: ${error_lines} (${error_rate}%), Warnings: ${warning_lines} (${warning_rate}%)"

 # Record metrics
 record_metric "${COMPONENT}" "error_count" "${error_lines}" "component=ingestion"
 record_metric "${COMPONENT}" "warning_count" "${warning_lines}" "component=ingestion"
 record_metric "${COMPONENT}" "error_rate_percent" "${error_rate}" "component=ingestion"
 record_metric "${COMPONENT}" "warning_rate_percent" "${warning_rate}" "component=ingestion"
 record_metric "${COMPONENT}" "log_lines_total" "${total_lines}" "component=ingestion"

 # Check error count threshold
 local error_count_threshold="${INGESTION_ERROR_COUNT_THRESHOLD:-1000}"
 if [[ ${error_lines} -gt ${error_count_threshold} ]]; then
  log_warning "${COMPONENT}: Error count (${error_lines}) exceeds threshold (${error_count_threshold})"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "error_rate" "High error count detected: ${error_lines} errors in 24h (threshold: ${error_count_threshold})" || true
  fi
 fi

 # Check warning count threshold
 local warning_count_threshold="${INGESTION_WARNING_COUNT_THRESHOLD:-2000}"
 if [[ ${warning_lines} -gt ${warning_count_threshold} ]]; then
  log_warning "${COMPONENT}: Warning count (${warning_lines}) exceeds threshold (${warning_count_threshold})"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "INFO" "warning_rate" "High warning count detected: ${warning_lines} warnings in 24h (threshold: ${warning_count_threshold})" || true
  fi
 fi

 # Check error rate threshold
 local max_error_rate="${INGESTION_MAX_ERROR_RATE:-5}"
 if [[ ${error_rate} -gt ${max_error_rate} ]]; then
  log_warning "${COMPONENT}: Error rate (${error_rate}%) exceeds threshold (${max_error_rate}%)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "error_rate" "High error rate detected: ${error_rate}% (threshold: ${max_error_rate}%, errors: ${error_lines}/${total_lines})" || true
  fi
  return 1
 fi

# Check warning rate threshold
local warning_rate_threshold="${INGESTION_WARNING_RATE_THRESHOLD:-15}"
if [[ ${warning_rate} -gt ${warning_rate_threshold} ]]; then
 log_warning "${COMPONENT}: Warning rate (${warning_rate}%) exceeds threshold (${warning_rate_threshold}%)"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "WARNING" "warning_rate" "High warning rate detected: ${warning_rate}% (threshold: ${warning_rate_threshold}%, warnings: ${warning_lines}/${total_lines})" || true
 fi
fi

 # Check for recent error spikes (errors in last hour)
 check_recent_error_spikes

 log_info "${COMPONENT}: Error rate check passed - Rate: ${error_rate}%"
 return 0
}

##
# Check for recent error spikes
##
check_recent_error_spikes() {
 log_debug "${COMPONENT}: Checking for recent error spikes"

 local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"

 # Find log files modified in last hour
 local recent_logs
 mapfile -t recent_logs < <(find "${ingestion_log_dir}" -name "*.log" -type f -mmin -60 2> /dev/null)

 if [[ ${#recent_logs[@]} -eq 0 ]]; then
  log_debug "${COMPONENT}: No recent log files found for spike detection"
  return 0
 fi

 local recent_errors=0
 local recent_total=0

 for log_file in "${recent_logs[@]}"; do
  # Count errors in last hour (check file modification time and content)
  local file_errors
  file_errors=$(grep -cE "\[ERROR\]|ERROR|error|failed|failure" "${log_file}" 2> /dev/null || echo "0")
  # Ensure numeric value (remove any whitespace and non-numeric characters)
  file_errors=$(echo "${file_errors}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
  file_errors=$((file_errors + 0))

  local file_total
  file_total=$(wc -l < "${log_file}" 2> /dev/null || echo "0")
  # Ensure numeric value (remove any whitespace and non-numeric characters)
  file_total=$(echo "${file_total}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
  file_total=$((file_total + 0))

  recent_errors=$((recent_errors + file_errors))
  recent_total=$((recent_total + file_total))
 done

 if [[ ${recent_total} -gt 0 ]]; then
  local recent_error_rate=$((recent_errors * 100 / recent_total))

  log_debug "${COMPONENT}: Recent error rate (last hour): ${recent_error_rate}% (${recent_errors}/${recent_total})"
  record_metric "${COMPONENT}" "recent_error_rate_percent" "${recent_error_rate}" "component=ingestion,period=1hour"

  # Alert if spike detected (error rate > 2x threshold)
  local max_error_rate="${INGESTION_MAX_ERROR_RATE:-5}"
  local spike_threshold=$((max_error_rate * 2))

  if [[ ${recent_error_rate} -gt ${spike_threshold} ]]; then
   log_warning "${COMPONENT}: Error spike detected in last hour: ${recent_error_rate}%"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "error_spike" "Error spike detected: ${recent_error_rate}% in last hour (${recent_errors} errors)" || true
   fi
  fi
 fi

 return 0
}

##
# Check disk space usage
##
check_disk_space() {
 log_info "${COMPONENT}: Starting disk space check"

 # Check if ingestion repository exists
 if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
  log_error "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
  return 1
 fi

 # Directories to check
 local directories_to_check=(
  "${INGESTION_REPO_PATH}"
  "${INGESTION_REPO_PATH}/logs"
  "${LOG_DIR}"
  "${TMP_DIR}"
 )

 local total_issues=0

 # Check each directory
 for dir in "${directories_to_check[@]}"; do
  if [[ ! -d "${dir}" ]]; then
   log_debug "${COMPONENT}: Directory does not exist: ${dir}"
   continue
  fi

  # Get disk usage percentage
  local usage_percent
  usage_percent=$(df -h "${dir}" 2> /dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")

  if [[ -z "${usage_percent}" ]] || [[ "${usage_percent}" == "0" ]]; then
   log_debug "${COMPONENT}: Could not determine disk usage for: ${dir}"
   continue
  fi

  # Get available space
  local available_space
  available_space=$(df -h "${dir}" 2> /dev/null | tail -1 | awk '{print $4}' || echo "unknown")

  # Get total space
  local total_space
  total_space=$(df -h "${dir}" 2> /dev/null | tail -1 | awk '{print $2}' || echo "unknown")

  # Get used space
  local used_space
  used_space=$(df -h "${dir}" 2> /dev/null | tail -1 | awk '{print $3}' || echo "unknown")

  log_info "${COMPONENT}: Disk usage for ${dir}: ${usage_percent}% (Used: ${used_space}, Available: ${available_space}, Total: ${total_space})"

  # Record metrics
  local dir_name
  dir_name=$(basename "${dir}")
  record_metric "${COMPONENT}" "disk_usage_percent" "${usage_percent}" "component=ingestion,directory=${dir_name}"

  # Check against threshold
  local disk_threshold="${INFRASTRUCTURE_DISK_THRESHOLD:-90}"

  if [[ ${usage_percent} -ge ${disk_threshold} ]]; then
   log_warning "${COMPONENT}: Disk usage (${usage_percent}%) exceeds threshold (${disk_threshold}%) for ${dir}"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "disk_space" "High disk usage: ${usage_percent}% on ${dir} (threshold: ${disk_threshold}%, available: ${available_space})" || true
   fi
   total_issues=$((total_issues + 1))
  elif [[ ${usage_percent} -ge $((disk_threshold - 10)) ]]; then
   log_warning "${COMPONENT}: Disk usage (${usage_percent}%) approaching threshold (${disk_threshold}%) for ${dir}"
  fi
 done

 # Check overall system disk usage
 check_system_disk_usage

 if [[ ${total_issues} -gt 0 ]]; then
  log_warning "${COMPONENT}: Disk space check found ${total_issues} issues"
  return 1
 fi

 log_info "${COMPONENT}: Disk space check passed"
 return 0
}

##
# Check system-wide disk usage
##
check_system_disk_usage() {
 log_debug "${COMPONENT}: Checking system-wide disk usage"

 # Get root filesystem usage
 local root_usage
 root_usage=$(df -h / 2> /dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")

 if [[ -n "${root_usage}" ]] && [[ "${root_usage}" != "0" ]]; then
  local root_available
  root_available=$(df -h / 2> /dev/null | tail -1 | awk '{print $4}' || echo "unknown")

  log_debug "${COMPONENT}: Root filesystem usage: ${root_usage}% (Available: ${root_available})"
  record_metric "${COMPONENT}" "disk_usage_percent" "${root_usage}" "component=ingestion,directory=root"

  local disk_threshold="${INFRASTRUCTURE_DISK_THRESHOLD:-90}"

  if [[ ${root_usage} -ge ${disk_threshold} ]]; then
   log_warning "${COMPONENT}: Root filesystem usage (${root_usage}%) exceeds threshold (${disk_threshold}%)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "disk_space" "High root filesystem usage: ${root_usage}% (available: ${root_available})" || true
   fi
  fi
 fi

 return 0
}

##
# Check last execution time from log files
##
check_last_execution_time() {
 local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"

 if [[ ! -d "${ingestion_log_dir}" ]]; then
  log_debug "${COMPONENT}: Log directory not found: ${ingestion_log_dir}"
  return 0
 fi

 # Find most recent log file
 local latest_log
 latest_log=$(find "${ingestion_log_dir}" -name "*.log" -type f -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2-)

 if [[ -z "${latest_log}" ]]; then
  log_warning "${COMPONENT}: No log files found"
  return 0
 fi

 # Get modification time
 local log_mtime
 log_mtime=$(stat -c %Y "${latest_log}" 2> /dev/null || stat -f %m "${latest_log}" 2> /dev/null || echo "0")
 local current_time
 current_time=$(date +%s)
 local age_seconds=$((current_time - log_mtime))
 local age_hours=$((age_seconds / 3600))

 log_info "${COMPONENT}: Latest log file: $(basename "${latest_log}"), Age: ${age_hours} hours"

 record_metric "${COMPONENT}" "last_log_age_hours" "${age_hours}" "component=ingestion"

 # Alert if log is too old
 local log_age_threshold="${INGESTION_LAST_LOG_AGE_THRESHOLD:-24}"
 if [[ ${age_hours} -gt ${log_age_threshold} ]]; then
  log_warning "${COMPONENT}: Log file is older than threshold (${age_hours} hours, threshold: ${log_age_threshold} hours)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "last_execution_time" "No recent activity detected: last log is ${age_hours} hours old (threshold: ${log_age_threshold} hours)" || true
  fi
 fi

 return 0
}

##
# Check ingestion component health
##
check_ingestion_health() {
 log_info "${COMPONENT}: Starting health check"

 local health_status="unknown"
 local error_message=""

 # Check if ingestion repository exists
 if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
  health_status="down"
  error_message="Ingestion repository not found: ${INGESTION_REPO_PATH}"
  log_error "${COMPONENT}: ${error_message}"
  record_metric "${COMPONENT}" "health_status" "0" "component=ingestion"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "CRITICAL" "ingestion_health" "Health check failed: ${error_message}" || true
  fi
  return 1
 fi

 # Check script execution status
 check_script_execution_status

 # Check if ingestion log files exist and are recent
 local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
 if [[ -d "${ingestion_log_dir}" ]]; then
  local latest_log
  latest_log=$(find "${ingestion_log_dir}" -name "*.log" -type f -mtime -1 2> /dev/null | head -1)

  if [[ -z "${latest_log}" ]]; then
   health_status="degraded"
   error_message="No recent log files found (older than 1 day)"
   log_warning "${COMPONENT}: ${error_message}"
   record_metric "${COMPONENT}" "health_status" "1" "component=ingestion"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "ingestion_health" "Health check warning: ${error_message}" || true
   fi
   return 0
  fi
 fi

 # Check if processCheckPlanetNotes.sh exists and can be executed
 local planet_check_script="${INGESTION_REPO_PATH}/bin/monitor/processCheckPlanetNotes.sh"
 if [[ -f "${planet_check_script}" ]]; then
  if [[ ! -x "${planet_check_script}" ]]; then
   log_warning "${COMPONENT}: processCheckPlanetNotes.sh exists but is not executable"
  else
   log_debug "${COMPONENT}: processCheckPlanetNotes.sh is available and executable"
  fi
 fi

 # If we get here, component appears healthy
 # shellcheck disable=SC2034
 health_status="healthy"
 log_info "${COMPONENT}: Health check passed"
 record_metric "${COMPONENT}" "health_status" "1" "component=ingestion"

 return 0
}

##
# Check database connection performance
##
check_database_connection_performance() {
 log_debug "${COMPONENT}: Checking database connection performance"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Database connection check failed"
  return 1
 fi

 # Measure connection time
 local start_time
 start_time=$(date +%s%N 2> /dev/null || date +%s000)

 # Simple query to test connection speed
 local test_query="SELECT 1;"
 execute_sql_query "${test_query}" > /dev/null 2>&1

 local end_time
 end_time=$(date +%s%N 2> /dev/null || date +%s000)
 local duration_ms=$(((end_time - start_time) / 1000000))

 log_debug "${COMPONENT}: Database connection time: ${duration_ms}ms"
 record_metric "${COMPONENT}" "db_connection_time_ms" "${duration_ms}" "component=ingestion"

# Alert if connection is slow (> 1000ms)
if [[ ${duration_ms} -gt 1000 ]]; then
 log_warning "${COMPONENT}: Slow database connection: ${duration_ms}ms"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "WARNING" "database_connection" "Slow database connection: ${duration_ms}ms" || true
 fi
fi

 return 0
}

##
# Check database query performance
##
check_database_query_performance() {
 log_debug "${COMPONENT}: Checking database query performance"

 if ! check_database_connection; then
  return 1
 fi

 # Test query performance with a simple count query
 local test_query="SELECT COUNT(*) FROM notes;"

 local start_time
 start_time=$(date +%s%N 2> /dev/null || date +%s000)

 local result
 result=$(execute_sql_query "${test_query}" 2> /dev/null || echo "")

 local end_time
 end_time=$(date +%s%N 2> /dev/null || date +%s000)
 local duration_ms=$(((end_time - start_time) / 1000000))

 if [[ -n "${result}" ]]; then
  log_debug "${COMPONENT}: Query performance test - Duration: ${duration_ms}ms, Result: ${result}"
  record_metric "${COMPONENT}" "db_query_time_ms" "${duration_ms}" "component=ingestion,query=count_notes"

  # Check against slow query threshold
  local slow_query_threshold="${PERFORMANCE_SLOW_QUERY_THRESHOLD:-1000}"

  if [[ ${duration_ms} -gt ${slow_query_threshold} ]]; then
   log_warning "${COMPONENT}: Slow query detected: ${duration_ms}ms (threshold: ${slow_query_threshold}ms)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "slow_query" "Slow query detected: ${duration_ms}ms" || true
   fi
  fi
 fi

 return 0
}

##
# Check database connection pool
##
check_database_connections() {
 log_debug "${COMPONENT}: Checking database connections"

 if ! check_database_connection; then
  return 1
 fi

 # Query to check active connections
 # This is PostgreSQL-specific
 local connections_query="
        SELECT
            count(*) as total_connections,
            count(*) FILTER (WHERE state = 'active') as active_connections,
            count(*) FILTER (WHERE state = 'idle') as idle_connections
        FROM pg_stat_activity
        WHERE datname = current_database();
    "

 local result
 result=$(execute_sql_query "${connections_query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  log_debug "${COMPONENT}: Database connections: ${result}"
  # Parse result and record metrics if needed
  # Format: total_connections|active_connections|idle_connections
 fi

 return 0
}

##
# Check database table sizes and growth
##
check_database_table_sizes() {
 log_debug "${COMPONENT}: Checking database table sizes"

 if ! check_database_connection; then
  return 1
 fi

 # Query to get table sizes (PostgreSQL-specific)
 local size_query="
        SELECT
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
            pg_total_relation_size(schemaname||'.'||tablename) AS size_bytes
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
        LIMIT 10;
    "

 local result
 result=$(execute_sql_query "${size_query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  log_debug "${COMPONENT}: Database table sizes:\n${result}"
  # Could parse and record individual table sizes if needed
 fi

 return 0
}

##
# Check advanced database metrics
##
check_advanced_database_metrics() {
 log_info "${COMPONENT}: Starting advanced database metrics collection"

 # Check if collectDatabaseMetrics.sh script exists
 local db_metrics_script="${SCRIPT_DIR}/collectDatabaseMetrics.sh"

 if [[ ! -f "${db_metrics_script}" ]]; then
  log_debug "${COMPONENT}: Advanced database metrics collection script not found: ${db_metrics_script}"
  return 0
 fi

 # Check if script is executable
 if [[ ! -x "${db_metrics_script}" ]]; then
  log_debug "${COMPONENT}: Advanced database metrics collection script is not executable: ${db_metrics_script}"
  return 0
 fi

 # Run advanced database metrics collection
 local output
 local exit_code=0

 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  # In test mode, capture output for debugging
  output=$(bash "${db_metrics_script}" 2>&1) || exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
   log_debug "${COMPONENT}: Advanced database metrics collection output: ${output}"
  fi
 else
  # In production, run silently and log errors
  bash "${db_metrics_script}" > /dev/null 2>&1 || exit_code=$?
 fi

 if [[ ${exit_code} -ne 0 ]]; then
  log_warning "${COMPONENT}: Advanced database metrics collection failed (exit code: ${exit_code})"
  return 1
 fi

 # Check cache hit ratio threshold
 local cache_hit_query
 cache_hit_query="SELECT metric_value FROM metrics
                     WHERE component = 'ingestion'
                       AND metric_name = 'db_cache_hit_ratio'
                     ORDER BY timestamp DESC
                     LIMIT 1;"

 local cache_hit_ratio
 cache_hit_ratio=$(execute_sql_query "${cache_hit_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${cache_hit_ratio}" ]] && [[ "${cache_hit_ratio}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  local cache_hit_threshold="${INGESTION_DB_CACHE_HIT_THRESHOLD:-70}"
  # Compare as float (multiply by 100 to avoid decimal comparison issues)
  local cache_hit_int
  cache_hit_int=$(echo "${cache_hit_ratio}" | awk '{printf "%.0f", $1}')
  local threshold_int=${cache_hit_threshold}

  if [[ ${cache_hit_int} -lt ${threshold_int} ]]; then
   log_warning "${COMPONENT}: Cache hit ratio (${cache_hit_ratio}%) below threshold (${cache_hit_threshold}%)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "db_cache_hit_ratio" "Database cache hit ratio (${cache_hit_ratio}%) below threshold (${cache_hit_threshold}%)" || true
   fi
  fi
 fi

 # Check for slow queries
 local slow_queries_query
 slow_queries_query="SELECT metric_value FROM metrics
                        WHERE component = 'ingestion'
                          AND metric_name = 'db_slow_queries_count'
                        ORDER BY timestamp DESC
                        LIMIT 1;"

 local slow_queries_count
 slow_queries_count=$(execute_sql_query "${slow_queries_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

if [[ -n "${slow_queries_count}" ]] && [[ "${slow_queries_count}" =~ ^[0-9]+$ ]]; then
 if [[ ${slow_queries_count} -gt 0 ]]; then
  log_warning "${COMPONENT}: ${slow_queries_count} slow queries detected"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "db_slow_queries" "${slow_queries_count} slow queries detected (>1s average execution time)" || true
  fi
 fi
fi

 # Check connection usage
 local conn_usage_query
 conn_usage_query="SELECT metric_value FROM metrics
                      WHERE component = 'ingestion'
                        AND metric_name = 'db_connection_usage_percent'
                      ORDER BY timestamp DESC
                      LIMIT 1;"

 local conn_usage
 conn_usage=$(execute_sql_query "${conn_usage_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${conn_usage}" ]] && [[ "${conn_usage}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  local conn_usage_threshold="${INGESTION_DB_CONNECTION_USAGE_THRESHOLD:-80}"
  local conn_usage_int
  conn_usage_int=$(echo "${conn_usage}" | awk '{printf "%.0f", $1}')
  local threshold_int=${conn_usage_threshold}

  if [[ ${conn_usage_int} -gt ${threshold_int} ]]; then
   log_warning "${COMPONENT}: Connection usage (${conn_usage}%) exceeds threshold (${conn_usage_threshold}%)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "db_connection_usage" "Database connection usage (${conn_usage}%) exceeds threshold (${conn_usage_threshold}%)" || true
   fi
  fi
 fi

 # Check for deadlocks
 local deadlocks_query
 deadlocks_query="SELECT metric_value FROM metrics
                      WHERE component = 'ingestion'
                        AND metric_name = 'db_deadlocks_count'
                      ORDER BY timestamp DESC
                      LIMIT 1;"

 local deadlocks_count
 deadlocks_count=$(execute_sql_query "${deadlocks_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

if [[ -n "${deadlocks_count}" ]] && [[ "${deadlocks_count}" =~ ^[0-9]+$ ]]; then
 if [[ ${deadlocks_count} -gt 0 ]]; then
  log_error "${COMPONENT}: ${deadlocks_count} deadlocks detected"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "CRITICAL" "db_deadlocks" "${deadlocks_count} deadlocks detected in database" || true
  fi
  return 1
 fi
fi

 log_info "${COMPONENT}: Advanced database metrics check completed"
 return 0
}

##
# Check ingestion performance metrics using analyzeDatabasePerformance.sh
##
check_ingestion_performance() {
 log_info "${COMPONENT}: Starting database performance check"

 # Check database connection performance
 check_database_connection_performance

 # Check query performance
 check_database_query_performance

 # Check database connections
 check_database_connections

 # Check table sizes
 check_database_table_sizes

 # Collect advanced database metrics
 check_advanced_database_metrics

 # Run analyzeDatabasePerformance.sh if enabled and available
 # IMPORTANT: This script is very resource-intensive and should run only once per month
 # from the ingestion project's cron. By default, it's disabled here.
 local analyze_db_perf_enabled="${INGESTION_ANALYZE_DB_PERFORMANCE_ENABLED:-false}"

 if [[ "${analyze_db_perf_enabled}" != "true" ]]; then
  log_info "${COMPONENT}: analyzeDatabasePerformance.sh execution is disabled (should run monthly from ingestion project cron)"
  log_debug "${COMPONENT}: Set INGESTION_ANALYZE_DB_PERFORMANCE_ENABLED=true to enable execution from monitoring"
  return 0
 fi

 if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
  log_error "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
  return 1
 fi

 # Path to analyzeDatabasePerformance.sh
 local perf_script="${INGESTION_REPO_PATH}/bin/monitor/analyzeDatabasePerformance.sh"

 if [[ -f "${perf_script}" ]]; then
  # Check if script is executable
  if [[ ! -x "${perf_script}" ]]; then
   log_warning "${COMPONENT}: analyzeDatabasePerformance.sh is not executable: ${perf_script}"
   log_info "${COMPONENT}: Attempting to make script executable"
   chmod +x "${perf_script}" 2> /dev/null || {
    log_error "${COMPONENT}: Cannot make analyzeDatabasePerformance.sh executable. Check permissions."
    return 1
   }
  fi

  # Check if analyzeDatabasePerformance.sh is already running to avoid concurrent executions
  # This script can take a long time (several minutes) and we don't want multiple instances
  local lock_file="${TMP_DIR}/analyzeDatabasePerformance.lock"
  local lock_timeout=3600 # 1 hour - if lock is older, assume process died

  if [[ -f "${lock_file}" ]]; then
   local lock_age
   lock_age=$(($(date +%s) - $(stat -c %Y "${lock_file}" 2> /dev/null || echo "0")))

   if [[ ${lock_age} -lt ${lock_timeout} ]]; then
    # Check if process is actually running
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2> /dev/null || echo "")

    if [[ -n "${lock_pid}" ]] && ps -p "${lock_pid}" > /dev/null 2>&1; then
     log_info "${COMPONENT}: analyzeDatabasePerformance.sh is already running (PID: ${lock_pid}, lock age: ${lock_age}s), skipping execution"
     return 0
    else
     # Lock file exists but process is not running - stale lock, remove it
     log_warning "${COMPONENT}: Stale lock file found (PID: ${lock_pid} not running), removing lock"
     rm -f "${lock_file}"
    fi
   else
    # Lock file is too old, assume process died
    log_warning "${COMPONENT}: Lock file is too old (${lock_age}s), assuming process died, removing lock"
    rm -f "${lock_file}"
   fi
  fi

  log_info "${COMPONENT}: Running analyzeDatabasePerformance.sh from ${perf_script}"

  # Create lock file with current PID
  echo $$ > "${lock_file}"

  # Verify script can be read and has valid shebang
  if ! head -1 "${perf_script}" | grep -qE "^#!.*bash"; then
   log_warning "${COMPONENT}: Script may not have valid bash shebang: ${perf_script}"
  fi

  # Ensure PATH includes standard binary directories for psql, timeout, and other tools
  # This is critical when script runs from cron or with limited PATH
  # The script itself also uses timeout and psql, so PATH must be set
  local saved_path="${PATH:-}"
  # Include common PostgreSQL installation paths and standard system paths
  export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/pgsql/bin:/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:/usr/lib/postgresql/13/bin:${PATH:-}"

  # Also export PATH in the environment for the script and its subprocesses
  # This ensures timeout, psql, and other commands are found
  export PATH

  # Check for common dependencies AFTER setting PATH (so we check with correct PATH)
  local missing_deps=()
  for cmd in bash psql timeout; do
   if ! command -v "${cmd}" > /dev/null 2>&1; then
    missing_deps+=("${cmd}")
   fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
   log_error "${COMPONENT}: Missing dependencies: ${missing_deps[*]}"
   log_error "${COMPONENT}: Current PATH: ${PATH}"
   rm -f "${lock_file}" # Remove lock on error
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "ERROR" "performance_check_failed" "Performance analysis failed: Missing dependencies (${missing_deps[*]}). Check PATH and install missing tools." || true
   fi
   export PATH="${saved_path}" # Restore PATH before returning
   return 1
  fi

  # Export database connection variables that analyzeDatabasePerformance.sh might need
  export DBHOST="${INGESTION_DBHOST:-${DBHOST:-localhost}}"
  export DBPORT="${INGESTION_DBPORT:-${DBPORT:-5432}}"
  export DBUSER="${INGESTION_DBUSER:-${DBUSER:-postgres}}"
  export DBNAME="${INGESTION_DBNAME:-notes}"

  # Run the performance analysis script
  # Use env to ensure PATH and environment variables are passed to all subprocesses
  local start_time
  start_time=$(date +%s)

  local exit_code=0
  local output
  local output_file
  output_file="${LOG_DIR}/performance_output/analyzeDatabasePerformance_$(date +%Y%m%d_%H%M%S).txt"
  mkdir -p "$(dirname "${output_file}")"

  # Use env to explicitly set PATH and environment variables for the script and all its subprocesses
  # Capture both stdout and stderr, and save to file
  # Note: analyzeDatabasePerformance.sh will execute SQL scripts that need psql and timeout in PATH
  # Ensure PATH is exported in the environment so subprocesses can find commands
  # Also export PGPASSWORD if set (for database authentication)
  local env_vars="PATH=${PATH}"
  env_vars="${env_vars} DBHOST=${DBHOST}"
  env_vars="${env_vars} DBPORT=${DBPORT}"
  env_vars="${env_vars} DBUSER=${DBUSER}"
  env_vars="${env_vars} DBNAME=${DBNAME}"
  if [[ -n "${PGPASSWORD:-}" ]]; then
   env_vars="${env_vars} PGPASSWORD=${PGPASSWORD}"
  fi

  # Set timeout for analyzeDatabasePerformance.sh execution
  # Default: 10 minutes (600 seconds), configurable via INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD
  # Add 60 seconds buffer to the threshold to allow script to complete if it's close to threshold
  local perf_timeout="${INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD:-300}"
  local script_timeout=$((perf_timeout + 60)) # Add buffer

  log_info "${COMPONENT}: Running analyzeDatabasePerformance.sh with timeout of ${script_timeout}s"

  # Execute with timeout to prevent script from hanging indefinitely
  # timeout returns 124 if timeout occurred, 125 if timeout command failed, 126 if command not found
  if command -v timeout > /dev/null 2>&1; then
   if ! output=$(cd "${INGESTION_REPO_PATH}" && timeout "${script_timeout}" env "${env_vars}" bash "${perf_script}" 2>&1 | tee "${output_file}"); then
    exit_code=$?
    # Check if it was a timeout
    if [[ ${exit_code} -eq 124 ]]; then
     log_error "${COMPONENT}: analyzeDatabasePerformance.sh timed out after ${script_timeout}s"
     log_error "${COMPONENT}: This may indicate the script is stuck or taking too long"
     log_error "${COMPONENT}: Consider increasing INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD or investigating script performance"
     # Add timeout message to output
     echo "ERROR: Script execution timed out after ${script_timeout} seconds" >> "${output_file}"
    fi
   fi
  else
   # Fallback if timeout command is not available (should not happen as we check for it above)
   log_warning "${COMPONENT}: timeout command not available, running without timeout (risky)"
   if ! output=$(cd "${INGESTION_REPO_PATH}" && env "${env_vars}" bash "${perf_script}" 2>&1 | tee "${output_file}"); then
    exit_code=$?
   fi
  fi

  # If output is empty but file exists, read from file
  if [[ -z "${output}" ]] && [[ -f "${output_file}" ]]; then
   output=$(cat "${output_file}" 2> /dev/null || echo "")
  fi

  # Restore original PATH
  export PATH="${saved_path}"

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Log the output (truncate if too long for debug log)
  local output_preview
  output_preview=$(echo "${output}" | head -50)
  log_debug "${COMPONENT}: analyzeDatabasePerformance.sh output (first 50 lines):\n${output_preview}"

  # Log where full output is saved
  if [[ -f "${output_file}" ]]; then
   log_debug "${COMPONENT}: Full performance check output saved to: ${output_file}"
   # Keep only last 10 output files
   find "$(dirname "${output_file}")" -name "analyzeDatabasePerformance_*.txt" -type f -mtime +7 -delete 2> /dev/null || true
  fi

  # Check exit code
  if [[ ${exit_code} -eq 0 ]]; then
   log_info "${COMPONENT}: Performance analysis passed (duration: ${duration}s)"
   record_metric "${COMPONENT}" "performance_check_status" "1" "component=ingestion,check=analyzeDatabasePerformance"
   record_metric "${COMPONENT}" "performance_check_duration" "${duration}" "component=ingestion,check=analyzeDatabasePerformance"

   # Parse output for performance metrics
   # Look for PASS/FAIL/WARNING patterns
   local pass_count
   pass_count=$(echo "${output}" | grep -c "PASS\|✓" || echo "0")
   local fail_count
   fail_count=$(echo "${output}" | grep -c "FAIL\|✗" || echo "0")
   local warning_count
   warning_count=$(echo "${output}" | grep -c "WARNING\|⚠" || echo "0")

   # Check if failures are due to technical issues
   # Exit code 127 = command not found (PATH issues)
   # Exit code 3 = SQL syntax errors or missing database objects (script compatibility issues)
   # These are not real performance issues, just execution/configuration problems
   local technical_failures=0
   if echo "${output}" | grep -q "exit code: 127\|exit code: 3\|command not found\|syntax error\|does not exist\|ERROR:"; then
    technical_failures=$(echo "${output}" | grep -c "exit code: 127\|exit code: 3\|command not found\|syntax error\|does not exist\|ERROR:" || echo "0")
    log_warning "${COMPONENT}: Performance check found ${technical_failures} technical failures (scripts have SQL errors or compatibility issues, not performance problems)"
    # Don't count technical failures as performance issues
    fail_count=$((fail_count - technical_failures))
    if [[ ${fail_count} -lt 0 ]]; then
     fail_count=0
    fi
   fi

   record_metric "${COMPONENT}" "performance_check_passes" "${pass_count}" "component=ingestion"
   record_metric "${COMPONENT}" "performance_check_failures" "${fail_count}" "component=ingestion"
   record_metric "${COMPONENT}" "performance_check_warnings" "${warning_count}" "component=ingestion"
   if [[ ${technical_failures} -gt 0 ]]; then
    record_metric "${COMPONENT}" "performance_check_technical_failures" "${technical_failures}" "component=ingestion"
   fi

   # Check performance check duration threshold
   local perf_duration_threshold="${INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD:-300}"
   if [[ ${duration} -gt ${perf_duration_threshold} ]]; then
    log_warning "${COMPONENT}: Performance check duration (${duration}s) exceeds threshold (${perf_duration_threshold}s)"
    if command -v send_alert >/dev/null 2>&1; then
     send_alert "${COMPONENT}" "WARNING" "performance_check" "Performance check took too long: ${duration}s (threshold: ${perf_duration_threshold}s)" || true
    fi
   fi

   # Log if script took a long time (for monitoring purposes)
   if [[ ${duration} -gt 600 ]]; then
    log_warning "${COMPONENT}: Performance check took ${duration}s (> 10 minutes) - consider optimizing or running less frequently"
   fi

   # Check performance check failures (only alert on real performance failures, not technical issues)
   if [[ ${fail_count} -gt 0 ]]; then
    log_warning "${COMPONENT}: Performance check found ${fail_count} performance failures"
    if command -v send_alert >/dev/null 2>&1; then
     send_alert "${COMPONENT}" "WARNING" "performance_check" "Performance check found ${fail_count} failures, ${warning_count} warnings" || true
    fi
   elif [[ ${technical_failures} -gt 0 ]]; then
    # Log technical failures but don't alert (these are configuration issues, not performance problems)
    log_info "${COMPONENT}: Performance check completed with ${technical_failures} technical failures (scripts cannot execute - check PATH configuration)"
   fi

   # Check performance check warnings threshold
   local perf_warnings_threshold="${INGESTION_PERFORMANCE_CHECK_WARNINGS_THRESHOLD:-10}"
   if [[ ${warning_count} -gt ${perf_warnings_threshold} ]]; then
    log_warning "${COMPONENT}: Performance check warnings (${warning_count}) exceeds threshold (${perf_warnings_threshold})"
    if command -v send_alert >/dev/null 2>&1; then
     send_alert "${COMPONENT}" "WARNING" "performance_check" "Performance check found ${warning_count} warnings (threshold: ${perf_warnings_threshold})" || true
    fi
   elif [[ ${warning_count} -gt 0 ]]; then
    log_warning "${COMPONENT}: Performance check found ${warning_count} warnings"
   fi

   # Remove lock file after successful execution
   if [[ -f "${lock_file}" ]]; then
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2> /dev/null || echo "")
    if [[ "${lock_pid}" == "$$" ]]; then
     rm -f "${lock_file}"
    fi
   fi
  else
   # Extract error message from output (first few lines)
   local error_summary
   error_summary=$(echo "${output}" | head -10 | tr '\n' '; ' | sed 's/; $//')

   # Determine error type based on exit code
   local error_type="unknown"
   local error_hint=""
   case ${exit_code} in
   124)
    error_type="timeout"
    error_hint="Script execution timed out after ${script_timeout}s. The script may be stuck or taking too long. Consider increasing INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD or investigating why the script is slow."
    ;;
   255)
    error_type="script_execution_failed"
    error_hint="Exit code 255 usually indicates: script syntax error, command not found, or bash execution failure. Check script syntax and dependencies."
    ;;
   127)
    error_type="command_not_found"
    error_hint="Exit code 127 indicates a command was not found. Check PATH and script dependencies."
    ;;
   126)
    error_type="permission_denied"
    error_hint="Exit code 126 indicates permission denied. Check script and file permissions."
    ;;
   *)
    error_type="script_error"
    error_hint="Script returned exit code ${exit_code}. Review script output for details."
    ;;
   esac

   log_error "${COMPONENT}: Performance analysis failed (exit_code: ${exit_code}, duration: ${duration}s, type: ${error_type})"
   log_error "${COMPONENT}: Script path: ${perf_script}"
   log_error "${COMPONENT}: Error hint: ${error_hint}"

   # Log more details if output file exists
   if [[ -f "${output_file}" ]]; then
    log_error "${COMPONENT}: Full error output saved to: ${output_file}"
    log_error "${COMPONENT}: Error output (first 20 lines):"
    head -20 "${output_file}" | while IFS= read -r line; do
     log_error "${COMPONENT}:   ${line}"
    done
   else
    log_error "${COMPONENT}: Error output (first 20 lines):"
    echo "${output}" | head -20 | while IFS= read -r line; do
     log_error "${COMPONENT}:   ${line}"
    done
   fi

   record_metric "${COMPONENT}" "performance_check_status" "0" "component=ingestion,check=analyzeDatabasePerformance"
   record_metric "${COMPONENT}" "performance_check_duration" "${duration}" "component=ingestion,check=analyzeDatabasePerformance"
   record_metric "${COMPONENT}" "performance_check_exit_code" "${exit_code}" "component=ingestion,check=analyzeDatabasePerformance"

   # Include error summary in alert message (truncate if too long)
   local alert_message
   if [[ ${#error_summary} -gt 200 ]]; then
    alert_message="Performance analysis failed: exit_code=${exit_code} (${error_type}), duration=${duration}s. ${error_hint} Error: ${error_summary:0:150}... Full output: ${output_file}"
   else
    alert_message="Performance analysis failed: exit_code=${exit_code} (${error_type}), duration=${duration}s. ${error_hint} Error: ${error_summary} Full output: ${output_file}"
   fi

   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "CRITICAL" "performance_check_failed" "${alert_message}" || true
   fi

   # Remove lock file on error (including timeout)
   if [[ -f "${lock_file}" ]]; then
    local lock_pid
    lock_pid=$(cat "${lock_file}" 2> /dev/null || echo "")
    if [[ "${lock_pid}" == "$$" ]]; then
     rm -f "${lock_file}"
     log_debug "${COMPONENT}: Removed lock file after error/timeout"
    fi
   fi
  fi
 else
  log_warning "${COMPONENT}: analyzeDatabasePerformance.sh not found: ${perf_script}"
  log_info "${COMPONENT}: Skipping script-based performance check (script not available)"
 fi

 # Remove lock file if it exists (cleanup) - ensure we always clean up
 local lock_file="${TMP_DIR}/analyzeDatabasePerformance.lock"
 if [[ -f "${lock_file}" ]]; then
  local lock_pid
  lock_pid=$(cat "${lock_file}" 2> /dev/null || echo "")
  # Only remove if it's our lock (our PID)
  if [[ "${lock_pid}" == "$$" ]]; then
   rm -f "${lock_file}"
   log_debug "${COMPONENT}: Cleaned up lock file"
  fi
 fi

 log_info "${COMPONENT}: Database performance check completed"
 return 0
}

##
# Check data completeness
##
check_data_completeness() {
 log_debug "${COMPONENT}: Checking data completeness"

 # Check database connection
 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot check data completeness - database connection failed"
  return 0
 fi

 # Query to check for missing or null data
 # This is a placeholder - actual queries depend on database schema
 local completeness_query="
        SELECT
            COUNT(*) as total_notes,
            COUNT(*) FILTER (WHERE id IS NULL) as null_ids,
            COUNT(*) FILTER (WHERE created_at IS NULL) as null_dates
        FROM notes
        LIMIT 1;
    "

 # Try to execute query (may fail if table doesn't exist or schema differs)
 local result
 result=$(execute_sql_query "${completeness_query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  log_debug "${COMPONENT}: Data completeness check result: ${result}"
  # Parse and record metrics if needed
 fi

 return 0
}

##
# Check data freshness
##
check_data_freshness() {
 log_debug "${COMPONENT}: Checking data freshness"

 # Check database connection
 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot check data freshness - database connection failed"
  return 0
 fi

 # Query to check last update time
 # This is a placeholder - actual queries depend on database schema
 local freshness_query="
        SELECT
            EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) as freshness_seconds,
            COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') as recent_updates
        FROM notes
        LIMIT 1;
    "

 # Try to execute query
 local result
 result=$(execute_sql_query "${freshness_query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  log_debug "${COMPONENT}: Data freshness check result: ${result}"

  # Parse result (format: freshness_seconds|recent_updates)
  local freshness_seconds
  freshness_seconds=$(echo "${result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "")
  local recent_updates
  recent_updates=$(echo "${result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "")

  if [[ -n "${freshness_seconds}" ]] && [[ "${freshness_seconds}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
   log_debug "${COMPONENT}: Data freshness: ${freshness_seconds} seconds, Recent updates: ${recent_updates}"
   record_metric "${COMPONENT}" "data_freshness_seconds" "${freshness_seconds}" "component=ingestion"

   # Check against threshold
   local freshness_threshold="${INGESTION_DATA_FRESHNESS_THRESHOLD:-3600}"
   if (($(echo "${freshness_seconds} > ${freshness_threshold}" | bc -l 2> /dev/null || echo "0"))); then
    log_warning "${COMPONENT}: Data freshness (${freshness_seconds}s) exceeds threshold (${freshness_threshold}s)"
    if command -v send_alert >/dev/null 2>&1; then
     send_alert "${COMPONENT}" "WARNING" "data_freshness" "Data freshness exceeded: ${freshness_seconds}s (threshold: ${freshness_threshold}s)" || true
    fi
   fi
  fi

  if [[ -n "${recent_updates}" ]] && [[ "${recent_updates}" =~ ^[0-9]+$ ]]; then
   record_metric "${COMPONENT}" "recent_updates_count" "${recent_updates}" "component=ingestion,period=1hour"
  fi
 fi

 return 0
}

##
# Check ingestion data quality using notesCheckVerifier.sh
##
check_ingestion_data_quality() {
 log_info "${COMPONENT}: Starting data quality check"

 # Check if ingestion repository exists
 if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
  log_error "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
  return 1
 fi

 local quality_score=100
 local issues_found=0

 # Check notesCheckVerifier.sh status (script runs once daily via cron at 6 AM)
 # We don't execute it here, just check if it's running or completed successfully
 local verifier_script="${INGESTION_REPO_PATH}/bin/monitor/notesCheckVerifier.sh"

 if [[ -f "${verifier_script}" ]]; then
  log_info "${COMPONENT}: Checking notesCheckVerifier.sh status"

  # Check if script is currently running
  if pgrep -f "notesCheckVerifier.sh" > /dev/null 2>&1; then
   log_info "${COMPONENT}: notesCheckVerifier.sh is currently running (expected - runs daily at 6 AM)"
   record_metric "${COMPONENT}" "data_quality_check_status" "2" "component=ingestion,check=notesCheckVerifier,status=running"
   # Don't penalize quality score if script is running (it's normal)
  else
   # Script is not running - check if it ran successfully today
   # Look for recent execution in logs or check last successful run
   local today_date
   today_date=$(date +%Y-%m-%d)
   local recent_run=0

   # Check for recent temporary directories created by notesCheckVerifier
   local latest_verifier_dir
   latest_verifier_dir=$(find /tmp -maxdepth 1 -type d -name "notesCheckVerifier_*" -printf "%T@ %p\n" 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2-)

   if [[ -n "${latest_verifier_dir}" ]] && [[ -d "${latest_verifier_dir}" ]]; then
    # Check if there's a log file from today
    local verifier_log="${latest_verifier_dir}/notesCheckVerifier.log"
    if [[ -f "${verifier_log}" ]]; then
     local log_date
     log_date=$(stat -c %y "${verifier_log}" 2> /dev/null | cut -d' ' -f1 || echo "")
     if [[ "${log_date}" == "${today_date}" ]]; then
      # Check if log indicates success
      if grep -qiE "completed|success|no discrepancies|finished" "${verifier_log}" 2> /dev/null; then
       recent_run=1
       log_info "${COMPONENT}: notesCheckVerifier.sh completed successfully today"
       record_metric "${COMPONENT}" "data_quality_check_status" "1" "component=ingestion,check=notesCheckVerifier"

       # Count notes not found in database from check tables
       local notes_not_in_db=0
       if check_database_connection; then
        # Query notes_check table in ingestion database (if it exists)
        # Note: This queries the ingestion database, not monitoring database
        local ingestion_db="${INGESTION_DB_NAME:-notes}"
        local query_notes_not_found="SELECT COUNT(*) FROM notes_check nc WHERE NOT EXISTS (SELECT 1 FROM notes n WHERE n.note_id = nc.note_id);"

        # Try to execute query (may fail if table doesn't exist or wrong database)
        # Use execute_sql_query with second parameter to specify database
        local result
        result=$(execute_sql_query "${query_notes_not_found}" "${ingestion_db}" 2> /dev/null | tr -d '[:space:]' || echo "0")

        if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]]; then
         notes_not_in_db=$((result + 0))
         record_metric "${COMPONENT}" "validator_notes_not_in_db_count" "${notes_not_in_db}" "component=ingestion,check=notesCheckVerifier"
         log_info "${COMPONENT}: Found ${notes_not_in_db} notes in check table not present in main database"

         if [[ ${notes_not_in_db} -gt 0 ]]; then
          log_warning "${COMPONENT}: notesCheckVerifier found ${notes_not_in_db} notes not in database"
         fi
        else
         log_debug "${COMPONENT}: Could not query notes_check table (may not exist or not accessible)"
        fi
       fi
      elif grep -qiE "error|failed|discrepancy" "${verifier_log}" 2> /dev/null; then
       log_warning "${COMPONENT}: notesCheckVerifier.sh found issues today (check log: ${verifier_log})"
       record_metric "${COMPONENT}" "data_quality_check_status" "0" "component=ingestion,check=notesCheckVerifier"
       issues_found=$((issues_found + 1))
       quality_score=$((quality_score - 10))
      fi
     fi
    fi
   fi

   # If no recent run found and it's after 7 AM, note that it should have run
   local current_hour
   current_hour=$(date +%H)
   if [[ ${recent_run} -eq 0 ]] && [[ ${current_hour} -ge 7 ]]; then
    log_debug "${COMPONENT}: notesCheckVerifier.sh should have run today (scheduled at 6 AM)"
    # Don't penalize if it's early in the day or script might still be running
    # Only log for information
   fi
  fi
 else
  log_warning "${COMPONENT}: notesCheckVerifier.sh not found: ${verifier_script}"
  log_info "${COMPONENT}: Skipping notesCheckVerifier check (script not available)"
 fi

 # Check data completeness
 check_data_completeness

 # Check data freshness
 check_data_freshness

 # Record overall quality score
 record_metric "${COMPONENT}" "data_quality_score" "${quality_score}" "component=ingestion"

 # Check against threshold
 local quality_threshold="${INGESTION_DATA_QUALITY_THRESHOLD:-95}"

 # Debug in test mode
 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  echo "DEBUG: quality_score=${quality_score}, quality_threshold=${quality_threshold}" >&2
  echo "DEBUG: Will check if ${quality_score} -lt ${quality_threshold}" >&2
 fi

 if [[ ${quality_score} -lt ${quality_threshold} ]]; then
  log_warning "${COMPONENT}: Data quality score (${quality_score}%) below threshold (${quality_threshold}%)"
  if [[ "${TEST_MODE:-false}" == "true" ]]; then
   echo "DEBUG: Calling send_alert for low quality score" >&2
  fi
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "data_quality" "Data quality below threshold: ${quality_score}% (threshold: ${quality_threshold}%)" || true
  fi
  return 1
 fi

 log_info "${COMPONENT}: Data quality check passed - Score: ${quality_score}%"
 return 0
}

##
# Check processing latency
##
check_processing_latency() {
 log_info "${COMPONENT}: Starting processing latency check"

 # Check database connection
 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot check processing latency - database connection failed"
  return 0
 fi

 # Try to get latency from processing_log table if it exists
 local latency_query="
        SELECT
            EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) AS latency_seconds
        FROM processing_log
        WHERE status = 'success'
        LIMIT 1;
    "

 local latency_seconds
 latency_seconds=$(execute_sql_query "${latency_query}" 2> /dev/null || echo "")

 if [[ -n "${latency_seconds}" ]] && [[ "${latency_seconds}" != "" ]]; then
  # Remove any whitespace
  latency_seconds=$(echo "${latency_seconds}" | tr -d '[:space:]')

  # Check if it's a valid number
  if [[ "${latency_seconds}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
   log_info "${COMPONENT}: Processing latency: ${latency_seconds} seconds"
   record_metric "${COMPONENT}" "processing_latency_seconds" "${latency_seconds}" "component=ingestion"

   # Check against threshold
   local latency_threshold="${INGESTION_LATENCY_THRESHOLD:-300}"
   if (($(echo "${latency_seconds} > ${latency_threshold}" | bc -l 2> /dev/null || echo "0"))); then
    log_warning "${COMPONENT}: Processing latency (${latency_seconds}s) exceeds threshold (${latency_threshold}s)"
    if command -v send_alert >/dev/null 2>&1; then
     send_alert "${COMPONENT}" "WARNING" "processing_latency" "High processing latency: ${latency_seconds}s (threshold: ${latency_threshold}s)" || true
    fi
    return 1
   fi
  fi
 else
  # Fallback: Use log file age as proxy for latency
  local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
  if [[ -d "${ingestion_log_dir}" ]]; then
   local latest_log
   latest_log=$(find "${ingestion_log_dir}" -name "*.log" -type f -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2-)

   if [[ -n "${latest_log}" ]]; then
    local log_mtime
    log_mtime=$(stat -c %Y "${latest_log}" 2> /dev/null || stat -f %m "${latest_log}" 2> /dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    local latency_seconds=$((current_time - log_mtime))

    log_info "${COMPONENT}: Processing latency (from log age): ${latency_seconds} seconds"
    record_metric "${COMPONENT}" "processing_latency_seconds" "${latency_seconds}" "component=ingestion,source=log_age"

    # Check against threshold
    local latency_threshold="${INGESTION_LATENCY_THRESHOLD:-300}"
    if [[ ${latency_seconds} -gt ${latency_threshold} ]]; then
     log_warning "${COMPONENT}: Processing latency (${latency_seconds}s) exceeds threshold (${latency_threshold}s)"
     if command -v send_alert >/dev/null 2>&1; then
      send_alert "${COMPONENT}" "WARNING" "processing_latency" "High processing latency: ${latency_seconds}s (threshold: ${latency_threshold}s)" || true
     fi
     return 1
    fi
   fi
  fi
 fi

 log_info "${COMPONENT}: Processing latency check passed"
 return 0
}

##
# Check processing frequency
##
check_processing_frequency() {
 log_debug "${COMPONENT}: Checking processing frequency"

 # Check database connection
 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot check processing frequency - database connection failed"
  return 0
 fi

 # Try to get frequency from processing_log table
 local frequency_query="
        SELECT
            AVG(EXTRACT(EPOCH FROM (execution_time - LAG(execution_time) OVER (ORDER BY execution_time)))) / 3600.0 AS avg_frequency_hours
        FROM processing_log
        WHERE status = 'success'
          AND execution_time > NOW() - INTERVAL '7 days'
        ORDER BY execution_time DESC
        LIMIT 10;
    "

 local frequency_hours
 frequency_hours=$(execute_sql_query "${frequency_query}" 2> /dev/null | head -1 | tr -d '[:space:]' || echo "")

 if [[ -n "${frequency_hours}" ]] && [[ "${frequency_hours}" != "" ]] && [[ "${frequency_hours}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  log_debug "${COMPONENT}: Average processing frequency: ${frequency_hours} hours"
  record_metric "${COMPONENT}" "processing_frequency_hours" "${frequency_hours}" "component=ingestion"
 fi

 return 0
}

##
# Check API download status
##
check_api_download_status() {
 log_info "${COMPONENT}: Starting API download status check"

 # Check if ingestion repository exists
 if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
  log_warning "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
  return 0
 fi

 # Look for API download logs or status files
 local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
 local api_download_status=0 # 0 = unknown, 1 = success

 # Method 1: Check for recent API download activity in logs
 if [[ -d "${ingestion_log_dir}" ]]; then
  # Look for API-related log entries
  local recent_api_logs
  if [[ "${TEST_MODE:-false}" == "true" ]]; then
   mapfile -t recent_api_logs < <(find "${ingestion_log_dir}" \( -name "*api*" -o -name "*download*" \) -type f 2> /dev/null | head -5)
  else
   mapfile -t recent_api_logs < <(find "${ingestion_log_dir}" \( -name "*api*" -o -name "*download*" \) -type f -mmin -60 2> /dev/null | head -5)
  fi

  if [[ "${TEST_MODE:-false}" == "true" ]]; then
   echo "DEBUG: Found ${#recent_api_logs[@]} API/download log files" >&2
  fi

  if [[ ${#recent_api_logs[@]} -gt 0 ]]; then
   # Check for success indicators
   for log_file in "${recent_api_logs[@]}"; do
    # In test mode, skip old logs (older than 1 hour) even if found
    if [[ "${TEST_MODE:-false}" == "true" ]]; then
     local log_mtime
     log_mtime=$(stat -c %Y "${log_file}" 2> /dev/null || stat -f %m "${log_file}" 2> /dev/null || echo "0")
     local current_time
     current_time=$(date +%s)
     local age_seconds=$((current_time - log_mtime))
     # Skip logs older than 1 hour in test mode
     if [[ ${age_seconds} -gt 3600 ]]; then
      if [[ "${TEST_MODE:-false}" == "true" ]]; then
       echo "DEBUG: Skipping old log: ${log_file} (age: ${age_seconds}s)" >&2
      fi
      continue
     fi
    fi
    if grep -qE "success|completed|downloaded|200 OK" "${log_file}" 2> /dev/null; then
     if [[ "${TEST_MODE:-false}" == "true" ]]; then
      echo "DEBUG: Found success indicator in: ${log_file}" >&2
     fi
     api_download_status=1
     break
    fi
   done
  fi
 fi

 # Method 2: Check daemon log for API activity (if using daemon)
 if [[ ${api_download_status} -eq 0 ]]; then
  local daemon_log_file="${DAEMON_LOG_FILE:-/var/log/osm-notes-ingestion/daemon/processAPINotesDaemon.log}"
  if [[ -f "${daemon_log_file}" ]]; then
   # Check if daemon log was modified recently (within last hour)
   local log_mtime
   log_mtime=$(stat -c %Y "${daemon_log_file}" 2> /dev/null || stat -f %m "${daemon_log_file}" 2> /dev/null || echo "0")
   local current_time
   current_time=$(date +%s)
   local age_seconds=$((current_time - log_mtime))

   if [[ ${age_seconds} -lt 3600 ]]; then
    # Check for API-related activity in daemon log (last 100 lines)
    if tail -100 "${daemon_log_file}" 2> /dev/null | grep -qE "(API|download|downloading|notes.*API|Cycle.*completed)" 2> /dev/null; then
     log_debug "${COMPONENT}: Found API activity in daemon log (modified ${age_seconds}s ago)"
     api_download_status=1
    fi
   fi
  fi
 fi

 # Method 3: Check for API download script execution
 if [[ ${api_download_status} -eq 0 ]]; then
  local api_script="${INGESTION_REPO_PATH}/bin/process/processAPINotes.sh"
  if [[ -f "${api_script}" ]]; then
   if [[ "${TEST_MODE:-false}" == "true" ]]; then
    echo "DEBUG: Found API script: ${api_script}" >&2
   fi
   # Check if script ran recently (within last hour)
   if [[ -x "${api_script}" ]]; then
    local script_mtime
    script_mtime=$(stat -c %Y "${api_script}" 2> /dev/null || stat -f %m "${api_script}" 2> /dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    local age_seconds=$((current_time - script_mtime))

    if [[ "${TEST_MODE:-false}" == "true" ]]; then
     echo "DEBUG: Script age: ${age_seconds}s" >&2
    fi

    # If script was modified recently, assume it ran
    if [[ ${age_seconds} -lt 3600 ]]; then
     if [[ "${TEST_MODE:-false}" == "true" ]]; then
      echo "DEBUG: Script is recent, setting api_download_status=1" >&2
     fi
     api_download_status=1
    fi
   fi
  else
   if [[ "${TEST_MODE:-false}" == "true" ]]; then
    echo "DEBUG: API script not found: ${api_script}" >&2
   fi
  fi
 fi

 # Method 4: Check daemon metrics for recent activity
 if [[ ${api_download_status} -eq 0 ]]; then
  if check_database_connection 2> /dev/null; then
   # Check if there are recent daemon cycle metrics (indicates daemon is processing)
   local recent_cycle_query
   recent_cycle_query="SELECT COUNT(*) FROM metrics
                               WHERE component = 'ingestion'
                                 AND metric_name = 'daemon_cycle_number'
                                 AND timestamp > NOW() - INTERVAL '1 hour';"
   local recent_cycles
   recent_cycles=$(execute_sql_query "${recent_cycle_query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

   if [[ -n "${recent_cycles}" ]] && [[ "${recent_cycles}" =~ ^[0-9]+$ ]] && [[ ${recent_cycles} -gt 0 ]]; then
    log_debug "${COMPONENT}: Found ${recent_cycles} recent daemon cycle metrics (daemon is active)"
    api_download_status=1
   fi
  fi
 fi

 log_info "${COMPONENT}: API download status: ${api_download_status}"
 record_metric "${COMPONENT}" "api_download_status" "${api_download_status}" "component=ingestion"

 # Debug in test mode
 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  echo "DEBUG: api_download_status=${api_download_status}" >&2
  echo "DEBUG: Will check if ${api_download_status} -eq 0" >&2
 fi

 if [[ ${api_download_status} -eq 0 ]]; then
  log_warning "${COMPONENT}: No recent API download activity detected"
  if [[ "${TEST_MODE:-false}" == "true" ]]; then
   echo "DEBUG: Calling send_alert for no recent activity" >&2
  fi
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "api_download_status" "No recent API download activity detected" || true
  fi
  return 1
 fi

 log_info "${COMPONENT}: API download status check passed"
 return 0
}

##
# Check advanced API metrics using log parser
##
check_advanced_api_metrics() {
 log_info "${COMPONENT}: Starting advanced API metrics check"

 # Check if ingestion repository exists
 if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
  log_debug "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
  return 0
 fi

 # Check if parseApiLogs.sh exists
 local parse_script="${PROJECT_ROOT}/bin/lib/parseApiLogs.sh"
 if [[ ! -f "${parse_script}" ]]; then
  log_debug "${COMPONENT}: API log parser script not found: ${parse_script}"
  return 0
 fi

 # Look for API download logs
 local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
 if [[ ! -d "${ingestion_log_dir}" ]]; then
  log_debug "${COMPONENT}: Ingestion log directory not found: ${ingestion_log_dir}"
  return 0
 fi

 # Parse logs for last 60 minutes
 local time_window_minutes=60
 local metrics_output
 metrics_output=$(parse_api_logs_aggregated "${ingestion_log_dir}" "${time_window_minutes}" 2> /dev/null || echo "")

 if [[ -z "${metrics_output}" ]]; then
  log_debug "${COMPONENT}: No API metrics extracted from logs"
  return 0
 fi

 # Extract metrics from output
 local total_requests=0
 local errors_4xx=0
 local errors_5xx=0
 local rate_limit_hits=0
 local avg_response_time_ms=0
 local avg_response_size_bytes=0
 local avg_notes_per_request=0
 local success_rate_percent=100
 local timeout_rate_percent=0
 local requests_per_minute=0
 local requests_per_hour=0
 local last_note_timestamp=0

 # Note: successful_requests, failed_requests, timeout_requests, and last_request_timestamp
 # are extracted but not directly used (they're used indirectly via success_rate_percent, etc.)
 while IFS='=' read -r key value; do
  case "${key}" in
  total_requests)
   total_requests=${value}
   ;;
  errors_4xx)
   errors_4xx=${value}
   ;;
  errors_5xx)
   errors_5xx=${value}
   ;;
  rate_limit_hits)
   rate_limit_hits=${value}
   ;;
  avg_response_time_ms)
   avg_response_time_ms=${value}
   ;;
  avg_response_size_bytes)
   avg_response_size_bytes=${value}
   ;;
  avg_notes_per_request)
   avg_notes_per_request=${value}
   ;;
  success_rate_percent)
   success_rate_percent=${value}
   ;;
  timeout_rate_percent)
   timeout_rate_percent=${value}
   ;;
  requests_per_minute)
   requests_per_minute=${value}
   ;;
  requests_per_hour)
   requests_per_hour=${value}
   ;;
  last_note_timestamp)
   last_note_timestamp=${value}
   ;;
  # Ignore unused metrics: successful_requests, failed_requests, timeout_requests, last_request_timestamp
  successful_requests | failed_requests | timeout_requests | last_request_timestamp) ;;
  esac
 done <<< "${metrics_output}"

 # Record metrics
 if [[ ${total_requests} -gt 0 ]]; then
  record_metric "${COMPONENT}" "api_response_time_ms" "${avg_response_time_ms}" "component=ingestion"
  record_metric "${COMPONENT}" "api_success_rate_percent" "${success_rate_percent}" "component=ingestion"
  record_metric "${COMPONENT}" "api_timeout_rate_percent" "${timeout_rate_percent}" "component=ingestion"
  record_metric "${COMPONENT}" "api_errors_4xx_count" "${errors_4xx}" "component=ingestion"
  record_metric "${COMPONENT}" "api_errors_5xx_count" "${errors_5xx}" "component=ingestion"
  record_metric "${COMPONENT}" "api_requests_per_minute" "${requests_per_minute}" "component=ingestion"
  record_metric "${COMPONENT}" "api_requests_per_hour" "${requests_per_hour}" "component=ingestion"
  record_metric "${COMPONENT}" "api_rate_limit_hits_count" "${rate_limit_hits}" "component=ingestion"
  record_metric "${COMPONENT}" "api_response_size_bytes" "${avg_response_size_bytes}" "component=ingestion"
  record_metric "${COMPONENT}" "api_notes_per_request" "${avg_notes_per_request}" "component=ingestion"

  if [[ ${last_note_timestamp} -gt 0 ]]; then
   record_metric "${COMPONENT}" "api_last_note_timestamp" "${last_note_timestamp}" "component=ingestion"
  fi

  log_debug "${COMPONENT}: API metrics - Requests: ${total_requests}, Success: ${success_rate_percent}%, Response time: ${avg_response_time_ms}ms"
 fi

 # Check thresholds and send alerts
 local success_threshold="${INGESTION_API_SUCCESS_RATE_THRESHOLD:-95}"
 if [[ ${total_requests} -gt 0 ]] && [[ ${success_rate_percent} -lt ${success_threshold} ]]; then
  log_warning "${COMPONENT}: API success rate (${success_rate_percent}%) below threshold (${success_threshold}%)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "api_success_rate_low" "API success rate is low: ${success_rate_percent}% (threshold: ${success_threshold}%)" || true
  fi
 fi

 if [[ ${errors_5xx} -gt 0 ]]; then
  log_critical "${COMPONENT}: Detected ${errors_5xx} HTTP 5xx errors"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "CRITICAL" "api_errors_5xx" "Detected ${errors_5xx} HTTP 5xx errors" || true
  fi
  return 1
 fi

 local rate_limit_threshold="${INGESTION_API_RATE_LIMIT_THRESHOLD:-10}"
 if [[ ${rate_limit_hits} -gt ${rate_limit_threshold} ]]; then
  log_warning "${COMPONENT}: Rate limit hits (${rate_limit_hits}) exceed threshold (${rate_limit_threshold})"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "api_rate_limit_frequent" "Rate limit reached frequently: ${rate_limit_hits} hits" || true
  fi
 fi

 # Check sync gap (compare last note timestamp with database)
 if [[ ${last_note_timestamp} -gt 0 ]]; then
  local sync_gap_query
  sync_gap_query="SELECT EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))::integer FROM notes;"
  local db_last_note_age
  db_last_note_age=$(execute_sql_query "${sync_gap_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

  if [[ -n "${db_last_note_age}" ]] && [[ "${db_last_note_age}" =~ ^[0-9]+$ ]]; then
   local api_note_age
   api_note_age=$(date +%s)
   api_note_age=$((api_note_age - last_note_timestamp))

   local sync_gap=$((api_note_age - db_last_note_age))
   if [[ ${sync_gap} -lt 0 ]]; then
    sync_gap=$((sync_gap * -1))
   fi

   record_metric "${COMPONENT}" "api_sync_gap_seconds" "${sync_gap}" "component=ingestion"

   local sync_gap_threshold="${INGESTION_API_SYNC_GAP_THRESHOLD:-3600}"
   if [[ ${sync_gap} -gt ${sync_gap_threshold} ]]; then
    log_warning "${COMPONENT}: API sync gap (${sync_gap}s) exceeds threshold (${sync_gap_threshold}s)"
    if command -v send_alert >/dev/null 2>&1; then
     send_alert "${COMPONENT}" "WARNING" "api_sync_gap_high" "API sync gap is high: ${sync_gap}s (threshold: ${sync_gap_threshold}s)" || true
    fi
   fi
  fi
 fi

 log_info "${COMPONENT}: Advanced API metrics check completed"
 return 0
}

##
# Check boundary processing metrics
##
check_boundary_metrics() {
 log_info "${COMPONENT}: Starting boundary metrics check"

 # Check if boundary metrics collection script exists
 local boundary_metrics_script="${SCRIPT_DIR}/collectBoundaryMetrics.sh"

 if [[ ! -f "${boundary_metrics_script}" ]]; then
  log_debug "${COMPONENT}: Boundary metrics collection script not found: ${boundary_metrics_script}"
  return 0
 fi

 # Check if script is executable
 if [[ ! -x "${boundary_metrics_script}" ]]; then
  log_debug "${COMPONENT}: Boundary metrics collection script is not executable: ${boundary_metrics_script}"
  return 0
 fi

 # Run boundary metrics collection
 local output
 local exit_code=0

 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  # In test mode, capture output for debugging
  output=$(bash "${boundary_metrics_script}" 2>&1) || exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
   log_debug "${COMPONENT}: Boundary metrics collection output: ${output}"
  fi
 else
  # In production, run silently and log errors
  bash "${boundary_metrics_script}" > /dev/null 2>&1 || exit_code=$?
 fi

 if [[ ${exit_code} -ne 0 ]]; then
  log_warning "${COMPONENT}: Boundary metrics collection failed (exit code: ${exit_code})"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "boundary_metrics_collection_failed" "Boundary metrics collection failed with exit code ${exit_code}" || true
  fi
  return 1
 fi

 # Check collected metrics and send alerts
 local countries_update_age_query
 countries_update_age_query="SELECT metric_value FROM metrics
                                WHERE component = 'ingestion'
                                  AND metric_name = 'boundary_update_frequency_hours'
                                  AND metadata LIKE '%type=countries%'
                                ORDER BY timestamp DESC
                                LIMIT 1;"

 local countries_update_age
 countries_update_age=$(execute_sql_query "${countries_update_age_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 local update_age_threshold="${INGESTION_BOUNDARY_UPDATE_AGE_THRESHOLD:-168}" # 7 days = 168 hours
 if [[ -n "${countries_update_age}" ]] && [[ "${countries_update_age}" =~ ^[0-9]+$ ]]; then
  if [[ ${countries_update_age} -gt ${update_age_threshold} ]]; then
   log_warning "${COMPONENT}: Countries boundary update age (${countries_update_age} hours) exceeds threshold (${update_age_threshold} hours)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "boundary_update_stale" "Countries boundary data is stale: ${countries_update_age} hours old (threshold: ${update_age_threshold} hours)" || true
   fi
  fi
 fi

 # Check percentage of notes without country
 local notes_without_country_query
 notes_without_country_query="SELECT metric_value FROM metrics
                                 WHERE component = 'ingestion'
                                   AND metric_name = 'boundary_notes_without_country_count'
                                 ORDER BY timestamp DESC
                                 LIMIT 1;"

 local notes_without_country
 notes_without_country=$(execute_sql_query "${notes_without_country_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 local notes_with_country_query
 notes_with_country_query="SELECT metric_value FROM metrics
                              WHERE component = 'ingestion'
                                AND metric_name = 'boundary_notes_with_country_count'
                              ORDER BY timestamp DESC
                              LIMIT 1;"

 local notes_with_country
 notes_with_country=$(execute_sql_query "${notes_with_country_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${notes_without_country}" ]] && [[ "${notes_without_country}" =~ ^[0-9]+$ ]] \
  && [[ -n "${notes_with_country}" ]] && [[ "${notes_with_country}" =~ ^[0-9]+$ ]]; then
  local total_notes=$((notes_without_country + notes_with_country))
  if [[ ${total_notes} -gt 0 ]]; then
   local percentage_without_country=0
   percentage_without_country=$((notes_without_country * 100 / total_notes))

   local percentage_threshold="${INGESTION_BOUNDARY_NO_COUNTRY_THRESHOLD:-10}"
   if [[ ${percentage_without_country} -gt ${percentage_threshold} ]]; then
    log_warning "${COMPONENT}: Percentage of notes without country (${percentage_without_country}%) exceeds threshold (${percentage_threshold}%)"
    if command -v send_alert >/dev/null 2>&1; then
     send_alert "${COMPONENT}" "WARNING" "boundary_no_country_high" "High percentage of notes without country: ${percentage_without_country}% (${notes_without_country}/${total_notes})" || true
    fi
   fi
  fi
 fi

 # Check for notes with wrong country assignments
 local wrong_country_query
 wrong_country_query="SELECT metric_value FROM metrics
                        WHERE component = 'ingestion'
                          AND metric_name = 'boundary_notes_wrong_country_count'
                        ORDER BY timestamp DESC
                        LIMIT 1;"

 local wrong_country_count
 wrong_country_count=$(execute_sql_query "${wrong_country_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${wrong_country_count}" ]] && [[ "${wrong_country_count}" =~ ^[0-9]+$ ]] && [[ ${wrong_country_count} -gt 0 ]]; then
  log_warning "${COMPONENT}: Detected ${wrong_country_count} notes with wrong country assignment"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "boundary_wrong_country" "Detected ${wrong_country_count} notes with wrong country assignment" || true
  fi
 fi

 log_info "${COMPONENT}: Boundary metrics check completed"
 return 0
}

##
# Check structured log metrics
##
check_structured_log_metrics() {
 log_info "${COMPONENT}: Starting structured log metrics check"

 # Check if daemon log file exists
 local daemon_log_file="${DAEMON_LOG_FILE:-/var/log/osm-notes-ingestion/daemon/processAPINotesDaemon.log}"

 if [[ ! -f "${daemon_log_file}" ]]; then
  log_debug "${COMPONENT}: Daemon log file not found: ${daemon_log_file}"
  return 0
 fi

 # Parse structured logs (last 24 hours by default)
 local time_window_hours="${INGESTION_LOG_ANALYSIS_WINDOW_HOURS:-24}"

 if ! parse_structured_logs "${daemon_log_file}" "${time_window_hours}"; then
  log_warning "${COMPONENT}: Structured log parsing failed"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "structured_log_parsing_failed" "Failed to parse structured logs from ${daemon_log_file}" || true
  fi
  return 1
 fi

 # Check for failed cycles
 local failed_cycles
 failed_cycles=$(get_metric_value "${COMPONENT}" "daemon_cycles_failed_count" "component=ingestion" || echo "0")

 if [[ -n "${failed_cycles}" ]] && [[ "${failed_cycles}" =~ ^[0-9]+$ ]] && [[ ${failed_cycles} -gt 0 ]]; then
  log_warning "${COMPONENT}: Detected ${failed_cycles} failed cycles in logs"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "CRITICAL" "cycles_failed" "Detected ${failed_cycles} failed cycles in daemon logs" || true
  fi
 fi

 # Check for slow stages
 local slowest_stage_duration
 slowest_stage_duration=$(get_metric_value "${COMPONENT}" "log_slowest_stage_duration_seconds" "component=ingestion" || echo "0")
 local stage_threshold="${INGESTION_SLOW_STAGE_THRESHOLD_SECONDS:-30}"

if [[ -n "${slowest_stage_duration}" ]] && [[ "${slowest_stage_duration}" =~ ^[0-9]+$ ]] && [[ ${slowest_stage_duration} -gt ${stage_threshold} ]]; then
 log_warning "${COMPONENT}: Slowest stage duration (${slowest_stage_duration}s) exceeds threshold (${stage_threshold}s)"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "WARNING" "slow_stage_detected" "Slowest stage duration: ${slowest_stage_duration}s (threshold: ${stage_threshold}s)" || true
 fi
fi

 # Check for log gaps (no cycles in last hour)
 # Use multiple methods to detect cycles for better reliability
 local recent_cycles_count=0
 local cycles_found_in_log=0
 local cycles_found_via_grep=0

 if [[ -f "${daemon_log_file}" ]]; then
  # Get current time and time 1 hour ago
  local current_time
  current_time=$(date +%s)
  local one_hour_ago=$((current_time - 3600))

  # Method 1: Count cycles completed in last hour directly from log with timestamp parsing
  # Look for "Cycle X completed successfully" lines with timestamps in last hour
  while IFS= read -r line; do
   # Extract timestamp from log line (format: YYYY-MM-DD HH:MM:SS)
   if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
    local log_timestamp
    log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2> /dev/null || echo "0")
    if [[ ${log_timestamp} -ge ${one_hour_ago} ]] && [[ ${log_timestamp} -gt 0 ]]; then
     if [[ "${line}" =~ Cycle[[:space:]]+[0-9]+[[:space:]]+completed[[:space:]]+successfully ]]; then
      cycles_found_in_log=$((cycles_found_in_log + 1))
     fi
    fi
   fi
  done < <(tail -5000 "${daemon_log_file}" 2> /dev/null || echo "")

  # Method 2: Use grep to find recent cycles (more efficient for large logs)
  # Get hour pattern for last hour
  local hour_pattern
  hour_pattern=$(date -d '1 hour ago' '+%Y-%m-%d %H' 2> /dev/null || date -v-1H '+%Y-%m-%d %H' 2> /dev/null || echo "")
  if [[ -n "${hour_pattern}" ]]; then
   # Count cycles in last hour using hour pattern
   cycles_found_via_grep=$(grep -E "Cycle [0-9]+ completed successfully" "${daemon_log_file}" 2> /dev/null \
    | grep -c "${hour_pattern}" 2> /dev/null | tr -d '[:space:]' || echo "0")
   cycles_found_via_grep=$((cycles_found_via_grep + 0))
  fi

  # Use the maximum of both methods
  if [[ ${cycles_found_in_log} -gt ${cycles_found_via_grep} ]]; then
   recent_cycles_count=${cycles_found_in_log}
  else
   recent_cycles_count=${cycles_found_via_grep}
  fi

  log_debug "${COMPONENT}: Cycle detection - Direct parse: ${cycles_found_in_log}, Grep pattern: ${cycles_found_via_grep}, Final count: ${recent_cycles_count}"
 fi

 # Check metrics as additional verification
 local log_cycles_per_hour
 log_cycles_per_hour=$(get_metric_value "${COMPONENT}" "log_cycles_frequency_per_hour" "component=ingestion" || echo "")

 local daemon_cycles_per_hour
 daemon_cycles_per_hour=$(get_metric_value "${COMPONENT}" "daemon_cycles_per_hour" "component=ingestion" || echo "")

 # Check last cycle timestamp from metrics
 local last_cycle_timestamp_query
 last_cycle_timestamp_query="SELECT MAX(timestamp) FROM metrics
                                WHERE component = 'ingestion'
                                  AND metric_name = 'daemon_cycle_number'
                                  AND timestamp > NOW() - INTERVAL '1 hour';"
 local last_cycle_timestamp
 last_cycle_timestamp=$(execute_sql_query "${last_cycle_timestamp_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 # Determine if there's a gap
 # Alert if: no cycles found in log AND (metrics show 0 OR no recent cycle timestamp)
 local should_alert=false
 local alert_reason=""

 if [[ ${recent_cycles_count} -eq 0 ]]; then
  if [[ -n "${log_cycles_per_hour}" ]] && [[ "${log_cycles_per_hour}" =~ ^[0-9]+$ ]] && [[ ${log_cycles_per_hour} -eq 0 ]]; then
   if [[ -z "${last_cycle_timestamp}" ]]; then
    should_alert=true
    alert_reason="No cycles in log (${recent_cycles_count}), metric shows 0 (${log_cycles_per_hour}), and no recent cycle timestamp"
   fi
  elif [[ -z "${last_cycle_timestamp}" ]]; then
   should_alert=true
   alert_reason="No cycles in log (${recent_cycles_count}) and no recent cycle timestamp in metrics"
  fi
 fi

if [[ "${should_alert}" == "true" ]]; then
 log_warning "${COMPONENT}: No cycles detected in last hour (possible log gap) - Log cycles: ${recent_cycles_count}, log_cycles_per_hour: ${log_cycles_per_hour}, daemon_cycles_per_hour: ${daemon_cycles_per_hour}, last_cycle_timestamp: ${last_cycle_timestamp}"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "WARNING" "log_gap_detected" "No cycles detected in last hour - possible processing gap. ${alert_reason}" || true
 fi
 elif [[ ${recent_cycles_count} -gt 0 ]]; then
  log_debug "${COMPONENT}: Found ${recent_cycles_count} cycles in last hour (no gap detected)"
 fi

 log_info "${COMPONENT}: Structured log metrics check completed"
 return 0
}

##
# Check API download success rate
##
check_api_download_success_rate() {
 log_info "${COMPONENT}: Starting API download success rate check"

 local total_downloads=0
 local successful_downloads=0

 # Check daemon log file first (primary source)
 local daemon_log_file="${DAEMON_LOG_FILE:-/var/log/osm-notes-ingestion/daemon/processAPINotesDaemon.log}"

 if [[ -f "${daemon_log_file}" ]]; then
  # Source collectDaemonMetrics.sh to get parse_log_timestamp function
  # This function handles multiple timestamp formats robustly
  local daemon_metrics_script="${SCRIPT_DIR}/collectDaemonMetrics.sh"
  if [[ -f "${daemon_metrics_script}" ]]; then
   # shellcheck disable=SC1090
   source "${daemon_metrics_script}" 2> /dev/null || true
  fi

  # Define parse_log_timestamp if not available (fallback)
  if ! declare -f parse_log_timestamp > /dev/null 2>&1; then
   parse_log_timestamp() {
    local log_line="${1:-}"
    if [[ -z "${log_line}" ]]; then
     echo "0"
     return 0
    fi
    # Try multiple timestamp formats
    # Format 1: YYYY-MM-DD HH:MM:SS (basic format)
    if [[ "${log_line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
     local log_date="${BASH_REMATCH[1]}"
     local log_time="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
     local log_timestamp="${log_date} ${log_time}"
     local timestamp_epoch
     timestamp_epoch=$(date -d "${log_timestamp}" +%s 2> /dev/null || echo "0")
     if [[ ${timestamp_epoch} -gt 0 ]]; then
      echo "${timestamp_epoch}"
      return 0
     fi
    fi
    # Format 2: YYYY-MM-DD HH:MM:SS.microseconds
    if [[ "${log_line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2})\.[0-9]+ ]]; then
     local log_date="${BASH_REMATCH[1]}"
     local log_time="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
     local log_timestamp="${log_date} ${log_time}"
     local timestamp_epoch
     timestamp_epoch=$(date -d "${log_timestamp}" +%s 2> /dev/null || echo "0")
     if [[ ${timestamp_epoch} -gt 0 ]]; then
      echo "${timestamp_epoch}"
      return 0
     fi
    fi
    echo "0"
    return 0
   }
  fi

  # Count API download attempts in last 24 hours - look for "__getNewNotesFromApi" function calls
  # Each cycle calls this function once to download from API
  # Filter by timestamp (last 24 hours) instead of fixed line count to avoid changing values during the day
  local threshold_timestamp
  threshold_timestamp=$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S' 2> /dev/null || echo "")

  if [[ -n "${threshold_timestamp}" ]]; then
   # Convert threshold timestamp to epoch seconds for comparison
   local threshold_epoch
   threshold_epoch=$(date -d "${threshold_timestamp}" +%s 2> /dev/null || echo "0")

   if [[ ${threshold_epoch} -gt 0 ]]; then

    # Count downloads in last 24 hours by filtering lines with timestamps >= threshold
    local downloads=0
    while IFS= read -r line; do
     # Extract timestamp using robust parsing function
     local log_epoch
     log_epoch=$(parse_log_timestamp "${line}")
     # Compare timestamps (log_epoch >= threshold_epoch means within last 24 hours)
     if [[ ${log_epoch} -ge ${threshold_epoch} ]] && [[ ${log_epoch} -gt 0 ]]; then
      if [[ "${line}" =~ (__getNewNotesFromApi|getNewNotesFromApi) ]]; then
       downloads=$((downloads + 1))
      fi
     fi
    done < <(tail -5000 "${daemon_log_file}" 2> /dev/null || echo "")

    # Count successful downloads in last 24 hours
    # Look for explicit success messages or indicators that API call completed successfully
    # Success can be indicated by:
    # 1. Explicit success messages
    # 2. Cycle completion messages that mention API processing
    local successes=0
    while IFS= read -r line; do
     # Extract timestamp using robust parsing function
     local log_epoch
     log_epoch=$(parse_log_timestamp "${line}")
     # Compare timestamps
     if [[ ${log_epoch} -ge ${threshold_epoch} ]] && [[ ${log_epoch} -gt 0 ]]; then
      # Check for explicit success messages
      if [[ "${line}" =~ (Successfully downloaded notes from API|SEQUENTIAL API XML PROCESSING COMPLETED SUCCESSFULLY) ]]; then
       successes=$((successes + 1))
      # Also check for cycle completion messages that mention API processing
      # This indicates the API call finished successfully
      elif [[ "${line}" =~ (API.*processing.*complete|API.*call.*complete|API.*download.*complete|cycle.*API.*complete) ]]; then
       successes=$((successes + 1))
      fi
     fi
    done < <(tail -5000 "${daemon_log_file}" 2> /dev/null || echo "")

    # If we still have fewer successes than downloads, apply heuristic:
    # If there are no API-related errors in the logs, assume unmatched downloads succeeded
    # This handles cases where API returns successfully but with no new data
    # (which may not log explicit success messages)
    if [[ ${downloads} -gt ${successes} ]]; then
     # Count explicit API-related errors in the same time window
     local api_errors=0
     while IFS= read -r line; do
      local log_epoch
      log_epoch=$(parse_log_timestamp "${line}")
      if [[ ${log_epoch} -ge ${threshold_epoch} ]] && [[ ${log_epoch} -gt 0 ]]; then
       # Look for API-related error messages (errors that occur with API calls)
       if [[ "${line}" =~ (__getNewNotesFromApi|getNewNotesFromApi|API.*download) ]] \
        && [[ "${line}" =~ (error|ERROR|failed|FAILED|exception|EXCEPTION|timeout|TIMEOUT|connection.*refused|network.*error|HTTP.*[45][0-9]{2}) ]]; then
        api_errors=$((api_errors + 1))
       fi
      fi
     done < <(tail -5000 "${daemon_log_file}" 2> /dev/null || echo "")

     # Calculate unmatched downloads (downloads without explicit success or error indicators)
     local unmatched_downloads=$((downloads - successes))

     # If there are unmatched downloads and no API errors, assume they succeeded
     # This is a conservative heuristic: if API call completes without errors,
     # it's likely successful even if it doesn't log an explicit success message
     # (e.g., when API returns successfully but with no new data to process)
     if [[ ${unmatched_downloads} -gt 0 ]] && [[ ${api_errors} -eq 0 ]]; then
      # No errors found, assume all unmatched downloads succeeded
      successes=${downloads}
      log_debug "${COMPONENT}: Assuming ${unmatched_downloads} unmatched API downloads succeeded (no errors found)"
     fi

     # Ensure we don't exceed downloads
     if [[ ${successes} -gt ${downloads} ]]; then
      successes=${downloads}
     fi
    fi

    # Log detailed information for debugging low success rates
    if [[ ${downloads} -gt 0 ]] && [[ ${successes} -lt ${downloads} ]]; then
     local success_rate_calc=$((successes * 100 / downloads))
     if [[ ${success_rate_calc} -lt 50 ]]; then
      log_debug "${COMPONENT}: Low API download success rate detected: ${success_rate_calc}% (${successes}/${downloads}). This may be normal if API calls succeed but return no new data."
     fi
    fi

    total_downloads=${downloads}
    successful_downloads=${successes}
   else
    # Fallback: use tail -10000 if date conversion fails
    # WARNING: This fallback uses tail -10000 instead of 24-hour timestamp filtering.
    # This may include older log entries if the log file has fewer than 10000 recent lines,
    # potentially inflating error counts with stale data. This is a limitation when date command fails.
    local downloads
    downloads=$(tail -10000 "${daemon_log_file}" 2> /dev/null | grep -cE "__getNewNotesFromApi|getNewNotesFromApi" 2> /dev/null || echo "0")
    downloads=$(echo "${downloads}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
    downloads=$((downloads + 0))

    local successes
    # Count explicit success messages and API completion messages
    # Note: Includes cycle.*API.*complete pattern to match primary code path (line 2247)
    successes=$(tail -10000 "${daemon_log_file}" 2> /dev/null | grep -cE "Successfully downloaded notes from API|SEQUENTIAL API XML PROCESSING COMPLETED SUCCESSFULLY|API.*processing.*complete|API.*call.*complete|API.*download.*complete|cycle.*API.*complete" 2> /dev/null || echo "0")
    successes=$(echo "${successes}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
    successes=$((successes + 0))

    # If fewer successes than downloads and no errors, assume unmatched downloads succeeded
    if [[ ${downloads} -gt ${successes} ]]; then
     # Look for API-related errors (errors that occur near API download calls)
     # Check for errors in lines containing API download function names
     # WARNING: Error counting also uses tail -10000 without timestamp filtering,
     # which may include stale errors from days or weeks ago, artificially inflating
     # error counts and producing false low success-rate alerts.
     local api_errors
     api_errors=$(tail -10000 "${daemon_log_file}" 2> /dev/null | grep -E "(__getNewNotesFromApi|getNewNotesFromApi|API.*download)" 2> /dev/null | grep -cE "(error|ERROR|failed|FAILED|exception|EXCEPTION|timeout|TIMEOUT|connection.*refused|network.*error|HTTP.*[45][0-9]{2})" 2> /dev/null || echo "0")
     api_errors=$(echo "${api_errors}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
     api_errors=$((api_errors + 0))

     if [[ ${api_errors} -eq 0 ]]; then
      # No errors found, assume all downloads succeeded
      successes=${downloads}
     fi
    fi

    total_downloads=${downloads}
    successful_downloads=${successes}
   fi
  else
   # Fallback: use tail -10000 if date command fails
   # WARNING: This fallback uses tail -10000 instead of 24-hour timestamp filtering.
   # This may include older log entries if the log file has fewer than 10000 recent lines,
   # potentially inflating error counts with stale data. This is a limitation when date command fails.
   local downloads
   downloads=$(tail -10000 "${daemon_log_file}" 2> /dev/null | grep -cE "__getNewNotesFromApi|getNewNotesFromApi" 2> /dev/null || echo "0")
   downloads=$(echo "${downloads}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
   downloads=$((downloads + 0))

   local successes
   # Count explicit success messages and API completion messages
   # Note: Includes cycle.*API.*complete pattern to match primary code path (line 2247)
   successes=$(tail -10000 "${daemon_log_file}" 2> /dev/null | grep -cE "Successfully downloaded notes from API|SEQUENTIAL API XML PROCESSING COMPLETED SUCCESSFULLY|API.*processing.*complete|API.*call.*complete|API.*download.*complete|cycle.*API.*complete" 2> /dev/null || echo "0")
   successes=$(echo "${successes}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
   successes=$((successes + 0))

   # If fewer successes than downloads and no errors, assume unmatched downloads succeeded
   if [[ ${downloads} -gt ${successes} ]]; then
    # Look for API-related errors (errors that occur near API download calls)
    # Check for errors in lines containing API download function names
    # WARNING: Error counting also uses tail -10000 without timestamp filtering,
    # which may include stale errors from days or weeks ago, artificially inflating
    # error counts and producing false low success-rate alerts.
    local api_errors
    api_errors=$(tail -10000 "${daemon_log_file}" 2> /dev/null | grep -E "(__getNewNotesFromApi|getNewNotesFromApi|API.*download)" 2> /dev/null | grep -cE "(error|ERROR|failed|FAILED|exception|EXCEPTION|timeout|TIMEOUT|connection.*refused|network.*error|HTTP.*[45][0-9]{2})" 2> /dev/null || echo "0")
    api_errors=$(echo "${api_errors}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
    api_errors=$((api_errors + 0))

    if [[ ${api_errors} -eq 0 ]]; then
     # No errors found, assume all downloads succeeded
     successes=${downloads}
    fi
   fi

   total_downloads=${downloads}
   successful_downloads=${successes}
  fi

  if [[ "${TEST_MODE:-false}" == "true" ]]; then
   echo "DEBUG: ${daemon_log_file}: downloads=${total_downloads}, successes=${successful_downloads}" >&2
  fi
 fi

 # Also check ingestion repository logs if available (fallback)
 if [[ -d "${INGESTION_REPO_PATH:-}" ]] && [[ -d "${INGESTION_REPO_PATH}/logs" ]]; then
  local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"

  # Find API-related log files from last 24 hours
  local api_logs
  if [[ "${TEST_MODE:-false}" == "true" ]]; then
   mapfile -t api_logs < <(find "${ingestion_log_dir}" \( -name "*api*" -o -name "*download*" \) -type f 2> /dev/null | head -10)
  else
   mapfile -t api_logs < <(find "${ingestion_log_dir}" \( -name "*api*" -o -name "*download*" \) -type f -mtime -1 2> /dev/null | head -10)
  fi

  for log_file in "${api_logs[@]}"; do
   # Count download attempts - use same specific patterns as daemon log
   # Only count actual API download function calls, not generic "download" or "GET/POST" patterns
   local downloads
   downloads=$(grep -cE "__getNewNotesFromApi|getNewNotesFromApi" "${log_file}" 2> /dev/null || echo "0")
   downloads=$(echo "${downloads}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
   downloads=$((downloads + 0))
   total_downloads=$((total_downloads + downloads))

   # Count successful downloads - use same specific patterns as daemon log
   # Count explicit success messages and API completion messages
   # Note: Includes cycle.*API.*complete pattern to match primary code path (line 2247)
   # WARNING: This counts all matching patterns in the file without timestamp filtering.
   # Files are filtered by -mtime -1 (last 24 hours), but entries within files are not
   # filtered by timestamp, which may include stale log entries if files contain mixed
   # old and new entries. This is a limitation when date command fails.
   local successes
   successes=$(grep -cE "Successfully downloaded notes from API|SEQUENTIAL API XML PROCESSING COMPLETED SUCCESSFULLY|API.*processing.*complete|API.*call.*complete|API.*download.*complete|cycle.*API.*complete" "${log_file}" 2> /dev/null || echo "0")
   successes=$(echo "${successes}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
   successes=$((successes + 0))

   # If fewer successes than downloads and no errors, assume unmatched downloads succeeded
   if [[ ${downloads} -gt ${successes} ]]; then
    # Look for API-related errors (errors that occur near API download calls)
    # Check for errors in lines containing API download function names
    # WARNING: Error counting uses grep without timestamp filtering within files.
    # Files are filtered by -mtime -1 (last 24 hours), but entries within files are not
    # filtered by timestamp, which may include stale errors from days or weeks ago if
    # files contain mixed old and new entries, artificially inflating error counts and
    # producing false low success-rate alerts.
    local api_errors
    api_errors=$(grep -E "(__getNewNotesFromApi|getNewNotesFromApi|API.*download)" "${log_file}" 2> /dev/null | grep -cE "(error|ERROR|failed|FAILED|exception|EXCEPTION|timeout|TIMEOUT|connection.*refused|network.*error|HTTP.*[45][0-9]{2})" 2> /dev/null || echo "0")
    api_errors=$(echo "${api_errors}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
    api_errors=$((api_errors + 0))

    if [[ ${api_errors} -eq 0 ]]; then
     # No errors found, assume all downloads succeeded
     successes=${downloads}
    fi
   fi

   successful_downloads=$((successful_downloads + successes))

   if [[ "${TEST_MODE:-false}" == "true" ]]; then
    echo "DEBUG: ${log_file}: downloads=${downloads}, successes=${successes}" >&2
   fi
  done
 fi

 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  echo "DEBUG: Total: downloads=${total_downloads}, successes=${successful_downloads}" >&2
 fi

 # Calculate success rate
 local success_rate=100
 if [[ ${total_downloads} -gt 0 ]]; then
  success_rate=$((successful_downloads * 100 / total_downloads))
 fi

 log_info "${COMPONENT}: API download success rate: ${success_rate}% (${successful_downloads}/${total_downloads})"
 record_metric "${COMPONENT}" "api_download_success_rate_percent" "${success_rate}" "component=ingestion"
 record_metric "${COMPONENT}" "api_download_total_count" "${total_downloads}" "component=ingestion"
 record_metric "${COMPONENT}" "api_download_successful_count" "${successful_downloads}" "component=ingestion"

 # Check against threshold
 local success_threshold="${INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD:-95}"

 # Debug in test mode
 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  echo "DEBUG: success_rate=${success_rate}, success_threshold=${success_threshold}, total_downloads=${total_downloads}" >&2
  echo "DEBUG: Will check if ${success_rate} -lt ${success_threshold} && ${total_downloads} -gt 0" >&2
 fi

 if [[ ${success_rate} -lt ${success_threshold} ]] && [[ ${total_downloads} -gt 0 ]]; then
  log_warning "${COMPONENT}: API download success rate (${success_rate}%) below threshold (${success_threshold}%)"
  if [[ "${TEST_MODE:-false}" == "true" ]]; then
   echo "DEBUG: Calling send_alert for low success rate" >&2
  fi
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "api_download_success_rate" "Low API download success rate: ${success_rate}% (threshold: ${success_threshold}%, ${successful_downloads}/${total_downloads})" || true
  fi
  return 1
 fi

 log_info "${COMPONENT}: API download success rate check passed"
 return 0
}

##
# Check daemon metrics
##
check_daemon_metrics() {
 log_info "${COMPONENT}: Starting daemon metrics check"

 # Check if daemon metrics collection script exists
 local daemon_metrics_script="${SCRIPT_DIR}/collectDaemonMetrics.sh"

 if [[ ! -f "${daemon_metrics_script}" ]]; then
  log_warning "${COMPONENT}: Daemon metrics collection script not found: ${daemon_metrics_script}"
  return 0
 fi

 # Check if script is executable
 if [[ ! -x "${daemon_metrics_script}" ]]; then
  log_warning "${COMPONENT}: Daemon metrics collection script is not executable: ${daemon_metrics_script}"
  return 0
 fi

 # Ensure PATH includes standard binary directories for systemctl and other tools
 # This is critical when script runs from cron or with limited PATH
 local saved_path="${PATH:-}"
 export PATH="/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin:${PATH:-}"

 # Run daemon metrics collection
 local output
 local exit_code=0

 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  # In test mode, capture output for debugging
  output=$(env PATH="${PATH}" bash "${daemon_metrics_script}" 2>&1) || exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
   log_debug "${COMPONENT}: Daemon metrics collection output: ${output}"
  fi
 else
  # In production, run silently and log errors
  env PATH="${PATH}" bash "${daemon_metrics_script}" > /dev/null 2>&1 || exit_code=$?
 fi

 # Restore original PATH
 export PATH="${saved_path}"

 if [[ ${exit_code} -ne 0 ]]; then
  log_warning "${COMPONENT}: Daemon metrics collection failed (exit code: ${exit_code})"
  return 1
 fi

 # Check daemon status from metrics (if available)
 # Get latest daemon_status metric
 local daemon_status_query
 daemon_status_query="SELECT metric_value FROM metrics
                         WHERE component = 'ingestion'
                           AND metric_name = 'daemon_status'
                         ORDER BY timestamp DESC
                         LIMIT 1;"

 local daemon_status
 daemon_status=$(execute_sql_query "${daemon_status_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${daemon_status}" ]]; then
  if [[ "${daemon_status}" == "0" ]]; then
   log_warning "${COMPONENT}: Daemon is not active"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "CRITICAL" "daemon_down" "Daemon service is not active" || true
   fi
   return 1
  fi
 fi

 # Check cycle duration threshold
 local cycle_duration_query
 cycle_duration_query="SELECT metric_value FROM metrics
                          WHERE component = 'ingestion'
                            AND metric_name = 'daemon_cycle_duration_seconds'
                          ORDER BY timestamp DESC
                          LIMIT 1;"

 local cycle_duration
 cycle_duration=$(execute_sql_query "${cycle_duration_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${cycle_duration}" ]] && [[ "${cycle_duration}" =~ ^[0-9]+$ ]]; then
  local cycle_duration_threshold="${INGESTION_DAEMON_CYCLE_DURATION_THRESHOLD:-30}"
  if [[ ${cycle_duration} -gt ${cycle_duration_threshold} ]]; then
   log_warning "${COMPONENT}: Cycle duration (${cycle_duration}s) exceeds threshold (${cycle_duration_threshold}s)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "daemon_cycle_duration" "Cycle duration (${cycle_duration}s) exceeds threshold (${cycle_duration_threshold}s)" || true
   fi
  fi
 fi

 # Check cycle success rate
 local success_rate_query
 success_rate_query="SELECT metric_value FROM metrics
                        WHERE component = 'ingestion'
                          AND metric_name = 'daemon_cycle_success_rate_percent'
                        ORDER BY timestamp DESC
                        LIMIT 1;"

 local success_rate
 success_rate=$(execute_sql_query "${success_rate_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${success_rate}" ]] && [[ "${success_rate}" =~ ^[0-9]+$ ]]; then
  local success_rate_threshold="${INGESTION_DAEMON_SUCCESS_RATE_THRESHOLD:-95}"
  if [[ ${success_rate} -lt ${success_rate_threshold} ]]; then
   log_warning "${COMPONENT}: Cycle success rate (${success_rate}%) below threshold (${success_rate_threshold}%)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "daemon_success_rate" "Cycle success rate (${success_rate}%) below threshold (${success_rate_threshold}%)" || true
   fi
  fi
 fi

 # Check if no processing in last 5 minutes
 local last_cycle_query
 last_cycle_query="SELECT MAX(timestamp) FROM metrics
                      WHERE component = 'ingestion'
                        AND metric_name = 'daemon_cycle_number'
                        AND timestamp > NOW() - INTERVAL '5 minutes';"

 local last_cycle_time
 last_cycle_time=$(execute_sql_query "${last_cycle_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -z "${last_cycle_time}" ]]; then
  log_warning "${COMPONENT}: No daemon processing detected in last 5 minutes"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "CRITICAL" "daemon_no_processing" "No daemon processing detected in last 5 minutes" || true
  fi
  return 1
 fi

 log_info "${COMPONENT}: Daemon metrics check passed"
 return 0
}

##
# Run all checks
##
run_all_checks() {
 log_info "${COMPONENT}: Starting all monitoring checks"

 local checks_passed=0
 local checks_failed=0

 # Health check
 if check_ingestion_health; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Execution status check
 if check_script_execution_status; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Latency check
 if check_processing_latency; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Processing frequency check
 check_processing_frequency

 # Performance check
 if check_ingestion_performance; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Data quality check
 if check_ingestion_data_quality; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Error rate check
 if check_error_rate; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Disk space check
 if check_disk_space; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # API download status check
 if check_api_download_status; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # API download success rate check
 if check_api_download_success_rate; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Advanced API metrics check
 if check_advanced_api_metrics; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Daemon metrics check
 if check_daemon_metrics; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Boundary metrics check
 if check_boundary_metrics; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 # Structured log metrics check
 if check_structured_log_metrics; then
  checks_passed=$((checks_passed + 1))
 else
  checks_failed=$((checks_failed + 1))
 fi

 log_info "${COMPONENT}: Monitoring checks completed - passed: ${checks_passed}, failed: ${checks_failed}"

 if [[ ${checks_failed} -gt 0 ]]; then
  return 1
 fi

 return 0
}

##
# Main
##
main() {
 local check_type="all"
 # shellcheck disable=SC2034
 local verbose=false
 # shellcheck disable=SC2034
 local dry_run=false

 # Parse arguments
 while [[ $# -gt 0 ]]; do
  case "${1}" in
  -c | --check)
   check_type="${2}"
   shift 2
   ;;
  -v | --verbose)
   # shellcheck disable=SC2034
   verbose=true
   export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
   shift
   ;;
  -d | --dry-run)
   # shellcheck disable=SC2034
   dry_run=true
   shift
   ;;
  -h | --help)
   usage
   exit 0
   ;;
  *)
   log_error "${COMPONENT}: Unknown option: ${1}"
   usage
   exit 1
   ;;
  esac
 done

 # Load configuration
 if ! load_all_configs; then
  log_error "${COMPONENT}: Failed to load configuration"
  exit 1
 fi

 # Validate configuration
 if ! validate_all_configs; then
  log_error "${COMPONENT}: Configuration validation failed"
  exit 1
 fi

 # Check if monitoring is enabled
 if [[ "${INGESTION_ENABLED:-true}" != "true" ]]; then
  log_info "${COMPONENT}: Monitoring disabled in configuration"
  exit 0
 fi

 log_info "${COMPONENT}: Starting ingestion monitoring"

 # Run requested check
 case "${check_type}" in
 health)
  if check_ingestion_health; then
   exit 0
  else
   exit 1
  fi
  ;;
 performance)
  if check_ingestion_performance; then
   exit 0
  else
   exit 1
  fi
  ;;
 data-quality)
  if check_ingestion_data_quality; then
   exit 0
  else
   exit 1
  fi
  ;;
 execution-status)
  if check_script_execution_status; then
   exit 0
  else
   exit 1
  fi
  ;;
 latency)
  if check_processing_latency; then
   exit 0
  else
   exit 1
  fi
  ;;
 error-rate)
  if check_error_rate; then
   exit 0
  else
   exit 1
  fi
  ;;
 disk-space)
  if check_disk_space; then
   exit 0
  else
   exit 1
  fi
  ;;
 api-download)
  if check_api_download_status && check_api_download_success_rate; then
   exit 0
  else
   exit 1
  fi
  ;;
 api-advanced)
  if check_advanced_api_metrics; then
   exit 0
  else
   exit 1
  fi
  ;;
 daemon)
  if check_daemon_metrics; then
   exit 0
  else
   exit 1
  fi
  ;;
 boundary)
  if check_boundary_metrics; then
   exit 0
  else
   exit 1
  fi
  ;;
 log-analysis | structured-logs)
  if check_structured_log_metrics; then
   exit 0
  else
   exit 1
  fi
  ;;
 all)
  if run_all_checks; then
   exit 0
  else
   exit 1
  fi
  ;;
 *)
  log_error "${COMPONENT}: Unknown check type: ${check_type}"
  usage
  exit 1
  ;;
 esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
