#!/usr/bin/env bash
#
# System Metrics Collection Script
# Collects comprehensive system resource metrics (CPU, memory, I/O, network)
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
init_logging "${LOG_DIR}/system_metrics.log" "collectSystemMetrics"

# Component name
readonly COMPONENT="INFRASTRUCTURE"

##
# Get load average
##
collect_load_average() {
 log_info "${COMPONENT}: Collecting load average"

 if [[ ! -f /proc/loadavg ]]; then
  log_debug "${COMPONENT}: /proc/loadavg not available"
  return 0
 fi

 local load_1min load_5min load_15min
 read -r load_1min load_5min load_15min _ < /proc/loadavg

 if [[ -n "${load_1min}" ]] && [[ "${load_1min}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  record_metric "${COMPONENT}" "system_load_average_1min" "${load_1min}" "component=infrastructure"
  record_metric "${COMPONENT}" "system_load_average_5min" "${load_5min}" "component=infrastructure"
  record_metric "${COMPONENT}" "system_load_average_15min" "${load_15min}" "component=infrastructure"

  log_debug "${COMPONENT}: Load average - 1min: ${load_1min}, 5min: ${load_5min}, 15min: ${load_15min}"
 fi

 return 0
}

##
# Get CPU usage by process
##
collect_cpu_by_process() {
 log_info "${COMPONENT}: Collecting CPU usage by process"

 # Get CPU usage for PostgreSQL
 local postgres_cpu=0
 if command -v ps > /dev/null 2>&1; then
  # Get CPU usage for postgres processes
  local postgres_pids
  postgres_pids=$(pgrep -x postgres 2> /dev/null || echo "")

  if [[ -n "${postgres_pids}" ]]; then
   # Sum CPU usage from all postgres processes
   local total_cpu=0
   while IFS= read -r pid; do
    if [[ -n "${pid}" ]]; then
     local cpu_usage
     cpu_usage=$(ps -p "${pid}" -o %cpu --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
     if [[ "${cpu_usage}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
      # Convert to numeric for addition
      total_cpu=$(awk "BEGIN {printf \"%.2f\", ${total_cpu} + ${cpu_usage}}")
     fi
    fi
   done <<< "${postgres_pids}"

   postgres_cpu="${total_cpu}"
  fi
 fi

 if [[ -n "${postgres_cpu}" ]] && [[ "${postgres_cpu}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  record_metric "${COMPONENT}" "system_cpu_postgres_percent" "${postgres_cpu}" "component=infrastructure,process=postgres"
  log_debug "${COMPONENT}: PostgreSQL CPU usage: ${postgres_cpu}%"
 fi

 return 0
}

##
# Get memory usage by process
##
collect_memory_by_process() {
 log_info "${COMPONENT}: Collecting memory usage by process"

 # Get memory usage for PostgreSQL
 local postgres_memory=0
 local postgres_shared_memory=0

 if command -v ps > /dev/null 2>&1; then
  local postgres_pids
  postgres_pids=$(pgrep -x postgres 2> /dev/null || echo "")

  if [[ -n "${postgres_pids}" ]]; then
   # Sum memory usage from all postgres processes
   local total_memory=0
   local total_shared=0

   while IFS= read -r pid; do
    if [[ -n "${pid}" ]]; then
     # Get RSS (Resident Set Size) in KB, convert to bytes
     local rss_kb
     rss_kb=$(ps -p "${pid}" -o rss= --no-headers 2> /dev/null | tr -d '[:space:]' || echo "0")
     if [[ "${rss_kb}" =~ ^[0-9]+$ ]]; then
      local rss_bytes=$((rss_kb * 1024))
      total_memory=$((total_memory + rss_bytes))
     fi

     # Get shared memory from /proc/[pid]/statm (column 3)
     if [[ -f "/proc/${pid}/statm" ]]; then
      local shared_pages
      shared_pages=$(awk '{print $3}' "/proc/${pid}/statm" 2> /dev/null || echo "0")
      if [[ "${shared_pages}" =~ ^[0-9]+$ ]]; then
       # Convert pages to bytes (assuming 4KB pages)
       local shared_bytes=$((shared_pages * 4096))
       total_shared=$((total_shared + shared_bytes))
      fi
     fi
    fi
   done <<< "${postgres_pids}"

   postgres_memory="${total_memory}"
   postgres_shared_memory="${total_shared}"
  fi
 fi

 if [[ ${postgres_memory} -gt 0 ]]; then
  record_metric "${COMPONENT}" "system_memory_postgres_bytes" "${postgres_memory}" "component=infrastructure,process=postgres"
  log_debug "${COMPONENT}: PostgreSQL memory usage: ${postgres_memory} bytes"
 fi

 if [[ ${postgres_shared_memory} -gt 0 ]]; then
  record_metric "${COMPONENT}" "system_memory_postgres_shared_bytes" "${postgres_shared_memory}" "component=infrastructure,process=postgres"
  log_debug "${COMPONENT}: PostgreSQL shared memory: ${postgres_shared_memory} bytes"
 fi

 return 0
}

##
# Get swap usage
##
collect_swap_usage() {
 log_info "${COMPONENT}: Collecting swap usage"

 if command -v free > /dev/null 2>&1; then
  local swap_output
  swap_output=$(free | grep Swap || echo "")

  if [[ -n "${swap_output}" ]]; then
   local swap_total swap_used
   swap_total=$(echo "${swap_output}" | awk '{print $2}' || echo "0")
   swap_used=$(echo "${swap_output}" | awk '{print $3}' || echo "0")

   # Convert from KB to bytes
   swap_total=$((swap_total * 1024))
   swap_used=$((swap_used * 1024))

   if [[ ${swap_total} -gt 0 ]]; then
    record_metric "${COMPONENT}" "system_swap_total_bytes" "${swap_total}" "component=infrastructure"
    record_metric "${COMPONENT}" "system_swap_used_bytes" "${swap_used}" "component=infrastructure"

    local swap_percent=0
    swap_percent=$((swap_used * 100 / swap_total))
    record_metric "${COMPONENT}" "system_swap_usage_percent" "${swap_percent}" "component=infrastructure"

    log_debug "${COMPONENT}: Swap usage: ${swap_used} bytes (${swap_percent}%)"
   fi
  fi
 fi

 return 0
}

##
# Get disk I/O statistics
##
collect_disk_io() {
 log_info "${COMPONENT}: Collecting disk I/O statistics"

 # Try to get I/O stats from /proc/diskstats or iostat
 if [[ -f /proc/diskstats ]]; then
  # Read diskstats for root device (sda, vda, nvme0n1, etc.)
  local root_device
  root_device=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/\/dev\///' || echo "")

  if [[ -n "${root_device}" ]] && [[ -f "/proc/diskstats" ]]; then
   local disk_line
   disk_line=$(grep -E "^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+${root_device}" /proc/diskstats | head -1 || echo "")

   if [[ -n "${disk_line}" ]]; then
    # Parse diskstats: sectors read, sectors written
    # Note: We only extract sectors_read and sectors_written for I/O metrics
    # Other fields (reads_completed, reads_merged, time_reading, etc.) are available
    # but not currently used for metrics collection
    local sectors_read sectors_written

    sectors_read=$(echo "${disk_line}" | awk '{print $6}' || echo "0")
    sectors_written=$(echo "${disk_line}" | awk '{print $10}' || echo "0")

    # Convert sectors to bytes (assuming 512 bytes per sector)
    local reads_bytes=$((sectors_read * 512))
    local writes_bytes=$((sectors_written * 512))

    record_metric "${COMPONENT}" "system_disk_reads_bytes" "${reads_bytes}" "component=infrastructure,device=${root_device}"
    record_metric "${COMPONENT}" "system_disk_writes_bytes" "${writes_bytes}" "component=infrastructure,device=${root_device}"

    log_debug "${COMPONENT}: Disk I/O - Reads: ${reads_bytes} bytes, Writes: ${writes_bytes} bytes"
   fi
  fi
 elif command -v iostat > /dev/null 2>&1; then
  # Alternative: use iostat if available
  local iostat_output
  iostat_output=$(iostat -x 1 2 2> /dev/null | tail -n +4 || echo "")

  if [[ -n "${iostat_output}" ]]; then
   # Parse iostat output (implementation depends on iostat version)
   log_debug "${COMPONENT}: iostat available but parsing not fully implemented"
  fi
 fi

 return 0
}

##
# Get network traffic statistics
##
collect_network_traffic() {
 log_info "${COMPONENT}: Collecting network traffic statistics"

 if [[ -f /proc/net/dev ]]; then
  # Get total network traffic (sum of all interfaces except loopback)
  local total_rx_bytes=0
  local total_tx_bytes=0

  while IFS= read -r line; do
   # Skip header lines and loopback interface
   if [[ "${line}" =~ ^[[:space:]]*[a-z0-9]+: ]] && [[ ! "${line}" =~ lo: ]]; then
    local rx_bytes tx_bytes
    # Extract RX and TX bytes (interface name not needed for aggregation)
    rx_bytes=$(echo "${line}" | awk '{print $2}' || echo "0")
    tx_bytes=$(echo "${line}" | awk '{print $10}' || echo "0")

    if [[ "${rx_bytes}" =~ ^[0-9]+$ ]] && [[ "${tx_bytes}" =~ ^[0-9]+$ ]]; then
     total_rx_bytes=$((total_rx_bytes + rx_bytes))
     total_tx_bytes=$((total_tx_bytes + tx_bytes))
    fi
   fi
  done < /proc/net/dev

  if [[ ${total_rx_bytes} -gt 0 ]] || [[ ${total_tx_bytes} -gt 0 ]]; then
   record_metric "${COMPONENT}" "system_network_rx_bytes" "${total_rx_bytes}" "component=infrastructure"
   record_metric "${COMPONENT}" "system_network_tx_bytes" "${total_tx_bytes}" "component=infrastructure"

   local total_traffic=$((total_rx_bytes + total_tx_bytes))
   record_metric "${COMPONENT}" "system_network_traffic_bytes" "${total_traffic}" "component=infrastructure"

   log_debug "${COMPONENT}: Network traffic - RX: ${total_rx_bytes} bytes, TX: ${total_tx_bytes} bytes"
  fi
 fi

 return 0
}

##
# Get number of CPU cores
##
get_cpu_count() {
 local cpu_count=1

 if [[ -f /proc/cpuinfo ]]; then
  cpu_count=$(grep -c "^processor" /proc/cpuinfo 2> /dev/null || echo "1")
 elif command -v nproc > /dev/null 2>&1; then
  cpu_count=$(nproc 2> /dev/null || echo "1")
 fi

 echo "${cpu_count}"
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting system metrics collection"

 # Load configuration
 if ! load_all_configs; then
  log_error "${COMPONENT}: Failed to load configuration"
  return 1
 fi

 # Collect all metrics
 collect_load_average
 collect_cpu_by_process
 collect_memory_by_process
 collect_swap_usage
 collect_disk_io
 collect_network_traffic

 # Record CPU count (useful for load average thresholds)
 local cpu_count
 cpu_count=$(get_cpu_count)
 record_metric "${COMPONENT}" "system_cpu_count" "${cpu_count}" "component=infrastructure"

 log_info "${COMPONENT}: System metrics collection completed"

 return 0
}

# Export functions for testing
export -f collect_load_average collect_cpu_by_process collect_memory_by_process
export -f collect_swap_usage collect_disk_io collect_network_traffic get_cpu_count

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
