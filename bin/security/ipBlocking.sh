#!/usr/bin/env bash
#
# IP Blocking Management Script
# Manages IP whitelist, blacklist, and temporary blocks
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
init_logging "${LOG_DIR}/ip_blocking.log" "ipBlocking"

# Initialize security functions
init_security

# Component name (used in logging and alerts)
export COMPONENT="SECURITY"
readonly COMPONENT

##
# Show usage
##
usage() {
    cat << EOF
IP Blocking Management Script

Usage: ${0} [OPTIONS] ACTION [IP] [OPTIONS...]

Actions:
    whitelist add IP [REASON]         Add IP to whitelist
    whitelist remove IP               Remove IP from whitelist
    whitelist list                    List all whitelisted IPs
    blacklist add IP [REASON]         Add IP to blacklist
    blacklist remove IP               Remove IP from blacklist
    blacklist list                    List all blacklisted IPs
    block IP [DURATION] [REASON]      Temporarily block IP
    unblock IP                        Unblock IP (remove from temp_block/blacklist)
    list [TYPE]                       List blocked/whitelisted IPs
    status IP                         Check status of IP
    cleanup                           Clean up expired temporary blocks

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file

Examples:
    ${0} whitelist add 192.168.1.100 "Internal server"
    ${0} blacklist add 192.168.1.200 "Known attacker"
    ${0} block 192.168.1.300 60 "Abuse detected"
    ${0} unblock 192.168.1.300
    ${0} list temp_block
    ${0} status 192.168.1.100

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
}

##
# Add IP to whitelist
#
# Arguments:
#   $1 - IP address
#   $2 - Reason (optional)
##
whitelist_add() {
    local ip="${1:?IP address required}"
    local reason="${2:-Added to whitelist}"
    
    # Validate IP
    if ! is_valid_ip "${ip}"; then
        log_error "Invalid IP address: ${ip}"
        return 1
    fi
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        INSERT INTO ip_management (ip_address, list_type, reason, created_by)
        VALUES ('${ip}'::inet, 'whitelist', '${reason}', '${USER:-system}')
        ON CONFLICT (ip_address) DO UPDATE
        SET list_type = 'whitelist',
            reason = '${reason}',
            expires_at = NULL,
            created_at = CURRENT_TIMESTAMP;
    "
    
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1; then
        log_info "IP ${ip} added to whitelist: ${reason}"
        record_security_event "unblock" "${ip}" "" "{\"action\": \"whitelist_add\", \"reason\": \"${reason}\"}"
        return 0
    else
        log_error "Failed to add IP ${ip} to whitelist"
        return 1
    fi
}

##
# Remove IP from whitelist
#
# Arguments:
#   $1 - IP address
##
whitelist_remove() {
    local ip="${1:?IP address required}"
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="DELETE FROM ip_management WHERE ip_address = '${ip}'::inet AND list_type = 'whitelist';"
    
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1; then
        log_info "IP ${ip} removed from whitelist"
        return 0
    else
        log_error "Failed to remove IP ${ip} from whitelist"
        return 1
    fi
}

##
# List whitelisted IPs
##
whitelist_list() {
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        SELECT ip_address, reason, created_at, created_by
        FROM ip_management
        WHERE list_type = 'whitelist'
        ORDER BY created_at DESC;
    "
    
    echo "Whitelisted IPs:"
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Add IP to blacklist
#
# Arguments:
#   $1 - IP address
#   $2 - Reason (optional)
##
blacklist_add() {
    local ip="${1:?IP address required}"
    local reason="${2:-Added to blacklist}"
    
    # Validate IP
    if ! is_valid_ip "${ip}"; then
        log_error "Invalid IP address: ${ip}"
        return 1
    fi
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        INSERT INTO ip_management (ip_address, list_type, reason, created_by)
        VALUES ('${ip}'::inet, 'blacklist', '${reason}', '${USER:-system}')
        ON CONFLICT (ip_address) DO UPDATE
        SET list_type = 'blacklist',
            reason = '${reason}',
            expires_at = NULL,
            created_at = CURRENT_TIMESTAMP;
    "
    
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1; then
        log_info "IP ${ip} added to blacklist: ${reason}"
        record_security_event "block" "${ip}" "" "{\"action\": \"blacklist_add\", \"reason\": \"${reason}\"}"
        return 0
    else
        log_error "Failed to add IP ${ip} to blacklist"
        return 1
    fi
}

##
# Remove IP from blacklist
#
# Arguments:
#   $1 - IP address
##
blacklist_remove() {
    local ip="${1:?IP address required}"
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="DELETE FROM ip_management WHERE ip_address = '${ip}'::inet AND list_type = 'blacklist';"
    
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1; then
        log_info "IP ${ip} removed from blacklist"
        record_security_event "unblock" "${ip}" "" "{\"action\": \"blacklist_remove\"}"
        return 0
    else
        log_error "Failed to remove IP ${ip} from blacklist"
        return 1
    fi
}

##
# List blacklisted IPs
##
blacklist_list() {
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        SELECT ip_address, reason, created_at, expires_at, created_by
        FROM ip_management
        WHERE list_type = 'blacklist'
        ORDER BY created_at DESC;
    "
    
    echo "Blacklisted IPs:"
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Temporarily block IP
#
# Arguments:
#   $1 - IP address
#   $2 - Duration in minutes (optional, default: 15)
#   $3 - Reason (optional)
##
block_ip_temporary() {
    local ip="${1:?IP address required}"
    local duration_minutes="${2:-15}"
    local reason="${3:-Temporary block}"
    
    # Validate IP
    if ! is_valid_ip "${ip}"; then
        log_error "Invalid IP address: ${ip}"
        return 1
    fi
    
    # Calculate expiration time
    local expires_at
    expires_at=$(date -d "${duration_minutes} minutes" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -v+"${duration_minutes}"M +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")
    
    if block_ip "${ip}" "temp_block" "${reason}" "${expires_at}"; then
        log_info "IP ${ip} temporarily blocked for ${duration_minutes} minutes: ${reason}"
        return 0
    else
        log_error "Failed to block IP ${ip}"
        return 1
    fi
}

##
# Unblock IP (remove from temp_block or blacklist)
#
# Arguments:
#   $1 - IP address
##
unblock_ip() {
    local ip="${1:?IP address required}"
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="DELETE FROM ip_management WHERE ip_address = '${ip}'::inet AND list_type IN ('temp_block', 'blacklist');"
    
    if PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1; then
        log_info "IP ${ip} unblocked"
        record_security_event "unblock" "${ip}" "" "{\"action\": \"manual_unblock\"}"
        return 0
    else
        log_error "Failed to unblock IP ${ip}"
        return 1
    fi
}

##
# List IPs by type
#
# Arguments:
#   $1 - List type (whitelist, blacklist, temp_block, or all)
##
list_ips() {
    local list_type="${1:-all}"
    
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        SELECT ip_address, list_type, reason, created_at, expires_at, created_by
        FROM ip_management
    "
    
    if [[ "${list_type}" != "all" ]]; then
        query="${query} WHERE list_type = '${list_type}'"
    fi
    
    query="${query} ORDER BY created_at DESC;"
    
    echo "IP Management List (${list_type}):"
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || true
}

##
# Check status of IP
#
# Arguments:
#   $1 - IP address
##
check_ip_status() {
    local ip="${1:?IP address required}"
    
    echo "Status for IP: ${ip}"
    echo ""
    
    if is_ip_whitelisted "${ip}"; then
        echo "  Status: WHITELISTED"
    elif is_ip_blacklisted "${ip}"; then
        echo "  Status: BLOCKED"
    else
        echo "  Status: NORMAL"
    fi
    
    # Get details from database
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        SELECT list_type, reason, created_at, expires_at, created_by
        FROM ip_management
        WHERE ip_address = '${ip}'::inet
          AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);
    "
    
    echo ""
    echo "Details:"
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" 2>/dev/null || echo "  No entries found"
}

##
# Clean up expired temporary blocks
##
cleanup_expired() {
    local dbname="${DBNAME:-osm_notes_monitoring}"
    local dbhost="${DBHOST:-localhost}"
    local dbport="${DBPORT:-5432}"
    local dbuser="${DBUSER:-postgres}"
    
    local query="
        DELETE FROM ip_management
        WHERE list_type = 'temp_block'
          AND expires_at IS NOT NULL
          AND expires_at < CURRENT_TIMESTAMP;
    "
    
    local deleted
    deleted=$(PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -t -A \
        -c "SELECT COUNT(*) FROM (${query}) deleted;" 2>/dev/null || echo "0")
    
    # Actually delete
    PGPASSWORD="${PGPASSWORD:-}" psql \
        -h "${dbhost}" \
        -p "${dbport}" \
        -U "${dbuser}" \
        -d "${dbname}" \
        -c "${query}" > /dev/null 2>&1 || true
    
    deleted=$(echo "${deleted}" | tr -d '[:space:]' || echo "0")
    
    log_info "Cleaned up ${deleted} expired temporary block(s)"
    echo "Cleaned up ${deleted} expired temporary block(s)"
}

##
# Main function
##
main() {
    local action="${1:-}"
    local subaction="${2:-}"
    
    # Load configuration
    load_config "${CONFIG_FILE:-}"
    
    # Initialize alerting
    init_alerting
    
    case "${action}" in
        whitelist)
            case "${subaction}" in
                add)
                    local ip="${3:-}"
                    local reason="${4:-Added to whitelist}"
                    if [[ -z "${ip}" ]]; then
                        log_error "IP address required"
                        usage
                        exit 1
                    fi
                    whitelist_add "${ip}" "${reason}"
                    ;;
                remove)
                    local ip="${3:-}"
                    if [[ -z "${ip}" ]]; then
                        log_error "IP address required"
                        usage
                        exit 1
                    fi
                    whitelist_remove "${ip}"
                    ;;
                list)
                    whitelist_list
                    ;;
                *)
                    log_error "Unknown whitelist action: ${subaction}"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        blacklist)
            case "${subaction}" in
                add)
                    local ip="${3:-}"
                    local reason="${4:-Added to blacklist}"
                    if [[ -z "${ip}" ]]; then
                        log_error "IP address required"
                        usage
                        exit 1
                    fi
                    blacklist_add "${ip}" "${reason}"
                    ;;
                remove)
                    local ip="${3:-}"
                    if [[ -z "${ip}" ]]; then
                        log_error "IP address required"
                        usage
                        exit 1
                    fi
                    blacklist_remove "${ip}"
                    ;;
                list)
                    blacklist_list
                    ;;
                *)
                    log_error "Unknown blacklist action: ${subaction}"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        block)
            local ip="${2:-}"
            local duration="${3:-15}"
            local reason="${4:-Temporary block}"
            if [[ -z "${ip}" ]]; then
                log_error "IP address required"
                usage
                exit 1
            fi
            block_ip_temporary "${ip}" "${duration}" "${reason}"
            ;;
        unblock)
            local ip="${2:-}"
            if [[ -z "${ip}" ]]; then
                log_error "IP address required"
                usage
                exit 1
            fi
            unblock_ip "${ip}"
            ;;
        list)
            local list_type="${2:-all}"
            list_ips "${list_type}"
            ;;
        status)
            local ip="${2:-}"
            if [[ -z "${ip}" ]]; then
                log_error "IP address required"
                usage
                exit 1
            fi
            check_ip_status "${ip}"
            ;;
        cleanup)
            cleanup_expired
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

