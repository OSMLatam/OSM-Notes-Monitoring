#!/usr/bin/env bash
#
# WMS Monitoring Script
# Monitors the OSM-Notes-WMS component health and performance
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

# Only initialize logging if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 # Initialize logging
 init_logging "${LOG_DIR}/wms.log" "monitorWMS"
fi

# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]] || [[ "${TEST_MODE:-false}" == "true" ]]; then
 COMPONENT="${COMPONENT:-WMS}"
fi
readonly COMPONENT

##
# Show usage
##
usage() {
 cat << EOF
WMS Monitoring Script

Usage: ${0} [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --check CHECK       Run specific check only
                        Available checks: availability, health, response_time,
                                        error_rate, tile_performance, cache_hit_rate

Examples:
    ${0}                          # Run all checks
    ${0} --check availability     # Run only availability check
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
 export WMS_ENABLED="${WMS_ENABLED:-true}"
 export WMS_BASE_URL="${WMS_BASE_URL:-http://localhost:8080}"
 export WMS_HEALTH_CHECK_URL="${WMS_HEALTH_CHECK_URL:-${WMS_BASE_URL}/health}"
 export WMS_CHECK_TIMEOUT="${WMS_CHECK_TIMEOUT:-30}"
 export WMS_RESPONSE_TIME_THRESHOLD="${WMS_RESPONSE_TIME_THRESHOLD:-2000}"
 export WMS_ERROR_RATE_THRESHOLD="${WMS_ERROR_RATE_THRESHOLD:-5}"
 export WMS_TILE_GENERATION_THRESHOLD="${WMS_TILE_GENERATION_THRESHOLD:-5000}"
 export WMS_CACHE_HIT_RATE_THRESHOLD="${WMS_CACHE_HIT_RATE_THRESHOLD:-80}"
 export WMS_AVAILABILITY_CHECK_INTERVAL="${WMS_AVAILABILITY_CHECK_INTERVAL:-60}"
}

##
# Check WMS service availability
##
check_wms_service_availability() {
 log_info "${COMPONENT}: Starting WMS service availability check"

 if [[ "${WMS_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: WMS monitoring is disabled"
  return 0
 fi

 local service_url="${WMS_BASE_URL}"
 local timeout="${WMS_CHECK_TIMEOUT}"
 local is_available=false
 local response_code=0
 local response_time=0

 # Check if service is responding
 local start_time
 start_time=$(date +%s%N)

 if command -v curl > /dev/null 2>&1; then
  response_code=$(curl -s -o /dev/null -w "%{http_code}" \
   --max-time "${timeout}" \
   --connect-timeout 10 \
   "${service_url}" 2> /dev/null || echo "000")

  local end_time
  end_time=$(date +%s%N)
  response_time=$(((end_time - start_time) / 1000000))

  if [[ "${response_code}" =~ ^[23][0-9]{2}$ ]]; then
   is_available=true
   log_info "${COMPONENT}: WMS service is available (HTTP ${response_code}, ${response_time}ms)"
  else
   log_warning "${COMPONENT}: WMS service returned HTTP ${response_code}"
  fi
 else
  log_warning "${COMPONENT}: curl not available, skipping availability check"
  return 0
 fi

 # Record metric
 local availability_value=0
 if [[ "${is_available}" == "true" ]]; then
  availability_value=1
 fi

 record_metric "${COMPONENT}" "service_availability" "${availability_value}" "component=wms,url=${service_url}"
 record_metric "${COMPONENT}" "service_response_time_ms" "${response_time}" "component=wms,url=${service_url}"

# Alert if service is unavailable
if [[ "${is_available}" != "true" ]]; then
 log_error "${COMPONENT}: WMS service is unavailable (HTTP ${response_code})"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "CRITICAL" "service_unavailable" "WMS service is unavailable (HTTP ${response_code}, URL: ${service_url})" || true
 fi
 return 1
fi

 return 0
}

##
# Check HTTP health endpoint
##
check_http_health() {
 log_info "${COMPONENT}: Starting HTTP health check"

 if [[ "${WMS_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: WMS monitoring is disabled"
  return 0
 fi

 local health_url="${WMS_HEALTH_CHECK_URL}"
 local timeout="${WMS_CHECK_TIMEOUT}"
 local health_status="unknown"
 local response_code=0
 local response_time=0

 if ! command -v curl > /dev/null 2>&1; then
  log_warning "${COMPONENT}: curl not available, skipping health check"
  return 0
 fi

 # Check health endpoint
 local start_time
 start_time=$(date +%s%N)

 local health_response
 health_response=$(curl -s -w "\n%{http_code}" \
  --max-time "${timeout}" \
  --connect-timeout 10 \
  "${health_url}" 2> /dev/null || echo -e "\n000")

 local end_time
 end_time=$(date +%s%N)
 response_time=$(((end_time - start_time) / 1000000))

 response_code=$(echo "${health_response}" | tail -1)
 local health_body
 health_body=$(echo "${health_response}" | head -n -1)

 if [[ "${response_code}" =~ ^[23][0-9]{2}$ ]]; then
  # Try to parse health status from response
  if echo "${health_body}" | grep -qi "healthy\|ok\|up"; then
   health_status="healthy"
  elif echo "${health_body}" | grep -qi "unhealthy\|down\|error"; then
   health_status="unhealthy"
  else
   health_status="unknown"
  fi

  log_info "${COMPONENT}: Health check passed (HTTP ${response_code}, status: ${health_status}, ${response_time}ms)"
 else
  health_status="unhealthy"
  log_warning "${COMPONENT}: Health check failed (HTTP ${response_code})"
 fi

 # Record metric
 local health_value=0
 if [[ "${health_status}" == "healthy" ]]; then
  health_value=1
 fi

 record_metric "${COMPONENT}" "health_status" "${health_value}" "component=wms,url=${health_url}"
 record_metric "${COMPONENT}" "health_check_response_time_ms" "${response_time}" "component=wms,url=${health_url}"

# Alert if unhealthy
if [[ "${health_status}" != "healthy" ]]; then
 log_error "${COMPONENT}: WMS health check failed (HTTP ${response_code}, status: ${health_status})"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "CRITICAL" "health_check_failed" "WMS health check failed (HTTP ${response_code}, status: ${health_status}, URL: ${health_url})" || true
 fi
 return 1
fi

 return 0
}

##
# Monitor response time
##
check_response_time() {
 log_info "${COMPONENT}: Starting response time monitoring"

 if [[ "${WMS_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: WMS monitoring is disabled"
  return 0
 fi

 local test_url="${WMS_BASE_URL}"
 local timeout="${WMS_CHECK_TIMEOUT}"
 local threshold="${WMS_RESPONSE_TIME_THRESHOLD}"
 local response_time=0
 local response_code=0

 if ! command -v curl > /dev/null 2>&1; then
  log_warning "${COMPONENT}: curl not available, skipping response time check"
  return 0
 fi

 # Measure response time
 local start_time
 start_time=$(date +%s%N)

 response_code=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time "${timeout}" \
  --connect-timeout 10 \
  "${test_url}" 2> /dev/null || echo "000")

 local end_time
 end_time=$(date +%s%N)
 response_time=$(((end_time - start_time) / 1000000))

 # Record metric
 record_metric "${COMPONENT}" "response_time_ms" "${response_time}" "component=wms,url=${test_url}"

 if [[ "${response_code}" =~ ^[23][0-9]{2}$ ]]; then
  log_info "${COMPONENT}: Response time: ${response_time}ms (threshold: ${threshold}ms)"

  # Alert if response time exceeds threshold
  if [[ ${response_time} -gt ${threshold} ]]; then
   log_warning "${COMPONENT}: Response time (${response_time}ms) exceeds threshold (${threshold}ms)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "response_time_exceeded" "WMS response time (${response_time}ms) exceeds threshold (${threshold}ms, URL: ${test_url})" || true
   fi
   return 1
  fi
 else
  log_warning "${COMPONENT}: Failed to measure response time (HTTP ${response_code})"
  return 1
 fi

 return 0
}

##
# Track error rate
##
check_error_rate() {
 log_info "${COMPONENT}: Starting error rate tracking"

 if [[ "${WMS_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: WMS monitoring is disabled"
  return 0
 fi

 local threshold="${WMS_ERROR_RATE_THRESHOLD}"
 local error_count=0
 local total_requests=0
 local error_rate=0

 # Check WMS logs for errors (if log directory is configured)
 local wms_log_dir="${WMS_LOG_DIR:-}"
 if [[ -n "${wms_log_dir}" ]] && [[ -d "${wms_log_dir}" ]]; then
  # Count errors in recent logs (last hour)
  local current_time
  current_time=$(date +%s)
  local one_hour_ago=$((current_time - 3600))

  # Find recent log files
  local log_files
  log_files=$(find "${wms_log_dir}" -name "*.log" -type f -newermt "@${one_hour_ago}" 2> /dev/null || echo "")

  if [[ -n "${log_files}" ]]; then
   # Count error patterns
   error_count=$(grep -h -iE "(error|exception|failed|failure)" "${wms_log_dir}"/*.log 2> /dev/null \
    | grep -v "^#" \
    | awk -v since="${one_hour_ago}" '
                    {
                        # Try to extract timestamp and count if recent
                        # This is a simplified version - adjust based on actual log format
                        count++
                    }
                    END { print count+0 }
                ' || echo "0")

   # Count total requests (simplified - adjust based on log format)
   total_requests=$(grep -h -cE "(GET|POST|PUT|DELETE)" "${wms_log_dir}"/*.log 2> /dev/null || echo "0")
  fi
 else
  # If no log directory, check recent metrics
  if check_database_connection 2> /dev/null; then
   local query="
                SELECT
                    SUM(CASE WHEN metric_name = 'error_count' THEN metric_value::numeric ELSE 0 END) as errors,
                    SUM(CASE WHEN metric_name = 'request_count' THEN metric_value::numeric ELSE 0 END) as requests
                FROM metrics
                WHERE component = 'wms'
                  AND timestamp > NOW() - INTERVAL '1 hour';
            "

   local result
   result=$(execute_sql_query "${query}" 2> /dev/null || echo "0|0")
   error_count=$(echo "${result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "0")
   total_requests=$(echo "${result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "0")
  fi
 fi

 # Calculate error rate
 if [[ -n "${total_requests}" ]] && [[ "${total_requests}" =~ ^[0-9]+$ ]] && [[ ${total_requests} -gt 0 ]]; then
  error_rate=$(((error_count * 100) / total_requests))
 else
  error_rate=0
 fi

 # Record metrics
 record_metric "${COMPONENT}" "error_count" "${error_count}" "component=wms,period=1h"
 record_metric "${COMPONENT}" "request_count" "${total_requests}" "component=wms,period=1h"
 record_metric "${COMPONENT}" "error_rate_percent" "${error_rate}" "component=wms,period=1h"

 log_info "${COMPONENT}: Error rate: ${error_rate}% (${error_count} errors / ${total_requests} requests, threshold: ${threshold}%)"

# Alert if error rate exceeds threshold
if [[ ${error_rate} -gt ${threshold} ]]; then
 log_warning "${COMPONENT}: Error rate (${error_rate}%) exceeds threshold (${threshold}%)"
 if command -v send_alert >/dev/null 2>&1; then
  send_alert "${COMPONENT}" "WARNING" "error_rate_exceeded" "WMS error rate (${error_rate}%) exceeds threshold (${threshold}%, errors: ${error_count}, requests: ${total_requests})" || true
 fi
 return 1
fi

 return 0
}

##
# Monitor tile generation performance
##
check_tile_generation_performance() {
 log_info "${COMPONENT}: Starting tile generation performance check"

 if [[ "${WMS_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: WMS monitoring is disabled"
  return 0
 fi

 local threshold="${WMS_TILE_GENERATION_THRESHOLD}"
 local tile_url="${WMS_BASE_URL}/tile"
 local timeout="${WMS_CHECK_TIMEOUT}"
 local generation_time=0
 local response_code=0

 if ! command -v curl > /dev/null 2>&1; then
  log_warning "${COMPONENT}: curl not available, skipping tile generation check"
  return 0
 fi

 # Test tile generation with a sample request
 # Use a common zoom level and coordinates
 local test_tile_url="${tile_url}/10/512/512.png"

 local start_time
 start_time=$(date +%s%N)

 response_code=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time "${timeout}" \
  --connect-timeout 10 \
  "${test_tile_url}" 2> /dev/null || echo "000")

 local end_time
 end_time=$(date +%s%N)
 generation_time=$(((end_time - start_time) / 1000000))

 # Record metric
 record_metric "${COMPONENT}" "tile_generation_time_ms" "${generation_time}" "component=wms,zoom=10"

 if [[ "${response_code}" =~ ^[23][0-9]{2}$ ]]; then
  log_info "${COMPONENT}: Tile generation time: ${generation_time}ms (threshold: ${threshold}ms)"

  # Alert if generation time exceeds threshold
  if [[ ${generation_time} -gt ${threshold} ]]; then
   log_warning "${COMPONENT}: Tile generation time (${generation_time}ms) exceeds threshold (${threshold}ms)"
   if command -v send_alert >/dev/null 2>&1; then
    send_alert "${COMPONENT}" "WARNING" "tile_generation_slow" "WMS tile generation time (${generation_time}ms) exceeds threshold (${threshold}ms, URL: ${test_tile_url})" || true
   fi
   return 1
  fi
 else
  log_warning "${COMPONENT}: Failed to generate test tile (HTTP ${response_code})"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "tile_generation_failed" "WMS tile generation failed (HTTP ${response_code}, URL: ${test_tile_url})" || true
  fi
  return 1
 fi

 return 0
}

##
# Monitor cache hit rate
##
check_cache_hit_rate() {
 log_info "${COMPONENT}: Starting cache hit rate monitoring"

 if [[ "${WMS_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: WMS monitoring is disabled"
  return 0
 fi

 local threshold="${WMS_CACHE_HIT_RATE_THRESHOLD}"
 local cache_hits=0
 local cache_misses=0
 local total_requests=0
 local hit_rate=0

 # Check WMS logs for cache statistics (if log directory is configured)
 local wms_log_dir="${WMS_LOG_DIR:-}"
 if [[ -n "${wms_log_dir}" ]] && [[ -d "${wms_log_dir}" ]]; then
  # Count cache hits and misses in recent logs (last hour)
  local current_time
  current_time=$(date +%s)
  local one_hour_ago=$((current_time - 3600))

  # Find recent log files
  local log_files
  log_files=$(find "${wms_log_dir}" -name "*.log" -type f -newermt "@${one_hour_ago}" 2> /dev/null || echo "")

  if [[ -n "${log_files}" ]]; then
   # Count cache hit patterns (adjust based on actual log format)
   # Patterns: "cache hit", "hit cache", "HIT", "cache.*hit", etc.
   # Use grep -c and sum counts across multiple files
   cache_hits=0
   for log_file in "${wms_log_dir}"/*.log; do
    if [[ -f "${log_file}" ]]; then
     local count
     # Search for common GeoWebCache cache hit patterns
     # Pattern 1: "HIT" (standalone, common in GWC logs)
     # Pattern 2: "cache.*hit" or "hit.*cache" (descriptive)
     count=$(grep -iE "(^.*HIT.*$|cache.*hit|hit.*cache)" "${log_file}" 2> /dev/null | grep -v -iE "(miss|error)" | grep -c . || echo "0")
     cache_hits=$((cache_hits + count))
    fi
   done
   cache_misses=0
   for log_file in "${wms_log_dir}"/*.log; do
    if [[ -f "${log_file}" ]]; then
     local count
     # Search for common GeoWebCache cache miss patterns
     # Pattern 1: "MISS" (standalone, common in GWC logs)
     # Pattern 2: "cache.*miss" or "miss.*cache" (descriptive)
     # shellcheck disable=SC2126
     # Using grep -c . instead of wc -l to handle empty output correctly
     count=$(grep -iE "(^.*MISS.*$|cache.*miss|miss.*cache)" "${log_file}" 2> /dev/null | grep -v -iE "(hit|error)" | grep -c . 2>/dev/null || echo "0")
     # Ensure count is a valid number
     if [[ "${count}" =~ ^[0-9]+$ ]]; then
      cache_misses=$((cache_misses + count))
     fi
    fi
   done
   total_requests=$((cache_hits + cache_misses))
  fi
 else
  # If no log directory, check recent metrics
  if check_database_connection 2> /dev/null; then
   local query="
                SELECT
                    SUM(CASE WHEN metric_name = 'cache_hits' THEN metric_value::numeric ELSE 0 END) as hits,
                    SUM(CASE WHEN metric_name = 'cache_misses' THEN metric_value::numeric ELSE 0 END) as misses
                FROM metrics
                WHERE component = 'wms'
                  AND timestamp > NOW() - INTERVAL '1 hour';
            "

   local result
   result=$(execute_sql_query "${query}" 2> /dev/null || echo "0|0")
   cache_hits=$(echo "${result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "0")
   cache_misses=$(echo "${result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "0")
   total_requests=$((cache_hits + cache_misses))
  fi
 fi

 # Calculate hit rate
 if [[ -n "${total_requests}" ]] && [[ "${total_requests}" =~ ^[0-9]+$ ]] && [[ ${total_requests} -gt 0 ]]; then
  hit_rate=$(((cache_hits * 100) / total_requests))
 else
  hit_rate=0
 fi

 # Record metrics
 record_metric "${COMPONENT}" "cache_hits" "${cache_hits}" "component=wms,period=1h"
 record_metric "${COMPONENT}" "cache_misses" "${cache_misses}" "component=wms,period=1h"
 record_metric "${COMPONENT}" "cache_hit_rate_percent" "${hit_rate}" "component=wms,period=1h"

 log_info "${COMPONENT}: Cache hit rate: ${hit_rate}% (${cache_hits} hits / ${total_requests} requests, threshold: ${threshold}%)"

 # Only alert if there is actual activity and hit rate is below threshold
 # Don't alert when there's no data (0 requests) - this is normal when there's no recent activity
 if [[ ${total_requests} -gt 0 ]] && [[ ${hit_rate} -lt ${threshold} ]]; then
  log_warning "${COMPONENT}: Cache hit rate (${hit_rate}%) is below threshold (${threshold}%)"
  if command -v send_alert >/dev/null 2>&1; then
   send_alert "${COMPONENT}" "WARNING" "cache_hit_rate_low" "WMS cache hit rate (${hit_rate}%) is below threshold (${threshold}%, hits: ${cache_hits}, misses: ${cache_misses})" || true
  fi
  return 1
 elif [[ ${total_requests} -eq 0 ]]; then
  log_debug "${COMPONENT}: No cache activity detected in the last hour (no hits or misses). Skipping cache hit rate alert."
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

 log_info "${COMPONENT}: Starting WMS monitoring"

 # Validate specific_check if provided
 if [[ -n "${specific_check}" ]]; then
  case "${specific_check}" in
  availability | health | response_time | error_rate | tile_performance | cache_hit_rate)
   # Valid check
   ;;
  *)
   log_error "${COMPONENT}: Unknown check action: ${specific_check}"
   usage
   return 1
   ;;
  esac
 fi

 # Run checks
 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "availability" ]]; then
  if ! check_wms_service_availability; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "health" ]]; then
  if ! check_http_health; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "response_time" ]]; then
  if ! check_response_time; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "error_rate" ]]; then
  if ! check_error_rate; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "tile_performance" ]]; then
  if ! check_tile_generation_performance; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "cache_hit_rate" ]]; then
  if ! check_cache_hit_rate; then
   overall_result=1
  fi
 fi

 # Update component health status based on check results
 local health_status="healthy"
 if [[ ${overall_result} -ne 0 ]]; then
  # Determine health status based on recent metrics
  if check_database_connection 2> /dev/null; then
   local availability_query="SELECT metric_value FROM metrics WHERE component = 'wms' AND metric_name = 'service_availability' ORDER BY timestamp DESC LIMIT 1;"
   local availability
   availability=$(execute_sql_query "${availability_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

   if [[ -n "${availability}" ]] && [[ "${availability}" =~ ^[01]$ ]]; then
    if [[ ${availability} -eq 0 ]]; then
     health_status="down"
    else
     health_status="degraded"
    fi
   else
    health_status="unknown"
   fi
  else
   health_status="unknown"
  fi
 fi

 # Update component_health table
 if check_database_connection 2> /dev/null; then
  if update_component_health "wms" "${health_status}" 0; then
   log_debug "${COMPONENT}: Updated component health status to: ${health_status}"
  else
   log_warning "${COMPONENT}: Failed to update component health status"
  fi
 fi

 if [[ ${overall_result} -eq 0 ]]; then
  log_info "${COMPONENT}: All WMS checks passed"
 else
  log_warning "${COMPONENT}: Some WMS checks failed"
 fi

 return ${overall_result}
}

# Parse command line arguments only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
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
