#!/usr/bin/env bash
#
# DDoS Protection Script
# Implements DDoS attack detection, automatic IP blocking, and connection rate limiting
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

# Initialize logging
init_logging "${LOG_DIR}/ddos_protection.log" "ddosProtection"

# Initialize security functions
init_security

# Component name
COMPONENT="SECURITY"
readonly COMPONENT

##
# Show usage
##
usage() {
    cat << EOF
DDoS Protection Script

Usage: ${0} [OPTIONS] [ACTION]

Actions:
    check [IP]                    Check for DDoS attacks
    monitor                       Monitor connection rates continuously
    block IP [REASON]             Manually block an IP address
    unblock IP                    Unblock an IP address
    stats                         Show DDoS protection statistics

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --window SECONDS    Time window for detection (default: 60)
    --threshold COUNT   Request threshold per window (default: from config)

Examples:
    ${0} check                    # Check all IPs for attacks
    ${0} check 192.168.1.100      # Check specific IP
    ${0} monitor                  # Continuous monitoring
    ${0} block 192.168.1.100 "DDoS attack detected"
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
    export DDOS_THRESHOLD_REQUESTS_PER_SECOND="${DDOS_THRESHOLD_REQUESTS_PER_SECOND:-100}"
    export DDOS_THRESHOLD_CONCURRENT_CONNECTIONS="${DDOS_THRESHOLD_CONCURRENT_CONNECTIONS:-500}"
    export DDOS_AUTO_BLOCK_DURATION_MINUTES="${DDOS_AUTO_BLOCK_DURATION_MINUTES:-15}"
    export DDOS_CHECK_WINDOW_SECONDS="${DDOS_CHECK_WINDOW_SECONDS:-60}"
    export DDOS_ENABLED="${DDOS_ENABLED:-true}"
    export DDOS_GEO_FILTERING_ENABLED="${DDOS_GEO_FILTERING_ENABLED:-false}"
    export DDOS_ALLOWED_COUNTRIES="${DDOS_ALLOWED_COUNTRIES:-}"
    export DDOS_BLOCKED_COUNTRIES="${DDOS_BLOCKED_COUNTRIES:-}"
}

##
# Detect DDoS attack for an IP address
#
# Arguments:
#   $1 - IP address
#   $2 - Time window in seconds (default: 60)
#   $3 - Request threshold (default: from config)
#
# Returns:
#   0 if attack detected, 1 if normal
##
detect_ddos_attack() {
    local ip="${1:?IP address required}"
    local window_seconds="${2:-${DDOS_CHECK_WINDOW_SECONDS}}"
    local threshold="${3:-${DDOS_THRESHOLD_REQUESTS_PER_SECOND}}"
    
    # Check if whitelisted (bypass DDoS detection)
    if is_ip_whitelisted "${ip}"; then
        log_debug "IP ${ip} is whitelisted, bypassing DDoS detection"
        return 1
    fi
    
    # Check geographic filter
    if check_geographic_filter "${ip}"; then
        log_info "${COMPONENT}: IP ${ip} blocked by geographic filter"
        auto_block_ip "${ip}" "Geographic filter violation"
        return 0  # Treated as attack
    fi
    
    # Count requests in time window
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        SELECT COUNT(*) 
        FROM security_events
        WHERE ip_address = '${ip}'::inet
          AND event_type IN ('rate_limit', 'ddos')
          AND timestamp > CURRENT_TIMESTAMP - INTERVAL '${window_seconds} seconds';
    "
    
    local request_count
    request_count=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null || echo "0")
    
    # Remove whitespace
    request_count=$(echo "${request_count}" | tr -d '[:space:]' || echo "0")
    
    # Calculate requests per second
    local requests_per_second=0
    if [[ ${window_seconds} -gt 0 ]]; then
        requests_per_second=$((request_count / window_seconds))
    fi
    
    # Record metric
    record_metric "${COMPONENT}" "ddos_requests_per_second" "${requests_per_second}" "component=security,ip=${ip}"
    record_metric "${COMPONENT}" "ddos_request_count" "${request_count}" "component=security,ip=${ip}"
    
    log_info "${COMPONENT}: DDoS check for ${ip} - Requests: ${request_count}, RPS: ${requests_per_second}, Threshold: ${threshold}"
    
    # Check if threshold exceeded
    if [[ ${requests_per_second} -ge ${threshold} ]]; then
        log_warning "${COMPONENT}: DDoS attack detected for ${ip}: ${requests_per_second} requests/second (threshold: ${threshold})"
        record_security_event "ddos" "${ip}" "" "{\"requests_per_second\": ${requests_per_second}, \"threshold\": ${threshold}, \"window_seconds\": ${window_seconds}}"
        return 0  # Attack detected
    else
        return 1  # Normal traffic
    fi
}

##
# Get geographic location for an IP address (optional)
#
# Arguments:
#   $1 - IP address
#
# Returns:
#   Country code (e.g., "US", "GB") or empty string if not available
##
get_ip_country() {
    local ip="${1:?IP address required}"
    
    # Check if geographic filtering is enabled
    if [[ "${DDOS_GEO_FILTERING_ENABLED:-false}" != "true" ]]; then
        return 1
    fi
    
    # Try using geoiplookup if available
    if command -v geoiplookup > /dev/null 2>&1; then
        local country
        country=$(geoiplookup "${ip}" 2>/dev/null | grep -i "country" | awk -F': ' '{print $2}' | awk '{print $1}' | tr -d ',' || echo "")
        if [[ -n "${country}" ]]; then
            echo "${country}"
            return 0
        fi
    fi
    
    # Try using curl with ip-api.com (free service)
    if command -v curl > /dev/null 2>&1; then
        local country
        country=$(curl -s "http://ip-api.com/json/${ip}?fields=countryCode" 2>/dev/null | grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4 || echo "")
        if [[ -n "${country}" ]]; then
            echo "${country}"
            return 0
        fi
    fi
    
    return 1
}

##
# Check if IP should be blocked based on geographic filtering
#
# Arguments:
#   $1 - IP address
#
# Returns:
#   0 if should be blocked, 1 if allowed
##
check_geographic_filter() {
    local ip="${1:?IP address required}"
    
    # Check if geographic filtering is enabled
    if [[ "${DDOS_GEO_FILTERING_ENABLED:-false}" != "true" ]]; then
        return 1  # Not blocked (filtering disabled)
    fi
    
    # Get country code
    local country
    country=$(get_ip_country "${ip}" || echo "")
    
    if [[ -z "${country}" ]]; then
        # If we can't determine country, allow by default
        log_debug "${COMPONENT}: Could not determine country for ${ip}, allowing"
        return 1  # Not blocked
    fi
    
    # Check blocked countries list
    if [[ -n "${DDOS_BLOCKED_COUNTRIES:-}" ]]; then
        local blocked_list
        IFS=',' read -ra blocked_list <<< "${DDOS_BLOCKED_COUNTRIES}"
        for blocked_country in "${blocked_list[@]}"; do
            blocked_country=$(echo "${blocked_country}" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
            if [[ "${country}" == "${blocked_country}" ]]; then
                log_info "${COMPONENT}: IP ${ip} from blocked country ${country}"
                return 0  # Should be blocked
            fi
        done
    fi
    
    # Check allowed countries list (whitelist approach)
    if [[ -n "${DDOS_ALLOWED_COUNTRIES:-}" ]]; then
        local allowed=false
        local allowed_list
        IFS=',' read -ra allowed_list <<< "${DDOS_ALLOWED_COUNTRIES}"
        for allowed_country in "${allowed_list[@]}"; do
            allowed_country=$(echo "${allowed_country}" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
            if [[ "${country}" == "${allowed_country}" ]]; then
                allowed=true
                break
            fi
        done
        
        if [[ "${allowed}" != "true" ]]; then
            log_info "${COMPONENT}: IP ${ip} from country ${country} not in allowed list"
            return 0  # Should be blocked
        fi
    fi
    
    return 1  # Not blocked
}

##
# Check concurrent connections for an IP
#
# Arguments:
#   $1 - IP address
#   $2 - Threshold (default: from config)
#
# Returns:
#   0 if threshold exceeded, 1 if normal
##
check_concurrent_connections() {
    local ip="${1:?IP address required}"
    local threshold="${2:-${DDOS_THRESHOLD_CONCURRENT_CONNECTIONS}}"
    
    # Check if whitelisted
    if is_ip_whitelisted "${ip}"; then
        log_debug "IP ${ip} is whitelisted, bypassing connection check"
        return 1
    fi
    
    # Count active connections (this would typically use netstat/ss)
    # For now, we'll use a database query to count recent connections
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        SELECT COUNT(DISTINCT ip_address)
        FROM security_events
        WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '10 seconds'
          AND event_type IN ('rate_limit', 'ddos');
    "
    
    local connection_count
    connection_count=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "${query}" 2>/dev/null || echo "0")
    
    connection_count=$(echo "${connection_count}" | tr -d '[:space:]' || echo "0")
    
    # Record metric
    record_metric "${COMPONENT}" "ddos_concurrent_connections" "${connection_count}" "component=security"
    
    log_info "${COMPONENT}: Concurrent connections check - Count: ${connection_count}, Threshold: ${threshold}"
    
    if [[ ${connection_count} -ge ${threshold} ]]; then
        log_warning "${COMPONENT}: High concurrent connections detected: ${connection_count} (threshold: ${threshold})"
        record_security_event "ddos" "" "" "{\"concurrent_connections\": ${connection_count}, \"threshold\": ${threshold}}"
        return 0  # Threshold exceeded
    else
        return 1  # Normal
    fi
}

##
# Automatically block IP address for DDoS attack
#
# Arguments:
#   $1 - IP address
#   $2 - Reason (optional)
#   $3 - Duration in minutes (default: from config)
##
auto_block_ip() {
    local ip="${1:?IP address required}"
    local reason="${2:-DDoS attack detected}"
    local duration_minutes="${3:-${DDOS_AUTO_BLOCK_DURATION_MINUTES}}"
    
    # Calculate expiration time
    local expires_at
    expires_at=$(date -d "${duration_minutes} minutes" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -v+"${duration_minutes}"M +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")
    
    log_warning "${COMPONENT}: Auto-blocking IP ${ip} for ${duration_minutes} minutes: ${reason}"
    
    # Block IP using security functions
    if block_ip "${ip}" "temp_block" "${reason}" "${expires_at}"; then
        # Send alert
        send_alert "${COMPONENT}" "CRITICAL" "ddos_ip_blocked" "IP ${ip} automatically blocked due to DDoS attack: ${reason} (duration: ${duration_minutes} minutes)"
        
        # Record metric
        record_metric "${COMPONENT}" "ddos_ips_blocked" "1" "component=security,ip=${ip}"
        
        return 0
    else
        log_error "${COMPONENT}: Failed to auto-block IP ${ip}"
        return 1
    fi
}

##
# Check for DDoS attacks and auto-block if detected
#
# Arguments:
#   $1 - IP address (optional, checks all if not provided)
##
check_and_block_ddos() {
    local ip="${1:-}"
    
    if [[ "${DDOS_ENABLED:-false}" != "true" ]]; then
        log_info "${COMPONENT}: DDoS protection is disabled"
        return 0
    fi
    
    local attacks_detected=0
    
    if [[ -n "${ip}" ]]; then
        # Check specific IP
        if detect_ddos_attack "${ip}"; then
            auto_block_ip "${ip}" "DDoS attack detected (${DDOS_THRESHOLD_REQUESTS_PER_SECOND} req/s threshold)"
            attacks_detected=1
        fi
    else
        # Check all IPs with recent activity
        local dbname="${DBNAME:-osm_notes_monitoring}"
        local dbhost="${DBHOST:-localhost}"
        local dbport="${DBPORT:-5432}"
        local dbuser="${DBUSER:-postgres}"
        
        local query="
            SELECT DISTINCT ip_address::text
            FROM security_events
            WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '${DDOS_CHECK_WINDOW_SECONDS} seconds'
              AND event_type IN ('rate_limit', 'ddos')
            ORDER BY ip_address;
        "
        
        local ips
        ips=$(PGPASSWORD="${PGPASSWORD:-}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${query}" 2>/dev/null || echo "")
        
        if [[ -n "${ips}" ]]; then
            while IFS= read -r check_ip; do
                check_ip=$(echo "${check_ip}" | tr -d '[:space:]')
                if [[ -n "${check_ip}" ]]; then
                    if detect_ddos_attack "${check_ip}"; then
                        auto_block_ip "${check_ip}" "DDoS attack detected (${DDOS_THRESHOLD_REQUESTS_PER_SECOND} req/s threshold)"
                        attacks_detected=$((attacks_detected + 1))
                    fi
                fi
            done <<< "${ips}"
        fi
    fi
    
    # Check concurrent connections
    if check_concurrent_connections ""; then
        log_warning "${COMPONENT}: High concurrent connections detected, but no specific IP to block"
    fi
    
    if [[ ${attacks_detected} -gt 0 ]]; then
        log_warning "${COMPONENT}: DDoS protection blocked ${attacks_detected} IP(s)"
        return 1
    else
        log_info "${COMPONENT}: No DDoS attacks detected"
        return 0
    fi
}

##
# Monitor connection rates continuously
##
monitor_connections() {
    log_info "${COMPONENT}: Starting DDoS monitoring (continuous mode)"
    
    while true; do
        check_and_block_ddos
        
        # Wait before next check
        sleep "${DDOS_CHECK_WINDOW_SECONDS}"
    done
}

##
# Get DDoS protection statistics
##
get_ddos_stats() {
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        SELECT 
            COUNT(*) FILTER (WHERE event_type = 'ddos') as ddos_events,
            COUNT(DISTINCT ip_address) FILTER (WHERE event_type = 'ddos') as unique_attacking_ips,
            MAX(timestamp) FILTER (WHERE event_type = 'ddos') as last_attack_time
        FROM security_events
        WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours';
    "
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
    
    # Show blocked IPs
    echo ""
    echo "Currently blocked IPs:"
    query="
        SELECT ip_address, list_type, reason, expires_at
        FROM ip_management
        WHERE list_type IN ('temp_block', 'blacklist')
          AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        ORDER BY created_at DESC
        LIMIT 20;
    "
    
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
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
        check)
            local ip="${2:-}"
            check_and_block_ddos "${ip}"
            ;;
        monitor)
            monitor_connections
            ;;
        block)
            local ip="${2:-}"
            local reason="${3:-Manual block}"
            
            if [[ -z "${ip}" ]]; then
                log_error "IP address required for block action"
                usage
                exit 1
            fi
            
            block_ip "${ip}" "temp_block" "${reason}"
            ;;
        unblock)
            local ip="${2:-}"
            
            if [[ -z "${ip}" ]]; then
                log_error "IP address required for unblock action"
                usage
                exit 1
            fi
            
            # Unblock by removing from ip_management
            local dbname="${DBNAME:-osm_notes_monitoring}"
            local dbhost="${DBHOST:-localhost}"
            local dbport="${DBPORT:-5432}"
            local dbuser="${DBUSER:-postgres}"
            
            local query="DELETE FROM ip_management WHERE ip_address = '${ip}'::inet AND list_type = 'temp_block';"
            
            if PGPASSWORD="${PGPASSWORD:-}" psql \
                -h "${dbhost}" \
                -p "${dbport}" \
                -U "${dbuser}" \
                -d "${dbname}" \
                -c "${query}" > /dev/null 2>&1; then
                log_info "IP ${ip} unblocked"
                record_security_event "unblock" "${ip}" "" "{\"reason\": \"manual_unblock\"}"
            else
                log_error "Failed to unblock IP ${ip}"
                exit 1
            fi
            ;;
        stats)
            get_ddos_stats
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
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
            shift
            ;;
        -q|--quiet)
            export LOG_LEVEL="${LOG_LEVEL_ERROR}"
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --window)
            DDOS_CHECK_WINDOW_SECONDS="$2"
            shift 2
            ;;
        --threshold)
            DDOS_THRESHOLD_REQUESTS_PER_SECOND="$2"
            shift 2
            ;;
        *)
            # Remaining arguments are action and parameters
            break
            ;;
    esac
done

# Run main function
main "$@"

