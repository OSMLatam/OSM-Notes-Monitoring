#!/usr/bin/env bash
#
# Abuse Detection Script
# Implements pattern analysis, anomaly detection, behavioral analysis, and automatic response
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
source "${PROJECT_ROOT}/bin/lib/securityFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging only if not in test mode
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 init_logging "${LOG_DIR}/abuse_detection.log" "abuseDetection"

 # Initialize security functions
 init_security
fi

# Component name
COMPONENT="SECURITY"
readonly COMPONENT

##
# Show usage
##
usage() {
 cat << EOF
Abuse Detection Script

Usage: ${0} [OPTIONS] [ACTION]

Actions:
    analyze [IP]                  Analyze patterns and detect abuse
    check IP                      Check specific IP for abuse patterns
    stats                         Show abuse detection statistics
    patterns                      Show detected abuse patterns

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file

Examples:
    ${0} analyze                  # Analyze all IPs
    ${0} analyze 192.168.1.100     # Analyze specific IP
    ${0} check 192.168.1.100       # Check IP for abuse
    ${0} stats                    # Show statistics

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

 # Load security config if available
 if [[ -f "${PROJECT_ROOT}/config/security.conf" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/config/security.conf" || true
 elif [[ -f "${PROJECT_ROOT}/config/security.conf.example" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/config/security.conf.example" || true
 fi

 # Set defaults
 export ABUSE_DETECTION_ENABLED="${ABUSE_DETECTION_ENABLED:-true}"
 export ABUSE_RAPID_REQUEST_THRESHOLD="${ABUSE_RAPID_REQUEST_THRESHOLD:-10}"
 export ABUSE_ERROR_RATE_THRESHOLD="${ABUSE_ERROR_RATE_THRESHOLD:-50}"
 export ABUSE_EXCESSIVE_REQUESTS_THRESHOLD="${ABUSE_EXCESSIVE_REQUESTS_THRESHOLD:-1000}"
 export ABUSE_PATTERN_ANALYSIS_WINDOW="${ABUSE_PATTERN_ANALYSIS_WINDOW:-3600}"
}

##
# Analyze request patterns for abuse detection
#
# Arguments:
#   $1 - IP address
#
# Returns:
#   0 if abuse detected, 1 if normal
##
analyze_patterns() {
 local ip="${1:?IP address required}"

 # Check if whitelisted
 if is_ip_whitelisted "${ip}"; then
  log_debug "IP ${ip} is whitelisted, bypassing pattern analysis"
  return 1
 fi

 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 # Analyze rapid requests pattern
 local rapid_query="
        SELECT COUNT(*) 
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '10 seconds';
    "

 local rapid_count
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  rapid_count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${rapid_query}" 2> /dev/null || echo "0")
 else
  rapid_count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${rapid_query}" 2> /dev/null || echo "0")
 fi

 rapid_count=$(echo "${rapid_count}" | tr -d '[:space:]' || echo "0")

 # Analyze error rate pattern
 local error_query="
        SELECT 
            COUNT(*) FILTER (WHERE metadata->>'status_code' ~ '^[45]') as error_count,
            COUNT(*) as total_count
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${ABUSE_PATTERN_ANALYSIS_WINDOW} seconds';
    "

 local error_result
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  error_result=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${error_query}" 2> /dev/null || echo "0|0")
 else
  error_result=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${error_query}" 2> /dev/null || echo "0|0")
 fi

 local error_count
 error_count=$(echo "${error_result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "0")
 local total_count
 total_count=$(echo "${error_result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "0")

 local error_rate=0
 if [[ ${total_count} -gt 0 ]]; then
  error_rate=$(((error_count * 100) / total_count))
 fi

 # Analyze excessive requests pattern
 local excessive_query="
        SELECT COUNT(*) 
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour';
    "

 local excessive_count
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  excessive_count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${excessive_query}" 2> /dev/null || echo "0")
 else
  excessive_count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${excessive_query}" 2> /dev/null || echo "0")
 fi

 excessive_count=$(echo "${excessive_count}" | tr -d '[:space:]' || echo "0")

 # Record metrics
 record_metric "${COMPONENT}" "abuse_rapid_requests" "${rapid_count}" "component=security,ip=${ip}"
 record_metric "${COMPONENT}" "abuse_error_rate_percent" "${error_rate}" "component=security,ip=${ip}"
 record_metric "${COMPONENT}" "abuse_excessive_requests" "${excessive_count}" "component=security,ip=${ip}"

 log_info "${COMPONENT}: Pattern analysis for ${ip} - Rapid: ${rapid_count}, Error rate: ${error_rate}%, Excessive: ${excessive_count}"

 local abuse_detected=false
 local abuse_reasons=()

 # Check rapid requests pattern
 if [[ ${rapid_count} -ge ${ABUSE_RAPID_REQUEST_THRESHOLD} ]]; then
  abuse_detected=true
  abuse_reasons+=("rapid_requests:${rapid_count}")
 fi

 # Check error rate pattern
 if [[ ${error_rate} -ge ${ABUSE_ERROR_RATE_THRESHOLD} ]]; then
  abuse_detected=true
  abuse_reasons+=("high_error_rate:${error_rate}%")
 fi

 # Check excessive requests pattern
 if [[ ${excessive_count} -ge ${ABUSE_EXCESSIVE_REQUESTS_THRESHOLD} ]]; then
  abuse_detected=true
  abuse_reasons+=("excessive_requests:${excessive_count}")
 fi

 if [[ "${abuse_detected}" == "true" ]]; then
  local reason_str
  reason_str=$(
   IFS=','
   echo "${abuse_reasons[*]}"
  )
  log_warning "${COMPONENT}: Abuse pattern detected for ${ip}: ${reason_str}"
  record_security_event "abuse" "${ip}" "" "{\"patterns\": [$(
   IFS=','
   printf '"%s"' "${abuse_reasons[@]}"
  )], \"rapid_count\": ${rapid_count}, \"error_rate\": ${error_rate}, \"excessive_count\": ${excessive_count}}"
  return 0 # Abuse detected
 else
  return 1 # Normal
 fi
}

##
# Detect anomalies in request behavior
#
# Arguments:
#   $1 - IP address
#
# Returns:
#   0 if anomaly detected, 1 if normal
##
detect_anomalies() {
 local ip="${1:?IP address required}"

 # Check if whitelisted
 if is_ip_whitelisted "${ip}"; then
  return 1
 fi

 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 # Get baseline (average requests per hour for this IP over last 7 days)
 local baseline_query="
        SELECT AVG(hourly_count)::integer
        FROM (
            SELECT DATE_TRUNC('hour', timestamp) as hour, COUNT(*) as hourly_count
            FROM security_events
            WHERE ip_address = '${ip}'::inet
              AND timestamp > CURRENT_TIMESTAMP - INTERVAL '7 days'
            GROUP BY hour
        ) hourly_stats;
    "

 local baseline
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  baseline=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${baseline_query}" 2> /dev/null || echo "0")
 else
  baseline=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${baseline_query}" 2> /dev/null || echo "0")
 fi

 baseline=$(echo "${baseline}" | tr -d '[:space:]' || echo "0")

 # Get current hour requests
 local current_query="
        SELECT COUNT(*) 
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND timestamp > DATE_TRUNC('hour', CURRENT_TIMESTAMP);
    "

 local current_count
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  current_count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${current_query}" 2> /dev/null || echo "0")
 else
  current_count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${current_query}" 2> /dev/null || echo "0")
 fi

 current_count=$(echo "${current_count}" | tr -d '[:space:]' || echo "0")

 # Record metrics
 record_metric "${COMPONENT}" "abuse_baseline_requests" "${baseline}" "component=security,ip=${ip}"
 record_metric "${COMPONENT}" "abuse_current_requests" "${current_count}" "component=security,ip=${ip}"

 # Anomaly: current is 3x baseline (if baseline > 0)
 if [[ ${baseline} -gt 0 ]]; then
  local threshold=$((baseline * 3))
  if [[ ${current_count} -ge ${threshold} ]]; then
   log_warning "${COMPONENT}: Anomaly detected for ${ip}: ${current_count} requests (baseline: ${baseline}, threshold: ${threshold})"
   record_security_event "abuse" "${ip}" "" "{\"type\": \"anomaly\", \"current\": ${current_count}, \"baseline\": ${baseline}, \"threshold\": ${threshold}}"
   return 0 # Anomaly detected
  fi
 fi

 return 1 # Normal
}

##
# Analyze behavioral patterns
#
# Arguments:
#   $1 - IP address
#
# Returns:
#   0 if suspicious behavior detected, 1 if normal
##
analyze_behavior() {
 local ip="${1:?IP address required}"

 # Check if whitelisted
 if is_ip_whitelisted "${ip}"; then
  return 1
 fi

 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 # Analyze endpoint diversity (suspicious if hitting many different endpoints rapidly)
 local endpoint_query="
        SELECT COUNT(DISTINCT endpoint) 
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '5 minutes';
    "

 local endpoint_count
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  endpoint_count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${endpoint_query}" 2> /dev/null || echo "0")
 else
  endpoint_count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${endpoint_query}" 2> /dev/null || echo "0")
 fi

 endpoint_count=$(echo "${endpoint_count}" | tr -d '[:space:]' || echo "0")

 # Analyze user agent patterns (suspicious if many different user agents)
 local ua_query="
        SELECT COUNT(DISTINCT user_agent) 
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour';
    "

 local ua_count
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  ua_count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${ua_query}" 2> /dev/null || echo "0")
 else
  ua_count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${ua_query}" 2> /dev/null || echo "0")
 fi

 ua_count=$(echo "${ua_count}" | tr -d '[:space:]' || echo "0")

 # Record metrics
 record_metric "${COMPONENT}" "abuse_endpoint_diversity" "${endpoint_count}" "component=security,ip=${ip}"
 record_metric "${COMPONENT}" "abuse_user_agent_diversity" "${ua_count}" "component=security,ip=${ip}"

 log_info "${COMPONENT}: Behavior analysis for ${ip} - Endpoints: ${endpoint_count}, User agents: ${ua_count}"

 local suspicious=false
 local behavior_reasons=()

 # Suspicious: hitting many different endpoints in short time
 if [[ ${endpoint_count} -gt 20 ]]; then
  suspicious=true
  behavior_reasons+=("high_endpoint_diversity:${endpoint_count}")
 fi

 # Suspicious: many different user agents from same IP
 if [[ ${ua_count} -gt 10 ]]; then
  suspicious=true
  behavior_reasons+=("high_ua_diversity:${ua_count}")
 fi

 if [[ "${suspicious}" == "true" ]]; then
  local reason_str
  reason_str=$(
   IFS=','
   echo "${behavior_reasons[*]}"
  )
  log_warning "${COMPONENT}: Suspicious behavior detected for ${ip}: ${reason_str}"
  record_security_event "abuse" "${ip}" "" "{\"type\": \"behavioral\", \"reasons\": [$(
   IFS=','
   printf '"%s"' "${behavior_reasons[@]}"
  )], \"endpoint_count\": ${endpoint_count}, \"ua_count\": ${ua_count}}"
  return 0 # Suspicious behavior
 else
  return 1 # Normal
 fi
}

##
# Automatic response to abuse detection
#
# Arguments:
#   $1 - IP address
#   $2 - Abuse type (pattern, anomaly, behavioral)
#   $3 - Reason
##
automatic_response() {
 local ip="${1:?IP address required}"
 local abuse_type="${2:-pattern}"
 local reason="${3:-Abuse detected}"

 log_warning "${COMPONENT}: Automatic response for ${ip} (${abuse_type}): ${reason}"

 # Determine block duration based on abuse type and history
 local block_duration=15 # Default: 15 minutes

 # Check violation history
 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 local violation_query="
        SELECT COUNT(*) 
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND event_type = 'abuse'
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours';
    "

 local violation_count
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  violation_count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${violation_query}" 2> /dev/null || echo "0")
 else
  violation_count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${violation_query}" 2> /dev/null || echo "0")
 fi

 violation_count=$(echo "${violation_count}" | tr -d '[:space:]' || echo "0")

 # Escalate block duration based on violation count
 if [[ ${violation_count} -ge 3 ]]; then
  block_duration=1440 # 24 hours for repeat offenders
 elif [[ ${violation_count} -ge 2 ]]; then
  block_duration=60 # 1 hour for second violation
 fi

 # Auto-block IP
 auto_block_ip "${ip}" "${reason} (${abuse_type}, violation #${violation_count})" "${block_duration}"

 # Send alert
 send_alert "${COMPONENT}" "WARNING" "abuse_detected" "Abuse detected for IP ${ip}: ${reason} (type: ${abuse_type}, violations: ${violation_count}, blocked for ${block_duration} minutes)"

 # Record metric
 record_metric "${COMPONENT}" "abuse_auto_blocks" "1" "component=security,ip=${ip},type=${abuse_type}"
}

##
# Check IP for abuse (combines all detection methods)
#
# Arguments:
#   $1 - IP address
##
check_ip_for_abuse() {
 local ip="${1:?IP address required}"

 if [[ "${ABUSE_DETECTION_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Abuse detection is disabled"
  return 0
 fi

 local abuse_detected=false

 # Pattern analysis
 if analyze_patterns "${ip}"; then
  abuse_detected=true
  automatic_response "${ip}" "pattern" "Abuse pattern detected"
 fi

 # Anomaly detection
 if detect_anomalies "${ip}"; then
  abuse_detected=true
  automatic_response "${ip}" "anomaly" "Behavioral anomaly detected"
 fi

 # Behavioral analysis
 if analyze_behavior "${ip}"; then
  abuse_detected=true
  automatic_response "${ip}" "behavioral" "Suspicious behavior detected"
 fi

 if [[ "${abuse_detected}" == "true" ]]; then
  return 0 # Abuse detected
 else
  return 1 # Normal
 fi
}

##
# Analyze all IPs for abuse
##
analyze_all() {
 log_info "${COMPONENT}: Starting abuse analysis for all IPs"

 if [[ "${ABUSE_DETECTION_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Abuse detection is disabled"
  return 0
 fi

 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 # Get all IPs with recent activity
 local query="
        SELECT DISTINCT ip_address::text
        FROM security_events
        WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour'
        ORDER BY ip_address;
    "

 local ips
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  ips=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null || echo "")
 else
  ips=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null || echo "")
 fi

 local abuse_count=0

 if [[ -n "${ips}" ]]; then
  while IFS= read -r ip; do
   ip=$(echo "${ip}" | tr -d '[:space:]')
   if [[ -n "${ip}" ]]; then
    if check_ip_for_abuse "${ip}"; then
     abuse_count=$((abuse_count + 1))
    fi
   fi
  done <<< "${ips}"
 fi

 log_info "${COMPONENT}: Abuse analysis complete - ${abuse_count} IP(s) flagged"

 if [[ ${abuse_count} -gt 0 ]]; then
  return 1
 else
  return 0
 fi
}

##
# Get abuse detection statistics
##
get_abuse_stats() {
 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 local query="
        SELECT 
            COUNT(*) FILTER (WHERE event_type = 'abuse') as abuse_events,
            COUNT(DISTINCT ip_address) FILTER (WHERE event_type = 'abuse') as unique_abusive_ips,
            MAX(timestamp) FILTER (WHERE event_type = 'abuse') as last_abuse_time
        FROM security_events
        WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours';
    "

 echo "Abuse Detection Statistics (last 24 hours):"
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" 2> /dev/null || true
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" 2> /dev/null || true
 fi

 echo ""
 echo "Top abusive IPs:"
 query="
        SELECT 
            ip_address,
            COUNT(*) as abuse_count,
            MAX(timestamp) as last_abuse
        FROM security_events
        WHERE event_type = 'abuse'
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
        GROUP BY ip_address
        ORDER BY abuse_count DESC
        LIMIT 10;
    "

 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" 2> /dev/null || true
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" 2> /dev/null || true
 fi
}

##
# Show detected abuse patterns
##
show_patterns() {
 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 local query="
        SELECT 
            ip_address,
            metadata->>'patterns' as patterns,
            MAX(timestamp) as detected_at
        FROM security_events
        WHERE event_type = 'abuse'
          AND metadata->>'patterns' IS NOT NULL
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
        GROUP BY ip_address, patterns
        ORDER BY detected_at DESC
        LIMIT 20;
    "

 echo "Detected Abuse Patterns:"
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" 2> /dev/null || true
 else
  psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" 2> /dev/null || true
 fi
}

##
# Main function
##
main() {
 local action="${1:-}"

 # Load configuration
 load_config "${CONFIG_FILE:-}"

 # Initialize alerting
 init_alerting

 case "${action}" in
 analyze)
  local ip="${2:-}"
  if [[ -n "${ip}" ]]; then
   check_ip_for_abuse "${ip}"
  else
   analyze_all
  fi
  ;;
 check)
  local ip="${2:-}"
  if [[ -z "${ip}" ]]; then
   log_error "IP address required for check action"
   usage
   exit 1
  fi
  check_ip_for_abuse "${ip}"
  ;;
 stats)
  get_abuse_stats
  ;;
 patterns)
  show_patterns
  ;;
 *)
  if [[ -n "${action}" ]]; then
   log_error "Unknown action: ${action}"
  fi
  usage
  exit 1
  ;;
 esac
}

# Parse command line arguments
CONFIG_FILE=""

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
  CONFIG_FILE="$2"
  shift 2
  ;;
 *)
  # Remaining arguments are action and parameters
  break
  ;;
 esac
done

# Run main function only if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
