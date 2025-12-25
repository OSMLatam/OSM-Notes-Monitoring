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
readonly COMPONENT="INGESTION"

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
        local file_warnings
        file_warnings=$(grep -cE "\[WARNING\]|WARNING|warning" "${log_file}" 2>/dev/null || echo "0")
        local file_info
        file_info=$(grep -cE "\[INFO\]|INFO|info" "${log_file}" 2>/dev/null || echo "0")
        local file_total
        file_total=$(wc -l < "${log_file}" 2>/dev/null || echo "0")
        
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
    
    # Check against threshold
    local max_error_rate="${INGESTION_MAX_ERROR_RATE:-5}"
    
    if [[ ${error_rate} -gt ${max_error_rate} ]]; then
        log_warning "${COMPONENT}: Error rate (${error_rate}%) exceeds threshold (${max_error_rate}%)"
        send_alert "WARNING" "${COMPONENT}" "High error rate detected: ${error_rate}% (threshold: ${max_error_rate}%, errors: ${error_lines}/${total_lines})"
        return 1
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
        local file_total
        file_total=$(wc -l < "${log_file}" 2>/dev/null || echo "0")
        
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
    
    # Alert if log is too old (more than 24 hours)
    if [[ ${age_hours} -gt 24 ]]; then
        log_warning "${COMPONENT}: Log file is older than 24 hours (${age_hours} hours)"
        send_alert "WARNING" "${COMPONENT}" "No recent activity detected: last log is ${age_hours} hours old"
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
            
            if [[ ${fail_count} -gt 0 ]]; then
                log_warning "${COMPONENT}: Performance check found ${fail_count} failures"
                send_alert "WARNING" "${COMPONENT}" "Performance check found ${fail_count} failures, ${warning_count} warnings"
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
            MAX(updated_at) as last_update,
            COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') as recent_updates
        FROM notes
        LIMIT 1;
    "
    
    # Try to execute query
    local result
    result=$(execute_sql_query "${freshness_query}" 2>/dev/null || echo "")
    
    if [[ -n "${result}" ]]; then
        log_debug "${COMPONENT}: Data freshness check result: ${result}"
        # Parse and record metrics if needed
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

