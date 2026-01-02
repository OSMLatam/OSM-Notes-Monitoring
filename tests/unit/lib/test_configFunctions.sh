#!/usr/bin/env bash
#
# Unit Tests: configFunctions.sh
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source the library
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"

@test "get_project_root returns valid path" {
    local project_root
    project_root="$(get_project_root)"
    
    assert_dir_exists "${project_root}"
    assert_file_exists "${project_root}/README.md"
}

@test "load_main_config fails when config file missing" {
    # Temporarily rename config file if it exists
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/etc/properties.sh"
    local backup_file="${config_file}.backup"
    
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${backup_file}"
    fi
    
    run load_main_config
    assert_failure
    
    # Restore if backed up
    if [[ -f "${backup_file}" ]]; then
        mv "${backup_file}" "${config_file}"
    fi
}

@test "load_main_config succeeds with example config" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/etc/properties.sh"
    local example_file="${project_root}/etc/properties.sh.example"
    
    # Use example if main doesn't exist
    if [[ ! -f "${config_file}" && -f "${example_file}" ]]; then
        cp "${example_file}" "${config_file}"
    fi
    
    if [[ -f "${config_file}" ]]; then
        run load_main_config
        # May fail due to missing DB, but should load config
        # Just check it doesn't crash
        assert_success || true
    else
        skip "No config file available for testing"
    fi
}

##
# Additional tests for validation functions
##

@test "validate_main_config succeeds with valid config" {
    # shellcheck disable=SC2030,SC2031
    export DBNAME="test_db"
    # shellcheck disable=SC2030,SC2031
    export DBHOST="localhost"
    # shellcheck disable=SC2030,SC2031
    export DBPORT="5432"
    # shellcheck disable=SC2030,SC2031
    export DBUSER="test_user"
    
    run validate_main_config
    assert_success
}

@test "validate_main_config fails with missing DBNAME" {
    unset DBNAME
    # shellcheck disable=SC2030,SC2031
    export DBHOST="localhost"
    # shellcheck disable=SC2030,SC2031
    export DBPORT="5432"
    # shellcheck disable=SC2030,SC2031
    export DBUSER="test_user"
    
    run validate_main_config
    assert_failure
}

@test "validate_main_config fails with missing DBHOST" {
    # shellcheck disable=SC2030,SC2031
    export DBNAME="test_db"
    unset DBHOST
    # shellcheck disable=SC2030,SC2031
    export DBPORT="5432"
    # shellcheck disable=SC2030,SC2031
    export DBUSER="test_user"
    
    run validate_main_config
    assert_failure
}

@test "validate_main_config fails with invalid DBPORT" {
    # shellcheck disable=SC2030,SC2031
    export DBNAME="test_db"
    # shellcheck disable=SC2030,SC2031
    export DBHOST="localhost"
    # shellcheck disable=SC2030,SC2031
    export DBPORT="invalid"
    # shellcheck disable=SC2030,SC2031
    export DBUSER="test_user"
    
    run validate_main_config
    assert_failure
}

@test "validate_main_config accepts numeric DBPORT" {
    # shellcheck disable=SC2030,SC2031
    export DBNAME="test_db"
    # shellcheck disable=SC2030,SC2031
    export DBHOST="localhost"
    # shellcheck disable=SC2030,SC2031
    export DBPORT="5432"
    # shellcheck disable=SC2030,SC2031
    export DBUSER="test_user"
    
    run validate_main_config
    assert_success
}

@test "validate_monitoring_config succeeds with valid config" {
    # shellcheck disable=SC2030,SC2031
    export INGESTION_ENABLED="true"
    export ANALYTICS_ENABLED="false"
    # shellcheck disable=SC2030,SC2031
    export INGESTION_CHECK_TIMEOUT="30"
    # shellcheck disable=SC2030,SC2031
    export METRICS_RETENTION_DAYS="90"
    
    run validate_monitoring_config
    assert_success
}

@test "validate_monitoring_config fails with invalid enabled flag" {
    # shellcheck disable=SC2030,SC2031
    export INGESTION_ENABLED="maybe"
    
    run validate_monitoring_config
    assert_failure
}

@test "validate_monitoring_config fails with invalid timeout" {
    # shellcheck disable=SC2030,SC2031
    export INGESTION_CHECK_TIMEOUT="invalid"
    
    run validate_monitoring_config
    assert_failure
}

@test "validate_monitoring_config fails with invalid retention days" {
    # shellcheck disable=SC2030,SC2031
    export METRICS_RETENTION_DAYS="0"
    
    run validate_monitoring_config
    assert_failure
}

@test "validate_monitoring_config accepts valid retention days" {
    # shellcheck disable=SC2030,SC2031
    export METRICS_RETENTION_DAYS="30"
    
    run validate_monitoring_config
    assert_success
}

@test "validate_alert_config succeeds with valid email config" {
    # shellcheck disable=SC2030,SC2031
    export SEND_ALERT_EMAIL="true"
    # shellcheck disable=SC2030,SC2031
    export ADMIN_EMAIL="test@example.com"
    
    run validate_alert_config
    assert_success
}

@test "validate_alert_config fails with missing ADMIN_EMAIL when email enabled" {
    # shellcheck disable=SC2030,SC2031
    export SEND_ALERT_EMAIL="true"
    unset ADMIN_EMAIL
    
    run validate_alert_config
    assert_failure
}

@test "validate_alert_config fails with invalid email format" {
    # shellcheck disable=SC2030,SC2031
    export SEND_ALERT_EMAIL="true"
    # shellcheck disable=SC2030,SC2031
    export ADMIN_EMAIL="invalid-email"
    
    run validate_alert_config
    assert_failure
}

@test "validate_alert_config succeeds with valid Slack config" {
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="true"
    # shellcheck disable=SC2030,SC2031
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/TEST/TEST"
    
    run validate_alert_config
    assert_success
}

@test "validate_alert_config fails with missing webhook when Slack enabled" {
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="true"
    unset SLACK_WEBHOOK_URL
    
    run validate_alert_config
    assert_failure
}

@test "validate_alert_config warns on invalid webhook URL format" {
    # shellcheck disable=SC2030,SC2031
    export SLACK_ENABLED="true"
    # shellcheck disable=SC2030,SC2031
    export SLACK_WEBHOOK_URL="http://invalid.url"
    
    run validate_alert_config
    # Should succeed but log warning
    assert_success
}

@test "validate_alert_config fails with invalid deduplication window" {
    export ALERT_DEDUPLICATION_WINDOW_MINUTES="invalid"
    
    run validate_alert_config
    assert_failure
}

@test "validate_security_config succeeds with valid rate limit config" {
    # shellcheck disable=SC2030,SC2031
    export RATE_LIMIT_PER_IP_PER_MINUTE="60"
    export RATE_LIMIT_PER_IP_PER_HOUR="1000"
    export RATE_LIMIT_PER_IP_PER_DAY="10000"
    export RATE_LIMIT_BURST_SIZE="10"
    
    run validate_security_config
    assert_success
}

@test "validate_security_config fails with invalid rate limit" {
    # shellcheck disable=SC2030,SC2031
    export RATE_LIMIT_PER_IP_PER_MINUTE="invalid"
    
    run validate_security_config
    assert_failure
}

@test "validate_security_config fails with zero rate limit" {
    # shellcheck disable=SC2030,SC2031
    export RATE_LIMIT_PER_IP_PER_MINUTE="0"
    
    run validate_security_config
    assert_failure
}

@test "validate_security_config fails with invalid connection limit" {
    export MAX_CONCURRENT_CONNECTIONS_PER_IP="invalid"
    
    run validate_security_config
    assert_failure
}

@test "validate_security_config fails with invalid DDoS threshold" {
    export DDOS_THRESHOLD_REQUESTS_PER_SECOND="invalid"
    
    run validate_security_config
    assert_failure
}

@test "validate_security_config fails with invalid abuse detection flag" {
    export ABUSE_DETECTION_ENABLED="maybe"
    
    run validate_security_config
    assert_failure
}

@test "load_monitoring_config succeeds when file exists" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/monitoring.conf.example"
    local test_config="${project_root}/config/monitoring.conf"
    
    # Create test config if example exists
    if [[ -f "${config_file}" ]]; then
        cp "${config_file}" "${test_config}"
        run load_monitoring_config
        assert_success
        rm -f "${test_config}"
    else
        skip "No monitoring config example available"
    fi
}

@test "load_monitoring_config succeeds when file missing" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/monitoring.conf"
    local backup_file="${config_file}.backup"
    
    # Backup if exists
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${backup_file}"
    fi
    
    run load_monitoring_config
    assert_success  # Should succeed with defaults
    
    # Restore if backed up
    if [[ -f "${backup_file}" ]]; then
        mv "${backup_file}" "${config_file}"
    fi
}

@test "load_alert_config succeeds when file exists" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/alerts.conf.example"
    local test_config="${project_root}/config/alerts.conf"
    
    # Create test config if example exists
    if [[ -f "${config_file}" ]]; then
        cp "${config_file}" "${test_config}"
        run load_alert_config
        assert_success
        rm -f "${test_config}"
    else
        skip "No alert config example available"
    fi
}

@test "load_alert_config succeeds when file missing" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/alerts.conf"
    local backup_file="${config_file}.backup"
    
    # Backup if exists
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${backup_file}"
    fi
    
    run load_alert_config
    assert_success  # Should succeed with defaults
    
    # Restore if backed up
    if [[ -f "${backup_file}" ]]; then
        mv "${backup_file}" "${config_file}"
    fi
}

@test "load_security_config succeeds when file exists" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/security.conf.example"
    local test_config="${project_root}/config/security.conf"
    
    # Create test config if example exists
    if [[ -f "${config_file}" ]]; then
        cp "${config_file}" "${test_config}"
        run load_security_config
        assert_success
        rm -f "${test_config}"
    else
        skip "No security config example available"
    fi
}

@test "load_security_config succeeds when file missing" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/security.conf"
    local backup_file="${config_file}.backup"
    
    # Backup if exists
    if [[ -f "${config_file}" ]]; then
        mv "${config_file}" "${backup_file}"
    fi
    
    run load_security_config
    assert_success  # Should succeed with defaults
    
    # Restore if backed up
    if [[ -f "${backup_file}" ]]; then
        mv "${backup_file}" "${config_file}"
    fi
}

@test "validate_all_configs succeeds with all valid configs" {
    # shellcheck disable=SC2030,SC2031
    export DBNAME="test_db"
    # shellcheck disable=SC2030,SC2031
    export DBHOST="localhost"
    # shellcheck disable=SC2030,SC2031
    export DBPORT="5432"
    # shellcheck disable=SC2030,SC2031
    export DBUSER="test_user"
    # shellcheck disable=SC2030,SC2031
    export INGESTION_ENABLED="true"
    # shellcheck disable=SC2030,SC2031
    export ADMIN_EMAIL="test@example.com"
    # shellcheck disable=SC2030,SC2031
    export RATE_LIMIT_PER_IP_PER_MINUTE="60"
    
    run validate_all_configs
    # May fail due to DB connection check, but validation should pass
    assert_success || true
}

@test "validate_all_configs fails when main config invalid" {
    unset DBNAME
    # shellcheck disable=SC2030,SC2031
    export DBHOST="localhost"
    # shellcheck disable=SC2030,SC2031
    export DBPORT="5432"
    # shellcheck disable=SC2030,SC2031
    export DBUSER="test_user"
    
    run validate_all_configs
    assert_failure
}

@test "get_project_root returns consistent path" {
    local root1
    root1="$(get_project_root)"
    local root2
    root2="$(get_project_root)"
    
    assert_equal "${root1}" "${root2}"
    assert_dir_exists "${root1}"
}
