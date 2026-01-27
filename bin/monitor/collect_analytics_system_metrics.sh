#!/usr/bin/env bash
#
# Analytics System Metrics Collection Script
# Collects system resource metrics specific to Analytics processes (ETL, PostgreSQL, etc.)
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

# Initialize logging only if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 init_logging "${LOG_DIR}/analytics_system_metrics.log" "collectAnalyticsSystemMetrics"
fi

# Component name
readonly COMPONENT="ANALYTICS"

# ETL process name pattern
readonly ETL_PROCESS_PATTERN="${ETL_PROCESS_PATTERN:-ETL.sh}"

# Log directories to monitor
readonly ETL_LOG_DIR="${ETL_LOG_DIR:-/tmp/ETL_*}"

##
# Show usage
##
usage() {
 cat << EOF
Analytics System Metrics Collection Script

Collects system resource metrics specific to Analytics processes.

Usage: $0 [OPTIONS]

Options:
    -h, --help            Show this help message

Examples:
    # Collect all analytics system metrics
    $0
EOF
}

##
# Collect CPU usage by ETL process
##
collect_etl_cpu_usage() {
 log_info "${COMPONENT}: Collecting ETL CPU usage"

 local etl_pid
 etl_pid=$(pgrep -f "${ETL_PROCESS_PATTERN}" | head -1 || echo "")

 if [[ -z "${etl_pid}" ]]; then
  log_debug "${COMPONENT}: ETL process not running"
  record_metric "${COMPONENT}" "etl_cpu_usage_percent" "0" "component=analytics,process=etl"
  return 0
 fi

 # Get CPU usage for ETL process using ps or top
 local cpu_usage=0
 if command -v ps > /dev/null 2>&1; then
  # Get CPU usage percentage (may require multiple samples for accuracy)
  cpu_usage=$(ps -p "${etl_pid}" -o %cpu --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
  cpu_usage=$(echo "${cpu_usage}" | awk '{printf "%.2f", $1}' || echo "0")
 fi

 record_metric "${COMPONENT}" "etl_cpu_usage_percent" "${cpu_usage}" "component=analytics,process=etl"
 record_metric "${COMPONENT}" "etl_process_pid" "${etl_pid}" "component=analytics,process=etl"
 log_info "${COMPONENT}: ETL CPU usage: ${cpu_usage}% (PID: ${etl_pid})"

 return 0
}

##
# Collect memory usage by ETL process
##
collect_etl_memory_usage() {
 log_info "${COMPONENT}: Collecting ETL memory usage"

 local etl_pid
 etl_pid=$(pgrep -f "${ETL_PROCESS_PATTERN}" | head -1 || echo "")

 if [[ -z "${etl_pid}" ]]; then
  log_debug "${COMPONENT}: ETL process not running"
  record_metric "${COMPONENT}" "etl_memory_usage_bytes" "0" "component=analytics,process=etl"
  record_metric "${COMPONENT}" "etl_memory_usage_percent" "0" "component=analytics,process=etl"
  return 0
 fi

 # Get memory usage for ETL process
 local memory_bytes=0
 local memory_percent=0

 if command -v ps > /dev/null 2>&1; then
  # Get RSS (Resident Set Size) in KB, convert to bytes
  local rss_kb
  rss_kb=$(ps -p "${etl_pid}" -o rss --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
  memory_bytes=$((rss_kb * 1024))

  # Get memory percentage
  memory_percent=$(ps -p "${etl_pid}" -o %mem --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
  memory_percent=$(echo "${memory_percent}" | awk '{printf "%.2f", $1}' || echo "0")
 fi

 record_metric "${COMPONENT}" "etl_memory_usage_bytes" "${memory_bytes}" "component=analytics,process=etl"
 record_metric "${COMPONENT}" "etl_memory_usage_percent" "${memory_percent}" "component=analytics,process=etl"
 log_info "${COMPONENT}: ETL memory usage: ${memory_bytes} bytes (${memory_percent}%)"

 return 0
}

##
# Collect disk I/O for ETL process
##
collect_etl_disk_io() {
 log_info "${COMPONENT}: Collecting ETL disk I/O"

 local etl_pid
 etl_pid=$(pgrep -f "${ETL_PROCESS_PATTERN}" | head -1 || echo "")

 if [[ -z "${etl_pid}" ]]; then
  log_debug "${COMPONENT}: ETL process not running"
  record_metric "${COMPONENT}" "etl_disk_read_bytes" "0" "component=analytics,process=etl"
  record_metric "${COMPONENT}" "etl_disk_write_bytes" "0" "component=analytics,process=etl"
  return 0
 fi

 # Get disk I/O from /proc/[pid]/io if available
 local read_bytes=0
 local write_bytes=0

 if [[ -r "/proc/${etl_pid}/io" ]]; then
  read_bytes=$(grep "^read_bytes:" "/proc/${etl_pid}/io" 2> /dev/null | awk '{print $2}' || echo "0")
  write_bytes=$(grep "^write_bytes:" "/proc/${etl_pid}/io" 2> /dev/null | awk '{print $2}' || echo "0")
 fi

 record_metric "${COMPONENT}" "etl_disk_read_bytes" "${read_bytes}" "component=analytics,process=etl"
 record_metric "${COMPONENT}" "etl_disk_write_bytes" "${write_bytes}" "component=analytics,process=etl"
 log_info "${COMPONENT}: ETL disk I/O - Read: ${read_bytes} bytes, Write: ${write_bytes} bytes"

 return 0
}

##
# Collect disk usage for ETL log directories
##
collect_etl_log_disk_usage() {
 log_info "${COMPONENT}: Collecting ETL log disk usage"

 local total_size_bytes=0
 local directory_count=0

 # Find all ETL log directories
 if command -v find > /dev/null 2>&1; then
  while IFS= read -r log_dir; do
   if [[ -d "${log_dir}" ]]; then
    directory_count=$((directory_count + 1))
    local dir_size
    dir_size=$(du -sb "${log_dir}" 2> /dev/null | awk '{print $1}' || echo "0")
    total_size_bytes=$((total_size_bytes + dir_size))
   fi
  done < <(find /tmp -maxdepth 1 -type d -name "ETL_*" 2> /dev/null || true)
 fi

 record_metric "${COMPONENT}" "etl_log_disk_usage_bytes" "${total_size_bytes}" "component=analytics,directory=etl_logs"
 record_metric "${COMPONENT}" "etl_log_directory_count" "${directory_count}" "component=analytics,directory=etl_logs"
 log_info "${COMPONENT}: ETL log disk usage: ${total_size_bytes} bytes (${directory_count} directories)"

 return 0
}

##
# Collect PostgreSQL process metrics
##
collect_postgresql_metrics() {
 log_info "${COMPONENT}: Collecting PostgreSQL metrics"

 local postgres_pid
 postgres_pid=$(pgrep -f "postgres.*analytics\|postgres.*dwh" | head -1 || echo "")

 if [[ -z "${postgres_pid}" ]]; then
  # Try to find any postgres process
  postgres_pid=$(pgrep -f "postgres" | head -1 || echo "")
 fi

 if [[ -z "${postgres_pid}" ]]; then
  log_debug "${COMPONENT}: PostgreSQL process not found"
  record_metric "${COMPONENT}" "postgresql_cpu_usage_percent" "0" "component=analytics,process=postgresql"
  record_metric "${COMPONENT}" "postgresql_memory_usage_bytes" "0" "component=analytics,process=postgresql"
  return 0
 fi

 # Get CPU usage
 local cpu_usage=0
 if command -v ps > /dev/null 2>&1; then
  cpu_usage=$(ps -p "${postgres_pid}" -o %cpu --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
  cpu_usage=$(echo "${cpu_usage}" | awk '{printf "%.2f", $1}' || echo "0")
 fi

 # Get memory usage
 local memory_bytes=0
 local memory_percent=0
 if command -v ps > /dev/null 2>&1; then
  local rss_kb
  rss_kb=$(ps -p "${postgres_pid}" -o rss --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
  memory_bytes=$((rss_kb * 1024))
  memory_percent=$(ps -p "${postgres_pid}" -o %mem --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
  memory_percent=$(echo "${memory_percent}" | awk '{printf "%.2f", $1}' || echo "0")
 fi

 record_metric "${COMPONENT}" "postgresql_cpu_usage_percent" "${cpu_usage}" "component=analytics,process=postgresql"
 record_metric "${COMPONENT}" "postgresql_memory_usage_bytes" "${memory_bytes}" "component=analytics,process=postgresql"
 record_metric "${COMPONENT}" "postgresql_memory_usage_percent" "${memory_percent}" "component=analytics,process=postgresql"
 log_info "${COMPONENT}: PostgreSQL CPU: ${cpu_usage}%, Memory: ${memory_bytes} bytes (${memory_percent}%)"

 return 0
}

##
# Collect system load average
##
collect_load_average() {
 log_info "${COMPONENT}: Collecting system load average"

 if [[ ! -f /proc/loadavg ]]; then
  log_debug "${COMPONENT}: /proc/loadavg not available"
  return 0
 fi

 local load_1min load_5min load_15min
 read -r load_1min load_5min load_15min _ < /proc/loadavg

 if [[ -n "${load_1min}" ]] && [[ "${load_1min}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  record_metric "${COMPONENT}" "system_load_average_1min" "${load_1min}" "component=analytics"
  record_metric "${COMPONENT}" "system_load_average_5min" "${load_5min}" "component=analytics"
  record_metric "${COMPONENT}" "system_load_average_15min" "${load_15min}" "component=analytics"
  log_info "${COMPONENT}: Load average - 1min: ${load_1min}, 5min: ${load_5min}, 15min: ${load_15min}"
 fi

 return 0
}

##
# Collect overall disk usage for root filesystem
##
collect_disk_usage() {
 log_info "${COMPONENT}: Collecting disk usage"

 if ! command -v df > /dev/null 2>&1; then
  log_debug "${COMPONENT}: df command not available"
  return 0
 fi

 local df_output
 df_output=$(df / 2> /dev/null | tail -1 || echo "")

 if [[ -n "${df_output}" ]]; then
  local usage_percent
  usage_percent=$(echo "${df_output}" | awk '{print $5}' | sed 's/%//' || echo "0")
  local disk_total
  disk_total=$(echo "${df_output}" | awk '{print $2 * 1024}' || echo "0")
  local disk_available
  disk_available=$(echo "${df_output}" | awk '{print $4 * 1024}' || echo "0")

  record_metric "${COMPONENT}" "system_disk_usage_percent" "${usage_percent}" "component=analytics,filesystem=/"
  record_metric "${COMPONENT}" "system_disk_total_bytes" "${disk_total}" "component=analytics,filesystem=/"
  record_metric "${COMPONENT}" "system_disk_available_bytes" "${disk_available}" "component=analytics,filesystem=/"
  log_info "${COMPONENT}: Disk usage: ${usage_percent}% (Total: ${disk_total} bytes, Available: ${disk_available} bytes)"
 fi

 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting analytics system metrics collection"

 # Load configuration
 if ! load_monitoring_config; then
  log_error "${COMPONENT}: Failed to load monitoring configuration"
  exit 1
 fi

 # Collect ETL process metrics
 collect_etl_cpu_usage || true
 collect_etl_memory_usage || true
 collect_etl_disk_io || true

 # Collect PostgreSQL metrics
 collect_postgresql_metrics || true

 # Collect log disk usage
 collect_etl_log_disk_usage || true

 # Collect system metrics
 collect_load_average || true
 collect_disk_usage || true

 log_info "${COMPONENT}: Analytics system metrics collection completed"
 return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
