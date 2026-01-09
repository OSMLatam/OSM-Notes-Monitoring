#!/usr/bin/env bash
#
# API Logs Parser
# Parses HTTP request logs and extracts API metrics
#
# Version: 1.0.0
# Date: 2026-01-09
#

set -euo pipefail

##
# Parse API logs and extract metrics
# Usage: parse_api_logs <log_file> [time_window_minutes]
# Returns: JSON-like output with metrics
##
parse_api_logs() {
    local log_file="${1}"
    local time_window_minutes="${2:-60}"
    
    if [[ ! -f "${log_file}" ]]; then
        echo "{}"
        return 1
    fi
    
    # Calculate time threshold
    local threshold_timestamp
    threshold_timestamp=$(date -d "${time_window_minutes} minutes ago" +%s 2>/dev/null || date -v-"${time_window_minutes}"M +%s 2>/dev/null || echo "0")
    
    # Initialize counters
    local total_requests=0
    local successful_requests=0
    local failed_requests=0
    local timeout_requests=0
    local errors_4xx=0
    local errors_5xx=0
    local rate_limit_hits=0
    local total_response_time_ms=0
    local response_time_count=0
    local total_response_size_bytes=0
    local response_size_count=0
    local total_notes_per_request=0
    local notes_count=0
    local last_request_timestamp=0
    local last_note_timestamp=0
    
    # Parse log file
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "${line}" ]] && continue
        
        # Extract timestamp (try multiple formats)
        local log_timestamp=0
        if [[ "${line}" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2})\] ]]; then
            log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
        elif [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
        fi
        
        # Skip if timestamp is too old
        if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
            continue
        fi
        
        # Count HTTP requests
        if [[ "${line}" =~ (GET|POST|PUT|DELETE)[[:space:]]+https?:// ]]; then
            total_requests=$((total_requests + 1))
            last_request_timestamp=${log_timestamp}
        fi
        
        # Detect successful requests (200 OK, 201 Created, etc.)
        if [[ "${line}" =~ (200|201|202|204)[[:space:]]OK ]] || [[ "${line}" =~ "success" ]] || [[ "${line}" =~ "completed" ]]; then
            successful_requests=$((successful_requests + 1))
        fi
        
        # Detect failed requests
        if [[ "${line}" =~ "failed" ]] || [[ "${line}" =~ "error" ]] || [[ "${line}" =~ "ERROR" ]]; then
            failed_requests=$((failed_requests + 1))
        fi
        
        # Detect timeouts
        if [[ "${line}" =~ "timeout" ]] || [[ "${line}" =~ "timed out" ]] || [[ "${line}" =~ "TIMEOUT" ]]; then
            timeout_requests=$((timeout_requests + 1))
        fi
        
        # Detect HTTP 4xx errors
        if [[ "${line}" =~ [4][0-9]{2} ]]; then
            errors_4xx=$((errors_4xx + 1))
        fi
        
        # Detect HTTP 5xx errors
        if [[ "${line}" =~ [5][0-9]{2} ]]; then
            errors_5xx=$((errors_5xx + 1))
        fi
        
        # Detect rate limit hits
        if [[ "${line}" =~ "rate limit" ]] || [[ "${line}" =~ "429" ]] || [[ "${line}" =~ "too many requests" ]]; then
            rate_limit_hits=$((rate_limit_hits + 1))
        fi
        
        # Extract response time (look for patterns like "123ms", "1.23s", "duration: 123")
        if [[ "${line}" =~ ([0-9]+\.?[0-9]*)[[:space:]]*ms ]]; then
            local response_time
            response_time=$(echo "${BASH_REMATCH[1]}" | awk '{printf "%.0f", $1}')
            total_response_time_ms=$((total_response_time_ms + response_time))
            response_time_count=$((response_time_count + 1))
        elif [[ "${line}" =~ ([0-9]+\.?[0-9]*)[[:space:]]*s ]] && [[ "${line}" =~ (duration|time|elapsed) ]]; then
            local response_time
            response_time=$(echo "${BASH_REMATCH[1]}" | awk '{printf "%.0f", $1 * 1000}')
            total_response_time_ms=$((total_response_time_ms + response_time))
            response_time_count=$((response_time_count + 1))
        fi
        
        # Extract response size (look for patterns like "12345 bytes", "size: 12345")
        if [[ "${line}" =~ ([0-9]+)[[:space:]]*bytes ]] || [[ "${line}" =~ size:[[:space:]]*([0-9]+) ]]; then
            local response_size
            response_size=$(echo "${BASH_REMATCH[1]}" | awk '{print $1}')
            total_response_size_bytes=$((total_response_size_bytes + response_size))
            response_size_count=$((response_size_count + 1))
        fi
        
        # Extract notes count per request (look for patterns like "123 notes", "notes: 123")
        if [[ "${line}" =~ ([0-9]+)[[:space:]]*notes ]] || [[ "${line}" =~ notes:[[:space:]]*([0-9]+) ]]; then
            local notes_count_in_line
            notes_count_in_line=$(echo "${BASH_REMATCH[1]}" | awk '{print $1}')
            total_notes_per_request=$((total_notes_per_request + notes_count_in_line))
            notes_count=$((notes_count + 1))
            
            # Try to extract timestamp of last note
            if [[ "${line}" =~ created_at[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || [[ "${line}" =~ timestamp[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                local note_timestamp_str="${BASH_REMATCH[1]}"
                local note_timestamp
                note_timestamp=$(date -d "${note_timestamp_str}" +%s 2>/dev/null || echo "0")
                if [[ ${note_timestamp} -gt ${last_note_timestamp} ]]; then
                    last_note_timestamp=${note_timestamp}
                fi
            fi
        fi
    done < "${log_file}"
    
    # Calculate averages
    local avg_response_time_ms=0
    if [[ ${response_time_count} -gt 0 ]]; then
        avg_response_time_ms=$((total_response_time_ms / response_time_count))
    fi
    
    local avg_response_size_bytes=0
    if [[ ${response_size_count} -gt 0 ]]; then
        avg_response_size_bytes=$((total_response_size_bytes / response_size_count))
    fi
    
    local avg_notes_per_request=0
    if [[ ${notes_count} -gt 0 ]]; then
        avg_notes_per_request=$((total_notes_per_request / notes_count))
    fi
    
    # Calculate success rate
    local success_rate_percent=100
    if [[ ${total_requests} -gt 0 ]]; then
        success_rate_percent=$((successful_requests * 100 / total_requests))
    fi
    
    # Calculate timeout rate
    local timeout_rate_percent=0
    if [[ ${total_requests} -gt 0 ]]; then
        timeout_rate_percent=$((timeout_requests * 100 / total_requests))
    fi
    
    # Calculate requests per minute
    local requests_per_minute=0
    if [[ ${time_window_minutes} -gt 0 ]]; then
        requests_per_minute=$((total_requests / time_window_minutes))
    fi
    
    # Output metrics (simple key=value format for easy parsing)
    echo "total_requests=${total_requests}"
    echo "successful_requests=${successful_requests}"
    echo "failed_requests=${failed_requests}"
    echo "timeout_requests=${timeout_requests}"
    echo "errors_4xx=${errors_4xx}"
    echo "errors_5xx=${errors_5xx}"
    echo "rate_limit_hits=${rate_limit_hits}"
    echo "avg_response_time_ms=${avg_response_time_ms}"
    echo "avg_response_size_bytes=${avg_response_size_bytes}"
    echo "avg_notes_per_request=${avg_notes_per_request}"
    echo "success_rate_percent=${success_rate_percent}"
    echo "timeout_rate_percent=${timeout_rate_percent}"
    echo "requests_per_minute=${requests_per_minute}"
    echo "last_request_timestamp=${last_request_timestamp}"
    echo "last_note_timestamp=${last_note_timestamp}"
    
    return 0
}

##
# Parse multiple log files and aggregate metrics
# Usage: parse_api_logs_aggregated <log_dir> [time_window_minutes]
##
parse_api_logs_aggregated() {
    local log_dir="${1}"
    local time_window_minutes="${2:-60}"
    
    if [[ ! -d "${log_dir}" ]]; then
        echo "{}"
        return 1
    fi
    
    # Find API-related log files
    local log_files
    mapfile -t log_files < <(find "${log_dir}" \( -name "*api*" -o -name "*download*" -o -name "*http*" \) -type f -mmin "-${time_window_minutes}" 2>/dev/null | head -20)
    
    # Aggregate metrics from all files
    local total_requests=0
    local successful_requests=0
    local failed_requests=0
    local timeout_requests=0
    local errors_4xx=0
    local errors_5xx=0
    local rate_limit_hits=0
    local total_response_time_ms=0
    local response_time_count=0
    local total_response_size_bytes=0
    local response_size_count=0
    local total_notes_per_request=0
    local notes_count=0
    local last_request_timestamp=0
    local last_note_timestamp=0
    
    for log_file in "${log_files[@]}"; do
        if [[ ! -f "${log_file}" ]]; then
            continue
        fi
        
        # Parse individual file
        local metrics_output
        metrics_output=$(parse_api_logs "${log_file}" "${time_window_minutes}" 2>/dev/null || echo "")
        
        if [[ -z "${metrics_output}" ]]; then
            continue
        fi
        
        # Extract values from output
        while IFS='=' read -r key value; do
            case "${key}" in
                total_requests)
                    total_requests=$((total_requests + value))
                    ;;
                successful_requests)
                    successful_requests=$((successful_requests + value))
                    ;;
                failed_requests)
                    failed_requests=$((failed_requests + value))
                    ;;
                timeout_requests)
                    timeout_requests=$((timeout_requests + value))
                    ;;
                errors_4xx)
                    errors_4xx=$((errors_4xx + value))
                    ;;
                errors_5xx)
                    errors_5xx=$((errors_5xx + value))
                    ;;
                rate_limit_hits)
                    rate_limit_hits=$((rate_limit_hits + value))
                    ;;
                avg_response_time_ms)
                    if [[ ${value} -gt 0 ]]; then
                        total_response_time_ms=$((total_response_time_ms + value))
                        response_time_count=$((response_time_count + 1))
                    fi
                    ;;
                avg_response_size_bytes)
                    if [[ ${value} -gt 0 ]]; then
                        total_response_size_bytes=$((total_response_size_bytes + value))
                        response_size_count=$((response_size_count + 1))
                    fi
                    ;;
                avg_notes_per_request)
                    if [[ ${value} -gt 0 ]]; then
                        total_notes_per_request=$((total_notes_per_request + value))
                        notes_count=$((notes_count + 1))
                    fi
                    ;;
                last_request_timestamp)
                    if [[ ${value} -gt ${last_request_timestamp} ]]; then
                        last_request_timestamp=${value}
                    fi
                    ;;
                last_note_timestamp)
                    if [[ ${value} -gt ${last_note_timestamp} ]]; then
                        last_note_timestamp=${value}
                    fi
                    ;;
            esac
        done <<< "${metrics_output}"
    done
    
    # Calculate aggregated averages
    local avg_response_time_ms=0
    if [[ ${response_time_count} -gt 0 ]]; then
        avg_response_time_ms=$((total_response_time_ms / response_time_count))
    fi
    
    local avg_response_size_bytes=0
    if [[ ${response_size_count} -gt 0 ]]; then
        avg_response_size_bytes=$((total_response_size_bytes / response_size_count))
    fi
    
    local avg_notes_per_request=0
    if [[ ${notes_count} -gt 0 ]]; then
        avg_notes_per_request=$((total_notes_per_request / notes_count))
    fi
    
    # Calculate success rate
    local success_rate_percent=100
    if [[ ${total_requests} -gt 0 ]]; then
        success_rate_percent=$((successful_requests * 100 / total_requests))
    fi
    
    # Calculate timeout rate
    local timeout_rate_percent=0
    if [[ ${total_requests} -gt 0 ]]; then
        timeout_rate_percent=$((timeout_requests * 100 / total_requests))
    fi
    
    # Calculate requests per minute
    local requests_per_minute=0
    if [[ ${time_window_minutes} -gt 0 ]]; then
        requests_per_minute=$((total_requests / time_window_minutes))
    fi
    
    # Output aggregated metrics
    echo "total_requests=${total_requests}"
    echo "successful_requests=${successful_requests}"
    echo "failed_requests=${failed_requests}"
    echo "timeout_requests=${timeout_requests}"
    echo "errors_4xx=${errors_4xx}"
    echo "errors_5xx=${errors_5xx}"
    echo "rate_limit_hits=${rate_limit_hits}"
    echo "avg_response_time_ms=${avg_response_time_ms}"
    echo "avg_response_size_bytes=${avg_response_size_bytes}"
    echo "avg_notes_per_request=${avg_notes_per_request}"
    echo "success_rate_percent=${success_rate_percent}"
    echo "timeout_rate_percent=${timeout_rate_percent}"
    echo "requests_per_minute=${requests_per_minute}"
    echo "requests_per_hour=$((requests_per_minute * 60))"
    echo "last_request_timestamp=${last_request_timestamp}"
    echo "last_note_timestamp=${last_note_timestamp}"
    
    return 0
}

# Export functions for use in other scripts
export -f parse_api_logs parse_api_logs_aggregated

# Run if executed directly (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <log_file|log_dir> [time_window_minutes]"
        exit 1
    fi
    
    if [[ -f "${1}" ]]; then
        parse_api_logs "${1}" "${2:-60}"
    elif [[ -d "${1}" ]]; then
        parse_api_logs_aggregated "${1}" "${2:-60}"
    else
        echo "Error: ${1} is not a file or directory"
        exit 1
    fi
fi
