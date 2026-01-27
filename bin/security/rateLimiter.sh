#!/usr/bin/env bash
#
# Rate Limiter Script
# Implements rate limiting with per-IP, per-API-key, and per-endpoint support
# Uses sliding window algorithm with burst handling
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

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging
init_logging "${LOG_DIR}/rate_limiter.log" "rateLimiter"

# Initialize security functions
init_security

##
# Show usage
##
usage() {
 cat << EOF
Rate Limiter Script

Usage: ${0} [OPTIONS] [ACTION]

Actions:
    check IP [ENDPOINT] [API_KEY]    Check if request should be allowed
    record IP [ENDPOINT] [API_KEY]    Record a request (for tracking)
    stats [IP] [ENDPOINT]             Show rate limit statistics
    reset IP [ENDPOINT]               Reset rate limit counters

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --window SECONDS    Time window in seconds (default: 60)
    --limit COUNT       Maximum requests per window (default: from config)
    --burst COUNT       Burst size allowance (default: from config)

Examples:
    ${0} check 192.168.1.100 /api/notes
    ${0} check 192.168.1.100 /api/notes abc123
    ${0} record 192.168.1.100 /api/notes
    ${0} stats 192.168.1.100
    ${0} reset 192.168.1.100

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
 export RATE_LIMIT_PER_IP_PER_MINUTE="${RATE_LIMIT_PER_IP_PER_MINUTE:-60}"
 export RATE_LIMIT_PER_IP_PER_HOUR="${RATE_LIMIT_PER_IP_PER_HOUR:-1000}"
 export RATE_LIMIT_PER_IP_PER_DAY="${RATE_LIMIT_PER_IP_PER_DAY:-10000}"
 export RATE_LIMIT_BURST_SIZE="${RATE_LIMIT_BURST_SIZE:-10}"
 export RATE_LIMIT_PER_API_KEY_PER_MINUTE="${RATE_LIMIT_PER_API_KEY_PER_MINUTE:-100}"
 export RATE_LIMIT_PER_ENDPOINT_PER_MINUTE="${RATE_LIMIT_PER_ENDPOINT_PER_MINUTE:-200}"
 export RATE_LIMIT_WINDOW_SECONDS="${RATE_LIMIT_WINDOW_SECONDS:-60}"
}

##
# Check rate limit using sliding window algorithm
#
# Arguments:
#   $1 - IP address
#   $2 - Endpoint (optional)
#   $3 - API key (optional)
#   $4 - Window seconds (optional, default: 60)
#   $5 - Max requests (optional, default: from config)
#   $6 - Burst size (optional, default: from config)
#
# Returns:
#   0 if allowed, 1 if rate limited
##
check_rate_limit_sliding_window() {
 local ip="${1:?IP address required}"
 local endpoint="${2:-}"
 local api_key="${3:-}"
 local window_seconds="${4:-${RATE_LIMIT_WINDOW_SECONDS}}"
 local max_requests="${5:-}"
 local burst_size="${6:-${RATE_LIMIT_BURST_SIZE}}"

 # Determine max requests based on identifier type
 if [[ -n "${api_key}" ]]; then
  max_requests="${max_requests:-${RATE_LIMIT_PER_API_KEY_PER_MINUTE}}"
 elif [[ -n "${endpoint}" ]]; then
  max_requests="${max_requests:-${RATE_LIMIT_PER_ENDPOINT_PER_MINUTE}}"
 else
  max_requests="${max_requests:-${RATE_LIMIT_PER_IP_PER_MINUTE}}"
 fi

 # Check if whitelisted (bypass rate limiting)
 if is_ip_whitelisted "${ip}"; then
  log_debug "IP ${ip} is whitelisted, bypassing rate limit"
  return 0
 fi

 # Check if blacklisted
 if is_ip_blacklisted "${ip}"; then
  log_debug "IP ${ip} is blacklisted"
  return 1
 fi

 # Build identifier for rate limiting
 local identifier="${ip}"
 if [[ -n "${api_key}" ]]; then
  identifier="api_key:${api_key}"
 elif [[ -n "${endpoint}" ]]; then
  identifier="${ip}:${endpoint}"
 fi

 # Count requests in sliding window
 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 # Use sliding window: count requests in the last window_seconds
 local query="
        SELECT COUNT(*) 
        FROM security_events
        WHERE event_type = 'rate_limit'
          AND metadata->>'identifier' = '${identifier}'
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${window_seconds} seconds';
    "

 local count
 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  count=$(PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null || echo "0")
 else
  count=$(psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -t -A \
   -c "${query}" 2> /dev/null || echo "0")
 fi

 # Remove whitespace
 count=$(echo "${count}" | tr -d '[:space:]' || echo "0")

 # Check burst allowance (allow burst_size requests even if over limit)
 local effective_limit=$((max_requests + burst_size))

 if [[ "${count:-0}" -ge "${effective_limit}" ]]; then
  log_warning "Rate limit exceeded for ${identifier}: ${count}/${effective_limit} (limit: ${max_requests}, burst: ${burst_size})"
  record_security_event "rate_limit" "${ip}" "${endpoint}" "{\"identifier\": \"${identifier}\", \"count\": ${count}, \"limit\": ${max_requests}, \"exceeded\": true}"
  return 1 # Rate limited
 elif [[ "${count:-0}" -ge "${max_requests}" ]]; then
  # Within burst allowance but over normal limit
  log_info "Rate limit warning for ${identifier}: ${count}/${effective_limit} (within burst allowance)"
  return 0 # Allowed (burst)
 else
  return 0 # Within limit
 fi
}

##
# Record a request for rate limiting tracking
#
# Arguments:
#   $1 - IP address
#   $2 - Endpoint (optional)
#   $3 - API key (optional)
##
record_request() {
 local ip="${1:?IP address required}"
 local endpoint="${2:-}"
 local api_key="${3:-}"

 # Build identifier
 local identifier="${ip}"
 if [[ -n "${api_key}" ]]; then
  identifier="api_key:${api_key}"
 elif [[ -n "${endpoint}" ]]; then
  identifier="${ip}:${endpoint}"
 fi

 # Record security event
 local metadata="{\"identifier\": \"${identifier}\""
 if [[ -n "${endpoint}" ]]; then
  metadata="${metadata}, \"endpoint\": \"${endpoint}\""
 fi
 if [[ -n "${api_key}" ]]; then
  metadata="${metadata}, \"api_key\": \"${api_key}\""
 fi
 metadata="${metadata}}"

 # Record security event, but don't fail if it errors (graceful degradation)
 record_security_event "rate_limit" "${ip}" "${endpoint}" "${metadata}" || true
}

##
# Get rate limit statistics
#
# Arguments:
#   $1 - IP address (optional)
#   $2 - Endpoint (optional)
##
get_rate_limit_stats() {
 local ip="${1:-}"
 local endpoint="${2:-}"

 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 local query="
        SELECT 
            ip_address,
            metadata->>'identifier' as identifier,
            COUNT(*) as request_count,
            MIN(timestamp) as first_request,
            MAX(timestamp) as last_request
        FROM security_events
        WHERE event_type = 'rate_limit'
    "

 if [[ -n "${ip}" ]]; then
  query="${query} AND ip_address = '${ip}'::inet"
 fi

 if [[ -n "${endpoint}" ]]; then
  query="${query} AND endpoint = '${endpoint}'"
 fi

 query="${query}
        AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour'
        GROUP BY ip_address, identifier
        ORDER BY request_count DESC
        LIMIT 20;
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
# Reset rate limit counters
#
# Arguments:
#   $1 - IP address
#   $2 - Endpoint (optional)
##
reset_rate_limit() {
 local ip="${1:?IP address required}"
 local endpoint="${2:-}"

 local dbname="${DBNAME:-osm_notes_monitoring}"
 local dbhost="${DBHOST:-localhost}"
 local dbport="${DBPORT:-5432}"
 local dbuser="${DBUSER:-postgres}"

 local query="DELETE FROM security_events WHERE event_type = 'rate_limit' AND ip_address = '${ip}'::inet"

 if [[ -n "${endpoint}" ]]; then
  query="${query} AND endpoint = '${endpoint}'"
 fi

 # Use PGPASSWORD only if set, otherwise let psql use default authentication
 if [[ -n "${PGPASSWORD:-}" ]]; then
  if PGPASSWORD="${PGPASSWORD}" psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" > /dev/null 2>&1; then
   log_info "Rate limit counters reset for ${ip}${endpoint:+:${endpoint}}"
   return 0
  else
   log_error "Failed to reset rate limit counters for ${ip}"
   return 1
  fi
 else
  if psql \
   -h "${dbhost}" \
   -p "${dbport}" \
   -U "${dbuser}" \
   -d "${dbname}" \
   -c "${query}" > /dev/null 2>&1; then
   log_info "Rate limit counters reset for ${ip}${endpoint:+:${endpoint}}"
   return 0
  else
   log_error "Failed to reset rate limit counters for ${ip}"
   return 1
  fi
 fi
}

##
# Main function
##
main() {
 local action="${1:-}"

 # Load configuration
 load_config "${CONFIG_FILE:-}"

 case "${action}" in
 check)
  local ip="${2:-}"
  local endpoint="${3:-}"
  local api_key="${4:-}"

  if [[ -z "${ip}" ]]; then
   log_error "IP address required for check action"
   usage
   exit 1
  fi

  if check_rate_limit_sliding_window "${ip}" "${endpoint}" "${api_key}" "${RATE_LIMIT_WINDOW_SECONDS}" "${RATE_LIMIT_MAX_REQUESTS}" "${RATE_LIMIT_BURST_SIZE}"; then
   echo "ALLOWED"
   exit 0
  else
   echo "RATE_LIMITED"
   exit 1
  fi
  ;;
 record)
  local ip="${2:-}"
  local endpoint="${3:-}"
  local api_key="${4:-}"

  if [[ -z "${ip}" ]]; then
   log_error "IP address required for record action"
   usage
   exit 1
  fi

  record_request "${ip}" "${endpoint}" "${api_key}"
  ;;
 stats)
  local ip="${2:-}"
  local endpoint="${3:-}"

  get_rate_limit_stats "${ip}" "${endpoint}"
  ;;
 reset)
  local ip="${2:-}"
  local endpoint="${3:-}"

  if [[ -z "${ip}" ]]; then
   log_error "IP address required for reset action"
   usage
   exit 1
  fi

  reset_rate_limit "${ip}" "${endpoint}"
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
RATE_LIMIT_WINDOW_SECONDS="${RATE_LIMIT_WINDOW_SECONDS:-60}"
RATE_LIMIT_MAX_REQUESTS=""
RATE_LIMIT_BURST_SIZE="${RATE_LIMIT_BURST_SIZE:-10}"

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
 --window)
  RATE_LIMIT_WINDOW_SECONDS="$2"
  shift 2
  ;;
 --limit)
  RATE_LIMIT_MAX_REQUESTS="$2"
  shift 2
  ;;
 --burst)
  RATE_LIMIT_BURST_SIZE="$2"
  shift 2
  ;;
 *)
  # Remaining arguments are action and parameters
  break
  ;;
 esac
done

# Run main function only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
