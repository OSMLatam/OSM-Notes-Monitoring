#!/usr/bin/env bash
#
# Configuration Functions Library
# Provides configuration loading and validation utilities
#
# Version: 1.0.0
# Date: 2025-01-23
#

# Source logging functions
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
    
    # Validate database connection
    if [[ ${errors} -eq 0 ]]; then
        if ! check_database_connection 2>/dev/null; then
            log_warning "Cannot connect to database (this may be OK in some contexts)"
        fi
    fi
    
    if [[ ${errors} -gt 0 ]]; then
        return 1
    fi
    
    return 0
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
    
    # Validate main config
    if ! validate_main_config; then
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

