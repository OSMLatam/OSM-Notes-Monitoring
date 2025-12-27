#!/usr/bin/env bash
#
# Ingestion Monitoring Script
# Monitors the OSM-Notes-Ingestion component health and performance
#
# Version: 1.0.0
# Date: 2025-12-24
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

# Initialize logging
init_logging "${LOG_DIR}/ingestion.log" "monitorIngestion"

# Component name
# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]] || [[ "${TEST_MODE:-false}" == "true" ]]; then
    COMPONENT="${COMPONENT:-INGESTION}"
fi
readonly COMPONENT

##
# Show usage
##
usage() {
    cat << EOF
Ingestion Monitoring Script

Monitors the OSM-Notes-Ingestion component for health, performance, and data quality.

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
    execution-status Check script execution status
    latency         Check processing latency
    error-rate      Check error rate from logs
    disk-space      Check disk space usage
    api-download    Check API download status
    all             Run all checks (default)

Examples:
    # Run all checks
    $0

    # Run only health check
    $0 --check health

    # Dry run (no database writes)
    $0 --dry-run

EOF
}

##
# Check script execution status
##
check_script_execution_status() {
    log_info "${COMPONENT}: Starting script execution status check"
    
    local scripts_to_check=(
        "processAPINotes.sh"
        "processPlanetNotes.sh"
        "notesCheckVerifier.sh"
        "processCheckPlanetNotes.sh"
        "analyzeDatabasePerformance.sh"
    )
    
    local scripts_dir="${INGESTION_REPO_PATH}/bin"
    local scripts_found=0
    local scripts_executable=0
    local scripts_running=0
    
    for script_name in "${scripts_to_check[@]}"; do
        local script_path="${scripts_dir}/${script_name}"
        
        # Check if script exists
        if [[ ! -f "${script_path}" ]]; then
            log_debug "${COMPONENT}: Script not found: ${script_name}"
            continue
        fi
        
        scripts_found=$((scripts_found + 1))
        
        # Check if script is executable
        if [[ -x "${script_path}" ]]; then
            scripts_executable=$((scripts_executable + 1))
        else
            log_warning "${COMPONENT}: Script exists but not executable: ${script_name}"
        fi
        
        # Check if script process is running
        local script_basename
        script_basename=$(basename "${script_path}")
        if pgrep -f "${script_basename}" > /dev/null 2>&1; then
            scripts_running=$((scripts_running + 1))
            log_info "${COMPONENT}: Script is running: ${script_name}"
            
            # Get process info
            local pid
            pid=$(pgrep -f "${script_basename}" | head -1)
            local runtime
            runtime=$(ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ' || echo "unknown")
            log_debug "${COMPONENT}: Script ${script_name} PID: ${pid}, Runtime: ${runtime}"
        fi
    done
    
    # Record metrics
    record_metric "${COMPONENT}" "scripts_found" "${scripts_found}" "component=ingestion"
    record_metric "${COMPONENT}" "scripts_executable" "${scripts_executable}" "component=ingestion"
    record_metric "${COMPONENT}" "scripts_running" "${scripts_running}" "component=ingestion"
    
    log_info "${COMPONENT}: Script execution status - Found: ${scripts_found}, Executable: ${scripts_executable}, Running: ${scripts_running}"
    
    # Check against thresholds
    local scripts_found_threshold="${INGESTION_SCRIPTS_FOUND_THRESHOLD:-3}"
    if [[ ${scripts_found} -lt ${scripts_found_threshold} ]]; then
        log_warning "${COMPONENT}: Scripts found (${scripts_found}) below threshold (${scripts_found_threshold})"
        send_alert "WARNING" "${COMPONENT}" "Low number of scripts found: ${scripts_found} (threshold: ${scripts_found_threshold})"
    fi
    
    if [[ ${scripts_executable} -lt ${scripts_found} ]]; then
        log_warning "${COMPONENT}: Some scripts are not executable (${scripts_executable}/${scripts_found})"
        send_alert "WARNING" "${COMPONENT}" "Scripts executable count (${scripts_executable}) is less than scripts found (${scripts_found})"
    fi
    
    # Check last execution time from log files
    check_last_execution_time
    
    return 0
}

##
# Check error rate from log files
##
check_error_rate() {
    log_info "${COMPONENT}: Starting error rate check"
    
    local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
    
    if [[ ! -d "${ingestion_log_dir}" ]]; then
        log_warning "${COMPONENT}: Log directory not found: ${ingestion_log_dir}"
        return 0
    fi
    
    # Find recent log files (last 24 hours)
    local log_files
    mapfile -t log_files < <(find "${ingestion_log_dir}" -name "*.log" -type f -mtime -1 2>/dev/null | head -10)
    
    if [[ ${#log_files[@]} -eq 0 ]]; then
        log_warning "${COMPONENT}: No recent log files found for error rate analysis"
        return 0
    fi
    
    local total_lines=0
    local error_lines=0
    local warning_lines=0
    local info_lines=0
    
    # Parse log files for error patterns
    for log_file in "${log_files[@]}"; do
        # Count lines by log level
        local file_errors
        file_errors=$(grep -cE "\[ERROR\]|ERROR|error|failed|failure" "${log_file}" 2>/dev/null || echo "0")
        # Ensure numeric value (remove any whitespace and non-numeric characters)
        file_errors=$(echo "${file_errors}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
        file_errors=$((file_errors + 0))
        
        local file_warnings
        file_warnings=$(grep -cE "\[WARNING\]|WARNING|warning" "${log_file}" 2>/dev/null || echo "0")
        # Ensure numeric value (remove any whitespace and non-numeric characters)
        file_warnings=$(echo "${file_warnings}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
        file_warnings=$((file_warnings + 0))
        
        local file_info
        file_info=$(grep -cE "\[INFO\]|INFO|info" "${log_file}" 2>/dev/null || echo "0")
        # Ensure numeric value (remove any whitespace and non-numeric characters)
        file_info=$(echo "${file_info}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
        file_info=$((file_info + 0))
        
        local file_total
        file_total=$(wc -l < "${log_file}" 2>/dev/null || echo "0")
        # Ensure numeric value (remove any whitespace and non-numeric characters)
        file_total=$(echo "${file_total}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
        file_total=$((file_total + 0))
        
        error_lines=$((error_lines + file_errors))
        warning_lines=$((warning_lines + file_warnings))
        info_lines=$((info_lines + file_info))
        total_lines=$((total_lines + file_total))
    done
    
    if [[ ${total_lines} -eq 0 ]]; then
        log_info "${COMPONENT}: No log lines found for error rate analysis"
        return 0
    fi
    
    # Calculate error rate percentage
    local error_rate=0
    if [[ ${total_lines} -gt 0 ]]; then
        error_rate=$((error_lines * 100 / total_lines))
    fi
    
    local warning_rate=0
    if [[ ${total_lines} -gt 0 ]]; then
        warning_rate=$((warning_lines * 100 / total_lines))
    fi
    
    log_info "${COMPONENT}: Error rate analysis - Total: ${total_lines}, Errors: ${error_lines} (${error_rate}%), Warnings: ${warning_lines} (${warning_rate}%)"
    
    # Record metrics
    record_metric "${COMPONENT}" "error_count" "${error_lines}" "component=ingestion"
    record_metric "${COMPONENT}" "warning_count" "${warning_lines}" "component=ingestion"
    record_metric "${COMPONENT}" "error_rate_percent" "${error_rate}" "component=ingestion"
    record_metric "${COMPONENT}" "warning_rate_percent" "${warning_rate}" "component=ingestion"
    record_metric "${COMPONENT}" "log_lines_total" "${total_lines}" "component=ingestion"
    
    # Check error count threshold
    local error_count_threshold="${INGESTION_ERROR_COUNT_THRESHOLD:-1000}"
    if [[ ${error_lines} -gt ${error_count_threshold} ]]; then
        log_warning "${COMPONENT}: Error count (${error_lines}) exceeds threshold (${error_count_threshold})"
        send_alert "WARNING" "${COMPONENT}" "High error count detected: ${error_lines} errors in 24h (threshold: ${error_count_threshold})"
    fi
    
    # Check warning count threshold
    local warning_count_threshold="${INGESTION_WARNING_COUNT_THRESHOLD:-2000}"
    if [[ ${warning_lines} -gt ${warning_count_threshold} ]]; then
        log_warning "${COMPONENT}: Warning count (${warning_lines}) exceeds threshold (${warning_count_threshold})"
        send_alert "INFO" "${COMPONENT}" "High warning count detected: ${warning_lines} warnings in 24h (threshold: ${warning_count_threshold})"
    fi
    
    # Check error rate threshold
    local max_error_rate="${INGESTION_MAX_ERROR_RATE:-5}"
    if [[ ${error_rate} -gt ${max_error_rate} ]]; then
        log_warning "${COMPONENT}: Error rate (${error_rate}%) exceeds threshold (${max_error_rate}%)"
        send_alert "WARNING" "${COMPONENT}" "High error rate detected: ${error_rate}% (threshold: ${max_error_rate}%, errors: ${error_lines}/${total_lines})"
        return 1
    fi
    
    # Check warning rate threshold
    local warning_rate_threshold="${INGESTION_WARNING_RATE_THRESHOLD:-15}"
    if [[ ${warning_rate} -gt ${warning_rate_threshold} ]]; then
        log_warning "${COMPONENT}: Warning rate (${warning_rate}%) exceeds threshold (${warning_rate_threshold}%)"
        send_alert "WARNING" "${COMPONENT}" "High warning rate detected: ${warning_rate}% (threshold: ${warning_rate_threshold}%, warnings: ${warning_lines}/${total_lines})"
    fi
    
    # Check for recent error spikes (errors in last hour)
    check_recent_error_spikes
    
    log_info "${COMPONENT}: Error rate check passed - Rate: ${error_rate}%"
    return 0
}

##
# Check for recent error spikes
##
check_recent_error_spikes() {
    log_debug "${COMPONENT}: Checking for recent error spikes"
    
    local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
    
    # Find log files modified in last hour
    local recent_logs
    mapfile -t recent_logs < <(find "${ingestion_log_dir}" -name "*.log" -type f -mmin -60 2>/dev/null)
    
    if [[ ${#recent_logs[@]} -eq 0 ]]; then
        log_debug "${COMPONENT}: No recent log files found for spike detection"
        return 0
    fi
    
    local recent_errors=0
    local recent_total=0
    
    for log_file in "${recent_logs[@]}"; do
        # Count errors in last hour (check file modification time and content)
        local file_errors
        file_errors=$(grep -cE "\[ERROR\]|ERROR|error|failed|failure" "${log_file}" 2>/dev/null || echo "0")
        # Ensure numeric value (remove any whitespace and non-numeric characters)
        file_errors=$(echo "${file_errors}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
        file_errors=$((file_errors + 0))
        
        local file_total
        file_total=$(wc -l < "${log_file}" 2>/dev/null || echo "0")
        # Ensure numeric value (remove any whitespace and non-numeric characters)
        file_total=$(echo "${file_total}" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo "0")
        file_total=$((file_total + 0))
        
        recent_errors=$((recent_errors + file_errors))
        recent_total=$((recent_total + file_total))
    done
    
    if [[ ${recent_total} -gt 0 ]]; then
        local recent_error_rate=$((recent_errors * 100 / recent_total))
        
        log_debug "${COMPONENT}: Recent error rate (last hour): ${recent_error_rate}% (${recent_errors}/${recent_total})"
        record_metric "${COMPONENT}" "recent_error_rate_percent" "${recent_error_rate}" "component=ingestion,period=1hour"
        
        # Alert if spike detected (error rate > 2x threshold)
        local max_error_rate="${INGESTION_MAX_ERROR_RATE:-5}"
        local spike_threshold=$((max_error_rate * 2))
        
        if [[ ${recent_error_rate} -gt ${spike_threshold} ]]; then
            log_warning "${COMPONENT}: Error spike detected in last hour: ${recent_error_rate}%"
            send_alert "WARNING" "${COMPONENT}" "Error spike detected: ${recent_error_rate}% in last hour (${recent_errors} errors)"
        fi
    fi
    
    return 0
}

##
# Check disk space usage
##
check_disk_space() {
    log_info "${COMPONENT}: Starting disk space check"
    
    # Check if ingestion repository exists
    if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        log_error "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
        return 1
    fi
    
    # Directories to check
    local directories_to_check=(
        "${INGESTION_REPO_PATH}"
        "${INGESTION_REPO_PATH}/logs"
        "${LOG_DIR}"
        "${TMP_DIR}"
    )
    
    local total_issues=0
    
    # Check each directory
    for dir in "${directories_to_check[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            log_debug "${COMPONENT}: Directory does not exist: ${dir}"
            continue
        fi
        
        # Get disk usage percentage
        local usage_percent
        usage_percent=$(df -h "${dir}" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
        
        if [[ -z "${usage_percent}" ]] || [[ "${usage_percent}" == "0" ]]; then
            log_debug "${COMPONENT}: Could not determine disk usage for: ${dir}"
            continue
        fi
        
        # Get available space
        local available_space
        available_space=$(df -h "${dir}" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
        
        # Get total space
        local total_space
        total_space=$(df -h "${dir}" 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
        
        # Get used space
        local used_space
        used_space=$(df -h "${dir}" 2>/dev/null | tail -1 | awk '{print $3}' || echo "unknown")
        
        log_info "${COMPONENT}: Disk usage for ${dir}: ${usage_percent}% (Used: ${used_space}, Available: ${available_space}, Total: ${total_space})"
        
        # Record metrics
        local dir_name
        dir_name=$(basename "${dir}")
        record_metric "${COMPONENT}" "disk_usage_percent" "${usage_percent}" "component=ingestion,directory=${dir_name}"
        
        # Check against threshold
        local disk_threshold="${INFRASTRUCTURE_DISK_THRESHOLD:-90}"
        
        if [[ ${usage_percent} -ge ${disk_threshold} ]]; then
            log_warning "${COMPONENT}: Disk usage (${usage_percent}%) exceeds threshold (${disk_threshold}%) for ${dir}"
            send_alert "WARNING" "${COMPONENT}" "High disk usage: ${usage_percent}% on ${dir} (threshold: ${disk_threshold}%, available: ${available_space})"
            total_issues=$((total_issues + 1))
        elif [[ ${usage_percent} -ge $((disk_threshold - 10)) ]]; then
            log_warning "${COMPONENT}: Disk usage (${usage_percent}%) approaching threshold (${disk_threshold}%) for ${dir}"
        fi
    done
    
    # Check overall system disk usage
    check_system_disk_usage
    
    if [[ ${total_issues} -gt 0 ]]; then
        log_warning "${COMPONENT}: Disk space check found ${total_issues} issues"
        return 1
    fi
    
    log_info "${COMPONENT}: Disk space check passed"
    return 0
}

##
# Check system-wide disk usage
##
check_system_disk_usage() {
    log_debug "${COMPONENT}: Checking system-wide disk usage"
    
    # Get root filesystem usage
    local root_usage
    root_usage=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
    
    if [[ -n "${root_usage}" ]] && [[ "${root_usage}" != "0" ]]; then
        local root_available
        root_available=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
        
        log_debug "${COMPONENT}: Root filesystem usage: ${root_usage}% (Available: ${root_available})"
        record_metric "${COMPONENT}" "disk_usage_percent" "${root_usage}" "component=ingestion,directory=root"
        
        local disk_threshold="${INFRASTRUCTURE_DISK_THRESHOLD:-90}"
        
        if [[ ${root_usage} -ge ${disk_threshold} ]]; then
            log_warning "${COMPONENT}: Root filesystem usage (${root_usage}%) exceeds threshold (${disk_threshold}%)"
            send_alert "WARNING" "${COMPONENT}" "High root filesystem usage: ${root_usage}% (available: ${root_available})"
        fi
    fi
    
    return 0
}

##
# Check last execution time from log files
##
check_last_execution_time() {
    local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
    
    if [[ ! -d "${ingestion_log_dir}" ]]; then
        log_debug "${COMPONENT}: Log directory not found: ${ingestion_log_dir}"
        return 0
    fi
    
    # Find most recent log file
    local latest_log
    latest_log=$(find "${ingestion_log_dir}" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "${latest_log}" ]]; then
        log_warning "${COMPONENT}: No log files found"
        return 0
    fi
    
    # Get modification time
    local log_mtime
    log_mtime=$(stat -c %Y "${latest_log}" 2>/dev/null || stat -f %m "${latest_log}" 2>/dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    local age_seconds=$((current_time - log_mtime))
    local age_hours=$((age_seconds / 3600))
    
    log_info "${COMPONENT}: Latest log file: $(basename "${latest_log}"), Age: ${age_hours} hours"
    
    record_metric "${COMPONENT}" "last_log_age_hours" "${age_hours}" "component=ingestion"
    
    # Alert if log is too old
    local log_age_threshold="${INGESTION_LAST_LOG_AGE_THRESHOLD:-24}"
    if [[ ${age_hours} -gt ${log_age_threshold} ]]; then
        log_warning "${COMPONENT}: Log file is older than threshold (${age_hours} hours, threshold: ${log_age_threshold} hours)"
        send_alert "WARNING" "${COMPONENT}" "No recent activity detected: last log is ${age_hours} hours old (threshold: ${log_age_threshold} hours)"
    fi
    
    return 0
}

##
# Check ingestion component health
##
check_ingestion_health() {
    log_info "${COMPONENT}: Starting health check"
    
    local health_status="unknown"
    local error_message=""
    
    # Check if ingestion repository exists
    if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        health_status="down"
        error_message="Ingestion repository not found: ${INGESTION_REPO_PATH}"
        log_error "${COMPONENT}: ${error_message}"
        record_metric "${COMPONENT}" "health_status" "0" "component=ingestion"
        send_alert "CRITICAL" "${COMPONENT}" "Health check failed: ${error_message}"
        return 1
    fi
    
    # Check script execution status
    check_script_execution_status
    
    # Check if ingestion log files exist and are recent
    local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
    if [[ -d "${ingestion_log_dir}" ]]; then
        local latest_log
        latest_log=$(find "${ingestion_log_dir}" -name "*.log" -type f -mtime -1 2>/dev/null | head -1)
        
        if [[ -z "${latest_log}" ]]; then
            health_status="degraded"
            error_message="No recent log files found (older than 1 day)"
            log_warning "${COMPONENT}: ${error_message}"
            record_metric "${COMPONENT}" "health_status" "1" "component=ingestion"
            send_alert "WARNING" "${COMPONENT}" "Health check warning: ${error_message}"
            return 0
        fi
    fi
    
    # Check if processCheckPlanetNotes.sh exists and can be executed
    local planet_check_script="${INGESTION_REPO_PATH}/bin/monitor/processCheckPlanetNotes.sh"
    if [[ -f "${planet_check_script}" ]]; then
        if [[ ! -x "${planet_check_script}" ]]; then
            log_warning "${COMPONENT}: processCheckPlanetNotes.sh exists but is not executable"
        else
            log_debug "${COMPONENT}: processCheckPlanetNotes.sh is available and executable"
        fi
    fi
    
    # If we get here, component appears healthy
    # shellcheck disable=SC2034
    health_status="healthy"
    log_info "${COMPONENT}: Health check passed"
    record_metric "${COMPONENT}" "health_status" "1" "component=ingestion"
    
    return 0
}

##
# Check database connection performance
##
check_database_connection_performance() {
    log_debug "${COMPONENT}: Checking database connection performance"
    
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Database connection check failed"
        return 1
    fi
    
    # Measure connection time
    local start_time
    start_time=$(date +%s%N 2>/dev/null || date +%s000)
    
    # Simple query to test connection speed
    local test_query="SELECT 1;"
    execute_sql_query "${test_query}" > /dev/null 2>&1
    
    local end_time
    end_time=$(date +%s%N 2>/dev/null || date +%s000)
    local duration_ms=$(((end_time - start_time) / 1000000))
    
    log_debug "${COMPONENT}: Database connection time: ${duration_ms}ms"
    record_metric "${COMPONENT}" "db_connection_time_ms" "${duration_ms}" "component=ingestion"
    
    # Alert if connection is slow (> 1000ms)
    if [[ ${duration_ms} -gt 1000 ]]; then
        log_warning "${COMPONENT}: Slow database connection: ${duration_ms}ms"
        send_alert "WARNING" "${COMPONENT}" "Slow database connection: ${duration_ms}ms"
    fi
    
    return 0
}

##
# Check database query performance
##
check_database_query_performance() {
    log_debug "${COMPONENT}: Checking database query performance"
    
    if ! check_database_connection; then
        return 1
    fi
    
    # Test query performance with a simple count query
    local test_query="SELECT COUNT(*) FROM notes;"
    
    local start_time
    start_time=$(date +%s%N 2>/dev/null || date +%s000)
    
    local result
    result=$(execute_sql_query "${test_query}" 2>/dev/null || echo "")
    
    local end_time
    end_time=$(date +%s%N 2>/dev/null || date +%s000)
    local duration_ms=$(((end_time - start_time) / 1000000))
    
    if [[ -n "${result}" ]]; then
        log_debug "${COMPONENT}: Query performance test - Duration: ${duration_ms}ms, Result: ${result}"
        record_metric "${COMPONENT}" "db_query_time_ms" "${duration_ms}" "component=ingestion,query=count_notes"
        
        # Check against slow query threshold
        local slow_query_threshold="${PERFORMANCE_SLOW_QUERY_THRESHOLD:-1000}"
        
        if [[ ${duration_ms} -gt ${slow_query_threshold} ]]; then
            log_warning "${COMPONENT}: Slow query detected: ${duration_ms}ms (threshold: ${slow_query_threshold}ms)"
            send_alert "WARNING" "${COMPONENT}" "Slow query detected: ${duration_ms}ms"
        fi
    fi
    
    return 0
}

##
# Check database connection pool
##
check_database_connections() {
    log_debug "${COMPONENT}: Checking database connections"
    
    if ! check_database_connection; then
        return 1
    fi
    
    # Query to check active connections
    # This is PostgreSQL-specific
    local connections_query="
        SELECT 
            count(*) as total_connections,
            count(*) FILTER (WHERE state = 'active') as active_connections,
            count(*) FILTER (WHERE state = 'idle') as idle_connections
        FROM pg_stat_activity
        WHERE datname = current_database();
    "
    
    local result
    result=$(execute_sql_query "${connections_query}" 2>/dev/null || echo "")
    
    if [[ -n "${result}" ]]; then
        log_debug "${COMPONENT}: Database connections: ${result}"
        # Parse result and record metrics if needed
        # Format: total_connections|active_connections|idle_connections
    fi
    
    return 0
}

##
# Check database table sizes and growth
##
check_database_table_sizes() {
    log_debug "${COMPONENT}: Checking database table sizes"
    
    if ! check_database_connection; then
        return 1
    fi
    
    # Query to get table sizes (PostgreSQL-specific)
    local size_query="
        SELECT 
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
            pg_total_relation_size(schemaname||'.'||tablename) AS size_bytes
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
        LIMIT 10;
    "
    
    local result
    result=$(execute_sql_query "${size_query}" 2>/dev/null || echo "")
    
    if [[ -n "${result}" ]]; then
        log_debug "${COMPONENT}: Database table sizes:\n${result}"
        # Could parse and record individual table sizes if needed
    fi
    
    return 0
}

##
# Check ingestion performance metrics using analyzeDatabasePerformance.sh
##
check_ingestion_performance() {
    log_info "${COMPONENT}: Starting database performance check"
    
    # Check database connection performance
    check_database_connection_performance
    
    # Check query performance
    check_database_query_performance
    
    # Check database connections
    check_database_connections
    
    # Check table sizes
    check_database_table_sizes
    
    # Run analyzeDatabasePerformance.sh if available
    if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        log_error "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
        return 1
    fi
    
    # Path to analyzeDatabasePerformance.sh
    local perf_script="${INGESTION_REPO_PATH}/bin/monitor/analyzeDatabasePerformance.sh"
    
    if [[ -f "${perf_script}" ]]; then
        log_info "${COMPONENT}: Running analyzeDatabasePerformance.sh"
        
        # Run the performance analysis script
        local start_time
        start_time=$(date +%s)
        
        local exit_code=0
        local output
        output=$(cd "${INGESTION_REPO_PATH}" && bash "${perf_script}" 2>&1) || exit_code=$?
        
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Log the output
        log_debug "${COMPONENT}: analyzeDatabasePerformance.sh output:\n${output}"
        
        # Check exit code
        if [[ ${exit_code} -eq 0 ]]; then
            log_info "${COMPONENT}: Performance analysis passed (duration: ${duration}s)"
            record_metric "${COMPONENT}" "performance_check_status" "1" "component=ingestion,check=analyzeDatabasePerformance"
            record_metric "${COMPONENT}" "performance_check_duration" "${duration}" "component=ingestion,check=analyzeDatabasePerformance"
            
            # Parse output for performance metrics
            # Look for PASS/FAIL/WARNING patterns
            local pass_count
            pass_count=$(echo "${output}" | grep -c "PASS\|✓" || echo "0")
            local fail_count
            fail_count=$(echo "${output}" | grep -c "FAIL\|✗" || echo "0")
            local warning_count
            warning_count=$(echo "${output}" | grep -c "WARNING\|⚠" || echo "0")
            
            record_metric "${COMPONENT}" "performance_check_passes" "${pass_count}" "component=ingestion"
            record_metric "${COMPONENT}" "performance_check_failures" "${fail_count}" "component=ingestion"
            record_metric "${COMPONENT}" "performance_check_warnings" "${warning_count}" "component=ingestion"
            
            # Check performance check duration threshold
            local perf_duration_threshold="${INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD:-300}"
            if [[ ${duration} -gt ${perf_duration_threshold} ]]; then
                log_warning "${COMPONENT}: Performance check duration (${duration}s) exceeds threshold (${perf_duration_threshold}s)"
                send_alert "WARNING" "${COMPONENT}" "Performance check took too long: ${duration}s (threshold: ${perf_duration_threshold}s)"
            fi
            
            # Check performance check failures (any failure triggers alert)
            if [[ ${fail_count} -gt 0 ]]; then
                log_warning "${COMPONENT}: Performance check found ${fail_count} failures"
                send_alert "WARNING" "${COMPONENT}" "Performance check found ${fail_count} failures, ${warning_count} warnings"
            fi
            
            # Check performance check warnings threshold
            local perf_warnings_threshold="${INGESTION_PERFORMANCE_CHECK_WARNINGS_THRESHOLD:-10}"
            if [[ ${warning_count} -gt ${perf_warnings_threshold} ]]; then
                log_warning "${COMPONENT}: Performance check warnings (${warning_count}) exceeds threshold (${perf_warnings_threshold})"
                send_alert "WARNING" "${COMPONENT}" "Performance check found ${warning_count} warnings (threshold: ${perf_warnings_threshold})"
            elif [[ ${warning_count} -gt 0 ]]; then
                log_warning "${COMPONENT}: Performance check found ${warning_count} warnings"
            fi
        else
            log_error "${COMPONENT}: Performance analysis failed (exit_code: ${exit_code}, duration: ${duration}s)"
            record_metric "${COMPONENT}" "performance_check_status" "0" "component=ingestion,check=analyzeDatabasePerformance"
            record_metric "${COMPONENT}" "performance_check_duration" "${duration}" "component=ingestion,check=analyzeDatabasePerformance"
            send_alert "ERROR" "${COMPONENT}" "Performance analysis failed: exit_code=${exit_code}"
        fi
    else
        log_warning "${COMPONENT}: analyzeDatabasePerformance.sh not found: ${perf_script}"
        log_info "${COMPONENT}: Skipping script-based performance check (script not available)"
    fi
    
    log_info "${COMPONENT}: Database performance check completed"
    return 0
}

##
# Check data completeness
##
check_data_completeness() {
    log_debug "${COMPONENT}: Checking data completeness"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check data completeness - database connection failed"
        return 0
    fi
    
    # Query to check for missing or null data
    # This is a placeholder - actual queries depend on database schema
    local completeness_query="
        SELECT 
            COUNT(*) as total_notes,
            COUNT(*) FILTER (WHERE id IS NULL) as null_ids,
            COUNT(*) FILTER (WHERE created_at IS NULL) as null_dates
        FROM notes
        LIMIT 1;
    "
    
    # Try to execute query (may fail if table doesn't exist or schema differs)
    local result
    result=$(execute_sql_query "${completeness_query}" 2>/dev/null || echo "")
    
    if [[ -n "${result}" ]]; then
        log_debug "${COMPONENT}: Data completeness check result: ${result}"
        # Parse and record metrics if needed
    fi
    
    return 0
}

##
# Check data freshness
##
check_data_freshness() {
    log_debug "${COMPONENT}: Checking data freshness"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check data freshness - database connection failed"
        return 0
    fi
    
    # Query to check last update time
    # This is a placeholder - actual queries depend on database schema
    local freshness_query="
        SELECT 
            EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) as freshness_seconds,
            COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') as recent_updates
        FROM notes
        LIMIT 1;
    "
    
    # Try to execute query
    local result
    result=$(execute_sql_query "${freshness_query}" 2>/dev/null || echo "")
    
    if [[ -n "${result}" ]]; then
        log_debug "${COMPONENT}: Data freshness check result: ${result}"
        
        # Parse result (format: freshness_seconds|recent_updates)
        local freshness_seconds
        freshness_seconds=$(echo "${result}" | cut -d'|' -f1 | tr -d '[:space:]' || echo "")
        local recent_updates
        recent_updates=$(echo "${result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "")
        
        if [[ -n "${freshness_seconds}" ]] && [[ "${freshness_seconds}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            log_debug "${COMPONENT}: Data freshness: ${freshness_seconds} seconds, Recent updates: ${recent_updates}"
            record_metric "${COMPONENT}" "data_freshness_seconds" "${freshness_seconds}" "component=ingestion"
            
            # Check against threshold
            local freshness_threshold="${INGESTION_DATA_FRESHNESS_THRESHOLD:-3600}"
            if (( $(echo "${freshness_seconds} > ${freshness_threshold}" | bc -l 2>/dev/null || echo "0") )); then
                log_warning "${COMPONENT}: Data freshness (${freshness_seconds}s) exceeds threshold (${freshness_threshold}s)"
                send_alert "WARNING" "${COMPONENT}" "Data freshness exceeded: ${freshness_seconds}s (threshold: ${freshness_threshold}s)"
            fi
        fi
        
        if [[ -n "${recent_updates}" ]] && [[ "${recent_updates}" =~ ^[0-9]+$ ]]; then
            record_metric "${COMPONENT}" "recent_updates_count" "${recent_updates}" "component=ingestion,period=1hour"
        fi
    fi
    
    return 0
}

##
# Check ingestion data quality using notesCheckVerifier.sh
##
check_ingestion_data_quality() {
    log_info "${COMPONENT}: Starting data quality check"
    
    # Check if ingestion repository exists
    if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        log_error "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
        return 1
    fi
    
    local quality_score=100
    local issues_found=0
    
    # Run notesCheckVerifier.sh if available
    local verifier_script="${INGESTION_REPO_PATH}/bin/monitor/notesCheckVerifier.sh"
    
    if [[ -f "${verifier_script}" ]]; then
        log_info "${COMPONENT}: Running notesCheckVerifier.sh"
        
        # Run the verifier script
        local start_time
        start_time=$(date +%s)
        
        local exit_code=0
        local output
        output=$(cd "${INGESTION_REPO_PATH}" && bash "${verifier_script}" 2>&1) || exit_code=$?
        
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Log the output
        log_debug "${COMPONENT}: notesCheckVerifier.sh output:\n${output}"
        
        # Check exit code
        if [[ ${exit_code} -eq 0 ]]; then
            log_info "${COMPONENT}: notesCheckVerifier check passed (duration: ${duration}s)"
            record_metric "${COMPONENT}" "data_quality_check_status" "1" "component=ingestion,check=notesCheckVerifier"
            record_metric "${COMPONENT}" "data_quality_check_duration" "${duration}" "component=ingestion,check=notesCheckVerifier"
            
            # Check data quality check duration threshold
            local quality_duration_threshold="${INGESTION_DATA_QUALITY_CHECK_DURATION_THRESHOLD:-600}"
            if [[ ${duration} -gt ${quality_duration_threshold} ]]; then
                log_warning "${COMPONENT}: Data quality check duration (${duration}s) exceeds threshold (${quality_duration_threshold}s)"
                send_alert "WARNING" "${COMPONENT}" "Data quality check took too long: ${duration}s (threshold: ${quality_duration_threshold}s)"
            fi
        else
            log_error "${COMPONENT}: notesCheckVerifier check failed (exit_code: ${exit_code}, duration: ${duration}s)"
            record_metric "${COMPONENT}" "data_quality_check_status" "0" "component=ingestion,check=notesCheckVerifier"
            record_metric "${COMPONENT}" "data_quality_check_duration" "${duration}" "component=ingestion,check=notesCheckVerifier"
            issues_found=$((issues_found + 1))
            quality_score=$((quality_score - 10))
            
            # Parse output for error details
            local error_count
            error_count=$(echo "${output}" | grep -c "error\|failed\|discrepancy" || echo "0")
            
            if [[ ${error_count} -gt 0 ]]; then
                log_warning "${COMPONENT}: Found ${error_count} potential issues in notesCheckVerifier"
                quality_score=$((quality_score - (error_count * 5)))
            fi
        fi
    else
        log_warning "${COMPONENT}: notesCheckVerifier.sh not found: ${verifier_script}"
        log_info "${COMPONENT}: Skipping notesCheckVerifier check (script not available)"
    fi
    
    # Check data completeness
    check_data_completeness
    
    # Check data freshness
    check_data_freshness
    
    # Record overall quality score
    record_metric "${COMPONENT}" "data_quality_score" "${quality_score}" "component=ingestion"
    
    # Check against threshold
    local quality_threshold="${INGESTION_DATA_QUALITY_THRESHOLD:-95}"
    
    if [[ ${quality_score} -lt ${quality_threshold} ]]; then
        log_warning "${COMPONENT}: Data quality score (${quality_score}%) below threshold (${quality_threshold}%)"
        send_alert "WARNING" "${COMPONENT}" "Data quality below threshold: ${quality_score}% (threshold: ${quality_threshold}%)"
        return 1
    fi
    
    log_info "${COMPONENT}: Data quality check passed - Score: ${quality_score}%"
    return 0
}

##
# Check processing latency
##
check_processing_latency() {
    log_info "${COMPONENT}: Starting processing latency check"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check processing latency - database connection failed"
        return 0
    fi
    
    # Try to get latency from processing_log table if it exists
    local latency_query="
        SELECT 
            EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) AS latency_seconds
        FROM processing_log
        WHERE status = 'success'
        LIMIT 1;
    "
    
    local latency_seconds
    latency_seconds=$(execute_sql_query "${latency_query}" 2>/dev/null || echo "")
    
    if [[ -n "${latency_seconds}" ]] && [[ "${latency_seconds}" != "" ]]; then
        # Remove any whitespace
        latency_seconds=$(echo "${latency_seconds}" | tr -d '[:space:]')
        
        # Check if it's a valid number
        if [[ "${latency_seconds}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            log_info "${COMPONENT}: Processing latency: ${latency_seconds} seconds"
            record_metric "${COMPONENT}" "processing_latency_seconds" "${latency_seconds}" "component=ingestion"
            
            # Check against threshold
            local latency_threshold="${INGESTION_LATENCY_THRESHOLD:-300}"
            if (( $(echo "${latency_seconds} > ${latency_threshold}" | bc -l 2>/dev/null || echo "0") )); then
                log_warning "${COMPONENT}: Processing latency (${latency_seconds}s) exceeds threshold (${latency_threshold}s)"
                send_alert "WARNING" "${COMPONENT}" "High processing latency: ${latency_seconds}s (threshold: ${latency_threshold}s)"
                return 1
            fi
        fi
    else
        # Fallback: Use log file age as proxy for latency
        local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
        if [[ -d "${ingestion_log_dir}" ]]; then
            local latest_log
            latest_log=$(find "${ingestion_log_dir}" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
            
            if [[ -n "${latest_log}" ]]; then
                local log_mtime
                log_mtime=$(stat -c %Y "${latest_log}" 2>/dev/null || stat -f %m "${latest_log}" 2>/dev/null || echo "0")
                local current_time
                current_time=$(date +%s)
                local latency_seconds=$((current_time - log_mtime))
                
                log_info "${COMPONENT}: Processing latency (from log age): ${latency_seconds} seconds"
                record_metric "${COMPONENT}" "processing_latency_seconds" "${latency_seconds}" "component=ingestion,source=log_age"
                
                # Check against threshold
                local latency_threshold="${INGESTION_LATENCY_THRESHOLD:-300}"
                if [[ ${latency_seconds} -gt ${latency_threshold} ]]; then
                    log_warning "${COMPONENT}: Processing latency (${latency_seconds}s) exceeds threshold (${latency_threshold}s)"
                    send_alert "WARNING" "${COMPONENT}" "High processing latency: ${latency_seconds}s (threshold: ${latency_threshold}s)"
                    return 1
                fi
            fi
        fi
    fi
    
    log_info "${COMPONENT}: Processing latency check passed"
    return 0
}

##
# Check processing frequency
##
check_processing_frequency() {
    log_debug "${COMPONENT}: Checking processing frequency"
    
    # Check database connection
    if ! check_database_connection; then
        log_warning "${COMPONENT}: Cannot check processing frequency - database connection failed"
        return 0
    fi
    
    # Try to get frequency from processing_log table
    local frequency_query="
        SELECT 
            AVG(EXTRACT(EPOCH FROM (execution_time - LAG(execution_time) OVER (ORDER BY execution_time)))) / 3600.0 AS avg_frequency_hours
        FROM processing_log
        WHERE status = 'success'
          AND execution_time > NOW() - INTERVAL '7 days'
        ORDER BY execution_time DESC
        LIMIT 10;
    "
    
    local frequency_hours
    frequency_hours=$(execute_sql_query "${frequency_query}" 2>/dev/null | head -1 | tr -d '[:space:]' || echo "")
    
    if [[ -n "${frequency_hours}" ]] && [[ "${frequency_hours}" != "" ]] && [[ "${frequency_hours}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        log_debug "${COMPONENT}: Average processing frequency: ${frequency_hours} hours"
        record_metric "${COMPONENT}" "processing_frequency_hours" "${frequency_hours}" "component=ingestion"
    fi
    
    return 0
}

##
# Check API download status
##
check_api_download_status() {
    log_info "${COMPONENT}: Starting API download status check"
    
    # Check if ingestion repository exists
    if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        log_warning "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
        return 0
    fi
    
    # Look for API download logs or status files
    local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
    local api_download_status=0  # 0 = unknown, 1 = success
    
    # Check for recent API download activity in logs
    if [[ -d "${ingestion_log_dir}" ]]; then
        # Look for API-related log entries
        local recent_api_logs
        mapfile -t recent_api_logs < <(find "${ingestion_log_dir}" -name "*api*" -o -name "*download*" -type f -mmin -60 2>/dev/null | head -5)
        
        if [[ ${#recent_api_logs[@]} -gt 0 ]]; then
            # Check for success indicators
            for log_file in "${recent_api_logs[@]}"; do
                if grep -qE "success|completed|downloaded|200 OK" "${log_file}" 2>/dev/null; then
                    api_download_status=1
                    break
                fi
            done
        fi
    fi
    
    # Check for API download script execution
    local api_script="${INGESTION_REPO_PATH}/bin/processAPINotes.sh"
    if [[ -f "${api_script}" ]]; then
        # Check if script ran recently (within last hour)
        if [[ -x "${api_script}" ]]; then
            local script_mtime
            script_mtime=$(stat -c %Y "${api_script}" 2>/dev/null || stat -f %m "${api_script}" 2>/dev/null || echo "0")
            local current_time
            current_time=$(date +%s)
            local age_seconds=$((current_time - script_mtime))
            
            # If script was modified recently, assume it ran
            if [[ ${age_seconds} -lt 3600 ]]; then
                api_download_status=1
            fi
        fi
    fi
    
    log_info "${COMPONENT}: API download status: ${api_download_status}"
    record_metric "${COMPONENT}" "api_download_status" "${api_download_status}" "component=ingestion"
    
    if [[ ${api_download_status} -eq 0 ]]; then
        log_warning "${COMPONENT}: No recent API download activity detected"
        send_alert "WARNING" "${COMPONENT}" "No recent API download activity detected"
        return 1
    fi
    
    log_info "${COMPONENT}: API download status check passed"
    return 0
}

##
# Check API download success rate
##
check_api_download_success_rate() {
    log_info "${COMPONENT}: Starting API download success rate check"
    
    # Check if ingestion repository exists
    if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
        log_warning "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
        return 0
    fi
    
    local ingestion_log_dir="${INGESTION_REPO_PATH}/logs"
    local total_downloads=0
    local successful_downloads=0
    
    # Analyze log files for download attempts
    if [[ -d "${ingestion_log_dir}" ]]; then
        # Find API-related log files from last 24 hours
        local api_logs
        mapfile -t api_logs < <(find "${ingestion_log_dir}" -name "*api*" -o -name "*download*" -type f -mtime -1 2>/dev/null | head -10)
        
        for log_file in "${api_logs[@]}"; do
            # Count download attempts
            local downloads
            downloads=$(grep -cE "download|fetch|GET|POST" "${log_file}" 2>/dev/null || echo "0")
            total_downloads=$((total_downloads + downloads))
            
            # Count successful downloads
            local successes
            successes=$(grep -cE "success|completed|200 OK|downloaded" "${log_file}" 2>/dev/null || echo "0")
            successful_downloads=$((successful_downloads + successes))
        done
    fi
    
    # Calculate success rate
    local success_rate=100
    if [[ ${total_downloads} -gt 0 ]]; then
        success_rate=$((successful_downloads * 100 / total_downloads))
    fi
    
    log_info "${COMPONENT}: API download success rate: ${success_rate}% (${successful_downloads}/${total_downloads})"
    record_metric "${COMPONENT}" "api_download_success_rate_percent" "${success_rate}" "component=ingestion"
    record_metric "${COMPONENT}" "api_download_total_count" "${total_downloads}" "component=ingestion"
    record_metric "${COMPONENT}" "api_download_successful_count" "${successful_downloads}" "component=ingestion"
    
    # Check against threshold
    local success_threshold="${INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD:-95}"
    if [[ ${success_rate} -lt ${success_threshold} ]] && [[ ${total_downloads} -gt 0 ]]; then
        log_warning "${COMPONENT}: API download success rate (${success_rate}%) below threshold (${success_threshold}%)"
        send_alert "WARNING" "${COMPONENT}" "Low API download success rate: ${success_rate}% (threshold: ${success_threshold}%, ${successful_downloads}/${total_downloads})"
        return 1
    fi
    
    log_info "${COMPONENT}: API download success rate check passed"
    return 0
}

##
# Run all checks
##
run_all_checks() {
    log_info "${COMPONENT}: Starting all monitoring checks"
    
    local checks_passed=0
    local checks_failed=0
    
    # Health check
    if check_ingestion_health; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Execution status check
    if check_script_execution_status; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Latency check
    if check_processing_latency; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Processing frequency check
    check_processing_frequency
    
    # Performance check
    if check_ingestion_performance; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Data quality check
    if check_ingestion_data_quality; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Error rate check
    if check_error_rate; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # Disk space check
    if check_disk_space; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # API download status check
    if check_api_download_status; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    # API download success rate check
    if check_api_download_success_rate; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
    fi
    
    log_info "${COMPONENT}: Monitoring checks completed - passed: ${checks_passed}, failed: ${checks_failed}"
    
    if [[ ${checks_failed} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

##
# Main
##
main() {
    local check_type="all"
    # shellcheck disable=SC2034
    local verbose=false
    # shellcheck disable=SC2034
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -c|--check)
                check_type="${2}"
                shift 2
                ;;
            -v|--verbose)
                # shellcheck disable=SC2034
                verbose=true
                export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
                shift
                ;;
            -d|--dry-run)
                # shellcheck disable=SC2034
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "${COMPONENT}: Unknown option: ${1}"
                usage
                exit 1
                ;;
        esac
    done
    
    # Load configuration
    if ! load_all_configs; then
        log_error "${COMPONENT}: Failed to load configuration"
        exit 1
    fi
    
    # Validate configuration
    if ! validate_all_configs; then
        log_error "${COMPONENT}: Configuration validation failed"
        exit 1
    fi
    
    # Check if monitoring is enabled
    if [[ "${INGESTION_ENABLED:-true}" != "true" ]]; then
        log_info "${COMPONENT}: Monitoring disabled in configuration"
        exit 0
    fi
    
    log_info "${COMPONENT}: Starting ingestion monitoring"
    
    # Run requested check
    case "${check_type}" in
        health)
            if check_ingestion_health; then
                exit 0
            else
                exit 1
            fi
            ;;
        performance)
            if check_ingestion_performance; then
                exit 0
            else
                exit 1
            fi
            ;;
        data-quality)
            if check_ingestion_data_quality; then
                exit 0
            else
                exit 1
            fi
            ;;
        execution-status)
            if check_script_execution_status; then
                exit 0
            else
                exit 1
            fi
            ;;
        latency)
            if check_processing_latency; then
                exit 0
            else
                exit 1
            fi
            ;;
        error-rate)
            if check_error_rate; then
                exit 0
            else
                exit 1
            fi
            ;;
        disk-space)
            if check_disk_space; then
                exit 0
            else
                exit 1
            fi
            ;;
        api-download)
            if check_api_download_status && check_api_download_success_rate; then
                exit 0
            else
                exit 1
            fi
            ;;
        all)
            if run_all_checks; then
                exit 0
            else
                exit 1
            fi
            ;;
        *)
            log_error "${COMPONENT}: Unknown check type: ${check_type}"
            usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

