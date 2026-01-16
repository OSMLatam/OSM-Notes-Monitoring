#!/usr/bin/env bash
#
# Structured Logs Parser
# Parses daemon logs and extracts detailed structured metrics
#
# Version: 1.0.0
# Date: 2026-01-09
#

set -euo pipefail

##
# Parse structured logs and extract detailed metrics
# Usage: parse_structured_logs <log_file> [time_window_hours]
# Returns: Metrics via record_metric calls
##
parse_structured_logs() {
    local log_file="${1}"
    local time_window_hours="${2:-24}"
    
    if [[ ! -f "${log_file}" ]]; then
        log_debug "Structured log file not found: ${log_file}"
        return 1
    fi
    
    # Calculate time threshold
    local threshold_timestamp
    threshold_timestamp=$(date -d "${time_window_hours} hours ago" +%s 2>/dev/null || date -v-"${time_window_hours}"H +%s 2>/dev/null || echo "0")
    
    # Parse cycle metrics
    parse_cycle_metrics "${log_file}" "${threshold_timestamp}"
    
    # Parse processing metrics
    parse_processing_metrics "${log_file}" "${threshold_timestamp}"
    
    # Parse stage timing metrics
    parse_stage_timing_metrics "${log_file}" "${threshold_timestamp}"
    
    # Parse optimization metrics
    parse_optimization_metrics "${log_file}" "${threshold_timestamp}"
    
    return 0
}

##
# Parse cycle completion metrics
##
parse_cycle_metrics() {
    local log_file="${1}"
    local threshold_timestamp="${2}"
    
    # Get recent cycle completions
    local cycle_completions
    cycle_completions=$(grep -E "Cycle [0-9]+ completed successfully in [0-9]+ seconds" "${log_file}" 2>/dev/null | tail -100 || echo "")
    
    if [[ -z "${cycle_completions}" ]]; then
        return 0
    fi
    
    local last_cycle_number=0
    local last_cycle_duration=0
    local total_cycles=0
    local total_duration=0
    local successful_cycles=0
    local failed_cycles=0
    local min_duration=999999
    local max_duration=0
    local cycle_timestamps=()
    
    while IFS= read -r line; do
        # Extract timestamp
        local log_timestamp=0
        if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
        fi
        
        # Skip if too old
        if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
            continue
        fi
        
        # Extract cycle number and duration
        if [[ "${line}" =~ Cycle[[:space:]]+([0-9]+)[[:space:]]+completed[[:space:]]+successfully[[:space:]]+in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
            local cycle_num="${BASH_REMATCH[1]}"
            local cycle_dur="${BASH_REMATCH[2]}"
            
            last_cycle_number=${cycle_num}
            last_cycle_duration=${cycle_dur}
            total_cycles=$((total_cycles + 1))
            total_duration=$((total_duration + cycle_dur))
            successful_cycles=$((successful_cycles + 1))
            cycle_timestamps+=("${log_timestamp}")
            
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
        while IFS= read -r line; do
            local log_timestamp=0
            if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
            fi
            if [[ ${log_timestamp} -ge ${threshold_timestamp} ]] || [[ ${log_timestamp} -eq 0 ]]; then
                failed_cycles=$((failed_cycles + 1))
            fi
        done <<< "${cycle_failures}"
    fi
    
    # Calculate metrics
    local avg_duration=0
    if [[ ${total_cycles} -gt 0 ]]; then
        avg_duration=$((total_duration / total_cycles))
    fi
    
    local total_cycle_attempts=$((successful_cycles + failed_cycles))
    local success_rate=100
    if [[ ${total_cycle_attempts} -gt 0 ]]; then
        success_rate=$((successful_cycles * 100 / total_cycle_attempts))
    fi
    
    # Calculate cycles per hour (from timestamps)
    local cycles_per_hour=0
    if [[ ${#cycle_timestamps[@]} -gt 0 ]]; then
        local first_timestamp="${cycle_timestamps[0]}"
        local last_timestamp="${cycle_timestamps[-1]}"
        if [[ ${last_timestamp} -gt ${first_timestamp} ]]; then
            local time_span_hours
            time_span_hours=$(( (last_timestamp - first_timestamp) / 3600 + 1 ))
            if [[ ${time_span_hours} -gt 0 ]]; then
                cycles_per_hour=$(( total_cycles / time_span_hours ))
            fi
        fi
    fi
    
    # Record metrics
    record_metric "INGESTION" "log_cycle_total_duration_seconds" "${last_cycle_duration}" "component=ingestion"
    record_metric "INGESTION" "log_cycle_number" "${last_cycle_number}" "component=ingestion"
    record_metric "INGESTION" "log_cycles_frequency_per_hour" "${cycles_per_hour}" "component=ingestion"
    record_metric "INGESTION" "log_cycle_success_rate_percent" "${success_rate}" "component=ingestion"
    record_metric "INGESTION" "log_cycle_avg_duration_seconds" "${avg_duration}" "component=ingestion"
    record_metric "INGESTION" "log_cycle_min_duration_seconds" "${min_duration}" "component=ingestion"
    record_metric "INGESTION" "log_cycle_max_duration_seconds" "${max_duration}" "component=ingestion"
    
    return 0
}

##
# Parse processing metrics (notes, comments)
##
parse_processing_metrics() {
    local log_file="${1}"
    local threshold_timestamp="${2}"
    
    # Get last cycle processing stats
    local last_cycle_line
    last_cycle_line=$(grep -E "Cycle [0-9]+ completed successfully" "${log_file}" 2>/dev/null | tail -1 || echo "")
    
    if [[ -z "${last_cycle_line}" ]]; then
        return 0
    fi
    
    # Extract cycle number
    local cycle_num=0
    if [[ "${last_cycle_line}" =~ Cycle[[:space:]]+([0-9]+) ]]; then
        cycle_num="${BASH_REMATCH[1]}"
    fi
    
    # Get context around last cycle
    local cycle_context
    cycle_context=$(grep -B 100 "Cycle ${cycle_num} completed successfully" "${log_file}" 2>/dev/null | tail -100 || echo "")
    
    # Extract notes processed (try old format first)
    local notes_processed=0
    if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+notes[[:space:]]+processed ]]; then
        notes_processed="${BASH_REMATCH[1]}"
    elif [[ "${cycle_context}" =~ Processed[[:space:]]+([0-9]+)[[:space:]]+notes ]]; then
        notes_processed="${BASH_REMATCH[1]}"
    fi
    
    # Extract new notes (try old format first)
    local notes_new=0
    if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+new[[:space:]]+notes ]]; then
        notes_new="${BASH_REMATCH[1]}"
    fi
    
    # Extract updated notes (try old format first)
    local notes_updated=0
    if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+updated[[:space:]]+notes ]]; then
        notes_updated="${BASH_REMATCH[1]}"
    fi
    
    # Extract comments processed (try old format first)
    local comments_processed=0
    if [[ "${cycle_context}" =~ ([0-9]+)[[:space:]]+comments[[:space:]]+processed ]]; then
        comments_processed="${BASH_REMATCH[1]}"
    elif [[ "${cycle_context}" =~ Processed[[:space:]]+([0-9]+)[[:space:]]+comments ]]; then
        comments_processed="${BASH_REMATCH[1]}"
    fi
    
    # Try new format: "current notes - before" and "current notes - after"
    # Format: "2026-01-15 23:08:08.235559+00 | 4985251 | current notes - before"
    local notes_before=0
    local notes_after=0
    
    while IFS= read -r line; do
        # Match format: timestamp | NUMBER | current notes - before/after
        if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+notes[[:space:]]+-[[:space:]]+before ]]; then
            notes_before="${BASH_REMATCH[1]}"
        elif [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+notes[[:space:]]+-[[:space:]]+after ]]; then
            notes_after="${BASH_REMATCH[1]}"
        fi
        # Also look for "Uploaded new notes" messages which are more accurate
        # Format: "2026-01-16 02:37:45.760507+00 |   1 | Uploaded new notes"
        if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+Uploaded[[:space:]]+new[[:space:]]+notes ]]; then
            local uploaded_notes="${BASH_REMATCH[1]}"
            if [[ ${uploaded_notes} -gt 0 ]]; then
                notes_new=${uploaded_notes}
                # If we haven't set processed count yet, use this as processed
                if [[ ${notes_processed} -eq 0 ]]; then
                    notes_processed=${uploaded_notes}
                fi
            fi
        fi
    done <<< "${cycle_context}"
    
    # Calculate notes processed from before/after counts (fallback if no "Uploaded new" found)
    if [[ ${notes_processed} -eq 0 ]] && [[ ${notes_before} -gt 0 ]] && [[ ${notes_after} -ge ${notes_before} ]]; then
        local notes_diff=$((notes_after - notes_before))
        # Use the difference as notes processed if we haven't found it yet
        notes_processed=${notes_diff}
        # If difference is positive, assume they are new notes
        if [[ ${notes_diff} -gt 0 ]] && [[ ${notes_new} -eq 0 ]]; then
            notes_new=${notes_diff}
        fi
    fi
    
    # Extract comments count before and after
    local comments_before=0
    local comments_after=0
    
    while IFS= read -r line; do
        # Match format: "| NUMBER | current comments - before" or "| NUMBER | current comments - after"
        if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+comments[[:space:]]+-[[:space:]]+before ]]; then
            comments_before="${BASH_REMATCH[1]}"
        elif [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+current[[:space:]]+comments[[:space:]]+-[[:space:]]+after ]]; then
            comments_after="${BASH_REMATCH[1]}"
        fi
        # Also look for "Uploaded new comments" messages which are more accurate
        # Format: "2026-01-16 02:37:45.763429+00 |   2 | Uploaded new comments"
        if [[ "${line}" =~ \|[[:space:]]+([0-9]+)[[:space:]]+\|[[:space:]]+Uploaded[[:space:]]+new[[:space:]]+comments ]]; then
            local uploaded_comments="${BASH_REMATCH[1]}"
            if [[ ${uploaded_comments} -gt 0 ]]; then
                comments_processed=${uploaded_comments}
            fi
        fi
    done <<< "${cycle_context}"
    
    # Calculate comments processed from before/after counts (fallback if no "Uploaded new" found)
    if [[ ${comments_processed} -eq 0 ]] && [[ ${comments_before} -gt 0 ]] && [[ ${comments_after} -ge ${comments_before} ]]; then
        local comments_diff=$((comments_after - comments_before))
        # Use the difference as comments processed if we haven't found it yet
        comments_processed=${comments_diff}
    fi
    
    # Calculate processing rate
    local processing_rate=0
    local cycle_duration=0
    if [[ "${last_cycle_line}" =~ in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
        cycle_duration="${BASH_REMATCH[1]}"
        if [[ ${cycle_duration} -gt 0 ]] && [[ ${notes_processed} -gt 0 ]]; then
            processing_rate=$((notes_processed / cycle_duration))
        fi
    fi
    
    # Record metrics
    record_metric "INGESTION" "log_notes_processed_per_cycle" "${notes_processed}" "component=ingestion"
    record_metric "INGESTION" "log_notes_new_count" "${notes_new}" "component=ingestion"
    record_metric "INGESTION" "log_notes_updated_count" "${notes_updated}" "component=ingestion"
    record_metric "INGESTION" "log_comments_processed_per_cycle" "${comments_processed}" "component=ingestion"
    record_metric "INGESTION" "log_processing_rate_notes_per_second" "${processing_rate}" "component=ingestion"
    
    return 0
}

##
# Parse stage timing metrics from [TIMING] logs
##
parse_stage_timing_metrics() {
    local log_file="${1}"
    local threshold_timestamp="${2}"
    
    # Try to get [TIMING] log entries first (old format)
    local timing_logs
    timing_logs=$(grep "\[TIMING\]" "${log_file}" 2>/dev/null | tail -200 || echo "")
    
    # Parse stage durations
    declare -A stage_durations
    declare -A stage_counts
    local slowest_stage=""
    local slowest_duration=0
    
    # Parse old format: [TIMING] Stage: <stage_name> - Duration: <duration> seconds
    if [[ -n "${timing_logs}" ]]; then
        while IFS= read -r line; do
            # Extract timestamp
            local log_timestamp=0
            if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
            fi
            
            # Skip if too old
            if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
                continue
            fi
            
            # Extract stage name and duration
            if [[ "${line}" =~ Stage:[[:space:]]+([^-]+)[[:space:]]+-[[:space:]]+Duration:[[:space:]]+([0-9.]+)[[:space:]]+seconds ]]; then
                local stage_name="${BASH_REMATCH[1]}"
                stage_name=$(echo "${stage_name}" | xargs)  # Trim whitespace
                local duration="${BASH_REMATCH[2]}"
                
                # Convert to integer (seconds)
                local duration_int
                duration_int=$(echo "${duration}" | awk '{printf "%.0f", $1}')
                
                # Accumulate durations
                if [[ -n "${stage_durations[${stage_name}]:-}" ]]; then
                    stage_durations["${stage_name}"]=$((stage_durations["${stage_name}"] + duration_int))
                else
                    stage_durations["${stage_name}"]=${duration_int}
                fi
                
                # Count occurrences
                if [[ -n "${stage_counts[${stage_name}]:-}" ]]; then
                    stage_counts["${stage_name}"]=$((stage_counts["${stage_name}"] + 1))
                else
                    stage_counts["${stage_name}"]=1
                fi
                
                # Track slowest stage
                if [[ ${duration_int} -gt ${slowest_duration} ]]; then
                    slowest_duration=${duration_int}
                    slowest_stage="${stage_name}"
                fi
            fi
        done <<< "${timing_logs}"
    fi
    
    # Parse new format: FINISHED FUNCTION_NAME followed by Took: Xh:Ym:Zs
    # Use awk to pair FINISHED lines with their Took lines
    local finished_took_pairs
    finished_took_pairs=$(tail -5000 "${log_file}" 2>/dev/null | awk '
        /FINISHED/ {finished=$0; getline; if (/Took:/) print finished " | " $0}
    ' | tail -200 || echo "")
    
    if [[ -n "${finished_took_pairs}" ]]; then
        while IFS= read -r pair; do
            # Split pair into finished line and took line
            local finished_line="${pair%% | *}"
            local took_line="${pair#* | }"
            
            # Extract timestamp from finished line
            local log_timestamp=0
            if [[ "${finished_line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
            fi
            
            # Skip if too old
            if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
                continue
            fi
            
            # Extract stage name from FINISHED line
            # Format: "timestamp - path:function:line - |-- FINISHED __FUNCTION_NAME IN PATH"
            local stage_name=""
            if [[ "${finished_line}" =~ FINISHED[[:space:]]+__?([A-Z_]+)[[:space:]]+IN ]]; then
                stage_name="${BASH_REMATCH[1]}"
                # Clean up stage name (remove common prefixes/suffixes, convert underscores to spaces)
                stage_name=$(echo "${stage_name}" | sed 's/^__//;s/__$//' | tr '_' ' ' | xargs)
            fi
            
            # Extract duration from Took line
            # Format: "|-- Took: Xh:Ym:Zs"
            local duration_int=0
            if [[ "${took_line}" =~ Took:[[:space:]]+([0-9]+)h:([0-9]+)m:([0-9]+)s ]]; then
                local hours="${BASH_REMATCH[1]}"
                local minutes="${BASH_REMATCH[2]}"
                local seconds="${BASH_REMATCH[3]}"
                duration_int=$((hours * 3600 + minutes * 60 + seconds))
            fi
            
            if [[ -n "${stage_name}" ]] && [[ ${duration_int} -ge 0 ]]; then
                # Accumulate durations
                if [[ -n "${stage_durations[${stage_name}]:-}" ]]; then
                    stage_durations["${stage_name}"]=$((stage_durations["${stage_name}"] + duration_int))
                else
                    stage_durations["${stage_name}"]=${duration_int}
                fi
                
                # Count occurrences
                if [[ -n "${stage_counts[${stage_name}]:-}" ]]; then
                    stage_counts["${stage_name}"]=$((stage_counts["${stage_name}"] + 1))
                else
                    stage_counts["${stage_name}"]=1
                fi
                
                # Track slowest stage (only if duration > 0)
                if [[ ${duration_int} -gt ${slowest_duration} ]]; then
                    slowest_duration=${duration_int}
                    slowest_stage="${stage_name}"
                fi
            fi
        done <<< "${finished_took_pairs}"
    fi
    
    # Record metrics for each stage
    for stage_name in "${!stage_durations[@]}"; do
        local total_duration="${stage_durations[${stage_name}]}"
        local count="${stage_counts[${stage_name}]}"
        local avg_duration=0
        if [[ ${count} -gt 0 ]]; then
            avg_duration=$((total_duration / count))
        fi
        
        # Record average duration per stage
        record_metric "INGESTION" "log_stage_duration_seconds" "${avg_duration}" "component=ingestion,stage=${stage_name}"
    done
    
    # Record slowest stage
    if [[ -n "${slowest_stage}" ]] && [[ ${slowest_duration} -gt 0 ]]; then
        record_metric "INGESTION" "log_slowest_stage_duration_seconds" "${slowest_duration}" "component=ingestion,stage=${slowest_stage}"
    fi
    
    return 0
}

##
# Parse optimization metrics
##
parse_optimization_metrics() {
    local log_file="${1}"
    local threshold_timestamp="${2}"
    
    # Get optimization-related log entries
    local analyze_cache_hits=0
    local analyze_cache_misses=0
    local integrity_optimizations=0
    local sequence_syncs=0
    local optimization_time_saved=0
    
    # Parse ANALYZE cache effectiveness
    # Note: ANALYZE commands in logs don't explicitly show cache hit/miss
    # We count ANALYZE operations as potential cache operations
    # If ANALYZE appears frequently, it suggests cache is being used
    local analyze_logs
    analyze_logs=$(tail -5000 "${log_file}" 2>/dev/null | grep -i "ANALYZE" | tail -100 || echo "")
    
    if [[ -n "${analyze_logs}" ]]; then
        local analyze_count=0
        while IFS= read -r line; do
            local log_timestamp=0
            if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
            fi
            
            if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
                continue
            fi
            
            # Count ANALYZE operations (these are likely cached)
            if [[ "${line}" =~ ANALYZE ]]; then
                analyze_count=$((analyze_count + 1))
                # Assume ANALYZE operations are cache hits (PostgreSQL caches statistics)
                analyze_cache_hits=$((analyze_cache_hits + 1))
            fi
            
            # Look for explicit cache hit/miss messages (if they exist)
            if [[ "${line}" =~ cache[[:space:]]+hit\|hit[[:space:]]+cache ]]; then
                analyze_cache_hits=$((analyze_cache_hits + 1))
            elif [[ "${line}" =~ cache[[:space:]]+miss\|miss[[:space:]]+cache ]]; then
                analyze_cache_misses=$((analyze_cache_misses + 1))
            fi
        done <<< "${analyze_logs}"
    fi
    
    # Parse integrity optimization logs
    # Look for SKIPPED messages which indicate optimizations (validation skipped)
    local integrity_logs
    integrity_logs=$(tail -5000 "${log_file}" 2>/dev/null | grep -iE "SKIPPED|skip|optimized|integrity" | tail -100 || echo "")
    
    if [[ -n "${integrity_logs}" ]]; then
        while IFS= read -r line; do
            local log_timestamp=0
            if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
            fi
            
            if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
                continue
            fi
            
            # Count SKIPPED operations as integrity optimizations
            if [[ "${line}" =~ SKIPPED ]]; then
                integrity_optimizations=$((integrity_optimizations + 1))
            fi
            
            # Look for other optimization indicators
            if [[ "${line}" =~ optimized\|saved ]]; then
                integrity_optimizations=$((integrity_optimizations + 1))
                
                # Try to extract time saved
                if [[ "${line}" =~ saved[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
                    local saved="${BASH_REMATCH[1]}"
                    optimization_time_saved=$((optimization_time_saved + saved))
                fi
            fi
        done <<< "${integrity_logs}"
    fi
    
    # Parse sequence sync logs
    local sequence_logs
    sequence_logs=$(grep -i "sequence.*sync\|sync.*sequence" "${log_file}" 2>/dev/null | tail -100 || echo "")
    
    if [[ -n "${sequence_logs}" ]]; then
        while IFS= read -r line; do
            local log_timestamp=0
            if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
            fi
            
            if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
                continue
            fi
            
            if [[ "${line}" =~ sync\|synced ]]; then
                sequence_syncs=$((sequence_syncs + 1))
            fi
        done <<< "${sequence_logs}"
    fi
    
    # Calculate effectiveness metrics
    local analyze_cache_effectiveness=0
    local total_analyze_ops=$((analyze_cache_hits + analyze_cache_misses))
    if [[ ${total_analyze_ops} -gt 0 ]]; then
        analyze_cache_effectiveness=$((analyze_cache_hits * 100 / total_analyze_ops))
    fi
    
    # Record metrics
    record_metric "INGESTION" "log_analyze_cache_hits" "${analyze_cache_hits}" "component=ingestion"
    record_metric "INGESTION" "log_analyze_cache_misses" "${analyze_cache_misses}" "component=ingestion"
    record_metric "INGESTION" "log_analyze_cache_effectiveness" "${analyze_cache_effectiveness}" "component=ingestion"
    record_metric "INGESTION" "log_integrity_optimization_count" "${integrity_optimizations}" "component=ingestion"
    record_metric "INGESTION" "log_sequence_sync_count" "${sequence_syncs}" "component=ingestion"
    record_metric "INGESTION" "log_optimization_time_saved_seconds" "${optimization_time_saved}" "component=ingestion"
    
    return 0
}

# Export functions for testing
export -f parse_structured_logs parse_cycle_metrics parse_processing_metrics
export -f parse_stage_timing_metrics parse_optimization_metrics

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Source required libraries
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
    
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"
    
    # Set default log file
    DAEMON_LOG_FILE="${DAEMON_LOG_FILE:-/var/log/osm-notes-ingestion/daemon/processAPINotesDaemon.log}"
    
    # Initialize logging
    init_logging "${LOG_DIR:-/tmp}/parseStructuredLogs.log" "parseStructuredLogs"
    
    # Parse logs
    parse_structured_logs "${DAEMON_LOG_FILE}" "${1:-24}"
fi
