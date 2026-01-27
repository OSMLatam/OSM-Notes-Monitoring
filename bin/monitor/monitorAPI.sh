#!/usr/bin/env bash
#
# API/Security Monitoring Script
# Monitors API availability, security events, rate limiting, and abuse detection
#
# Version: 1.0.0
# Date: 2026-01-02
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

# Initialize logging
init_logging "${LOG_DIR}/api.log" "monitorAPI"

# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]] || [[ "${TEST_MODE:-false}" == "true" ]]; then
 COMPONENT="${COMPONENT:-API}"
fi
readonly COMPONENT

##
# Show usage
##
usage() {
 cat << EOF
API/Security Monitoring Script

Usage: ${0} [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --check CHECK       Run specific check only
                        Available checks: availability, rate_limiting, 
                                        ddos_protection, abuse_detection

Examples:
    ${0}                          # Run all checks
    ${0} --check availability    # Run only availability check
    ${0} -v                       # Run with verbose logging

EOF
}

##
# Load configuration
##
load_config() {
 if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/etc/properties.sh"
 fi

 if [[ -f "${PROJECT_ROOT}/config/monitoring.conf" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/config/monitoring.conf"
 fi

 if [[ -f "${PROJECT_ROOT}/config/security.conf" ]]; then
  # shellcheck source=/dev/null
  source "${PROJECT_ROOT}/config/security.conf"
 fi
}

##
# Check API availability
##
check_api_availability() {
 log_info "Checking API availability..."

 # Check if API monitoring is enabled
 if [[ "${API_ENABLED:-true}" != "true" ]]; then
  log_info "API monitoring is disabled"
  return 0
 fi

 # Get API URL from config (try API_HEALTH_CHECK_URL first, then API_URL, then default)
 local api_url="${API_HEALTH_CHECK_URL:-${API_URL:-http://localhost:8080/api/health}}"

 if command -v curl > /dev/null 2>&1; then
  local http_code
  local response_time

  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${api_url}" 2> /dev/null || echo "000")
  response_time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 "${api_url}" 2> /dev/null || echo "0")

  if [[ "${http_code}" == "200" ]]; then
   log_info "API is available (HTTP ${http_code}, ${response_time}s)"
   record_metric "${COMPONENT}" "api_availability" "1" "API is available"
   record_metric "${COMPONENT}" "api_response_time_seconds" "${response_time}" "API response time"
   return 0
  else
   log_warn "API is not available (HTTP ${http_code})"
   record_metric "${COMPONENT}" "api_availability" "0" "API is not available"

   # Provide more descriptive message based on error code
   local alert_message
   if [[ "${http_code}" == "000" ]]; then
    alert_message="API connection failed - unable to connect to ${api_url}. Service may be down, unreachable, or network issues."
   else
    alert_message="API returned HTTP ${http_code} (URL: ${api_url})"
   fi

   send_alert "${COMPONENT}" "WARNING" "api_unavailable" "${alert_message}"
   return 1
  fi
 else
  log_warn "curl not available, skipping API availability check"
  return 0
 fi
}

##
# Check rate limiting status
##
check_rate_limiting() {
 log_info "Checking rate limiting status..."

 if [[ -f "${PROJECT_ROOT}/bin/security/rateLimiter.sh" ]]; then
  # Run rate limiter check (if it supports status check)
  if "${PROJECT_ROOT}/bin/security/rateLimiter.sh" --status > /dev/null 2>&1; then
   log_info "Rate limiting is active"
   record_metric "${COMPONENT}" "rate_limiting_active" "1" "Rate limiting is active"
  else
   log_warn "Rate limiting check failed or not configured"
   record_metric "${COMPONENT}" "rate_limiting_active" "0" "Rate limiting not active"
  fi
 else
  log_warn "Rate limiter script not found"
 fi
}

##
# Check DDoS protection status
##
check_ddos_protection() {
 log_info "Checking DDoS protection status..."

 if [[ -f "${PROJECT_ROOT}/bin/security/ddosProtection.sh" ]]; then
  # Run DDoS protection check
  if "${PROJECT_ROOT}/bin/security/ddosProtection.sh" --check > /dev/null 2>&1; then
   log_info "DDoS protection is active"
   record_metric "${COMPONENT}" "ddos_protection_active" "1" "DDoS protection is active"
  else
   log_warn "DDoS protection check failed or not configured"
   record_metric "${COMPONENT}" "ddos_protection_active" "0" "DDoS protection not active"
  fi
 else
  log_warn "DDoS protection script not found"
 fi
}

##
# Check abuse detection status
##
check_abuse_detection() {
 log_info "Checking abuse detection status..."

 if [[ -f "${PROJECT_ROOT}/bin/security/abuseDetection.sh" ]]; then
  # Run abuse detection check
  if "${PROJECT_ROOT}/bin/security/abuseDetection.sh" --check > /dev/null 2>&1; then
   log_info "Abuse detection is active"
   record_metric "${COMPONENT}" "abuse_detection_active" "1" "Abuse detection is active"
  else
   log_warn "Abuse detection check failed or not configured"
   record_metric "${COMPONENT}" "abuse_detection_active" "0" "Abuse detection not active"
  fi
 else
  log_warn "Abuse detection script not found"
 fi
}

##
# Main monitoring function
##
run_monitoring() {
 local check_type="${1:-all}"

 load_config

 case "${check_type}" in
 availability)
  check_api_availability
  ;;
 rate_limiting)
  check_rate_limiting
  ;;
 ddos_protection)
  check_ddos_protection
  ;;
 abuse_detection)
  check_abuse_detection
  ;;
 all | *)
  check_api_availability
  check_rate_limiting
  check_ddos_protection
  check_abuse_detection
  ;;
 esac
}

##
# Main
##
main() {
 local verbose=false
 local quiet=false
 local config_file=""
 local check_type="all"

 # Parse arguments
 while [[ $# -gt 0 ]]; do
  case "${1}" in
  -h | --help)
   usage
   exit 0
   ;;
  -v | --verbose)
   verbose=true
   shift
   ;;
  -q | --quiet)
   quiet=true
   shift
   ;;
  -c | --config)
   config_file="${2}"
   shift 2
   ;;
  --check)
   check_type="${2}"
   shift 2
   ;;
  *)
   log_error "Unknown option: ${1}"
   usage
   exit 1
   ;;
  esac
 done

 # Set log level
 if [[ "${verbose}" == "true" ]]; then
  export LOG_LEVEL="DEBUG"
 elif [[ "${quiet}" == "true" ]]; then
  export LOG_LEVEL="ERROR"
 fi

 # Load config file if specified
 if [[ -n "${config_file}" ]]; then
  if [[ -f "${config_file}" ]]; then
   # shellcheck source=/dev/null
   source "${config_file}"
  else
   log_error "Config file not found: ${config_file}"
   exit 1
  fi
 fi

 # Run monitoring
 run_monitoring "${check_type}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
