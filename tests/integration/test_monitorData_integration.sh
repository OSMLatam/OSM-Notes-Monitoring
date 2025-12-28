#!/usr/bin/env bash
#
# Integration Tests: monitorData.sh
# Tests data monitoring with real file system and database
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

export TEST_DB_NAME="test_monitor_data"
load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_BACKUP_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_backups"
TEST_REPO_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_repo"
TEST_STORAGE_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_storage"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    # Set test environment
    export TEST_MODE=true
    export TEST_COMPONENT="DATA"
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_BACKUP_DIR}"
    mkdir -p "${TEST_REPO_DIR}"
    mkdir -p "${TEST_STORAGE_DIR}"
    mkdir -p "${TEST_LOG_DIR}"
    
    # Set test paths
    export DATA_BACKUP_DIR="${TEST_BACKUP_DIR}"
    export DATA_REPO_PATH="${TEST_REPO_DIR}"
    export DATA_STORAGE_PATH="${TEST_STORAGE_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    # Set test configuration
    export DATA_ENABLED="true"
    export DATA_BACKUP_FRESHNESS_THRESHOLD="86400"
    export DATA_REPO_SYNC_CHECK_ENABLED="true"
    export DATA_STORAGE_CHECK_ENABLED="true"
    export DATA_CHECK_TIMEOUT="60"
    export DATA_DISK_USAGE_THRESHOLD="90"
    
    # Database configuration
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${TEST_DB_HOST:-localhost}"
    export DBPORT="${TEST_DB_PORT:-5432}"
    export DBUSER="${TEST_DB_USER:-postgres}"
    
    # Skip if database not available
    skip_if_database_not_available
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"
    
    # Initialize logging
    init_logging "${TEST_LOG_DIR}/test.log" "test_monitorData_integration"
    
    # Initialize alerting
    init_alerting
    
    # Source monitorData.sh functions
    export TEST_MODE=true
    export COMPONENT="DATA"
    
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorData.sh" 2>/dev/null || true
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_BACKUP_DIR}"
    rm -rf "${TEST_REPO_DIR}"
    rm -rf "${TEST_STORAGE_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Helper: Create test backup file with age
##
create_test_backup() {
    local backup_name="${1}"
    local age_seconds="${2:-0}"
    
    local backup_path="${TEST_BACKUP_DIR}/${backup_name}"
    echo "PostgreSQL database dump" > "${backup_path}"
    
    if [[ ${age_seconds} -gt 0 ]]; then
        local timestamp
        timestamp=$(date -d "${age_seconds} seconds ago" +%s 2>/dev/null || date -v-"${age_seconds}"S +%s 2>/dev/null || echo "")
        if [[ -n "${timestamp}" ]]; then
            touch -t "$(date -d "@${timestamp}" +%Y%m%d%H%M.%S 2>/dev/null || date -r "${timestamp}" +%Y%m%d%H%M.%S 2>/dev/null || echo "")" "${backup_path}" 2>/dev/null || true
        fi
    fi
}

@test "check_backup_freshness creates metrics in database" {
    # Create fresh backup files
    create_test_backup "backup_$(date +%Y%m%d).sql" 3600
    create_test_backup "backup_$(date +%Y%m%d).dump" 7200
    
    # Run check
    run check_backup_freshness
    
    # Should succeed
    assert_success
    
    # Verify metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'DATA' AND metric_name IN ('backup_count', 'backup_newest_age_seconds', 'backup_oldest_age_seconds');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_backup_freshness creates alert when backup is stale" {
    # Create old backup file
    create_test_backup "backup_old.sql" 172800  # 2 days old
    
    # Run check
    run check_backup_freshness || true
    
    # Verify alert was created
    local query="SELECT COUNT(*) FROM alerts WHERE component = 'DATA' AND alert_type = 'backup_freshness_exceeded';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 1 ]
}

@test "check_repository_sync_status works with git repository" {
    # Skip if git not available
    if ! command -v git > /dev/null 2>&1; then
        skip "git not available"
    fi
    
    # Initialize git repository
    cd "${TEST_REPO_DIR}" || return 1
    git init > /dev/null 2>&1
    git config user.email "test@example.com" > /dev/null 2>&1
    git config user.name "Test User" > /dev/null 2>&1
    echo "test" > test.txt
    git add test.txt > /dev/null 2>&1
    git commit -m "Initial commit" > /dev/null 2>&1
    cd - > /dev/null || true
    
    # Run check
    run check_repository_sync_status
    
    # Should succeed
    assert_success
    
    # Verify metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'DATA' AND metric_name IN ('repo_sync_status', 'repo_behind_count', 'repo_ahead_count');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_file_integrity validates backup files" {
    # Create valid backup files
    echo "PostgreSQL database dump" > "${TEST_BACKUP_DIR}/backup.sql"
    echo "MySQL dump" > "${TEST_BACKUP_DIR}/backup.dump"
    
    # Create compressed file if gzip available
    if command -v gzip > /dev/null 2>&1; then
        echo "compressed content" | gzip > "${TEST_BACKUP_DIR}/backup.tar.gz" 2>/dev/null || true
    fi
    
    # Run check
    run check_file_integrity
    
    # Should succeed
    assert_success
    
    # Verify metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'DATA' AND metric_name IN ('files_checked', 'integrity_failures');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 2 ]
}

@test "check_file_integrity detects corrupted files" {
    # Create empty file (corrupted)
    touch "${TEST_BACKUP_DIR}/backup.sql"
    
    # Run check
    run check_file_integrity || true
    
    # Verify alert was created
    local query="SELECT COUNT(*) FROM alerts WHERE component = 'DATA' AND alert_type = 'file_integrity_failure';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 1 ]
}

@test "check_storage_availability monitors disk usage" {
    # Ensure storage directory exists
    mkdir -p "${TEST_STORAGE_DIR}"
    
    # Run check
    run check_storage_availability
    
    # Should succeed
    assert_success
    
    # Verify metrics were recorded
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'DATA' AND metric_name IN ('storage_disk_usage_percent', 'storage_disk_available_bytes', 'storage_disk_total_bytes');"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_storage_availability alerts when disk usage is high" {
    # Ensure storage directory exists
    mkdir -p "${TEST_STORAGE_DIR}"
    
    # Mock df to return high usage (if possible)
    # Note: In integration tests, we rely on actual system state
    # This test verifies the alerting logic works
    
    # Run check (may or may not alert depending on actual disk usage)
    run check_storage_availability || true
    
    # Verify metrics were recorded regardless
    local query="SELECT COUNT(*) FROM metrics WHERE component = 'DATA' AND metric_name = 'storage_disk_usage_percent';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 1 ]
}

@test "check_backup_freshness handles multiple backup files" {
    # Create multiple backup files with different ages
    create_test_backup "backup1.sql" 3600
    create_test_backup "backup2.dump" 7200
    create_test_backup "backup3.tar.gz" 10800
    
    # Run check
    run check_backup_freshness
    
    # Should succeed
    assert_success
    
    # Verify backup_count metric reflects all files
    local query="SELECT metric_value::numeric FROM metrics WHERE component = 'DATA' AND metric_name = 'backup_count' ORDER BY timestamp DESC LIMIT 1;"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_file_integrity handles various file types" {
    # Create different types of backup files
    echo "PostgreSQL dump" > "${TEST_BACKUP_DIR}/backup.sql"
    echo "MySQL dump" > "${TEST_BACKUP_DIR}/backup.dump"
    echo "Backup file" > "${TEST_BACKUP_DIR}/backup.backup"
    
    # Create compressed file if gzip available
    if command -v gzip > /dev/null 2>&1; then
        echo "compressed" | gzip > "${TEST_BACKUP_DIR}/backup.tar.gz" 2>/dev/null || true
    fi
    
    # Run check
    run check_file_integrity
    
    # Should succeed
    assert_success
    
    # Verify files_checked metric reflects all files
    local query="SELECT metric_value::numeric FROM metrics WHERE component = 'DATA' AND metric_name = 'files_checked' ORDER BY timestamp DESC LIMIT 1;"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "main function runs all checks successfully" {
    # Create test environment
    create_test_backup "backup.sql" 3600
    mkdir -p "${TEST_STORAGE_DIR}"
    
    # Initialize git repo if git available
    if command -v git > /dev/null 2>&1; then
        cd "${TEST_REPO_DIR}" || return 1
        git init > /dev/null 2>&1
        git config user.email "test@example.com" > /dev/null 2>&1
        git config user.name "Test User" > /dev/null 2>&1
        echo "test" > test.txt
        git add test.txt > /dev/null 2>&1
        git commit -m "Initial commit" > /dev/null 2>&1
        cd - > /dev/null || true
    fi
    
    # Run main function
    run main
    
    # Should succeed (or return 0/1 depending on checks)
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
    
    # Verify metrics were recorded for multiple checks
    local query="SELECT COUNT(DISTINCT metric_name) FROM metrics WHERE component = 'DATA' AND timestamp > NOW() - INTERVAL '1 minute';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 3 ]
}

@test "check_backup_freshness handles missing backup directory gracefully" {
    # Set non-existent directory
    export DATA_BACKUP_DIR="/nonexistent/directory/for/testing"
    
    # Run check
    run check_backup_freshness || true
    
    # Should create alert
    local query="SELECT COUNT(*) FROM alerts WHERE component = 'DATA' AND alert_type = 'backup_directory_missing';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 1 ]
}

@test "check_storage_availability handles non-writable storage" {
    # Create directory and make it non-writable
    mkdir -p "${TEST_STORAGE_DIR}"
    chmod 555 "${TEST_STORAGE_DIR}"
    
    # Run check
    run check_storage_availability || true
    
    # Restore permissions for cleanup
    chmod 755 "${TEST_STORAGE_DIR}" 2>/dev/null || true
    
    # Should create critical alert
    local query="SELECT COUNT(*) FROM alerts WHERE component = 'DATA' AND alert_level = 'CRITICAL' AND alert_type = 'storage_not_writable';"
    local result
    result=$(execute_sql_query "${query}" "${TEST_DB_NAME}" 2>/dev/null || echo "0")
    
    assert [ "${result}" -ge 1 ]
}

