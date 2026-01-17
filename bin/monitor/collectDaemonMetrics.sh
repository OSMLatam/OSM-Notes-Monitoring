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
# Parse timestamp from log line to epoch seconds
# Handles multiple timestamp formats:
# - YYYY-MM-DD HH:MM:SS
# - YYYY-MM-DD HH:MM:SS.microseconds
# - YYYY-MM-DD HH:MM:SS+timezone
# - YYYY-MM-DD HH:MM:SS.microseconds+timezone
# - YYYY-MM-DDTHH:MM:SS (ISO format)
##
parse_log_timestamp() {
    local log_line="${1:-}"
    local timestamp_epoch=0
    
    if [[ -z "${log_line}" ]]; then
        echo "0"
        return 0
    fi
    
    # Try multiple timestamp formats
    # Format 1: YYYY-MM-DD HH:MM:SS (basic format)
    if [[ "${log_line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
        local log_date="${BASH_REMATCH[1]}"
        local log_time="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
        local log_timestamp="${log_date} ${log_time}"
        timestamp_epoch=$(date -d "${log_timestamp}" +%s 2>/dev/null || echo "0")
        if [[ ${timestamp_epoch} -gt 0 ]]; then
            echo "${timestamp_epoch}"
            return 0
        fi
    fi
    
    # Format 2: YYYY-MM-DD HH:MM:SS.microseconds (with microseconds)
    if [[ "${log_line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2})\.[0-9]+ ]]; then
        local log_date="${BASH_REMATCH[1]}"
        local log_time="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
        local log_timestamp="${log_date} ${log_time}"
        timestamp_epoch=$(date -d "${log_timestamp}" +%s 2>/dev/null || echo "0")
        if [[ ${timestamp_epoch} -gt 0 ]]; then
            echo "${timestamp_epoch}"
            return 0
        fi
    fi
    
    # Format 3: YYYY-MM-DDTHH:MM:SS (ISO format)
    if [[ "${log_line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
        local log_date="${BASH_REMATCH[1]}"
        local log_time="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
        local log_timestamp="${log_date} ${log_time}"
        timestamp_epoch=$(date -d "${log_timestamp}" +%s 2>/dev/null || echo "0")
        if [[ ${timestamp_epoch} -gt 0 ]]; then
            echo "${timestamp_epoch}"
            return 0
        fi
    fi
    
    # Format 4: Try to extract any date-time pattern and let date command handle it
    # This is a fallback that tries to parse the first date-time-like pattern
    # Handles formats like: YYYY-MM-DD HH:MM:SS+timezone or YYYY-MM-DD HH:MM:SS-timezone
    if [[ "${log_line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[^[:space:]]*) ]]; then
        local extracted_timestamp="${BASH_REMATCH[1]}"
        # Try parsing with timezone first (date command can handle +HH:MM or -HH:MM)
        timestamp_epoch=$(date -d "${extracted_timestamp}" +%s 2>/dev/null || echo "0")
        if [[ ${timestamp_epoch} -gt 0 ]]; then
            echo "${timestamp_epoch}"
            return 0
        fi
        # If that failed, try removing timezone info
        # Remove timezone offset (format: +HH:MM or -HH:MM at the end)
        if [[ "${extracted_timestamp}" =~ ^(.+)[+-][0-9]{2}:[0-9]{2}$ ]]; then
            extracted_timestamp="${BASH_REMATCH[1]}"
            timestamp_epoch=$(date -d "${extracted_timestamp}" +%s 2>/dev/null || echo "0")
            if [[ ${timestamp_epoch} -gt 0 ]]; then
                echo "${timestamp_epoch}"
                return 0
            fi
        fi
    fi
    
    # If all formats failed, return 0
    echo "0"
    return 0
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
    
    # Calculate cycles per hour (from last 60 minutes of logs, not the previous complete hour)
    # This fixes the issue where cycles show 0 during the first hour of the day (00:00-00:59)
    # because the old logic was looking for the previous complete hour (23:00-23:59 of previous day)
    local cycles_per_hour=0
    local recent_cycles=0
    
    # Get threshold timestamp (60 minutes ago) in epoch seconds for accurate comparison
    local threshold_epoch
    threshold_epoch=$(date -d '60 minutes ago' +%s 2>/dev/null || echo "0")
    
    if [[ ${threshold_epoch} -gt 0 ]]; then
        # Count cycles completed in the last 60 minutes by comparing timestamps
        # Increased buffer to 500 lines to ensure we capture all cycles even with high log volume
        # This handles cases where there are many log lines between cycle completions
        local recent_cycle_lines
        recent_cycle_lines=$(tail -500 "${log_file}" 2>/dev/null | grep -E "Cycle [0-9]+ completed successfully" || echo "")
        
        if [[ -n "${recent_cycle_lines}" ]]; then
            local parsed_count=0
            local valid_count=0
            while IFS= read -r line; do
                # Extract timestamp from log line using robust parsing function
                local log_epoch
                log_epoch=$(parse_log_timestamp "${line}")
                
                if [[ ${log_epoch} -gt 0 ]]; then
                    parsed_count=$((parsed_count + 1))
                    
                    # If log timestamp is >= threshold (within last 60 minutes), count it
                    if [[ ${log_epoch} -ge ${threshold_epoch} ]]; then
                        recent_cycles=$((recent_cycles + 1))
                        valid_count=$((valid_count + 1))
                    fi
                fi
            done <<< "${recent_cycle_lines}"
            
            # If we parsed lines but found no valid cycles, log debug info
            if [[ ${parsed_count} -gt 0 ]] && [[ ${valid_count} -eq 0 ]]; then
                log_debug "${COMPONENT}: Found ${parsed_count} cycle lines but none within last 60 minutes (threshold: ${threshold_epoch})"
            elif [[ ${parsed_count} -eq 0 ]] && [[ -n "${recent_cycle_lines}" ]]; then
                # Log if we found cycle lines but couldn't parse timestamps
                log_debug "${COMPONENT}: Found cycle lines but failed to parse timestamps (first line: $(echo "${recent_cycle_lines}" | head -1 | cut -c1-50))"
            fi
        fi
    fi
    
    # Fallback: if date command failed or no cycles found, use previous hour pattern
    # Only use fallback if we truly found zero cycles (not just parsing issues)
    if [[ ${recent_cycles} -eq 0 ]] && [[ ${threshold_epoch} -eq 0 ]]; then
        log_debug "${COMPONENT}: Using fallback method for cycles_per_hour calculation"
        local hour_pattern
        hour_pattern=$(date -d '1 hour ago' '+%Y-%m-%d %H' 2>/dev/null || echo "")
        if [[ -n "${hour_pattern}" ]]; then
            recent_cycles=$(grep -E "Cycle [0-9]+ completed successfully" "${log_file}" 2>/dev/null | grep -c "${hour_pattern}" 2>/dev/null || echo "0")
            recent_cycles=$(echo "${recent_cycles}" | tr -d '[:space:]' || echo "0")
            recent_cycles=$((recent_cycles + 0))
        fi
    fi
    
    # Ensure cycles_per_hour is set correctly
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
        # Extract cycle number and timestamp
        local cycle_num=0
        if [[ "${last_cycle_line}" =~ Cycle[[:space:]]+([0-9]+) ]]; then
            cycle_num="${BASH_REMATCH[1]}"
        fi
        # Extract timestamp from cycle completion line using robust parsing
        local cycle_timestamp_epoch=0
        cycle_timestamp_epoch=$(parse_log_timestamp "${last_cycle_line}")
        
        # Look for processing stats around this cycle
        # Instead of searching a fixed number of lines back, find the most recent
        # "Uploaded new notes/comments" messages that occurred BEFORE this cycle completed
        # This is more robust as the distance can vary significantly
        
        # First, try to find messages in a larger context (300 lines)
        local cycle_context
        cycle_context=$(grep -B 300 "Cycle ${cycle_num} completed successfully" "${log_file}" 2>/dev/null | tail -300 || echo "")
        
        # If no context found with grep -B, try alternative: find all "Uploaded new" messages
        # that occurred before the cycle timestamp
        if [[ -z "${cycle_context}" ]] || [[ "${cycle_context}" =~ ^[[:space:]]*$ ]]; then
            
            # Get recent "Uploaded new" messages from tail of log
            if [[ ${cycle_timestamp_epoch} -gt 0 ]]; then
                local recent_uploaded_messages
                recent_uploaded_messages=$(tail -500 "${log_file}" 2>/dev/null | grep -E "Uploaded new (notes|comments)" || echo "")
                
                # Filter messages that occurred before cycle completion
                if [[ -n "${recent_uploaded_messages}" ]]; then
                    while IFS= read -r line; do
                        local msg_timestamp_epoch
                        msg_timestamp_epoch=$(parse_log_timestamp "${line}")
                        if [[ ${msg_timestamp_epoch} -lt ${cycle_timestamp_epoch} ]] && [[ ${msg_timestamp_epoch} -gt 0 ]]; then
                            cycle_context="${cycle_context}${line}"$'\n'
                        fi
                    done <<< "${recent_uploaded_messages}"
                fi
            fi
        fi
        
        # Try old format first: "Processed X notes", "X new notes", etc.
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+notes[[:space:]]+processed ]]; then
            last_notes_processed="${BASH_REMATCH[1]}"
        elif [[ "${cycle_context}" =~ Processed[[:space:]]+([0-9]+)[[:space:]]+notes ]]; then
            last_notes_processed="${BASH_REMATCH[1]}"
        fi
        
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+new[[:space:]]+notes ]]; then
            last_notes_new="${BASH_REMATCH[1]}"
        fi
        
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+updated[[:space:]]+notes ]]; then
            last_notes_updated="${BASH_REMATCH[1]}"
        fi
        
        if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+comments[[:space:]]+processed ]]; then
            last_comments_processed="${BASH_REMATCH[1]}"
        elif [[ "${cycle_context}" =~ Processed[[:space:]]+([0-9]+)[[:space:]]+comments ]]; then
            last_comments_processed="${BASH_REMATCH[1]}"
        fi
        
        # Try new format: "current notes - before" and "current notes - after"
        # Format: "2026-01-15 23:08:08.235559+00 | 4985251 | current notes - before"
        # Extract notes count before and after
        local notes_before=0
        local notes_after=0
        
        # Look for lines with "current notes - before" or "current notes - after"
        # Format: "2026-01-16 02:37:45.992228+00 | 4985317 | current notes - before"
        while IFS= read -r line; do
            # Match format: timestamp | NUMBER | current notes - before/after
            # Pattern: any chars, pipe, spaces, number, spaces, pipe, spaces, "current notes - before/after"
            if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+notes[[:space:]]+-[[:space:]]+before ]]; then
                notes_before="${BASH_REMATCH[1]}"
            elif [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+notes[[:space:]]+-[[:space:]]+after ]]; then
                notes_after="${BASH_REMATCH[1]}"
            fi
            # Also look for "Uploaded new notes" messages which are more accurate
            # Format: "2026-01-16 02:37:45.760507+00 |   1 | Uploaded new notes"
            # Note: The number may have leading spaces, so we need to handle that
            if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+Uploaded[[:space:]]+new[[:space:]]+notes ]]; then
                local uploaded_notes="${BASH_REMATCH[1]}"
                uploaded_notes=$((uploaded_notes + 0))  # Convert to integer, removing leading spaces
                if [[ ${uploaded_notes} -gt 0 ]]; then
                    # Accumulate notes (there might be multiple "Uploaded new notes" messages in one cycle)
                    last_notes_new=$((last_notes_new + uploaded_notes))
                    # If we haven't set processed count yet, use this as processed
                    if [[ ${last_notes_processed} -eq 0 ]]; then
                        last_notes_processed=${uploaded_notes}
                    else
                        # Accumulate processed count too
                        last_notes_processed=$((last_notes_processed + uploaded_notes))
                    fi
                fi
            fi
        done <<< "${cycle_context}"
        
        # Calculate notes processed from before/after counts (fallback if no "Uploaded new" found)
        if [[ ${last_notes_processed} -eq 0 ]] && [[ ${notes_before} -gt 0 ]] && [[ ${notes_after} -ge ${notes_before} ]]; then
            local notes_diff=$((notes_after - notes_before))
            # Use the difference as notes processed (can be positive or zero)
            last_notes_processed=${notes_diff}
            # If difference is positive, assume they are new notes
            if [[ ${notes_diff} -gt 0 ]] && [[ ${last_notes_new} -eq 0 ]]; then
                last_notes_new=${notes_diff}
            fi
        fi
        
        # Extract comments count before and after
        local comments_before=0
        local comments_after=0
        
        # Look for lines with "current comments - before" or "current comments - after"
        # Format: "2026-01-16 02:37:47.485519+00 | 11067205 | current comments - before"
        while IFS= read -r line; do
            # Match format: timestamp | NUMBER | current comments - before/after
            if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+comments[[:space:]]+-[[:space:]]+before ]]; then
                comments_before="${BASH_REMATCH[1]}"
            elif [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+comments[[:space:]]+-[[:space:]]+after ]]; then
                comments_after="${BASH_REMATCH[1]}"
            fi
            # Also look for "Uploaded new comments" messages which are more accurate
            # Format: "2026-01-16 02:37:45.763429+00 |   2 | Uploaded new comments"
            # Note: The number may have leading spaces, so we need to handle that
            if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+Uploaded[[:space:]]+new[[:space:]]+comments ]]; then
                local uploaded_comments="${BASH_REMATCH[1]}"
                uploaded_comments=$((uploaded_comments + 0))  # Convert to integer, removing leading spaces
                if [[ ${uploaded_comments} -gt 0 ]]; then
                    # Accumulate comments (there might be multiple "Uploaded new comments" messages in one cycle)
                    last_comments_processed=$((last_comments_processed + uploaded_comments))
                fi
            fi
        done <<< "${cycle_context}"
        
        # Calculate comments processed from before/after counts (fallback if no "Uploaded new" found)
        if [[ ${last_comments_processed} -eq 0 ]] && [[ ${comments_before} -gt 0 ]] && [[ ${comments_after} -ge ${comments_before} ]]; then
            local comments_diff=$((comments_after - comments_before))
            # Use the difference as comments processed (can be positive or zero)
            last_comments_processed=${comments_diff}
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
    
    # Ensure Notes Total is the sum of New + Updated (even if Updated is 0)
    # This ensures consistency: Total = New + Updated
    if [[ ${last_notes_processed} -eq 0 ]] && [[ ${last_notes_new} -gt 0 ]]; then
        # If processed is 0 but we have new notes, set processed to new (since updated is 0)
        last_notes_processed=${last_notes_new}
    elif [[ ${last_notes_processed} -gt 0 ]]; then
        # If we have processed count, ensure it equals new + updated
        local calculated_total=$((last_notes_new + last_notes_updated))
        if [[ ${calculated_total} -gt 0 ]] && [[ ${calculated_total} -ne ${last_notes_processed} ]]; then
            # Use calculated total if it's different and non-zero
            last_notes_processed=${calculated_total}
        fi
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
