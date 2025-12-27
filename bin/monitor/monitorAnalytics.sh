#!/usr/bin/env bash
#
# Analytics Monitoring Script
# Monitors the OSM-Notes-Analytics component health and performance
#
# Version: 1.0.0
# Date: 2025-12-26
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
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging
init_logging "${LOG_DIR}/analytics.log" "monitorAnalytics"

# Component name
readonly COMPONENT="ANALYTICS"

##
# Show usage
##
usage() {
    cat << EOF
Analytics Monitoring Script

Monitors the OSM-Notes-Analytics component for health, performance, and data quality.

Usage: $0 [OPTIONS]

Options:
    -c, --check TYPE      Run specific check (health, performance, data-quality, all)
    -v, --verbose         Enable verbose output
    -d, --dry-run         Dry run (don't write to database)
    -h, --help            Show this help message

Check Types:
    health          Check component health status
    performance     Check performance metrics
    data-quality    Check data quality metrics
    etl-status      Check ETL job execution status
    data-freshness  Check data warehouse freshness
    storage         Check storage growth
    query-performance Check query performance
    all             Run all checks (default)

Examples:
    # Run all checks
    $0

    # Run only health check
    $0 --check health

    # Run ETL status check
    $0 --check etl-status

    # Dry run (no database writes)
    $0 --dry-run

EOF
}

##
# Check ETL job execution status
##
check_etl_job_execution_status() {
    log_info "${COMPONENT}: Starting ETL job execution status check"
    
    # Check if analytics repository path is configured
    if [[ -z "${ANALYTICS_REPO_PATH:-}" ]]; then
        log_warning "${COMPONENT}: ANALYTICS_REPO_PATH not configured, skipping ETL job status check"
        return 0
    fi
    
    # Expected ETL scripts/jobs
    local etl_scripts=(
        "etl_main.sh"
        "etl_daily.sh"
        "etl_hourly.sh"
        "load_data.sh"
        "transform_data.sh"
    )
    
    local scripts_dir="${ANALYTICS_REPO_PATH}/bin"
    local scripts_found=0
    local scripts_executable=0
    local scripts_running=0
    local last_execution_timestamp=""
    local last_execution_age_seconds=0
    
    # Check each ETL script
    for script_name in "${etl_scripts[@]}"; do
        local script_path="${scripts_dir}/${script_name}"
        
        # Check if script exists
        if [[ ! -f "${script_path}" ]]; then
            log_debug "${COMPONENT}: ETL script not found: ${script_name}"
            continue
        fi
        
        scripts_found=$((scripts_found + 1))
        
        # Check if script is executable
        if [[ -x "${script_path}" ]]; then
            scripts_executable=$((scripts_executable + 1))
        else
            log_warning "${COMPONENT}: ETL script exists but not executable: ${script_name}"
        fi
        
        # Check if script process is running
        local script_basename
        script_basename=$(basename "${script_path}")
        if pgrep -f "${script_basename}" > /dev/null 2>&1; then
            scripts_running=$((scripts_running + 1))
            log_info "${COMPONENT}: ETL script is running: ${script_name}"
            
            # Get process info
            local pid
            pid=$(pgrep -f "${script_basename}" | head -1)
            local runtime
            runtime=$(ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ' || echo "unknown")
            log_debug "${COMPONENT}: ETL script ${script_name} PID: ${pid}, Runtime: ${runtime}"
        fi
    done
    
    # Record metrics
    record_metric "${COMPONENT}" "etl_scripts_found" "${scripts_found}" "component=analytics"
    record_metric "${COMPONENT}" "etl_scripts_executable" "${scripts_executable}" "component=analytics"
    record_metric "${COMPONENT}" "etl_scripts_running" "${scripts_running}" "component=analytics"
    
    # Check for alerts
    local scripts_found_threshold="${ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD:-2}"
    if [[ ${scripts_found} -lt ${scripts_found_threshold} ]]; then
        log_warning "${COMPONENT}: Low number of ETL scripts found: ${scripts_found} (threshold: ${scripts_found_threshold})"
        send_alert "WARNING" "${COMPONENT}" "Low number of ETL scripts found: ${scripts_found} (threshold: ${scripts_found_threshold})"
    fi
    
    if [[ ${scripts_executable} -lt ${scripts_found} ]]; then
        log_warning "${COMPONENT}: Some ETL scripts are not executable: ${scripts_executable}/${scripts_found}"
        send_alert "WARNING" "${COMPONENT}" "ETL scripts executable count (${scripts_executable}) is less than scripts found (${scripts_found})"
    fi
    
    # Check last execution timestamp from logs
    local log_dir="${ANALYTICS_LOG_DIR:-${ANALYTICS_REPO_PATH}/logs}"
    if [[ -d "${log_dir}" ]]; then
        # Find most recent log file
        local latest_log
        latest_log=$(find "${log_dir}" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        
        if [[ -n "${latest_log}" ]] && [[ -f "${latest_log}" ]]; then
            # Get last modification time
            if command -v stat > /dev/null 2>&1; then
                # Try to get modification time (works on Linux and macOS with different flags)
                if stat -c %Y "${latest_log}" > /dev/null 2>&1; then
                    # Linux
                    last_execution_timestamp=$(stat -c %Y "${latest_log}")
                elif stat -f %m "${latest_log}" > /dev/null 2>&1; then
                    # macOS
                    last_execution_timestamp=$(stat -f %m "${latest_log}")
                fi
                
                if [[ -n "${last_execution_timestamp}" ]]; then
                    local current_timestamp
                    current_timestamp=$(date +%s)
                    last_execution_age_seconds=$((current_timestamp - last_execution_timestamp))
                    
                    # Record metric
                    record_metric "${COMPONENT}" "last_etl_execution_age_seconds" "${last_execution_age_seconds}" "component=analytics"
                    
                    # Check threshold
                    local freshness_threshold="${ANALYTICS_DATA_FRESHNESS_THRESHOLD:-3600}"
                    if [[ ${last_execution_age_seconds} -gt ${freshness_threshold} ]]; then
                        log_warning "${COMPONENT}: Last ETL execution is ${last_execution_age_seconds}s old (threshold: ${freshness_threshold}s)"
                        send_alert "WARNING" "${COMPONENT}" "Last ETL execution is ${last_execution_age_seconds}s old (threshold: ${freshness_threshold}s)"
                    fi
                fi
            fi
        else
            log_debug "${COMPONENT}: No log files found in ${log_dir}"
        fi
    else
        log_debug "${COMPONENT}: Log directory not found: ${log_dir}"
    fi
    
    # Check for ETL job failures in logs (last 24 hours)
    if [[ -d "${log_dir}" ]]; then
        local error_count=0
        local failure_count=0
        
        # Count errors and failures in recent logs
        if find "${log_dir}" -name "*.log" -type f -mtime -1 -exec grep -l -i "error\|failed\|failure" {} \; 2>/dev/null | head -10 | while read -r logfile; do
            local file_errors
            file_errors=$(grep -ic "error" "${logfile}" 2>/dev/null || echo "0")
            local file_failures
            file_failures=$(grep -ic -E "failed|failure" "${logfile}" 2>/dev/null || echo "0")
            error_count=$((error_count + file_errors))
            failure_count=$((failure_count + file_failures))
        done; then
            # Record metrics
            if [[ ${error_count} -gt 0 ]]; then
                record_metric "${COMPONENT}" "etl_error_count" "${error_count}" "component=analytics,period=24h"
            fi
            if [[ ${failure_count} -gt 0 ]]; then
                record_metric "${COMPONENT}" "etl_failure_count" "${failure_count}" "component=analytics,period=24h"
                
                # Alert on failures
                send_alert "WARNING" "${COMPONENT}" "ETL job failures detected: ${failure_count} failures in last 24 hours"
            fi
        fi
    fi
    
    log_info "${COMPONENT}: ETL job execution status check completed - scripts found: ${scripts_found}, running: ${scripts_running}"
    
    return 0
}

##
# Check data warehouse freshness
##
check_data_warehouse_freshness() {
    log_info "${COMPONENT}: Starting data warehouse freshness check"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check data warehouse freshness - database connection failed"
        return 0
    fi
    
    # Check if analytics database is configured
    local analytics_dbname="${ANALYTICS_DBNAME:-${DBNAME}}"
    
    # Query to check last update time in data warehouse
    # This checks common DWH tables for their last update timestamp
    local freshness_query="
        SELECT 
            COALESCE(
                MAX(EXTRACT(EPOCH FROM (NOW() - updated_at))),
                MAX(EXTRACT(EPOCH FROM (NOW() - created_at))),
                MAX(EXTRACT(EPOCH FROM (NOW() - last_updated))),
                MAX(EXTRACT(EPOCH FROM (NOW() - timestamp)))
            ) as freshness_seconds,
            COUNT(*) FILTER (WHERE 
                updated_at > NOW() - INTERVAL '1 hour' OR
                created_at > NOW() - INTERVAL '1 hour' OR
                last_updated > NOW() - INTERVAL '1 hour' OR
                timestamp > NOW() - INTERVAL '1 hour'
            ) as recent_updates
        FROM (
            SELECT updated_at, created_at, last_updated, timestamp
            FROM notes
            UNION ALL
            SELECT updated_at, created_at, last_updated, timestamp
            FROM note_comments
            UNION ALL
            SELECT updated_at, created_at, last_updated, timestamp
            FROM note_comment_texts
            LIMIT 1000
        ) as all_tables
        LIMIT 1;
    "
    
    # Try to execute query
    local result
    result=$(execute_sql_query "${freshness_query}" "${analytics_dbname}" 2>/dev/null || echo "")
    
    if [[ -n "${result}" ]] && [[ "${result}" != "Error executing query:"* ]]; then
        log_debug "${COMPONENT}: Data warehouse freshness check result: ${result}"
        
        # Parse result (format: freshness_seconds|recent_updates)
        local freshness_seconds
        freshness_seconds=$(echo "${result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "")
        local recent_updates
        recent_updates=$(echo "${result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "")
        
        if [[ -n "${freshness_seconds}" ]] && [[ "${freshness_seconds}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            # Convert to integer seconds
            local freshness_int
            freshness_int=$(printf "%.0f" "${freshness_seconds}" 2>/dev/null || echo "${freshness_seconds}")
            
            record_metric "${COMPONENT}" "data_warehouse_freshness_seconds" "${freshness_int}" "component=analytics"
            
            # Check against threshold
            local freshness_threshold="${ANALYTICS_DATA_FRESHNESS_THRESHOLD:-3600}"
            if [[ ${freshness_int} -gt ${freshness_threshold} ]]; then
                log_warning "${COMPONENT}: Data warehouse freshness (${freshness_int}s) exceeds threshold (${freshness_threshold}s)"
                send_alert "WARNING" "${COMPONENT}" "Data warehouse freshness exceeded: ${freshness_int}s (threshold: ${freshness_threshold}s)"
            fi
        fi
        
        if [[ -n "${recent_updates}" ]] && [[ "${recent_updates}" =~ ^[0-9]+$ ]]; then
            record_metric "${COMPONENT}" "data_warehouse_recent_updates_count" "${recent_updates}" "component=analytics,period=1hour"
        fi
    else
        # Fallback: Check by table modification time or log file age
        log_debug "${COMPONENT}: Using fallback method for data warehouse freshness check"
        
        # Try to get table modification times from PostgreSQL
        local table_freshness_query="
            SELECT 
                schemaname,
                tablename,
                EXTRACT(EPOCH FROM (NOW() - last_vacuum)) as freshness_seconds
            FROM pg_stat_user_tables
            WHERE schemaname = 'public'
            ORDER BY last_vacuum DESC NULLS LAST
            LIMIT 1;
        "
        
        local table_result
        table_result=$(execute_sql_query "${table_freshness_query}" "${analytics_dbname}" 2>/dev/null || echo "")
        
        if [[ -n "${table_result}" ]] && [[ "${table_result}" != "Error executing query:"* ]]; then
            local table_freshness
            table_freshness=$(echo "${table_result}" | cut -d'|' -f3 | tr -d '[:space:]' || echo "")
            
            if [[ -n "${table_freshness}" ]] && [[ "${table_freshness}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                local table_freshness_int
                table_freshness_int=$(printf "%.0f" "${table_freshness}" 2>/dev/null || echo "${table_freshness}")
                
                record_metric "${COMPONENT}" "data_warehouse_freshness_seconds" "${table_freshness_int}" "component=analytics,source=pg_stat"
                
                local freshness_threshold="${ANALYTICS_DATA_FRESHNESS_THRESHOLD:-3600}"
                if [[ ${table_freshness_int} -gt ${freshness_threshold} ]]; then
                    log_warning "${COMPONENT}: Data warehouse freshness (from table stats) (${table_freshness_int}s) exceeds threshold (${freshness_threshold}s)"
                    send_alert "WARNING" "${COMPONENT}" "Data warehouse freshness exceeded: ${table_freshness_int}s (threshold: ${freshness_threshold}s)"
                fi
            fi
        else
            # Last fallback: Use ETL log file age
            local log_dir="${ANALYTICS_LOG_DIR:-${ANALYTICS_REPO_PATH}/logs}"
            if [[ -d "${log_dir}" ]]; then
                local latest_log
                latest_log=$(find "${log_dir}" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
                
                if [[ -n "${latest_log}" ]] && [[ -f "${latest_log}" ]]; then
                    local log_mtime
                    if stat -c %Y "${latest_log}" > /dev/null 2>&1; then
                        log_mtime=$(stat -c %Y "${latest_log}")
                    elif stat -f %m "${latest_log}" > /dev/null 2>&1; then
                        log_mtime=$(stat -f %m "${latest_log}")
                    else
                        log_mtime=0
                    fi
                    
                    if [[ ${log_mtime} -gt 0 ]]; then
                        local current_time
                        current_time=$(date +%s)
                        local freshness_seconds=$((current_time - log_mtime))
                        
                        record_metric "${COMPONENT}" "data_warehouse_freshness_seconds" "${freshness_seconds}" "component=analytics,source=log_age"
                        
                        local freshness_threshold="${ANALYTICS_DATA_FRESHNESS_THRESHOLD:-3600}"
                        if [[ ${freshness_seconds} -gt ${freshness_threshold} ]]; then
                            log_warning "${COMPONENT}: Data warehouse freshness (from log age) (${freshness_seconds}s) exceeds threshold (${freshness_threshold}s)"
                            send_alert "WARNING" "${COMPONENT}" "Data warehouse freshness exceeded: ${freshness_seconds}s (threshold: ${freshness_threshold}s)"
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    log_info "${COMPONENT}: Data warehouse freshness check completed"
    return 0
}

##
# Check ETL processing duration
##
check_etl_processing_duration() {
    log_info "${COMPONENT}: Starting ETL processing duration check"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check ETL processing duration - database connection failed"
        return 0
    fi
    
    # Define ETL scripts to monitor
    local etl_scripts=(
        "extract_data.sh"
        "load_data.sh"
        "transform_data.sh"
    )
    
    local scripts_dir="${ANALYTICS_REPO_PATH}/bin"
    local log_dir="${ANALYTICS_LOG_DIR:-${ANALYTICS_REPO_PATH}/logs}"
    local current_time
    current_time=$(date +%s)
    
    local total_duration=0
    local job_count=0
    local max_duration=0
    local min_duration=999999
    local long_running_jobs=0
    local running_jobs_duration=0
    
    # Check currently running ETL jobs
    for script_name in "${etl_scripts[@]}"; do
        local script_path="${scripts_dir}/${script_name}"
        
        if [[ ! -f "${script_path}" ]]; then
            continue
        fi
        
        local script_basename
        script_basename=$(basename "${script_path}")
        
        # Check if script process is running
        if pgrep -f "${script_basename}" > /dev/null 2>&1; then
            local pid
            pid=$(pgrep -f "${script_basename}" | head -1)
            
            if [[ -n "${pid}" ]]; then
                # Get process start time
                local start_time
                if [[ -f "/proc/${pid}/stat" ]]; then
                    # Linux: get start time from /proc
                    local starttime
                    starttime=$(awk '{print $22}' "/proc/${pid}/stat" 2>/dev/null || echo "0")
                    local uptime
                    uptime=$(awk '{print $1}' /proc/uptime 2>/dev/null || echo "0")
                    local clk_tck
                    clk_tck=$(getconf CLK_TCK 2>/dev/null || echo "100")
                    
                    if [[ ${starttime} -gt 0 ]] && [[ ${uptime} -gt 0 ]]; then
                        start_time=$((current_time - (uptime - starttime / clk_tck)))
                    else
                        start_time=${current_time}
                    fi
                else
                    # macOS/BSD: use ps to get elapsed time
                    local etime_str
                    etime_str=$(ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ' || echo "")
                    
                    if [[ -n "${etime_str}" ]]; then
                        # Parse elapsed time (format: [[DD-]HH:]MM:SS or MM:SS)
                        local etime_seconds=0
                        # shellcheck disable=SC1073,SC2001
                        if [[ "${etime_str}" =~ ^([0-9]+)-([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
                            # DD-HH:MM:SS format
                            local days="${BASH_REMATCH[1]}"
                            local hours="${BASH_REMATCH[2]}"
                            local minutes="${BASH_REMATCH[3]}"
                            local seconds="${BASH_REMATCH[4]}"
                            etime_seconds=$((days * 86400 + hours * 3600 + minutes * 60 + seconds))
                        elif [[ "${etime_str}" =~ ^([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]]; then
                            # HH:MM:SS format
                            local hours="${BASH_REMATCH[1]}"
                            local minutes="${BASH_REMATCH[2]}"
                            local seconds="${BASH_REMATCH[3]}"
                            etime_seconds=$((hours * 3600 + minutes * 60 + seconds))
                        elif [[ "${etime_str}" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
                            # MM:SS format
                            local minutes="${BASH_REMATCH[1]}"
                            local seconds="${BASH_REMATCH[2]}"
                            etime_seconds=$((minutes * 60 + seconds))
                        fi
                        
                        start_time=$((current_time - etime_seconds))
                    else
                        start_time=${current_time}
                    fi
                fi
                
                local job_duration=$((current_time - start_time))
                running_jobs_duration=$((running_jobs_duration + job_duration))
                
                log_info "${COMPONENT}: ETL job ${script_name} is running (duration: ${job_duration}s, PID: ${pid})"
                
                # Check if job is running too long
                local duration_threshold="${ANALYTICS_ETL_DURATION_THRESHOLD:-3600}"
                if [[ ${job_duration} -gt ${duration_threshold} ]]; then
                    long_running_jobs=$((long_running_jobs + 1))
                    log_warning "${COMPONENT}: ETL job ${script_name} has been running for ${job_duration}s (threshold: ${duration_threshold}s)"
                    send_alert "WARNING" "${COMPONENT}" "Long-running ETL job detected: ${script_name} has been running for ${job_duration}s (threshold: ${duration_threshold}s)"
                fi
                
                # Track statistics
                if [[ ${job_duration} -gt ${max_duration} ]]; then
                    max_duration=${job_duration}
                fi
                if [[ ${job_duration} -lt ${min_duration} ]]; then
                    min_duration=${job_duration}
                fi
                
                total_duration=$((total_duration + job_duration))
                job_count=$((job_count + 1))
            fi
        fi
    done
    
    # Check historical durations from logs
    if [[ -d "${log_dir}" ]]; then
        # Look for ETL execution logs (last 7 days)
        local log_files
        log_files=$(find "${log_dir}" -name "*etl*.log" -o -name "*extract*.log" -o -name "*load*.log" -o -name "*transform*.log" -type f -mtime -7 2>/dev/null | head -20)
        
        if [[ -n "${log_files}" ]]; then
            while IFS= read -r logfile; do
                if [[ ! -f "${logfile}" ]]; then
                    continue
                fi
                
                # Try to extract duration from log file
                # Look for patterns like "duration: 123s", "took 123 seconds", "completed in 123s"
                local log_durations
                log_durations=$(grep -oE "(duration|took|completed in|execution time)[: ]*[0-9]+[ ]*(seconds?|s|sec)" "${logfile}" 2>/dev/null | grep -oE "[0-9]+" | head -5)
                
                if [[ -n "${log_durations}" ]]; then
                    while IFS= read -r duration_str; do
                        if [[ "${duration_str}" =~ ^[0-9]+$ ]]; then
                            local duration=${duration_str}
                            
                            # Track statistics
                            if [[ ${duration} -gt ${max_duration} ]]; then
                                max_duration=${duration}
                            fi
                            if [[ ${duration} -lt ${min_duration} ]]; then
                                min_duration=${duration}
                            fi
                            
                            total_duration=$((total_duration + duration))
                            job_count=$((job_count + 1))
                        fi
                    done <<< "${log_durations}"
                fi
                
                # Also check log file modification time as proxy for execution duration
                # (if log was modified recently, it might indicate a recent execution)
                local log_mtime
                if stat -c %Y "${logfile}" > /dev/null 2>&1; then
                    log_mtime=$(stat -c %Y "${logfile}")
                elif stat -f %m "${logfile}" > /dev/null 2>&1; then
                    log_mtime=$(stat -f %m "${logfile}")
                else
                    log_mtime=0
                fi
                
                # If log was modified in last hour, use file size as proxy for duration
                # (larger files might indicate longer executions)
                if [[ ${log_mtime} -gt 0 ]]; then
                    local log_age=$((current_time - log_mtime))
                    if [[ ${log_age} -lt 3600 ]]; then
                        local log_size
                        log_size=$(stat -c %s "${logfile}" 2>/dev/null || stat -f %z "${logfile}" 2>/dev/null || echo "0")
                        # Estimate duration from log size (rough approximation: 1KB = 1 second)
                        local estimated_duration=$((log_size / 1024))
                        
                        if [[ ${estimated_duration} -gt 0 ]] && [[ ${estimated_duration} -lt 86400 ]]; then
                            if [[ ${estimated_duration} -gt ${max_duration} ]]; then
                                max_duration=${estimated_duration}
                            fi
                            if [[ ${estimated_duration} -lt ${min_duration} ]]; then
                                min_duration=${estimated_duration}
                            fi
                            
                            total_duration=$((total_duration + estimated_duration))
                            job_count=$((job_count + 1))
                        fi
                    fi
                fi
            done <<< "${log_files}"
        fi
    fi
    
    # Calculate average duration
    local avg_duration=0
    if [[ ${job_count} -gt 0 ]]; then
        avg_duration=$((total_duration / job_count))
    fi
    
    # Record metrics
    if [[ ${job_count} -gt 0 ]]; then
        record_metric "${COMPONENT}" "etl_processing_duration_avg_seconds" "${avg_duration}" "component=analytics,period=7days"
        record_metric "${COMPONENT}" "etl_processing_duration_max_seconds" "${max_duration}" "component=analytics,period=7days"
        record_metric "${COMPONENT}" "etl_processing_duration_min_seconds" "${min_duration}" "component=analytics,period=7days"
        record_metric "${COMPONENT}" "etl_processing_duration_total_seconds" "${total_duration}" "component=analytics,period=7days"
        record_metric "${COMPONENT}" "etl_job_count" "${job_count}" "component=analytics,period=7days"
    fi
    
    if [[ ${running_jobs_duration} -gt 0 ]]; then
        record_metric "${COMPONENT}" "etl_running_jobs_duration_seconds" "${running_jobs_duration}" "component=analytics"
    fi
    
    if [[ ${long_running_jobs} -gt 0 ]]; then
        record_metric "${COMPONENT}" "etl_long_running_jobs_count" "${long_running_jobs}" "component=analytics"
    fi
    
    # Check average duration threshold
    local avg_duration_threshold="${ANALYTICS_ETL_AVG_DURATION_THRESHOLD:-1800}"
    # shellcheck disable=SC1073
    if [[ "${avg_duration}" -gt "${avg_duration_threshold}" ]]; then
        log_warning "${COMPONENT}: Average ETL processing duration (${avg_duration}s) exceeds threshold (${avg_duration_threshold}s)"
        send_alert "WARNING" "${COMPONENT}" "Average ETL processing duration exceeded: ${avg_duration}s (threshold: ${avg_duration_threshold}s)"
    fi
    
    # Check max duration threshold
    local max_duration_threshold="${ANALYTICS_ETL_MAX_DURATION_THRESHOLD:-7200}"
    # shellcheck disable=SC1073
    if [[ "${max_duration}" -gt "${max_duration_threshold}" ]]; then
        log_warning "${COMPONENT}: Maximum ETL processing duration (${max_duration}s) exceeds threshold (${max_duration_threshold}s)"
        send_alert "WARNING" "${COMPONENT}" "Maximum ETL processing duration exceeded: ${max_duration}s (threshold: ${max_duration_threshold}s)"
    fi
    
    log_info "${COMPONENT}: ETL processing duration check completed - Jobs: ${job_count}, Avg: ${avg_duration}s, Max: ${max_duration}s, Min: ${min_duration}s"
    
    return 0
}

##
# Check data mart update status
##
check_data_mart_update_status() {
    log_info "${COMPONENT}: Starting data mart update status check"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check data mart update status - database connection failed"
        return 0
    fi
    
    # Check if analytics database is configured
    local analytics_dbname="${ANALYTICS_DBNAME:-${DBNAME}}"
    
    # Query to check data mart update status
    # This checks common data mart tables for their last update timestamp and status
    local mart_status_query="
        SELECT 
            'data_mart' as mart_name,
            COALESCE(
                MAX(EXTRACT(EPOCH FROM (NOW() - updated_at))),
                MAX(EXTRACT(EPOCH FROM (NOW() - last_updated))),
                MAX(EXTRACT(EPOCH FROM (NOW() - timestamp)))
            ) as last_update_age_seconds,
            COUNT(*) FILTER (WHERE 
                updated_at > NOW() - INTERVAL '1 hour' OR
                last_updated > NOW() - INTERVAL '1 hour' OR
                timestamp > NOW() - INTERVAL '1 hour'
            ) as recent_updates_count,
            COUNT(*) as total_records
        FROM (
            SELECT updated_at, last_updated, timestamp
            FROM notes_summary
            UNION ALL
            SELECT updated_at, last_updated, timestamp
            FROM notes_statistics
            UNION ALL
            SELECT updated_at, last_updated, timestamp
            FROM notes_aggregated
            LIMIT 1000
        ) as mart_tables
        LIMIT 1;
    "
    
    # Try to execute query
    local result
    result=$(execute_sql_query "${mart_status_query}" "${analytics_dbname}" 2>/dev/null || echo "")
    
    local marts_checked=0
    local marts_stale=0
    local marts_failed=0
    local total_update_age=0
    local max_update_age=0
    
    if [[ -n "${result}" ]] && [[ "${result}" != "Error executing query:"* ]]; then
        log_debug "${COMPONENT}: Data mart status check result: ${result}"
        
        # Parse result (format: mart_name|last_update_age_seconds|recent_updates_count|total_records)
        local update_age
        update_age=$(echo "${result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "")
        local recent_updates
        recent_updates=$(echo "${result}" | cut -d'|' -f3 | tr -d '[:space:]' || echo "")
        local total_records
        total_records=$(echo "${result}" | cut -d'|' -f4 | tr -d '[:space:]' || echo "")
        
        if [[ -n "${update_age}" ]] && [[ "${update_age}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            local update_age_int
            update_age_int=$(printf "%.0f" "${update_age}" 2>/dev/null || echo "${update_age}")
            
            marts_checked=$((marts_checked + 1))
            total_update_age=$((total_update_age + update_age_int))
            
            if [[ ${update_age_int} -gt ${max_update_age} ]]; then
                max_update_age=${update_age_int}
            fi
            
            # Record metric for this data mart
            record_metric "${COMPONENT}" "data_mart_update_age_seconds" "${update_age_int}" "component=analytics,mart=data_mart"
            
            # Check against threshold
            local update_age_threshold="${ANALYTICS_DATA_MART_UPDATE_AGE_THRESHOLD:-3600}"
            if [[ ${update_age_int} -gt ${update_age_threshold} ]]; then
                marts_stale=$((marts_stale + 1))
                log_warning "${COMPONENT}: Data mart update age (${update_age_int}s) exceeds threshold (${update_age_threshold}s)"
                send_alert "WARNING" "${COMPONENT}" "Data mart update age exceeded: ${update_age_int}s (threshold: ${update_age_threshold}s)"
            fi
            
            # Check if there are no recent updates
            if [[ -n "${recent_updates}" ]] && [[ "${recent_updates}" =~ ^[0-9]+$ ]] && [[ ${recent_updates} -eq 0 ]]; then
                log_warning "${COMPONENT}: No recent updates in data mart (last ${update_age_int}s)"
            fi
            
            # Record recent updates count
            if [[ -n "${recent_updates}" ]] && [[ "${recent_updates}" =~ ^[0-9]+$ ]]; then
                record_metric "${COMPONENT}" "data_mart_recent_updates_count" "${recent_updates}" "component=analytics,mart=data_mart,period=1hour"
            fi
            
            # Record total records
            if [[ -n "${total_records}" ]] && [[ "${total_records}" =~ ^[0-9]+$ ]]; then
                record_metric "${COMPONENT}" "data_mart_total_records" "${total_records}" "component=analytics,mart=data_mart"
            fi
        fi
    else
        # Fallback: Check data mart update logs or status files
        log_debug "${COMPONENT}: Using fallback method for data mart update status check"
        
        local log_dir="${ANALYTICS_LOG_DIR:-${ANALYTICS_REPO_PATH}/logs}"
        if [[ -d "${log_dir}" ]]; then
            # Look for data mart update logs
            local mart_logs
            mart_logs=$(find "${log_dir}" -name "*mart*.log" -o -name "*update*.log" -type f -mtime -1 2>/dev/null | head -10)
            
            if [[ -n "${mart_logs}" ]]; then
                while IFS= read -r logfile; do
                    if [[ ! -f "${logfile}" ]]; then
                        continue
                    fi
                    
                    # Check for failure indicators
                    local failure_count
                    failure_count=$(grep -ic "error\|failed\|failure" "${logfile}" 2>/dev/null || echo "0")
                    
                    if [[ ${failure_count} -gt 0 ]]; then
                        marts_failed=$((marts_failed + 1))
                        log_warning "${COMPONENT}: Data mart update failures detected in ${logfile}"
                    fi
                    
                    # Get log file modification time as proxy for last update
                    local log_mtime
                    if stat -c %Y "${logfile}" > /dev/null 2>&1; then
                        log_mtime=$(stat -c %Y "${logfile}")
                    elif stat -f %m "${logfile}" > /dev/null 2>&1; then
                        log_mtime=$(stat -f %m "${logfile}")
                    else
                        log_mtime=0
                    fi
                    
                    if [[ ${log_mtime} -gt 0 ]]; then
                        local current_time
                        current_time=$(date +%s)
                        local update_age=$((current_time - log_mtime))
                        
                        marts_checked=$((marts_checked + 1))
                        total_update_age=$((total_update_age + update_age))
                        
                        if [[ ${update_age} -gt ${max_update_age} ]]; then
                            max_update_age=${update_age}
                        fi
                        
                        record_metric "${COMPONENT}" "data_mart_update_age_seconds" "${update_age}" "component=analytics,source=log_age"
                        
                        local update_age_threshold="${ANALYTICS_DATA_MART_UPDATE_AGE_THRESHOLD:-3600}"
                        if [[ ${update_age} -gt ${update_age_threshold} ]]; then
                            marts_stale=$((marts_stale + 1))
                            log_warning "${COMPONENT}: Data mart update age (from log) (${update_age}s) exceeds threshold (${update_age_threshold}s)"
                            send_alert "WARNING" "${COMPONENT}" "Data mart update age exceeded: ${update_age}s (threshold: ${update_age_threshold}s)"
                        fi
                    fi
                done <<< "${mart_logs}"
            fi
        fi
    fi
    
    # Calculate average update age
    local avg_update_age=0
    if [[ ${marts_checked} -gt 0 ]]; then
        avg_update_age=$((total_update_age / marts_checked))
    fi
    
    # Record aggregate metrics
    if [[ ${marts_checked} -gt 0 ]]; then
        record_metric "${COMPONENT}" "data_mart_count" "${marts_checked}" "component=analytics"
        record_metric "${COMPONENT}" "data_mart_avg_update_age_seconds" "${avg_update_age}" "component=analytics"
        record_metric "${COMPONENT}" "data_mart_max_update_age_seconds" "${max_update_age}" "component=analytics"
    fi
    
    if [[ ${marts_stale} -gt 0 ]]; then
        record_metric "${COMPONENT}" "data_mart_stale_count" "${marts_stale}" "component=analytics"
    fi
    
    if [[ ${marts_failed} -gt 0 ]]; then
        record_metric "${COMPONENT}" "data_mart_failed_count" "${marts_failed}" "component=analytics"
        send_alert "ERROR" "${COMPONENT}" "Data mart update failures detected: ${marts_failed} mart(s) have update failures"
    fi
    
    # Check average update age threshold
    local avg_update_age_threshold="${ANALYTICS_DATA_MART_AVG_UPDATE_AGE_THRESHOLD:-1800}"
    if [[ ${avg_update_age} -gt ${avg_update_age_threshold} ]]; then
        log_warning "${COMPONENT}: Average data mart update age (${avg_update_age}s) exceeds threshold (${avg_update_age_threshold}s)"
        send_alert "WARNING" "${COMPONENT}" "Average data mart update age exceeded: ${avg_update_age}s (threshold: ${avg_update_age_threshold}s)"
    fi
    
    log_info "${COMPONENT}: Data mart update status check completed - Marts checked: ${marts_checked}, Stale: ${marts_stale}, Failed: ${marts_failed}, Avg age: ${avg_update_age}s"
    
    return 0
}

##
# Check query performance
##
check_query_performance() {
    log_info "${COMPONENT}: Starting query performance check"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check query performance - database connection failed"
        return 0
    fi
    
    # Check if analytics database is configured
    local analytics_dbname="${ANALYTICS_DBNAME:-${DBNAME}}"
    
    local slow_query_count=0
    local total_query_time=0
    local max_query_time=0
    local avg_query_time=0
    local queries_checked=0
    
    # Check if pg_stat_statements extension is available (PostgreSQL-specific)
    local pg_stat_check_query="
        SELECT COUNT(*) 
        FROM pg_extension 
        WHERE extname = 'pg_stat_statements';
    "
    
    local pg_stat_available
    pg_stat_available=$(execute_sql_query "${pg_stat_check_query}" "${analytics_dbname}" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    if [[ "${pg_stat_available}" == "1" ]]; then
        # Use pg_stat_statements to get slow queries
        local slow_query_threshold="${ANALYTICS_SLOW_QUERY_THRESHOLD:-1000}"
        # shellcheck disable=SC2016
        local slow_queries_query="
            SELECT 
                COUNT(*) as slow_query_count,
                SUM(mean_exec_time) as total_time_ms,
                MAX(mean_exec_time) as max_time_ms,
                AVG(mean_exec_time) as avg_time_ms,
                SUM(calls) as total_calls
            FROM pg_stat_statements
            WHERE mean_exec_time > ${slow_query_threshold}
              AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
            LIMIT 100;
        "
        
        local slow_queries_result
        slow_queries_result=$(execute_sql_query "${slow_queries_query}" "${analytics_dbname}" 2>/dev/null || echo "")
        
        if [[ -n "${slow_queries_result}" ]] && [[ "${slow_queries_result}" != "Error executing query:"* ]]; then
            # Parse result (format: slow_query_count|total_time_ms|max_time_ms|avg_time_ms|total_calls)
            local slow_count
            slow_count=$(echo "${slow_queries_result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "0")
            local total_time
            total_time=$(echo "${slow_queries_result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "0")
            local max_time
            max_time=$(echo "${slow_queries_result}" | cut -d'|' -f3 | tr -d '[:space:]' || echo "0")
            local avg_time
            avg_time=$(echo "${slow_queries_result}" | cut -d'|' -f4 | tr -d '[:space:]' || echo "0")
            local total_calls
            total_calls=$(echo "${slow_queries_result}" | cut -d'|' -f5 | tr -d '[:space:]' || echo "0")
            
            if [[ -n "${slow_count}" ]] && [[ "${slow_count}" =~ ^[0-9]+$ ]] && [[ ${slow_count} -gt 0 ]]; then
                slow_query_count=${slow_count}
                queries_checked=${slow_count}
                
                if [[ -n "${total_time}" ]] && [[ "${total_time}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    total_query_time=$(printf "%.0f" "${total_time}" 2>/dev/null || echo "${total_time}")
                fi
                
                if [[ -n "${max_time}" ]] && [[ "${max_time}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    max_query_time=$(printf "%.0f" "${max_time}" 2>/dev/null || echo "${max_time}")
                fi
                
                if [[ -n "${avg_time}" ]] && [[ "${avg_time}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    avg_query_time=$(printf "%.0f" "${avg_time}" 2>/dev/null || echo "${avg_time}")
                fi
                
                # Record metrics
                record_metric "${COMPONENT}" "slow_query_count" "${slow_query_count}" "component=analytics"
                record_metric "${COMPONENT}" "query_max_time_ms" "${max_query_time}" "component=analytics"
                record_metric "${COMPONENT}" "query_avg_time_ms" "${avg_query_time}" "component=analytics"
                
                if [[ -n "${total_calls}" ]] && [[ "${total_calls}" =~ ^[0-9]+$ ]]; then
                    record_metric "${COMPONENT}" "query_total_calls" "${total_calls}" "component=analytics"
                fi
                
                # Alert if there are slow queries
                local slow_query_threshold="${ANALYTICS_SLOW_QUERY_THRESHOLD:-1000}"
                if [[ ${slow_query_count} -gt 0 ]]; then
                    log_warning "${COMPONENT}: Found ${slow_query_count} slow queries (threshold: ${slow_query_threshold}ms)"
                    send_alert "WARNING" "${COMPONENT}" "Slow queries detected: ${slow_query_count} queries exceed ${slow_query_threshold}ms (max: ${max_query_time}ms, avg: ${avg_query_time}ms)"
                fi
            fi
        fi
        
        # Get top slow queries for detailed analysis
        local top_slow_queries_query="
            SELECT 
                LEFT(query, 100) as query_preview,
                mean_exec_time as avg_time_ms,
                calls as call_count,
                total_exec_time as total_time_ms
            FROM pg_stat_statements
            WHERE mean_exec_time > ${slow_query_threshold}
              AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
            ORDER BY mean_exec_time DESC
            LIMIT 5;
        "
        
        local top_queries_result
        top_queries_result=$(execute_sql_query "${top_slow_queries_query}" "${analytics_dbname}" 2>/dev/null || echo "")
        
        if [[ -n "${top_queries_result}" ]] && [[ "${top_queries_result}" != "Error executing query:"* ]]; then
            log_debug "${COMPONENT}: Top slow queries:\n${top_queries_result}"
        fi
    else
        # Fallback: Test query performance with sample queries
        log_debug "${COMPONENT}: pg_stat_statements not available, using fallback method"
        
        # Test common analytics queries
        local test_queries=(
            "SELECT COUNT(*) FROM notes;"
            "SELECT COUNT(*) FROM note_comments;"
            "SELECT COUNT(*) FROM notes_summary;"
        )
        
        for test_query in "${test_queries[@]}"; do
            local start_time
            start_time=$(date +%s%N 2>/dev/null || date +%s000)
            
            local result
            result=$(execute_sql_query "${test_query}" "${analytics_dbname}" 2>/dev/null || echo "")
            
            local end_time
            end_time=$(date +%s%N 2>/dev/null || date +%s000)
            local duration_ms=$(((end_time - start_time) / 1000000))
            
            if [[ -n "${result}" ]]; then
                queries_checked=$((queries_checked + 1))
                total_query_time=$((total_query_time + duration_ms))
                
                if [[ ${duration_ms} -gt ${max_query_time} ]]; then
                    max_query_time=${duration_ms}
                fi
                
                # Record metric for this query
                local query_hash
                query_hash=$(echo -n "${test_query}" | sha256sum | cut -d' ' -f1 | cut -c1-8)
                record_metric "${COMPONENT}" "query_time_ms" "${duration_ms}" "component=analytics,query_hash=${query_hash}"
                
                # Check against slow query threshold
                local slow_query_threshold="${ANALYTICS_SLOW_QUERY_THRESHOLD:-1000}"
                if [[ ${duration_ms} -gt ${slow_query_threshold} ]]; then
                    slow_query_count=$((slow_query_count + 1))
                    log_warning "${COMPONENT}: Slow query detected: ${duration_ms}ms (threshold: ${slow_query_threshold}ms)"
                    send_alert "WARNING" "${COMPONENT}" "Slow query detected: ${duration_ms}ms (query: ${test_query:0:50}...)"
                fi
            fi
        done
        
        # Calculate average
        if [[ ${queries_checked} -gt 0 ]]; then
            avg_query_time=$((total_query_time / queries_checked))
            record_metric "${COMPONENT}" "query_avg_time_ms" "${avg_query_time}" "component=analytics,source=test_queries"
            record_metric "${COMPONENT}" "query_max_time_ms" "${max_query_time}" "component=analytics,source=test_queries"
        fi
    fi
    
    # Check index usage (PostgreSQL-specific)
    local index_usage_query="
        SELECT 
            schemaname,
            tablename,
            indexname,
            idx_scan as index_scans,
            idx_tup_read as tuples_read,
            idx_tup_fetch as tuples_fetched
        FROM pg_stat_user_indexes
        WHERE schemaname = 'public'
          AND idx_scan = 0
        ORDER BY pg_relation_size(indexrelid) DESC
        LIMIT 10;
    "
    
    local unused_indexes_result
    unused_indexes_result=$(execute_sql_query "${index_usage_query}" "${analytics_dbname}" 2>/dev/null || echo "")
    
    if [[ -n "${unused_indexes_result}" ]] && [[ "${unused_indexes_result}" != "Error executing query:"* ]]; then
        local unused_index_count
        unused_index_count=$(echo "${unused_indexes_result}" | wc -l | tr -d '[:space:]' || echo "0")
        
        if [[ ${unused_index_count} -gt 0 ]]; then
            log_debug "${COMPONENT}: Found ${unused_index_count} potentially unused indexes"
            record_metric "${COMPONENT}" "unused_index_count" "${unused_index_count}" "component=analytics"
        fi
    fi
    
    # Record aggregate metrics
    if [[ ${queries_checked} -gt 0 ]]; then
        record_metric "${COMPONENT}" "queries_checked_count" "${queries_checked}" "component=analytics"
    fi
    
    if [[ ${slow_query_count} -gt 0 ]]; then
        record_metric "${COMPONENT}" "slow_query_count" "${slow_query_count}" "component=analytics"
    fi
    
    # Check average query time threshold
    local avg_query_time_threshold="${ANALYTICS_AVG_QUERY_TIME_THRESHOLD:-500}"
    if [[ ${avg_query_time} -gt ${avg_query_time_threshold} ]]; then
        log_warning "${COMPONENT}: Average query time (${avg_query_time}ms) exceeds threshold (${avg_query_time_threshold}ms)"
        send_alert "WARNING" "${COMPONENT}" "Average query time exceeded: ${avg_query_time}ms (threshold: ${avg_query_time_threshold}ms)"
    fi
    
    # Check max query time threshold
    local max_query_time_threshold="${ANALYTICS_MAX_QUERY_TIME_THRESHOLD:-5000}"
    if [[ ${max_query_time} -gt ${max_query_time_threshold} ]]; then
        log_warning "${COMPONENT}: Maximum query time (${max_query_time}ms) exceeds threshold (${max_query_time_threshold}ms)"
        send_alert "WARNING" "${COMPONENT}" "Maximum query time exceeded: ${max_query_time}ms (threshold: ${max_query_time_threshold}ms)"
    fi
    
    log_info "${COMPONENT}: Query performance check completed - Queries checked: ${queries_checked}, Slow: ${slow_query_count}, Avg: ${avg_query_time}ms, Max: ${max_query_time}ms"
    
    return 0
}

##
# Check storage growth
##
check_storage_growth() {
    log_info "${COMPONENT}: Starting storage growth check"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check storage growth - database connection failed"
        return 0
    fi
    
    # Check if analytics database is configured
    local analytics_dbname="${ANALYTICS_DBNAME:-${DBNAME}}"
    
    # Get database size (PostgreSQL-specific)
    local db_size_query="
        SELECT 
            pg_database.datname,
            pg_size_pretty(pg_database_size(pg_database.datname)) AS size,
            pg_database_size(pg_database.datname) AS size_bytes
        FROM pg_database
        WHERE datname = current_database();
    "
    
    local db_size_result
    db_size_result=$(execute_sql_query "${db_size_query}" "${analytics_dbname}" 2>/dev/null || echo "")
    
    local db_size_bytes=0
    local db_size_pretty="unknown"
    
    if [[ -n "${db_size_result}" ]] && [[ "${db_size_result}" != "Error executing query:"* ]]; then
        # Parse result (format: datname|size|size_bytes)
        db_size_pretty=$(echo "${db_size_result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "unknown")
        local db_size_str
        db_size_str=$(echo "${db_size_result}" | cut -d'|' -f3 | tr -d '[:space:]' || echo "0")
        
        if [[ -n "${db_size_str}" ]] && [[ "${db_size_str}" =~ ^[0-9]+$ ]]; then
            db_size_bytes=${db_size_str}
            
            # Record database size metric
            record_metric "${COMPONENT}" "database_size_bytes" "${db_size_bytes}" "component=analytics"
            
            log_info "${COMPONENT}: Database size: ${db_size_pretty} (${db_size_bytes} bytes)"
            
            # Check against database size threshold
            local db_size_threshold="${ANALYTICS_DB_SIZE_THRESHOLD:-107374182400}"
            if [[ ${db_size_bytes} -gt ${db_size_threshold} ]]; then
                log_warning "${COMPONENT}: Database size (${db_size_bytes} bytes) exceeds threshold (${db_size_threshold} bytes)"
                send_alert "WARNING" "${COMPONENT}" "Database size exceeded: ${db_size_pretty} (threshold: $(numfmt --to=iec-i --suffix=B "${db_size_threshold}" 2>/dev/null || echo "${db_size_threshold} bytes"))"
            fi
        fi
    fi
    
    # Get table sizes (PostgreSQL-specific)
    local table_sizes_query="
        SELECT 
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
            pg_total_relation_size(schemaname||'.'||tablename) AS size_bytes,
            pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
            pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
        LIMIT 20;
    "
    
    local table_sizes_result
    table_sizes_result=$(execute_sql_query "${table_sizes_query}" "${analytics_dbname}" 2>/dev/null || echo "")
    
    local total_table_size=0
    local largest_table_size=0
    local largest_table_name=""
    local tables_checked=0
    
    if [[ -n "${table_sizes_result}" ]] && [[ "${table_sizes_result}" != "Error executing query:"* ]]; then
        # Parse results line by line
        while IFS= read -r line; do
            if [[ -z "${line}" ]] || [[ "${line}" == "Error executing query:"* ]]; then
                continue
            fi
            
            # Parse line (format: schemaname|tablename|size|size_bytes|table_size|table_size_bytes)
            local table_name
            table_name=$(echo "${line}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "")
            local table_size_str
            table_size_str=$(echo "${line}" | cut -d'|' -f4 | tr -d '[:space:]' || echo "0")
            
            if [[ -n "${table_size_str}" ]] && [[ "${table_size_str}" =~ ^[0-9]+$ ]]; then
                local table_size=${table_size_str}
                total_table_size=$((total_table_size + table_size))
                tables_checked=$((tables_checked + 1))
                
                if [[ ${table_size} -gt ${largest_table_size} ]]; then
                    largest_table_size=${table_size}
                    largest_table_name=${table_name}
                fi
                
                # Record metric for individual table
                record_metric "${COMPONENT}" "table_size_bytes" "${table_size}" "component=analytics,table=${table_name}"
            fi
        done <<< "${table_sizes_result}"
        
        # Record aggregate metrics
        if [[ ${tables_checked} -gt 0 ]]; then
            record_metric "${COMPONENT}" "total_table_size_bytes" "${total_table_size}" "component=analytics"
            record_metric "${COMPONENT}" "largest_table_size_bytes" "${largest_table_size}" "component=analytics,table=${largest_table_name}"
            record_metric "${COMPONENT}" "tables_checked_count" "${tables_checked}" "component=analytics"
            
            log_info "${COMPONENT}: Total table size: $(numfmt --to=iec-i --suffix=B "${total_table_size}" 2>/dev/null || echo "${total_table_size} bytes"), Largest table: ${largest_table_name} ($(numfmt --to=iec-i --suffix=B "${largest_table_size}" 2>/dev/null || echo "${largest_table_size} bytes"))"
            
            # Check largest table size threshold
            local largest_table_threshold="${ANALYTICS_LARGEST_TABLE_SIZE_THRESHOLD:-10737418240}"
            if [[ ${largest_table_size} -gt ${largest_table_threshold} ]]; then
                log_warning "${COMPONENT}: Largest table size (${largest_table_size} bytes) exceeds threshold (${largest_table_threshold} bytes)"
                send_alert "WARNING" "${COMPONENT}" "Largest table size exceeded: ${largest_table_name} - $(numfmt --to=iec-i --suffix=B "${largest_table_size}" 2>/dev/null || echo "${largest_table_size} bytes") (threshold: $(numfmt --to=iec-i --suffix=B "${largest_table_threshold}" 2>/dev/null || echo "${largest_table_threshold} bytes"))"
            fi
        fi
    fi
    
    # Check disk space for database directory
    local db_data_dir
    db_data_dir=$(execute_sql_query "SHOW data_directory;" "${analytics_dbname}" 2>/dev/null | tr -d '[:space:]' || echo "")
    
    if [[ -n "${db_data_dir}" ]] && [[ -d "${db_data_dir}" ]]; then
        # Get disk usage percentage
        local disk_usage_percent
        disk_usage_percent=$(df -h "${db_data_dir}" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
        
        if [[ -n "${disk_usage_percent}" ]] && [[ "${disk_usage_percent}" =~ ^[0-9]+$ ]]; then
            local disk_available
            disk_available=$(df -h "${db_data_dir}" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
            
            record_metric "${COMPONENT}" "disk_usage_percent" "${disk_usage_percent}" "component=analytics,directory=database"
            
            log_info "${COMPONENT}: Disk usage for database directory: ${disk_usage_percent}% (Available: ${disk_available})"
            
            # Check against disk usage threshold
            local disk_threshold="${ANALYTICS_DISK_USAGE_THRESHOLD:-85}"
            if [[ ${disk_usage_percent} -ge ${disk_threshold} ]]; then
                log_warning "${COMPONENT}: Disk usage (${disk_usage_percent}%) exceeds threshold (${disk_threshold}%)"
                send_alert "WARNING" "${COMPONENT}" "High disk usage: ${disk_usage_percent}% (available: ${disk_available})"
            fi
        fi
    fi
    
    # Calculate growth rate (if we have historical data)
    # This would require storing previous sizes and comparing
    # For now, we'll just log current sizes for future comparison
    
    log_info "${COMPONENT}: Storage growth check completed - DB size: ${db_size_pretty}, Tables checked: ${tables_checked}, Total table size: $(numfmt --to=iec-i --suffix=B ${total_table_size} 2>/dev/null || echo "${total_table_size} bytes")"
    
    return 0
}

##
# Check data quality in DWH
##
check_data_quality() {
    log_info "${COMPONENT}: Starting data quality check"
    
    # TODO: Implement data quality check
    # This should check:
    # - Data completeness
    # - Data consistency
    # - Data validation results
    # - Data quality scores
    
    log_debug "${COMPONENT}: Data quality check not yet implemented"
    
    return 0
}

##
# Check component health status
##
check_health_status() {
    log_info "${COMPONENT}: Starting health status check"
    
    # Check database connection
    if ! check_database_connection; then
        log_error "${COMPONENT}: Database connection failed"
        send_alert "CRITICAL" "${COMPONENT}" "Database connection failed"
        return 1
    fi
    
    # Check if analytics database is accessible
    # TODO: Add specific analytics database connection check
    
    log_info "${COMPONENT}: Health check passed"
    return 0
}

##
# Check performance metrics
##
check_performance() {
    log_info "${COMPONENT}: Starting performance checks"
    
    check_etl_processing_duration
    check_query_performance
    check_storage_growth
    
    return 0
}

##
# Check data quality metrics
##
check_data_quality_metrics() {
    log_info "${COMPONENT}: Starting data quality checks"
    
    check_data_warehouse_freshness
    check_data_quality
    
    return 0
}

##
# Run all checks
##
run_all_checks() {
    log_info "${COMPONENT}: Running all monitoring checks"
    
    check_health_status
    check_etl_job_execution_status
    check_data_warehouse_freshness
    check_etl_processing_duration
    check_data_mart_update_status
    check_query_performance
    check_storage_growth
    check_data_quality
    
    return 0
}

##
# Main function
##
main() {
    local check_type="all"
    # shellcheck disable=SC2034
    local verbose=false
    # shellcheck disable=SC2034
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check)
                check_type="${2:-all}"
                shift 2
                ;;
            -v|--verbose)
                # shellcheck disable=SC2034
                verbose=true
                shift
                ;;
            -d|--dry-run)
                # shellcheck disable=SC2034
                dry_run=true
                export DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose logging if requested
    if [[ "${verbose}" == "true" ]]; then
        export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    fi
    
    # Load configuration
    if ! load_monitoring_config; then
        log_error "${COMPONENT}: Failed to load monitoring configuration"
        exit 1
    fi
    
    # Check if analytics monitoring is enabled
    if [[ "${ANALYTICS_ENABLED:-false}" != "true" ]]; then
        log_info "${COMPONENT}: Analytics monitoring is disabled"
        exit 0
    fi
    
    # Initialize alerting
    init_alerting
    
    # Run requested checks
    case "${check_type}" in
        health)
            check_health_status
            ;;
        performance)
            check_performance
            ;;
        data-quality)
            check_data_quality_metrics
            ;;
        etl-status)
            check_etl_job_execution_status
            ;;
        data-freshness)
            check_data_warehouse_freshness
            ;;
        storage)
            check_storage_growth
            ;;
        query-performance)
            check_query_performance
            ;;
        all)
            run_all_checks
            ;;
        *)
            log_error "Unknown check type: ${check_type}"
            usage
            exit 1
            ;;
    esac
    
    log_info "${COMPONENT}: Monitoring checks completed"
    return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

