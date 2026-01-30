#!/usr/bin/env bash
#
# Infrastructure Monitoring Script
# Monitors server resources, network connectivity, database health, and service dependencies
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
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Only initialize if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 # Initialize logging
 init_logging "${LOG_DIR}/infrastructure.log" "monitorInfrastructure"
fi

# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]] || [[ "${TEST_MODE:-false}" == "true" ]]; then
 COMPONENT="${COMPONENT:-INFRASTRUCTURE}"
fi
readonly COMPONENT

##
# Show usage
##
usage() {
 cat << EOF
Infrastructure Monitoring Script

Usage: ${0} [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --check CHECK       Run specific check only
                        Available checks: server_resources, network_connectivity,
                                        database_health, service_dependencies

Examples:
    ${0}                          # Run all checks
    ${0} --check server_resources # Run only server resources check
    ${0} -v                       # Run with verbose logging

EOF
}

##
# Load configuration
##
load_config() {
 local config_file="${1:-${PROJECT_ROOT}/config/monitoring.conf}"

 if [[ -f "${config_file}" ]]; then
  # shellcheck disable=SC1090
  source "${config_file}"
 elif [[ -f "${PROJECT_ROOT}/config/monitoring.conf.example" ]]; then
  log_warning "${COMPONENT}: Configuration file not found, using defaults"
 fi

 # Set defaults
 export INFRASTRUCTURE_ENABLED="${INFRASTRUCTURE_ENABLED:-true}"
 export INFRASTRUCTURE_CPU_THRESHOLD="${INFRASTRUCTURE_CPU_THRESHOLD:-80}"
 export INFRASTRUCTURE_MEMORY_THRESHOLD="${INFRASTRUCTURE_MEMORY_THRESHOLD:-85}"
 export INFRASTRUCTURE_DISK_THRESHOLD="${INFRASTRUCTURE_DISK_THRESHOLD:-90}"
 export INFRASTRUCTURE_CHECK_TIMEOUT="${INFRASTRUCTURE_CHECK_TIMEOUT:-30}"
 export INFRASTRUCTURE_NETWORK_HOSTS="${INFRASTRUCTURE_NETWORK_HOSTS:-localhost}"
 export INFRASTRUCTURE_SERVICE_DEPENDENCIES="${INFRASTRUCTURE_SERVICE_DEPENDENCIES:-postgresql}"
}

##
# Monitor server resources (CPU, memory, disk)
##
check_server_resources() {
 log_info "${COMPONENT}: Starting server resources check"

 if [[ "${INFRASTRUCTURE_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Infrastructure monitoring is disabled"
  return 0
 fi

 # Get CPU count to adjust threshold if needed
 # For servers with many cores, a higher threshold may be more appropriate
 local cpu_count=1
 if command -v nproc > /dev/null 2>&1; then
  cpu_count=$(nproc 2> /dev/null || echo "1")
 elif [[ -f /proc/cpuinfo ]]; then
  cpu_count=$(grep -c "^processor" /proc/cpuinfo 2> /dev/null || echo "1")
 fi

 # Adjust CPU threshold based on number of cores if threshold seems too low
 # For servers with 4+ cores, we can be more lenient as brief spikes are normal
 local cpu_threshold="${INFRASTRUCTURE_CPU_THRESHOLD}"
 if [[ ${cpu_count} -ge 4 ]] && [[ ${cpu_threshold} -lt 85 ]]; then
  # For servers with 4+ cores, suggest a higher threshold (but respect user override)
  # Only adjust if threshold is still at default (80) or very low
  if [[ ${cpu_threshold} -le 80 ]]; then
   log_debug "${COMPONENT}: Server has ${cpu_count} cores, consider increasing INFRASTRUCTURE_CPU_THRESHOLD above 80% to reduce false positives"
  fi
 fi

 local memory_threshold="${INFRASTRUCTURE_MEMORY_THRESHOLD}"
 local disk_threshold="${INFRASTRUCTURE_DISK_THRESHOLD}"

 # Check CPU usage
 # Use multiple samples and average them to avoid false positives from momentary spikes
 local cpu_usage=0
 if command -v top > /dev/null 2>&1; then
  # Get CPU usage from top (3 samples of 1 second each, then average)
  # This provides a more stable reading and reduces false alerts from brief spikes
  local cpu_samples=()
  local sample_count=3
  local failed_samples=0

  for i in $(seq 1 ${sample_count}); do
   local sample=0
   local top_output
   top_output=$(top -bn1 2> /dev/null | grep -i "Cpu(s)\|%Cpu" | head -1 || echo "")

   if [[ -n "${top_output}" ]]; then
    # Try multiple parsing methods for different top formats
    # Method 1: Extract idle time and calculate usage (most common format)
    local idle_time
    idle_time=$(echo "${top_output}" | grep -oE "[0-9.]+%id" | grep -oE "[0-9.]+" | head -1 || echo "")

    if [[ -n "${idle_time}" ]] && [[ "${idle_time}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
     # Calculate CPU usage: 100 - idle
     sample=$(awk "BEGIN {printf \"%.2f\", 100 - ${idle_time}}")
    else
     # Method 2: Try to extract us, sy, ni, etc. and sum them
     local us_time sy_time ni_time
     us_time=$(echo "${top_output}" | grep -oE "[0-9.]+%us" | grep -oE "[0-9.]+" | head -1 || echo "0")
     sy_time=$(echo "${top_output}" | grep -oE "[0-9.]+%sy" | grep -oE "[0-9.]+" | head -1 || echo "0")
     ni_time=$(echo "${top_output}" | grep -oE "[0-9.]+%ni" | grep -oE "[0-9.]+" | head -1 || echo "0")

     if [[ -n "${us_time}" ]] && [[ "${us_time}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
      sample=$(awk "BEGIN {printf \"%.2f\", ${us_time} + ${sy_time} + ${ni_time}}")
     else
      # Method 3: Fallback to sed parsing (original method)
      sample=$(echo "${top_output}" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" 2> /dev/null | awk '{print 100 - $1}' 2> /dev/null || echo "0")
     fi
    fi
   else
    failed_samples=$((failed_samples + 1))
   fi

   # Validate sample is reasonable (0-100)
   if [[ -n "${sample}" ]] && [[ "${sample}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    # Check if sample is within reasonable bounds
    local sample_int
    sample_int=$(printf "%.0f" "${sample}" 2> /dev/null || echo "0")
    if [[ ${sample_int} -ge 0 ]] && [[ ${sample_int} -le 100 ]]; then
     cpu_samples+=("${sample}")
    else
     log_warning "${COMPONENT}: Invalid CPU sample detected: ${sample}% (skipping)"
     failed_samples=$((failed_samples + 1))
    fi
   else
    failed_samples=$((failed_samples + 1))
   fi

   # Small delay between samples (except for last one)
   if [[ ${i} -lt ${sample_count} ]]; then
    sleep 0.5
   fi
  done

  # Log if many samples failed
  if [[ ${failed_samples} -gt 0 ]]; then
   log_warning "${COMPONENT}: Failed to parse ${failed_samples} CPU samples (out of ${sample_count})"
  fi

  # Calculate average if we have valid samples
  if [[ ${#cpu_samples[@]} -gt 0 ]]; then
   local sum=0
   local count=0
   for sample in "${cpu_samples[@]}"; do
    sum=$(awk "BEGIN {printf \"%.2f\", ${sum} + ${sample}}")
    count=$((count + 1))
   done
   if [[ ${count} -gt 0 ]]; then
    cpu_usage=$(awk "BEGIN {printf \"%.2f\", ${sum} / ${count}}")
    log_debug "${COMPONENT}: CPU samples: ${cpu_samples[*]}, Average: ${cpu_usage}%"
   fi
  else
   log_warning "${COMPONENT}: No valid CPU samples collected, using fallback method"
   # Fallback: try vmstat or /proc/stat
   if command -v vmstat > /dev/null 2>&1; then
    local vmstat_idle
    vmstat_idle=$(vmstat 1 2 | tail -1 | awk '{print $15}' 2> /dev/null || echo "0")
    if [[ -n "${vmstat_idle}" ]] && [[ "${vmstat_idle}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
     cpu_usage=$(awk "BEGIN {printf \"%.2f\", 100 - ${vmstat_idle}}")
    fi
   fi
  fi
 elif command -v vmstat > /dev/null 2>&1; then
  # Alternative: use vmstat (2 samples, 1 second apart)
  local vmstat_idle
  vmstat_idle=$(vmstat 1 2 | tail -1 | awk '{print $15}' 2> /dev/null || echo "0")
  if [[ -n "${vmstat_idle}" ]] && [[ "${vmstat_idle}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
   cpu_usage=$(awk "BEGIN {printf \"%.2f\", 100 - ${vmstat_idle}}")
  fi
 fi

 # Validate final CPU usage is reasonable
 local cpu_usage_int
 cpu_usage_int=$(printf "%.0f" "${cpu_usage}" 2> /dev/null || echo "0")
 if [[ ${cpu_usage_int} -lt 0 ]] || [[ ${cpu_usage_int} -gt 100 ]]; then
  log_warning "${COMPONENT}: Calculated CPU usage (${cpu_usage}%) is out of bounds, resetting to 0"
  cpu_usage=0
 fi

 # Check memory usage
 local memory_usage=0
 local memory_total=0
 local memory_available=0

 if command -v free > /dev/null 2>&1; then
  local free_output
  free_output=$(free | grep Mem || echo "")
  if [[ -n "${free_output}" ]]; then
   memory_total=$(echo "${free_output}" | awk '{print $2}')
   memory_available=$(echo "${free_output}" | awk '{print $7}')
   if [[ ${memory_total} -gt 0 ]]; then
    memory_usage=$(((memory_total - memory_available) * 100 / memory_total))
   fi
  fi
 fi

 # Check disk usage
 local disk_usage=0
 local disk_available=0
 local disk_total=0

 if command -v df > /dev/null 2>&1; then
  local df_output
  df_output=$(df / 2> /dev/null | tail -1 || echo "")
  if [[ -n "${df_output}" ]]; then
   local usage_percent
   usage_percent=$(echo "${df_output}" | awk '{print $5}' | sed 's/%//' || echo "0")
   disk_usage=${usage_percent}

   # Get available and total in KB, convert to bytes
   disk_total=$(echo "${df_output}" | awk '{print $2 * 1024}' || echo "0")
   disk_available=$(echo "${df_output}" | awk '{print $4 * 1024}' || echo "0")
  fi
 fi

 # Record metrics
 record_metric "${COMPONENT}" "cpu_usage_percent" "${cpu_usage}" "component=infrastructure"
 record_metric "${COMPONENT}" "memory_usage_percent" "${memory_usage}" "component=infrastructure"
 record_metric "${COMPONENT}" "memory_total_bytes" "${memory_total}" "component=infrastructure"
 record_metric "${COMPONENT}" "memory_available_bytes" "${memory_available}" "component=infrastructure"
 record_metric "${COMPONENT}" "disk_usage_percent" "${disk_usage}" "component=infrastructure"
 record_metric "${COMPONENT}" "disk_available_bytes" "${disk_available}" "component=infrastructure"
 record_metric "${COMPONENT}" "disk_total_bytes" "${disk_total}" "component=infrastructure"

 log_info "${COMPONENT}: Server resources - CPU: ${cpu_usage}%, Memory: ${memory_usage}%, Disk: ${disk_usage}%"

 local overall_result=0

 # Convert decimal percentages to integers for comparison
 local cpu_usage_int
 local memory_usage_int
 local disk_usage_int
 cpu_usage_int=$(printf "%.0f" "${cpu_usage}" 2> /dev/null || echo "0")
 memory_usage_int=$(printf "%.0f" "${memory_usage}" 2> /dev/null || echo "0")
 disk_usage_int=$(printf "%.0f" "${disk_usage}" 2> /dev/null || echo "0")

 # Alert if CPU usage exceeds threshold
 if [[ ${cpu_usage_int} -gt ${cpu_threshold} ]]; then
  local alert_level="WARNING"
  if [[ ${cpu_usage_int} -gt 95 ]]; then
   alert_level="CRITICAL"
  fi
  log_warning "${COMPONENT}: CPU usage (${cpu_usage}%) exceeds threshold (${cpu_threshold}%)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "${alert_level}" "cpu_usage_high" "CPU usage (${cpu_usage}%) exceeds threshold (${cpu_threshold}%)" || true
  fi
  overall_result=1
 fi

 # Alert if memory usage exceeds threshold
 if [[ ${memory_usage_int} -gt ${memory_threshold} ]]; then
  local alert_level="WARNING"
  if [[ ${memory_usage_int} -gt 95 ]]; then
   alert_level="CRITICAL"
  fi
  log_warning "${COMPONENT}: Memory usage (${memory_usage}%) exceeds threshold (${memory_threshold}%)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "${alert_level}" "memory_usage_high" "Memory usage (${memory_usage}%) exceeds threshold (${memory_threshold}%)" || true
  fi
  overall_result=1
 fi

 # Alert if disk usage exceeds threshold
 if [[ ${disk_usage_int} -gt ${disk_threshold} ]]; then
  local alert_level="WARNING"
  if [[ ${disk_usage_int} -gt 95 ]]; then
   alert_level="CRITICAL"
  fi
  log_warning "${COMPONENT}: Disk usage (${disk_usage}%) exceeds threshold (${disk_threshold}%)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "${alert_level}" "disk_usage_high" "Disk usage (${disk_usage}%) exceeds threshold (${disk_threshold}%)" || true
  fi
  overall_result=1
 fi

 return ${overall_result}
}

##
# Check advanced system metrics (load average, swap, I/O, network)
##
check_advanced_system_metrics() {
 log_info "${COMPONENT}: Starting advanced system metrics check"

 if [[ "${INFRASTRUCTURE_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Infrastructure monitoring is disabled"
  return 0
 fi

 # Check if collectSystemMetrics.sh script exists
 local system_metrics_script="${SCRIPT_DIR}/collectSystemMetrics.sh"

 if [[ ! -f "${system_metrics_script}" ]]; then
  log_debug "${COMPONENT}: Advanced system metrics collection script not found: ${system_metrics_script}"
  return 0
 fi

 # Check if script is executable
 if [[ ! -x "${system_metrics_script}" ]]; then
  log_debug "${COMPONENT}: Advanced system metrics collection script is not executable: ${system_metrics_script}"
  return 0
 fi

 # Run advanced system metrics collection
 local output
 local exit_code=0

 if [[ "${TEST_MODE:-false}" == "true" ]]; then
  # In test mode, capture output for debugging
  output=$(bash "${system_metrics_script}" 2>&1) || exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
   log_debug "${COMPONENT}: Advanced system metrics collection output: ${output}"
  fi
 else
  # In production, run silently and log errors
  bash "${system_metrics_script}" > /dev/null 2>&1 || exit_code=$?
 fi

 if [[ ${exit_code} -ne 0 ]]; then
  log_warning "${COMPONENT}: Advanced system metrics collection failed (exit code: ${exit_code})"
  return 1
 fi

 # Check load average threshold
 local load_avg_query
 load_avg_query="SELECT metric_value FROM metrics
                    WHERE component = 'infrastructure'
                      AND metric_name = 'system_load_average_1min'
                    ORDER BY timestamp DESC
                    LIMIT 1;"

 local load_1min
 load_1min=$(execute_sql_query "${load_avg_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${load_1min}" ]] && [[ "${load_1min}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  # Get CPU count for threshold calculation
  local cpu_count_query
  cpu_count_query="SELECT metric_value FROM metrics
                        WHERE component = 'infrastructure'
                          AND metric_name = 'system_cpu_count'
                        ORDER BY timestamp DESC
                        LIMIT 1;"

  local cpu_count
  cpu_count=$(execute_sql_query "${cpu_count_query}" 2> /dev/null | tr -d '[:space:]' || echo "1")

  # Threshold: 2x number of CPUs
  local load_threshold
  load_threshold=$(awk "BEGIN {printf \"%.2f\", ${cpu_count} * 2}")

  local load_1min_float
  load_1min_float=$(echo "${load_1min}" | awk '{printf "%.2f", $1}')

  # Use awk for comparison (more portable than bc)
  local comparison_result
  comparison_result=$(awk "BEGIN {print (${load_1min_float} > ${load_threshold})}")

  if [[ "${comparison_result}" == "1" ]]; then
   local load_multiplier="${INFRASTRUCTURE_LOAD_THRESHOLD_MULTIPLIER:-2}"
   log_warning "${COMPONENT}: Load average (${load_1min}) exceeds threshold (${load_threshold} = ${load_multiplier}x ${cpu_count} CPUs)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "system_load_high" "Load average (${load_1min}) exceeds threshold (${load_threshold})" || true
   fi
  fi
 fi

 # Check swap usage threshold
 local swap_usage_query
 swap_usage_query="SELECT metric_value FROM metrics
                     WHERE component = 'infrastructure'
                       AND metric_name = 'system_swap_usage_percent'
                     ORDER BY timestamp DESC
                     LIMIT 1;"

 local swap_usage
 swap_usage=$(execute_sql_query "${swap_usage_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${swap_usage}" ]] && [[ "${swap_usage}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  local swap_threshold="${INFRASTRUCTURE_SWAP_THRESHOLD:-50}"
  local swap_usage_int
  swap_usage_int=$(echo "${swap_usage}" | awk '{printf "%.0f", $1}')

  if [[ ${swap_usage_int} -gt ${swap_threshold} ]]; then
   log_warning "${COMPONENT}: Swap usage (${swap_usage}%) exceeds threshold (${swap_threshold}%)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "system_swap_high" "Swap usage (${swap_usage}%) exceeds threshold (${swap_threshold}%)" || true
   fi
  fi
 fi

 log_info "${COMPONENT}: Advanced system metrics check completed"
 return 0
}

##
# Check network connectivity
##
check_network_connectivity() {
 log_info "${COMPONENT}: Starting network connectivity check"

 if [[ "${INFRASTRUCTURE_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Infrastructure monitoring is disabled"
  return 0
 fi

 local hosts="${INFRASTRUCTURE_NETWORK_HOSTS}"
 local timeout="${INFRASTRUCTURE_CHECK_TIMEOUT}"
 local connectivity_failures=0
 local total_checks=0

 # Parse hosts (comma-separated or space-separated)
 local host_list
 IFS=',' read -ra host_list <<< "${hosts}"

 for host in "${host_list[@]}"; do
  host=$(echo "${host}" | tr -d '[:space:]')
  if [[ -z "${host}" ]]; then
   continue
  fi

  total_checks=$((total_checks + 1))
  local is_reachable=false

  # Try ping
  if command -v ping > /dev/null 2>&1; then
   if ping -c 1 -W "${timeout}" "${host}" > /dev/null 2>&1; then
    is_reachable=true
   fi
  # Try nc (netcat) as fallback
  elif command -v nc > /dev/null 2>&1; then
   # Extract host and port if specified (host:port)
   local check_host="${host}"
   local check_port="80"
   if [[ "${host}" == *":"* ]]; then
    check_host=$(echo "${host}" | cut -d: -f1)
    check_port=$(echo "${host}" | cut -d: -f2)
   fi

   if nc -z -w "${timeout}" "${check_host}" "${check_port}" > /dev/null 2>&1; then
    is_reachable=true
   fi
  fi

  if [[ "${is_reachable}" == "true" ]]; then
   log_info "${COMPONENT}: Host ${host} is reachable"
  else
   log_warning "${COMPONENT}: Host ${host} is not reachable"
   connectivity_failures=$((connectivity_failures + 1))
  fi
 done

 # Record metrics
 local connectivity_value=0
 if [[ ${connectivity_failures} -eq 0 ]] && [[ ${total_checks} -gt 0 ]]; then
  connectivity_value=1
 fi

 record_metric "${COMPONENT}" "network_connectivity" "${connectivity_value}" "component=infrastructure,hosts=${hosts}"
 record_metric "${COMPONENT}" "network_connectivity_failures" "${connectivity_failures}" "component=infrastructure,hosts=${hosts}"
 record_metric "${COMPONENT}" "network_connectivity_checks" "${total_checks}" "component=infrastructure,hosts=${hosts}"

 log_info "${COMPONENT}: Network connectivity - Checks: ${total_checks}, Failures: ${connectivity_failures}"

 # Alert if connectivity failures
 if [[ ${connectivity_failures} -gt 0 ]]; then
  log_warning "${COMPONENT}: Network connectivity check found ${connectivity_failures} failure(s)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "network_connectivity_failure" "Network connectivity check found ${connectivity_failures} failure(s) out of ${total_checks} hosts checked" || true
  fi
  return 1
 fi

 return 0
}

##
# Check database server health
##
check_database_server_health() {
 log_info "${COMPONENT}: Starting database server health check"

 if [[ "${INFRASTRUCTURE_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Infrastructure monitoring is disabled"
  return 0
 fi

# Check database connection
if ! check_database_connection; then
 log_error "${COMPONENT}: Database connection failed"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "CRITICAL" "database_connection_failed" "Database server connection failed" || true
 fi
 return 1
fi

 # Get database server status
 local db_version=""
 local db_uptime=0
 local active_connections=0
 local max_connections=0

 if check_database_connection 2> /dev/null; then
  # Get PostgreSQL version
  local version_query="SELECT version();"
  local version_result
  version_result=$(execute_sql_query "${version_query}" 2> /dev/null || echo "")
  if [[ -n "${version_result}" ]]; then
   db_version=$(echo "${version_result}" | head -1 | cut -d' ' -f2 || echo "unknown")
  fi

  # Get database uptime (PostgreSQL)
  local uptime_query="SELECT EXTRACT(EPOCH FROM (NOW() - pg_postmaster_start_time()))::bigint;"
  local uptime_result
  uptime_result=$(execute_sql_query "${uptime_query}" 2> /dev/null || echo "")
  if [[ -n "${uptime_result}" ]]; then
   db_uptime=$(echo "${uptime_result}" | tr -d '[:space:]' || echo "0")
  fi

  # Get connection statistics
  local conn_query="
            SELECT
                COUNT(*) as active_connections,
                (SELECT setting::integer FROM pg_settings WHERE name = 'max_connections') as max_connections
            FROM pg_stat_activity
            WHERE datname = current_database();
        "
  local conn_result
  conn_result=$(execute_sql_query "${conn_query}" 2> /dev/null || echo "")
  if [[ -n "${conn_result}" ]]; then
   active_connections=$(echo "${conn_result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "0")
   max_connections=$(echo "${conn_result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "0")
  fi
 fi

 # Record metrics
 record_metric "${COMPONENT}" "database_uptime_seconds" "${db_uptime}" "component=infrastructure,version=${db_version}"
 record_metric "${COMPONENT}" "database_active_connections" "${active_connections}" "component=infrastructure"
 record_metric "${COMPONENT}" "database_max_connections" "${max_connections}" "component=infrastructure"

 log_info "${COMPONENT}: Database server health - Version: ${db_version}, Uptime: ${db_uptime}s, Connections: ${active_connections}/${max_connections}"

 # Alert if connection usage is high (> 80% of max)
 if [[ -n "${max_connections}" ]] && [[ "${max_connections}" =~ ^[0-9]+$ ]] && [[ ${max_connections} -gt 0 ]]; then
  local connection_usage_percent=$(((active_connections * 100) / max_connections))
  if [[ ${connection_usage_percent} -gt 80 ]]; then
   log_warning "${COMPONENT}: Database connection usage (${connection_usage_percent}%) is high"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "database_connections_high" "Database connection usage (${connection_usage_percent}%, ${active_connections}/${max_connections}) is high" || true
   fi
   return 1
  fi
 fi

 return 0
}

##
# Check service dependencies
##
check_service_dependencies() {
 log_info "${COMPONENT}: Starting service dependencies check"

 if [[ "${INFRASTRUCTURE_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Infrastructure monitoring is disabled"
  return 0
 fi

 local dependencies="${INFRASTRUCTURE_SERVICE_DEPENDENCIES}"
 local service_failures=0
 local total_services=0

 # Parse dependencies (comma-separated)
 local dep_list
 IFS=',' read -ra dep_list <<< "${dependencies}"

 for service in "${dep_list[@]}"; do
  service=$(echo "${service}" | tr -d '[:space:]')
  if [[ -z "${service}" ]]; then
   continue
  fi

  total_services=$((total_services + 1))
  local is_running=false

  # Check if service is running
  if command -v systemctl > /dev/null 2>&1; then
   if systemctl is-active --quiet "${service}" 2> /dev/null; then
    is_running=true
   fi
  elif command -v service > /dev/null 2>&1; then
   if service "${service}" status > /dev/null 2>&1; then
    is_running=true
   fi
  elif command -v pgrep > /dev/null 2>&1; then
   if pgrep -f "${service}" > /dev/null 2>&1; then
    is_running=true
   fi
  fi

  if [[ "${is_running}" == "true" ]]; then
   log_info "${COMPONENT}: Service ${service} is running"
  else
   log_warning "${COMPONENT}: Service ${service} is not running"
   service_failures=$((service_failures + 1))
  fi
 done

 # Record metrics
 local services_available=0
 if [[ ${service_failures} -eq 0 ]] && [[ ${total_services} -gt 0 ]]; then
  services_available=1
 fi

 record_metric "${COMPONENT}" "service_dependencies_available" "${services_available}" "component=infrastructure,services=${dependencies}"
 record_metric "${COMPONENT}" "service_dependencies_failures" "${service_failures}" "component=infrastructure,services=${dependencies}"
 record_metric "${COMPONENT}" "service_dependencies_total" "${total_services}" "component=infrastructure,services=${dependencies}"

 log_info "${COMPONENT}: Service dependencies - Total: ${total_services}, Failures: ${service_failures}"

 # Alert if service failures
 if [[ ${service_failures} -gt 0 ]]; then
  log_warning "${COMPONENT}: Service dependencies check found ${service_failures} failure(s)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "service_dependency_failure" "Service dependencies check found ${service_failures} failure(s) out of ${total_services} services checked" || true
  fi
  return 1
 fi

 return 0
}

##
# Main monitoring function
##
main() {
 local specific_check="${1:-}"
 local overall_result=0

 # Load configuration
 load_config "${CONFIG_FILE:-}"

 # Initialize alerting
 init_alerting

 log_info "${COMPONENT}: Starting infrastructure monitoring"

 # Run checks
 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "server_resources" ]]; then
  if ! check_server_resources; then
   overall_result=1
  fi

  # Check advanced system metrics
  if ! check_advanced_system_metrics; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "network_connectivity" ]]; then
  if ! check_network_connectivity; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "database_health" ]]; then
  if ! check_database_server_health; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "service_dependencies" ]]; then
  if ! check_service_dependencies; then
   overall_result=1
  fi
 fi

 if [[ ${overall_result} -eq 0 ]]; then
  log_info "${COMPONENT}: All infrastructure checks passed"
 else
  log_warning "${COMPONENT}: Some infrastructure checks failed"
 fi

 return ${overall_result}
}

# Only run main if script is executed directly (not sourced) and not in test mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${TEST_MODE:-false}" != "true" ]]; then
 # Parse command line arguments
 SPECIFIC_CHECK=""
 while [[ $# -gt 0 ]]; do
  case $1 in
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
   export CONFIG_FILE="$2"
   shift 2
   ;;
  --check)
   SPECIFIC_CHECK="$2"
   shift 2
   ;;
  *)
   log_error "Unknown option: $1"
   usage
   exit 1
   ;;
  esac
 done

 # Run main function
 main "${SPECIFIC_CHECK}"
fi
