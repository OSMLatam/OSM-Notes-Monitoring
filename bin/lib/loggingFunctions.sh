#!/usr/bin/env bash
#
# Logging Functions Library
# Provides centralized logging utilities
#
# Version: 1.0.0
# Date: 2025-01-23
#

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Default log level
LOG_LEVEL="${LOG_LEVEL:-${LOG_LEVEL_INFO}}"
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
    local level_num
    case "${level}" in
        DEBUG)
            level_num=${LOG_LEVEL_DEBUG}
            ;;
        INFO)
            level_num=${LOG_LEVEL_INFO}
            ;;
        WARNING)
            level_num=${LOG_LEVEL_WARNING}
            ;;
        ERROR)
            level_num=${LOG_LEVEL_ERROR}
            ;;
        *)
            level_num=${LOG_LEVEL_INFO}
            ;;
    esac
    
    # Check if we should log this level
    if [[ ${level_num} -lt ${LOG_LEVEL} ]]; then
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

