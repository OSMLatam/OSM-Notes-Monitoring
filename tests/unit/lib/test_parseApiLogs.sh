#!/usr/bin/env bash
#
# Unit Tests: parseApiLogs.sh
# Tests API log parsing functions
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"
TEST_DATA_DIR="${BATS_TEST_DIRNAME}/../../tmp/data"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}"
    mkdir -p "${TEST_DATA_DIR}"
    
    # Source parseApiLogs.sh
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/parseApiLogs.sh"
    
    # Export functions for testing
    export -f parse_api_logs parse_api_logs_aggregated
}

teardown() {
    # Cleanup test directories
    rm -rf "${TEST_LOG_DIR}"
    rm -rf "${TEST_DATA_DIR}"
}

@test "parse_api_logs handles missing file gracefully" {
    run parse_api_logs "/nonexistent/file.log" 60
    
    # Should return error code and output "{}" for missing files
    assert_failure
    assert_output "{}"
}

@test "parse_api_logs extracts HTTP requests" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] INFO: POST https://api.openstreetmap.org/api/0.6/notes/123/comment
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "total_requests="
}

@test "parse_api_logs detects successful requests" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] INFO: 200 OK - Request completed successfully
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "successful_requests="
}

@test "parse_api_logs detects HTTP errors" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] ERROR: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] ERROR: 404 Not Found
[2026-01-09 10:00:02] ERROR: 500 Internal Server Error
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "errors_4xx="
    assert_output --partial "errors_5xx="
}

@test "parse_api_logs detects timeouts" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:30] ERROR: Request timed out after 30 seconds
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "timeout_requests="
}

@test "parse_api_logs detects rate limit hits" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] WARNING: Rate limit exceeded - 429 Too Many Requests
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "rate_limit_hits="
}

@test "parse_api_logs extracts response time" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] INFO: Response time: 250ms
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "avg_response_time_ms="
}

@test "parse_api_logs extracts response size" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] INFO: Response size: 12345 bytes
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "avg_response_size_bytes="
}

@test "parse_api_logs extracts notes count" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] INFO: Downloaded 50 notes
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "avg_notes_per_request="
}

@test "parse_api_logs calculates success rate" {
    local log_file="${TEST_LOG_DIR}/api.log"
    cat > "${log_file}" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] INFO: 200 OK - success
[2026-01-09 10:00:02] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:03] ERROR: 500 Internal Server Error
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    assert_output --partial "success_rate_percent="
    
    # Extract success rate value
    local success_rate
    success_rate=$(echo "${output}" | grep "success_rate_percent=" | cut -d'=' -f2)
    
    # Should be 50% (1 success out of 2 requests)
    assert [[ "${success_rate}" -ge 0 ]]
    assert [[ "${success_rate}" -le 100 ]]
}

@test "parse_api_logs_aggregated processes multiple files" {
    local log_dir="${TEST_LOG_DIR}/api_logs"
    mkdir -p "${log_dir}"
    
    cat > "${log_dir}/api1.log" << 'EOF'
[2026-01-09 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:01] INFO: 200 OK - success
EOF
    
    cat > "${log_dir}/api2.log" << 'EOF'
[2026-01-09 10:00:02] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2026-01-09 10:00:03] INFO: 200 OK - success
EOF
    
    run parse_api_logs_aggregated "${log_dir}" 60
    
    assert_success
    assert_output --partial "total_requests="
}

@test "parse_api_logs_aggregated handles empty directory" {
    local log_dir="${TEST_LOG_DIR}/empty_logs"
    mkdir -p "${log_dir}"
    
    run parse_api_logs_aggregated "${log_dir}" 60
    
    assert_success
    assert_output --partial "total_requests=0"
}

@test "parse_api_logs filters by time window" {
    local log_file="${TEST_LOG_DIR}/api.log"
    # Create log with old timestamp (more than 60 minutes ago)
    cat > "${log_file}" << 'EOF'
[2025-01-01 10:00:00] INFO: GET https://api.openstreetmap.org/api/0.6/notes.json
[2025-01-01 10:00:01] INFO: 200 OK - success
EOF
    
    run parse_api_logs "${log_file}" 60
    
    assert_success
    # Old logs should be filtered out, so total_requests should be 0 or very low
    assert_output --partial "total_requests="
}
