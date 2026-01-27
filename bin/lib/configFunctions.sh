#!/usr/bin/env bash
#
# Configuration Functions Library
# Provides configuration loading and validation utilities
#
# Version: 1.0.0
# Date: 2025-12-24
#

# Source logging functions
# shellcheck disable=SC1091
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh" ]]; then
 source "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh"
fi

##
# Get project root directory
#
# Returns:
#   Project root path via stdout
##
get_project_root() {
 local script_dir
 script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 local project_root
 project_root="$(dirname "$(dirname "${script_dir}")")"
 echo "${project_root}"
}

##
# Load main configuration (etc/properties.sh)
#
# Arguments:
#   None
#
# Returns:
#   0 on success, 1 on failure
##
load_main_config() {
 local project_root
 project_root="$(get_project_root)"
 local config_file="${project_root}/etc/properties.sh"

 if [[ ! -f "${config_file}" ]]; then
  log_error "Configuration file not found: ${config_file}"
  log_error "Please copy etc/properties.sh.example to etc/properties.sh and configure it"
  return 1
 fi

 # Source configuration
 # shellcheck disable=SC1090,SC1091
 if ! source "${config_file}"; then
  log_error "Failed to load configuration from ${config_file}"
  return 1
 fi

 log_debug "Configuration loaded from ${config_file}"
 return 0
}

##
# Validate main configuration
#
# Arguments:
#   None
#
# Returns:
#   0 if valid, 1 if invalid
##
validate_main_config() {
 local errors=0

 # Check required variables
 local required_vars=(
  "DBNAME"
  "DBHOST"
  "DBPORT"
  "DBUSER"
 )

 for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
   log_error "Required configuration variable not set: ${var}"
   errors=$((errors + 1))
  fi
 done

 # Validate database port is numeric
 if [[ -n "${DBPORT:-}" ]]; then
  if ! [[ "${DBPORT}" =~ ^[0-9]+$ ]]; then
   log_error "DBPORT must be a number, got: ${DBPORT}"
   errors=$((errors + 1))
  fi
 fi

 # Validate database connection (optional, only if function exists)
 if [[ ${errors} -eq 0 ]]; then
  if type check_database_connection > /dev/null 2>&1; then
   if ! check_database_connection 2> /dev/null; then
    log_warning "Cannot connect to database (this may be OK in some contexts)" || true
   fi
  fi
 fi

 if [[ ${errors} -gt 0 ]]; then
  return 1
 fi

 return 0
}

##
# Validate monitoring configuration
#
# Arguments:
#   None
#
# Returns:
#   0 if valid, 1 if invalid
##
validate_monitoring_config() {
 local errors=0

 # Check component-specific settings
 local components=("ingestion" "analytics" "wms" "api" "data" "infrastructure")

 for component in "${components[@]}"; do
  local enabled_var="${component^^}_ENABLED"
  enabled_var="${enabled_var//-/_}"

  # Check if enabled flag exists and is valid
  if [[ -n "${!enabled_var:-}" ]]; then
   if [[ "${!enabled_var}" != "true" && "${!enabled_var}" != "false" ]]; then
    log_error "Invalid ${enabled_var} value: ${!enabled_var} (must be true/false)"
    errors=$((errors + 1))
   fi
  fi

  # Check timeout values are numeric
  local timeout_var="${component^^}_CHECK_TIMEOUT"
  timeout_var="${timeout_var//-/_}"
  if [[ -n "${!timeout_var:-}" ]]; then
   if ! [[ "${!timeout_var}" =~ ^[0-9]+$ ]]; then
    log_error "Invalid ${timeout_var} value: ${!timeout_var} (must be a number)"
    errors=$((errors + 1))
   fi
  fi
 done

 # Validate retention days
 if [[ -n "${METRICS_RETENTION_DAYS:-}" ]]; then
  if ! [[ "${METRICS_RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
   log_error "METRICS_RETENTION_DAYS must be a number, got: ${METRICS_RETENTION_DAYS}"
   errors=$((errors + 1))
  elif [[ ${METRICS_RETENTION_DAYS} -lt 1 ]]; then
   log_error "METRICS_RETENTION_DAYS must be at least 1, got: ${METRICS_RETENTION_DAYS}"
   errors=$((errors + 1))
  fi
 fi

 if [[ ${errors} -gt 0 ]]; then
  return 1
 fi

 return 0
}

##
# Validate alert configuration
#
# Arguments:
#   None
#
# Returns:
#   0 if valid, 1 if invalid
##
validate_alert_config() {
 local errors=0

 # Validate email settings
 if [[ "${SEND_ALERT_EMAIL:-false}" == "true" ]]; then
  if [[ -z "${ADMIN_EMAIL:-}" ]]; then
   log_error "ADMIN_EMAIL required when SEND_ALERT_EMAIL is true"
   errors=$((errors + 1))
  elif ! [[ "${ADMIN_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
   log_error "Invalid ADMIN_EMAIL format: ${ADMIN_EMAIL}"
   errors=$((errors + 1))
  fi
 fi

 # Validate Slack settings
 if [[ "${SLACK_ENABLED:-false}" == "true" ]]; then
  if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
   log_error "SLACK_WEBHOOK_URL required when SLACK_ENABLED is true"
   errors=$((errors + 1))
  elif ! [[ "${SLACK_WEBHOOK_URL}" =~ ^https://hooks.slack.com/ ]]; then
   log_warning "SLACK_WEBHOOK_URL doesn't look like a valid Slack webhook URL"
  fi
 fi

 # Validate alert levels
 local alert_levels=("CRITICAL" "WARNING" "INFO")
 for level in "${alert_levels[@]}"; do
  local recipients_var="${level}_ALERT_RECIPIENTS"
  if [[ -n "${!recipients_var:-}" ]]; then
   # Basic email validation for recipients
   local recipients="${!recipients_var}"
   # Simple check - should contain @
   if [[ "${recipients}" =~ @ ]]; then
    # Looks like email(s), basic validation passed
    :
   else
    log_warning "Alert recipients format may be invalid: ${recipients_var}"
   fi
  fi
 done

 # Validate deduplication settings
 if [[ -n "${ALERT_DEDUPLICATION_WINDOW_MINUTES:-}" ]]; then
  if ! [[ "${ALERT_DEDUPLICATION_WINDOW_MINUTES}" =~ ^[0-9]+$ ]]; then
   log_error "ALERT_DEDUPLICATION_WINDOW_MINUTES must be a number"
   errors=$((errors + 1))
  fi
 fi

 if [[ ${errors} -gt 0 ]]; then
  return 1
 fi

 return 0
}

##
# Validate security configuration
#
# Arguments:
#   None
#
# Returns:
#   0 if valid, 1 if invalid
##
validate_security_config() {
 local errors=0

 # Validate rate limiting values
 local rate_limit_vars=(
  "RATE_LIMIT_PER_IP_PER_MINUTE"
  "RATE_LIMIT_PER_IP_PER_HOUR"
  "RATE_LIMIT_PER_IP_PER_DAY"
  "RATE_LIMIT_BURST_SIZE"
 )

 for var in "${rate_limit_vars[@]}"; do
  if [[ -n "${!var:-}" ]]; then
   if ! [[ "${!var}" =~ ^[0-9]+$ ]]; then
    log_error "${var} must be a number, got: ${!var}"
    errors=$((errors + 1))
   elif [[ ${!var} -lt 1 ]]; then
    log_error "${var} must be at least 1, got: ${!var}"
    errors=$((errors + 1))
   fi
  fi
 done

 # Validate connection limits
 local connection_vars=(
  "MAX_CONCURRENT_CONNECTIONS_PER_IP"
  "MAX_TOTAL_CONNECTIONS"
 )

 for var in "${connection_vars[@]}"; do
  if [[ -n "${!var:-}" ]]; then
   if ! [[ "${!var}" =~ ^[0-9]+$ ]]; then
    log_error "${var} must be a number, got: ${!var}"
    errors=$((errors + 1))
   fi
  fi
 done

 # Validate DDoS thresholds
 if [[ -n "${DDOS_THRESHOLD_REQUESTS_PER_SECOND:-}" ]]; then
  if ! [[ "${DDOS_THRESHOLD_REQUESTS_PER_SECOND}" =~ ^[0-9]+$ ]]; then
   log_error "DDOS_THRESHOLD_REQUESTS_PER_SECOND must be a number"
   errors=$((errors + 1))
  fi
 fi

 # Validate abuse detection settings
 if [[ -n "${ABUSE_DETECTION_ENABLED:-}" ]]; then
  if [[ "${ABUSE_DETECTION_ENABLED}" != "true" && "${ABUSE_DETECTION_ENABLED}" != "false" ]]; then
   log_error "ABUSE_DETECTION_ENABLED must be true or false"
   errors=$((errors + 1))
  fi
 fi

 if [[ ${errors} -gt 0 ]]; then
  return 1
 fi

 return 0
}

##
# Validate all configurations
#
# Arguments:
#   None
#
# Returns:
#   0 if all valid, 1 if any invalid
##
validate_all_configs() {
 local errors=0

 # Use log_info if available, otherwise silent
 if type log_info > /dev/null 2>&1; then
  log_info "Validating all configurations..." || true
 fi

 # Validate main config
 if ! validate_main_config; then
  errors=$((errors + 1))
 fi

 # Validate monitoring config (if loaded)
 local project_root
 project_root="$(get_project_root 2> /dev/null || echo "")"
 if [[ -n "${INGESTION_ENABLED:-}" ]] || [[ -f "${project_root}/config/monitoring.conf" ]] || [[ -f "config/monitoring.conf" ]]; then
  if ! validate_monitoring_config; then
   errors=$((errors + 1))
  fi
 fi

 # Validate alert config (if loaded)
 if [[ -n "${ADMIN_EMAIL:-}" ]] || [[ -f "${project_root}/config/alerts.conf" ]] || [[ -f "config/alerts.conf" ]]; then
  if ! validate_alert_config; then
   errors=$((errors + 1))
  fi
 fi

 # Validate security config (if loaded)
 if [[ -n "${RATE_LIMIT_PER_IP_PER_MINUTE:-}" ]] || [[ -f "${project_root}/config/security.conf" ]] || [[ -f "config/security.conf" ]]; then
  if ! validate_security_config; then
   errors=$((errors + 1))
  fi
 fi

 if [[ ${errors} -gt 0 ]]; then
  if type log_error > /dev/null 2>&1; then
   log_error "Configuration validation failed with ${errors} error(s)" || true
  fi
  return 1
 else
  if type log_info > /dev/null 2>&1; then
   log_info "All configurations validated successfully" || true
  fi
  return 0
 fi
}

##
# Load monitoring configuration (config/monitoring.conf)
#
# Arguments:
#   None
#
# Returns:
#   0 on success, 1 on failure
##
load_monitoring_config() {
 local project_root
 project_root="$(get_project_root)"
 local config_file="${project_root}/config/monitoring.conf"

 if [[ ! -f "${config_file}" ]]; then
  log_debug "Monitoring configuration not found: ${config_file} (using defaults)"
  return 0
 fi

 # shellcheck disable=SC1090,SC1091
 if ! source "${config_file}"; then
  log_error "Failed to load monitoring configuration from ${config_file}"
  return 1
 fi

 log_debug "Monitoring configuration loaded from ${config_file}"
 return 0
}

##
# Load alert configuration (config/alerts.conf)
#
# Arguments:
#   None
#
# Returns:
#   0 on success, 1 on failure
##
load_alert_config() {
 local project_root
 project_root="$(get_project_root)"
 local config_file="${project_root}/config/alerts.conf"

 if [[ ! -f "${config_file}" ]]; then
  log_debug "Alert configuration not found: ${config_file} (using defaults)"
  return 0
 fi

 # shellcheck disable=SC1090,SC1091
 if ! source "${config_file}"; then
  log_error "Failed to load alert configuration from ${config_file}"
  return 1
 fi

 log_debug "Alert configuration loaded from ${config_file}"
 return 0
}

##
# Load security configuration (config/security.conf)
#
# Arguments:
#   None
#
# Returns:
#   0 on success, 1 on failure
##
load_security_config() {
 local project_root
 project_root="$(get_project_root)"
 local config_file="${project_root}/config/security.conf"

 if [[ ! -f "${config_file}" ]]; then
  log_debug "Security configuration not found: ${config_file} (using defaults)"
  return 0
 fi

 # shellcheck disable=SC1090,SC1091
 if ! source "${config_file}"; then
  log_error "Failed to load security configuration from ${config_file}"
  return 1
 fi

 log_debug "Security configuration loaded from ${config_file}"
 return 0
}

##
# Load all configurations
#
# Arguments:
#   None
#
# Returns:
#   0 on success, 1 on failure
##
load_all_configs() {
 local errors=0

 # Load main config (required)
 if ! load_main_config; then
  errors=$((errors + 1))
 fi

 # Load optional configs
 load_monitoring_config || true
 load_alert_config || true
 load_security_config || true

 # Validate all configs
 if ! validate_all_configs; then
  errors=$((errors + 1))
 fi

 if [[ ${errors} -gt 0 ]]; then
  return 1
 fi

 return 0
}

# Initialize on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
 # Don't auto-load, let scripts call load_all_configs explicitly
 :
fi
