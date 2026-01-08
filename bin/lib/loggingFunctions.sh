#!/usr/bin/env bash
#
# Logging Functions Library
# Provides centralized logging utilities
#
# Version: 1.0.0
# Date: 2025-12-24
#

# Log levels (only define if not already set to allow multiple sourcing)
if [[ -z "${LOG_LEVEL_DEBUG:-}" ]]; then
readonly LOG_LEVEL_DEBUG=0
fi
if [[ -z "${LOG_LEVEL_INFO:-}" ]]; then
readonly LOG_LEVEL_INFO=1
fi
if [[ -z "${LOG_LEVEL_WARNING:-}" ]]; then
readonly LOG_LEVEL_WARNING=2
fi
if [[ -z "${LOG_LEVEL_ERROR:-}" ]]; then
readonly LOG_LEVEL_ERROR=3
fi

# Default log level
# Use default value if LOG_LEVEL_INFO is not set (for cron environment)
LOG_LEVEL="${LOG_LEVEL:-${LOG_LEVEL_INFO:-1}}"
LOG_FILE="${LOG_FILE:-/dev/stderr}"
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "${0:-unknown}")}"

##
# Initialize logging
#
# Arguments:
#   $1 - Log file path (optional)
#   $2 - Script name (optional)
##
init_logging() {
    local log_file="${1:-}"
    local script_name="${2:-}"
    
    if [[ -n "${log_file}" ]]; then
        LOG_FILE="${log_file}"
        # Create log directory if it doesn't exist
        local log_dir
        log_dir="$(dirname "${LOG_FILE}")"
        if [[ ! -d "${log_dir}" ]]; then
            mkdir -p "${log_dir}"
        fi
    fi
    
    if [[ -n "${script_name}" ]]; then
        SCRIPT_NAME="${script_name}"
    fi
}

##
# Get current timestamp
#
# Returns:
#   Timestamp string via stdout
##
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

##
# Log a message
#
# Arguments:
#   $1 - Log level (DEBUG, INFO, WARNING, ERROR)
#   $2 - Message
##
log_message() {
    local level="${1:?Log level required}"
    shift
    local message="$*"
    local timestamp
    timestamp=$(get_timestamp)
    
    # Map level to numeric value
    # Ensure constants are defined (may not be available in cron environment)
    local log_level_debug="${LOG_LEVEL_DEBUG:-0}"
    local log_level_info="${LOG_LEVEL_INFO:-1}"
    local log_level_warning="${LOG_LEVEL_WARNING:-2}"
    local log_level_error="${LOG_LEVEL_ERROR:-3}"
    
    local level_num
    case "${level}" in
        DEBUG)
            level_num="${log_level_debug}"
            ;;
        INFO)
            level_num="${log_level_info}"
            ;;
        WARNING)
            level_num="${log_level_warning}"
            ;;
        ERROR)
            level_num="${log_level_error}"
            ;;
        *)
            level_num="${log_level_info}"
            ;;
    esac
    
    # Check if we should log this level
    # Use default LOG_LEVEL_INFO if LOG_LEVEL is not set
    # Handle case where LOG_LEVEL might be a string (INFO, DEBUG, etc.) or a number
    local current_log_level_raw="${LOG_LEVEL:-}"
    local current_log_level="${log_level_info}"  # Default to INFO level
    
    if [[ -n "${current_log_level_raw}" ]]; then
        # If LOG_LEVEL is a number, use it directly
        if [[ "${current_log_level_raw}" =~ ^[0-9]+$ ]]; then
            current_log_level="${current_log_level_raw}"
        # If LOG_LEVEL is a string (INFO, DEBUG, etc.), convert to number
        else
            case "${current_log_level_raw}" in
                DEBUG)
                    current_log_level="${log_level_debug}"
                    ;;
                INFO)
                    current_log_level="${log_level_info}"
                    ;;
                WARNING)
                    current_log_level="${log_level_warning}"
                    ;;
                ERROR)
                    current_log_level="${log_level_error}"
                    ;;
                *)
                    # Unknown level, default to INFO
                    current_log_level="${log_level_info}"
                    ;;
            esac
        fi
    fi
    
    if [[ "${level_num}" -lt "${current_log_level}" ]]; then
        return 0
    fi
    
    # Format: TIMESTAMP [LEVEL] SCRIPT_NAME: MESSAGE
    echo "${timestamp} [${level}] ${SCRIPT_NAME}: ${message}" >> "${LOG_FILE}"
}

##
# Log debug message
#
# Arguments:
#   $@ - Message
##
log_debug() {
    log_message "DEBUG" "$@"
}

##
# Log info message
#
# Arguments:
#   $@ - Message
##
log_info() {
    log_message "INFO" "$@"
}

##
# Log warning message
#
# Arguments:
#   $@ - Message
##
log_warning() {
    log_message "WARNING" "$@"
}

##
# Log error message
#
# Arguments:
#   $@ - Message
##
log_error() {
    log_message "ERROR" "$@"
}

##
# Log and exit with error
#
# Arguments:
#   $1 - Exit code
#   $2 - Error message
##
log_error_and_exit() {
    local exit_code="${1:-1}"
    local error_message="${2:-Unknown error}"
    
    log_error "${error_message}"
    exit "${exit_code}"
}

