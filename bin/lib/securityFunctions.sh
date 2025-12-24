#!/usr/bin/env bash
#
# Security Functions Library
# Provides security utilities for rate limiting, IP management, etc.
#
# Version: 1.0.0
# Date: 2025-01-23
#

# Source logging functions
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/loggingFunctions.sh"
fi

##
# Initialize security functions
# Sources security configuration
##
init_security() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root
    project_root="$(dirname "$(dirname "${script_dir}")")"
    
    # Source security configuration if available
    if [[ -f "${project_root}/config/security.conf" ]]; then
        source "${project_root}/config/security.conf"
    fi
    
    # Set defaults
    export RATE_LIMIT_PER_IP_PER_MINUTE="${RATE_LIMIT_PER_IP_PER_MINUTE:-60}"
    export RATE_LIMIT_PER_IP_PER_HOUR="${RATE_LIMIT_PER_IP_PER_HOUR:-1000}"
    export DDOS_THRESHOLD_REQUESTS_PER_SECOND="${DDOS_THRESHOLD_REQUESTS_PER_SECOND:-100}"
}

##
# Validate IP address format
#
# Arguments:
#   $1 - IP address to validate
#
# Returns:
#   0 if valid, 1 if invalid
##
is_valid_ip() {
    local ip="${1:?IP address required}"
    
    # Basic IPv4 validation
    if [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Check each octet is 0-255
        local IFS='.'
        local -a octets=(${ip})
        for octet in "${octets[@]}"; do
            if [[ ${octet} -lt 0 || ${octet} -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    
    # IPv6 validation (basic)
    if [[ "${ip}" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    
    return 1
}

##
# Check if IP is whitelisted
#
# Arguments:
#   $1 - IP address
#
# Returns:
#   0 if whitelisted, 1 if not
##
is_ip_whitelisted() {
    local ip="${1:?IP address required}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    query="SELECT COUNT(*) FROM ip_management
           WHERE ip_address = '${ip}'::inet
             AND list_type = 'whitelist'
             AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);"
    
    local count
    count=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null)
    
    if [[ "${count:-0}" -gt 0 ]]; then
        return 0  # Whitelisted
    else
        return 1  # Not whitelisted
    fi
}

##
# Check if IP is blacklisted
#
# Arguments:
#   $1 - IP address
#
# Returns:
#   0 if blacklisted, 1 if not
##
is_ip_blacklisted() {
    local ip="${1:?IP address required}"
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    query="SELECT COUNT(*) FROM ip_management
           WHERE ip_address = '${ip}'::inet
             AND list_type IN ('blacklist', 'temp_block')
             AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);"
    
    local count
    count=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null)
    
    if [[ "${count:-0}" -gt 0 ]]; then
        return 0  # Blacklisted
    else
        return 1  # Not blacklisted
    fi
}

##
# Check rate limit for IP
#
# Arguments:
#   $1 - IP address
#   $2 - Time window in seconds (default: 60)
#   $3 - Maximum requests (default: from config)
#
# Returns:
#   0 if within limit, 1 if exceeded
##
check_rate_limit() {
    local ip="${1:?IP address required}"
    local window_seconds="${2:-60}"
    local max_requests="${3:-${RATE_LIMIT_PER_IP_PER_MINUTE}}"
    
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
    
    # Count requests in time window
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    query="SELECT COUNT(*) FROM security_events
           WHERE ip_address = '${ip}'::inet
             AND event_type = 'rate_limit'
             AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${window_seconds} seconds';"
    
    local count
    count=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null)
    
    if [[ "${count:-0}" -ge "${max_requests}" ]]; then
        log_warning "Rate limit exceeded for IP ${ip}: ${count}/${max_requests}"
        return 1  # Limit exceeded
    else
        return 0  # Within limit
    fi
}

##
# Record security event
#
# Arguments:
#   $1 - Event type (rate_limit, ddos, abuse, block, unblock)
#   $2 - IP address
#   $3 - Endpoint (optional)
#   $4 - Metadata JSON (optional)
#
# Returns:
#   0 on success, 1 on failure
##
record_security_event() {
    local event_type="${1:?Event type required}"
    local ip_address="${2:?IP address required}"
    local endpoint="${3:-}"
    local metadata="${4:-null}"
    
    # Validate event type
    case "${event_type}" in
        rate_limit|ddos|abuse|block|unblock)
            ;;
        *)
            log_error "Invalid event type: ${event_type}"
            return 1
            ;;
    esac
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    query="INSERT INTO security_events (event_type, ip_address, endpoint, metadata)
           VALUES ('${event_type}', '${ip_address}'::inet, '${endpoint}', '${metadata}'::jsonb);"
    
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1; then
        log_debug "Security event recorded: ${event_type} for ${ip_address}"
        return 0
    else
        log_error "Failed to record security event"
        return 1
    fi
}

##
# Block IP address
#
# Arguments:
#   $1 - IP address
#   $2 - Block type (temp_block or blacklist)
#   $3 - Reason
#   $4 - Expiration timestamp (optional, for temp_block)
#
# Returns:
#   0 on success, 1 on failure
##
block_ip() {
    local ip="${1:?IP address required}"
    local block_type="${2:-temp_block}"
    local reason="${3:-No reason provided}"
    local expires_at="${4:-}"
    
    # Validate block type
    case "${block_type}" in
        temp_block|blacklist)
            ;;
        *)
            log_error "Invalid block type: ${block_type}"
            return 1
            ;;
    esac
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query
    if [[ -n "${expires_at}" && "${block_type}" == "temp_block" ]]; then
        query="INSERT INTO ip_management (ip_address, list_type, reason, expires_at)
               VALUES ('${ip}'::inet, '${block_type}', '${reason}', '${expires_at}'::timestamp)
               ON CONFLICT (ip_address) DO UPDATE
               SET list_type = '${block_type}',
                   reason = '${reason}',
                   expires_at = '${expires_at}'::timestamp;"
    else
        query="INSERT INTO ip_management (ip_address, list_type, reason)
               VALUES ('${ip}'::inet, '${block_type}', '${reason}')
               ON CONFLICT (ip_address) DO UPDATE
               SET list_type = '${block_type}',
                   reason = '${reason}',
                   expires_at = NULL;"
    fi
    
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1; then
        log_info "IP ${ip} blocked (${block_type}): ${reason}"
        record_security_event "block" "${ip}" "" "{\"reason\": \"${reason}\", \"type\": \"${block_type}\"}"
        return 0
    else
        log_error "Failed to block IP ${ip}"
        return 1
    fi
}

# Initialize on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_security
fi

