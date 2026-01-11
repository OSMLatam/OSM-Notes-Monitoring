#!/usr/bin/env bash
#
# Daemon Metrics Collection Script
# Collects metrics from the OSM-Notes-Ingestion daemon process
#
# Version: 1.0.0
# Date: 2026-01-09
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
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging
init_logging "${LOG_DIR}/daemon_metrics.log" "collectDaemonMetrics"

# Component name
readonly COMPONENT="INGESTION"

# Daemon service name
readonly DAEMON_SERVICE_NAME="${DAEMON_SERVICE_NAME:-osm-notes-ingestion-daemon.service}"

# Daemon log file path
readonly DAEMON_LOG_FILE="${DAEMON_LOG_FILE:-/var/log/osm-notes-ingestion/daemon/processAPINotesDaemon.log}"

# Daemon lock file path
readonly DAEMON_LOCK_FILE="${DAEMON_LOCK_FILE:-/tmp/osm-notes-ingestion/locks/processAPINotesDaemon.lock}"

##
# Check daemon service status
##
check_daemon_service_status() {
    local service_status="unknown"
    local service_active=0
    local service_enabled=0
    
    # Ensure PATH includes standard binary directories for systemctl
    # This is critical when script runs from cron or with limited PATH
    local saved_path="${PATH:-}"
    export PATH="/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin:${PATH:-}"
    
    # Find systemctl command (may be in /usr/bin or /bin)
    local systemctl_cmd
    if command -v systemctl > /dev/null 2>&1; then
        systemctl_cmd="systemctl"
    elif [[ -x /usr/bin/systemctl ]]; then
        systemctl_cmd="/usr/bin/systemctl"
    elif [[ -x /bin/systemctl ]]; then
        systemctl_cmd="/bin/systemctl"
    else
        log_debug "${COMPONENT}: systemctl not available, skipping service status check"
        export PATH="${saved_path}"
        return 0
    fi
    
    if [[ -n "${systemctl_cmd}" ]]; then
        # Get service status directly (most reliable method)
        # This works even if list-unit-files fails or has formatting issues
        local status_output
        status_output=$("${systemctl_cmd}" is-active "${DAEMON_SERVICE_NAME}" 2>/dev/null || echo "unknown")
        
        # If we got a valid status (active, inactive, failed, etc.), service exists
        if [[ "${status_output}" != "unknown" ]]; then
            
            if [[ "${status_output}" == "active" ]]; then
                service_status="active"
                service_active=1
            elif [[ "${status_output}" == "inactive" ]]; then
                service_status="inactive"
            elif [[ "${status_output}" == "failed" ]]; then
                service_status="failed"
            else
                service_status="${status_output}"
            fi
            
            # Check if service is enabled
            local enabled_output
            enabled_output=$("${systemctl_cmd}" is-enabled "${DAEMON_SERVICE_NAME}" 2>/dev/null || echo "disabled")
            if [[ "${enabled_output}" == "enabled" ]]; then
                service_enabled=1
            fi
        else
            service_status="not-found"
            log_debug "${COMPONENT}: Daemon service not found: ${DAEMON_SERVICE_NAME}"
        fi
    fi
    
    # Restore original PATH
    export PATH="${saved_path}"
    
    # Record metrics
    record_metric "${COMPONENT}" "daemon_status" "${service_active}" "component=ingestion,status=${service_status}"
    record_metric "${COMPONENT}" "daemon_service_enabled" "${service_enabled}" "component=ingestion"
    
    log_info "${COMPONENT}: Daemon service status: ${service_status} (active: ${service_active}, enabled: ${service_enabled})"
    
    echo "${service_status}"
}

##
# Get daemon process information
##
get_daemon_process_info() {
    local daemon_pid=0
    local daemon_uptime_seconds=0
    local daemon_restarts=0
    
    # Try to find daemon process
    # Look for processAPINotesDaemon or processAPINotes (the actual script)
    local pid_candidates
    pid_candidates=$(pgrep -f "processAPINotesDaemon" 2>/dev/null || echo "")
    
    if [[ -z "${pid_candidates}" ]]; then
        pid_candidates=$(pgrep -f "processAPINotes.sh" 2>/dev/null || echo "")
    fi
    
    if [[ -n "${pid_candidates}" ]]; then
        # Get the first PID (main process)
        daemon_pid=$(echo "${pid_candidates}" | head -1 | tr -d '[:space:]')
        
        if [[ -n "${daemon_pid}" ]] && [[ "${daemon_pid}" =~ ^[0-9]+$ ]]; then
            # Get process uptime
            local etime_output
            etime_output=$(ps -o etime= -p "${daemon_pid}" 2>/dev/null | tr -d ' ' || echo "")
            
            if [[ -n "${etime_output}" ]]; then
                # Parse elapsed time (format: [[DD-]HH:]MM:SS or MM:SS)
                local days=0 hours=0 minutes=0 seconds=0
                
                if [[ "${etime_output}" =~ ^([0-9]+)-([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
                    # Format: DD-HH:MM:SS
                    days="${BASH_REMATCH[1]}"
                    hours="${BASH_REMATCH[2]}"
                    minutes="${BASH_REMATCH[3]}"
                    seconds="${BASH_REMATCH[4]}"
                elif [[ "${etime_output}" =~ ^([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
                    # Format: HH:MM:SS
                    hours="${BASH_REMATCH[1]}"
                    minutes="${BASH_REMATCH[2]}"
                    seconds="${BASH_REMATCH[3]}"
                elif [[ "${etime_output}" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
                    # Format: MM:SS
                    minutes="${BASH_REMATCH[1]}"
                    seconds="${BASH_REMATCH[2]}"
                fi
                
                # Convert to seconds
                daemon_uptime_seconds=$((days * 86400 + hours * 3600 + minutes * 60 + seconds))
            fi
            
            log_info "${COMPONENT}: Daemon process found - PID: ${daemon_pid}, Uptime: ${daemon_uptime_seconds}s (${etime_output})"
        fi
    else
        log_debug "${COMPONENT}: Daemon process not found"
    fi
    
    # Try to get restart count from systemd (if available)
    # Ensure PATH includes systemctl location
    local saved_path_restarts="${PATH:-}"
    export PATH="/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin:${PATH:-}"
    
    local systemctl_cmd_restarts
    if command -v systemctl > /dev/null 2>&1; then
        systemctl_cmd_restarts="systemctl"
    elif [[ -x /usr/bin/systemctl ]]; then
        systemctl_cmd_restarts="/usr/bin/systemctl"
    elif [[ -x /bin/systemctl ]]; then
        systemctl_cmd_restarts="/bin/systemctl"
    fi
    
    if [[ -n "${systemctl_cmd_restarts}" ]]; then
        local restart_count_output
        restart_count_output=$("${systemctl_cmd_restarts}" show "${DAEMON_SERVICE_NAME}" -p NRestarts 2>/dev/null | cut -d= -f2 || echo "")
        if [[ -n "${restart_count_output}" ]] && [[ "${restart_count_output}" =~ ^[0-9]+$ ]]; then
            daemon_restarts=${restart_count_output}
        fi
    fi
    
    export PATH="${saved_path_restarts}"
    
    # Record metrics
    record_metric "${COMPONENT}" "daemon_pid" "${daemon_pid}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_uptime_seconds" "${daemon_uptime_seconds}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_restarts_count" "${daemon_restarts}" "component=ingestion"
    
    echo "${daemon_pid}"
}

##
# Check daemon lock file status
##
check_daemon_lock_file() {
    local lock_status=0
    
    if [[ -f "${DAEMON_LOCK_FILE}" ]]; then
        lock_status=1
        
        # Check lock file age
        local lock_age_seconds=0
        if command -v stat > /dev/null 2>&1; then
            local lock_mtime
            lock_mtime=$(stat -c %Y "${DAEMON_LOCK_FILE}" 2>/dev/null || echo "0")
            local current_time
            current_time=$(date +%s)
            lock_age_seconds=$((current_time - lock_mtime))
        fi
        
        log_debug "${COMPONENT}: Daemon lock file exists: ${DAEMON_LOCK_FILE} (age: ${lock_age_seconds}s)"
        record_metric "${COMPONENT}" "daemon_lock_age_seconds" "${lock_age_seconds}" "component=ingestion"
    else
        log_debug "${COMPONENT}: Daemon lock file not found: ${DAEMON_LOCK_FILE}"
    fi
    
    # Record metric
    record_metric "${COMPONENT}" "daemon_lock_status" "${lock_status}" "component=ingestion"
    
    echo "${lock_status}"
}

##
# Parse daemon logs for cycle metrics
##
parse_daemon_cycle_metrics() {
    local log_file="${DAEMON_LOG_FILE}"
    
    if [[ ! -f "${log_file}" ]]; then
        log_debug "${COMPONENT}: Daemon log file not found: ${log_file}"
        return 0
    fi
    
    # Parse logs for cycle completion messages
    # Format: "Cycle N completed successfully in X seconds"
    local cycle_completions
    cycle_completions=$(grep -E "Cycle [0-9]+ completed successfully in [0-9]+ seconds" "${log_file}" 2>/dev/null | tail -100 || echo "")
    
    if [[ -z "${cycle_completions}" ]]; then
        log_debug "${COMPONENT}: No cycle completion messages found in logs"
        return 0
    fi
    
    # Extract cycle numbers and durations
    local last_cycle_number=0
    local last_cycle_duration=0
    local total_cycles=0
    local total_duration=0
    local successful_cycles=0
    local failed_cycles=0
    local min_duration=999999
    local max_duration=0
    
    while IFS= read -r line; do
        # Extract cycle number and duration
        if [[ "${line}" =~ Cycle[[:space:]]+([0-9]+)[[:space:]]+completed[[:space:]]+successfully[[:space:]]+in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
            local cycle_num="${BASH_REMATCH[1]}"
            local cycle_dur="${BASH_REMATCH[2]}"
            
            last_cycle_number=${cycle_num}
            last_cycle_duration=${cycle_dur}
            total_cycles=$((total_cycles + 1))
            total_duration=$((total_duration + cycle_dur))
            successful_cycles=$((successful_cycles + 1))
            
            if [[ ${cycle_dur} -lt ${min_duration} ]]; then
                min_duration=${cycle_dur}
            fi
            if [[ ${cycle_dur} -gt ${max_duration} ]]; then
                max_duration=${cycle_dur}
            fi
        fi
    done <<< "${cycle_completions}"
    
    # Check for failed cycles
    local cycle_failures
    cycle_failures=$(grep -E "Cycle [0-9]+ failed|Cycle [0-9]+ error" "${log_file}" 2>/dev/null | tail -100 || echo "")
    if [[ -n "${cycle_failures}" ]]; then
        failed_cycles=$(echo "${cycle_failures}" | wc -l | tr -d '[:space:]')
        failed_cycles=$((failed_cycles + 0))
    fi
    
    # Calculate average duration
    local avg_duration=0
    if [[ ${total_cycles} -gt 0 ]]; then
        avg_duration=$((total_duration / total_cycles))
    fi
    
    # Calculate success rate
    local total_cycle_attempts=$((successful_cycles + failed_cycles))
    local success_rate=100
    if [[ ${total_cycle_attempts} -gt 0 ]]; then
        success_rate=$((successful_cycles * 100 / total_cycle_attempts))
    fi
    
    # Calculate cycles per hour (from last hour of logs)
    local cycles_per_hour=0
    local recent_cycles
    local hour_pattern
    hour_pattern=$(date -d '1 hour ago' '+%Y-%m-%d %H' 2>/dev/null || echo "")
    if [[ -n "${hour_pattern}" ]]; then
        recent_cycles=$(grep -E "Cycle [0-9]+ completed successfully" "${log_file}" 2>/dev/null | grep -c "${hour_pattern}" 2>/dev/null || echo "0")
    else
        recent_cycles=0
    fi
    recent_cycles=$(echo "${recent_cycles}" | tr -d '[:space:]' || echo "0")
    cycles_per_hour=$((recent_cycles + 0))
    
    # Record metrics
    record_metric "${COMPONENT}" "daemon_cycle_number" "${last_cycle_number}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycle_duration_seconds" "${last_cycle_duration}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycles_total" "${total_cycles}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycle_avg_duration_seconds" "${avg_duration}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycle_min_duration_seconds" "${min_duration}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycle_max_duration_seconds" "${max_duration}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycle_success_rate_percent" "${success_rate}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycles_per_hour" "${cycles_per_hour}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycles_successful_count" "${successful_cycles}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_cycles_failed_count" "${failed_cycles}" "component=ingestion"
    
    log_info "${COMPONENT}: Cycle metrics - Last: ${last_cycle_number}, Duration: ${last_cycle_duration}s, Avg: ${avg_duration}s, Success: ${success_rate}%, Cycles/hour: ${cycles_per_hour}"
    
    return 0
}

##
# Parse daemon logs for processing metrics
##
parse_daemon_processing_metrics() {
    local log_file="${DAEMON_LOG_FILE}"
    
    if [[ ! -f "${log_file}" ]]; then
        return 0
    fi
    
    # Parse logs for processing statistics
    # Look for patterns like "Processed X notes", "X new notes", "X updated notes", "X comments"
    local last_notes_processed=0
    local last_notes_new=0
    local last_notes_updated=0
    local last_comments_processed=0
    
    # Get last cycle processing stats (from most recent cycle completion)
    local last_cycle_line
    last_cycle_line=$(grep -E "Cycle [0-9]+ completed successfully" "${log_file}" 2>/dev/null | tail -1 || echo "")
    
    if [[ -n "${last_cycle_line}" ]]; then
        # Extract cycle number
        local cycle_num=0
        if [[ "${last_cycle_line}" =~ Cycle[[:space:]]+([0-9]+) ]]; then
            cycle_num="${BASH_REMATCH[1]}"
        fi
        
        # Look for processing stats around this cycle
        # Search backwards from the cycle completion line
        local cycle_context
        cycle_context=$(grep -B 50 "Cycle ${cycle_num} completed successfully" "${log_file}" 2>/dev/null | tail -50 || echo "")
        
        # Extract notes processed
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+notes[[:space:]]+processed ]]; then
            last_notes_processed="${BASH_REMATCH[1]}"
        elif [[ "${cycle_context}" =~ Processed[[:space:]]+([0-9]+)[[:space:]]+notes ]]; then
            last_notes_processed="${BASH_REMATCH[1]}"
        fi
        
        # Extract new notes
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+new[[:space:]]+notes ]]; then
            last_notes_new="${BASH_REMATCH[1]}"
        fi
        
        # Extract updated notes
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+updated[[:space:]]+notes ]]; then
            last_notes_updated="${BASH_REMATCH[1]}"
        fi
        
        # Extract comments processed
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+comments[[:space:]]+processed ]]; then
            last_comments_processed="${BASH_REMATCH[1]}"
        elif [[ "${cycle_context}" =~ Processed[[:space:]]+([0-9]+)[[:space:]]+comments ]]; then
            last_comments_processed="${BASH_REMATCH[1]}"
        fi
    fi
    
    # Calculate processing rate (notes per second) from last cycle
    local processing_rate=0
    local last_cycle_duration=0
    local duration_str
    duration_str=$(grep -E "Cycle [0-9]+ completed successfully in [0-9]+ seconds" "${log_file}" 2>/dev/null | tail -1 | sed -n 's/.*in \([0-9]*\) seconds.*/\1/p' || echo "0")
    
    # Ensure duration_str is numeric
    if [[ -n "${duration_str}" ]] && [[ "${duration_str}" =~ ^[0-9]+$ ]]; then
        last_cycle_duration=$((duration_str + 0))
    fi
    
    if [[ ${last_cycle_duration} -gt 0 ]] && [[ ${last_notes_processed} -gt 0 ]]; then
        processing_rate=$((last_notes_processed / last_cycle_duration))
    fi
    
    # Record metrics
    record_metric "${COMPONENT}" "daemon_notes_processed_per_cycle" "${last_notes_processed}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_notes_new_count" "${last_notes_new}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_notes_updated_count" "${last_notes_updated}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_comments_processed_per_cycle" "${last_comments_processed}" "component=ingestion"
    record_metric "${COMPONENT}" "daemon_processing_rate_notes_per_second" "${processing_rate}" "component=ingestion"
    
    log_info "${COMPONENT}: Processing metrics - Notes: ${last_notes_processed} (new: ${last_notes_new}, updated: ${last_notes_updated}), Comments: ${last_comments_processed}, Rate: ${processing_rate} notes/s"
    
    return 0
}

##
# Main function
##
main() {
    log_info "${COMPONENT}: Starting daemon metrics collection"
    
    # Load configuration
    if ! load_all_configs; then
        log_error "${COMPONENT}: Failed to load configuration"
        return 1
    fi
    
    # Check daemon service status
    check_daemon_service_status > /dev/null
    
    # Get daemon process info
    get_daemon_process_info > /dev/null
    
    # Check lock file
    check_daemon_lock_file > /dev/null
    
    # Parse cycle metrics
    parse_daemon_cycle_metrics
    
    # Parse processing metrics
    parse_daemon_processing_metrics
    
    log_info "${COMPONENT}: Daemon metrics collection completed"
    
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
