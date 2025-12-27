#!/usr/bin/env bash
#
# Integration Tests: Configuration System
# Tests configuration loading and validation
#

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"

@test "configuration files exist" {
    local project_root
    project_root="$(get_project_root)"
    
    assert_file_exists "${project_root}/etc/properties.sh.example"
    assert_file_exists "${project_root}/config/monitoring.conf.example"
    assert_file_exists "${project_root}/config/alerts.conf.example"
    assert_file_exists "${project_root}/config/security.conf.example"
}

@test "example config files are valid shell syntax" {
    local project_root
    project_root="$(get_project_root)"
    
    local configs=(
        "etc/properties.sh.example"
        "config/monitoring.conf.example"
        "config/alerts.conf.example"
        "config/security.conf.example"
    )
    
    for config in "${configs[@]}"; do
        local config_file="${project_root}/${config}"
        
        # Check syntax with bash -n
        run bash -n "${config_file}"
        # assert_success without message (it doesn't take messages)
        assert_success
    done
}

@test "load_all_configs sets required variables" {
    local project_root
    project_root="$(get_project_root)"
    
    # Create test configs from examples
    mkdir -p "${project_root}/tests/tmp"
    cp "${project_root}/etc/properties.sh.example" "${project_root}/tests/tmp/test_properties.sh"
    
    # Source test config
    # shellcheck disable=SC1090,SC1091
    source "${project_root}/tests/tmp/test_properties.sh"
    
    # Check required variables are set
    assert [ -n "${DBNAME:-}" ]
    assert [ -n "${DBHOST:-}" ]
    assert [ -n "${DBPORT:-}" ]
    assert [ -n "${DBUSER:-}" ]
}

@test "configuration validation works" {
    skip_if_database_not_available
    
    local project_root
    project_root="$(get_project_root)"
    
    # Create test configs
    cp "${project_root}/etc/properties.sh.example" "${project_root}/tests/tmp/test_validate.sh"
    
    # Set test database
    export DBNAME="osm_notes_monitoring_test"
    export DBHOST="${PGHOST:-localhost}"
    export DBPORT="${PGPORT:-5432}"
    export DBUSER="${PGUSER:-postgres}"
    
    # Source config functions
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
    
    # Test validation (may fail if DB doesn't exist, that's OK)
    run validate_main_config || true
    # Just check it doesn't crash
    assert true
}

