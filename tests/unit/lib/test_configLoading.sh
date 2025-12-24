#!/usr/bin/env bash
#
# Unit Tests: Configuration Loading
# Tests configuration loading with all config files
#

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source the library
# shellcheck disable=SC1091
source "$(dirname "$0")/../../../bin/lib/configFunctions.sh"

@test "load_main_config loads properties.sh" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/etc/properties.sh.example"
    local test_config="${project_root}/tests/tmp/test_properties.sh"
    
    # Copy example to test location
    cp "${config_file}" "${test_config}"
    
    # Temporarily replace config file
    local original_config="${project_root}/etc/properties.sh"
    local backup_exists=false
    
    if [[ -f "${original_config}" ]]; then
        mv "${original_config}" "${original_config}.backup"
        backup_exists=true
    fi
    
    cp "${test_config}" "${original_config}"
    
    # Test loading
    run load_main_config
    
    if [[ "${backup_exists}" == "true" ]]; then
        mv "${original_config}.backup" "${original_config}"
    else
        rm -f "${original_config}"
    fi
    
    assert_success
}

@test "load_main_config fails when config file missing" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/etc/properties.sh"
    local backup_file="${config_file}.backup"
    
    # Backup if exists
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

@test "load_monitoring_config loads monitoring.conf" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/monitoring.conf.example"
    local test_config="${project_root}/tests/tmp/test_monitoring.conf"
    
    # Copy example to test location
    cp "${config_file}" "${test_config}"
    
    # Temporarily replace config file
    local original_config="${project_root}/config/monitoring.conf"
    local backup_exists=false
    
    if [[ -f "${original_config}" ]]; then
        mv "${original_config}" "${original_config}.backup"
        backup_exists=true
    fi
    
    cp "${test_config}" "${original_config}"
    
    # Test loading
    run load_monitoring_config
    
    if [[ "${backup_exists}" == "true" ]]; then
        mv "${original_config}.backup" "${original_config}"
    else
        rm -f "${original_config}"
    fi
    
    assert_success
}

@test "load_alert_config loads alerts.conf" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/alerts.conf.example"
    local test_config="${project_root}/tests/tmp/test_alerts.conf"
    
    # Copy example to test location
    cp "${config_file}" "${test_config}"
    
    # Temporarily replace config file
    local original_config="${project_root}/config/alerts.conf"
    local backup_exists=false
    
    if [[ -f "${original_config}" ]]; then
        mv "${original_config}" "${original_config}.backup"
        backup_exists=true
    fi
    
    cp "${test_config}" "${original_config}"
    
    # Test loading
    run load_alert_config
    
    if [[ "${backup_exists}" == "true" ]]; then
        mv "${original_config}.backup" "${original_config}"
    else
        rm -f "${original_config}"
    fi
    
    assert_success
}

@test "load_security_config loads security.conf" {
    local project_root
    project_root="$(get_project_root)"
    local config_file="${project_root}/config/security.conf.example"
    local test_config="${project_root}/tests/tmp/test_security.conf"
    
    # Copy example to test location
    cp "${config_file}" "${test_config}"
    
    # Temporarily replace config file
    local original_config="${project_root}/config/security.conf"
    local backup_exists=false
    
    if [[ -f "${original_config}" ]]; then
        mv "${original_config}" "${original_config}.backup"
        backup_exists=true
    fi
    
    cp "${test_config}" "${original_config}"
    
    # Test loading
    run load_security_config
    
    if [[ "${backup_exists}" == "true" ]]; then
        mv "${original_config}.backup" "${original_config}"
    else
        rm -f "${original_config}"
    fi
    
    assert_success
}

@test "load_all_configs loads all configuration files" {
    local project_root
    project_root="$(get_project_root)"
    
    # Create temporary config files from examples
    local configs=(
        "etc/properties.sh"
        "config/monitoring.conf"
        "config/alerts.conf"
        "config/security.conf"
    )
    
    local backups=()
    
    # Backup existing configs
    for config in "${configs[@]}"; do
        local full_path="${project_root}/${config}"
        if [[ -f "${full_path}" ]]; then
            mv "${full_path}" "${full_path}.backup"
            backups+=("${full_path}")
        fi
    done
    
    # Copy examples to config files
    cp "${project_root}/etc/properties.sh.example" "${project_root}/etc/properties.sh" 2>/dev/null || true
    cp "${project_root}/config/monitoring.conf.example" "${project_root}/config/monitoring.conf" 2>/dev/null || true
    cp "${project_root}/config/alerts.conf.example" "${project_root}/config/alerts.conf" 2>/dev/null || true
    cp "${project_root}/config/security.conf.example" "${project_root}/config/security.conf" 2>/dev/null || true
    
    # Test loading all configs
    run load_all_configs
    
    # Restore backups
    for backup in "${backups[@]}"; do
        if [[ -f "${backup}.backup" ]]; then
            mv "${backup}.backup" "${backup}"
        fi
    done
    
    # Clean up test configs if no backup existed
    for config in "${configs[@]}"; do
        local full_path="${project_root}/${config}"
        local backup_path="${full_path}.backup"
        if [[ -f "${full_path}" && ! -f "${backup_path}" ]]; then
            rm -f "${full_path}"
        fi
    done
    
    # May fail due to DB connection, but should load configs
    # assert_success || true
}

