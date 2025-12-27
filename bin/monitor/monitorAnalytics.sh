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
    
    # TODO: Implement data mart update status check
    # This should check:
    # - Data mart update timestamps
    # - Update success/failure status
    # - Update frequency
    
    log_debug "${COMPONENT}: Data mart update status check not yet implemented"
    
    return 0
}

##
# Check query performance
##
check_query_performance() {
    log_info "${COMPONENT}: Starting query performance check"
    
    # TODO: Implement query performance check
    # This should check:
    # - Slow queries
    # - Query execution times
    # - Query frequency
    # - Index usage
    
    log_debug "${COMPONENT}: Query performance check not yet implemented"
    
    return 0
}

##
# Check storage growth
##
check_storage_growth() {
    log_info "${COMPONENT}: Starting storage growth check"
    
    # TODO: Implement storage growth check
    # This should check:
    # - Database size
    # - Table sizes
    # - Growth rate
    # - Storage capacity
    
    log_debug "${COMPONENT}: Storage growth check not yet implemented"
    
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

