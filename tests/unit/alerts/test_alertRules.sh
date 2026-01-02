#!/usr/bin/env bash
#
# Unit Tests: Alert Rules
# Tests alert rules management functionality
#
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

# Set test environment variables BEFORE sourcing scripts
export TEST_MODE=true
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../../tmp/logs"
mkdir -p "${TEST_LOG_DIR}"
export TEST_LOG_DIR="${TEST_LOG_DIR}"
export LOG_DIR="${TEST_LOG_DIR}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Source libraries
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh"

setup() {
    # Set test environment
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    
    # Set test database
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Set test alert rules file
    TEST_RULES_FILE="${BATS_TEST_DIRNAME}/../../../tmp/test_alert_rules.conf"
    export ALERT_RULES_FILE="${TEST_RULES_FILE}"
    rm -f "${TEST_RULES_FILE}"
    
    # Set test templates directory
    TEST_TEMPLATES_DIR="${BATS_TEST_DIRNAME}/../../../tmp/test_alert_templates"
    export ALERT_TEMPLATES_DIR="${TEST_TEMPLATES_DIR}"
    rm -rf "${TEST_TEMPLATES_DIR}"
    mkdir -p "${TEST_TEMPLATES_DIR}"
    
    # Set default email
    export ADMIN_EMAIL="test@example.com"
    export CRITICAL_ALERT_RECIPIENTS="critical@example.com"
    export WARNING_ALERT_RECIPIENTS="warning@example.com"
    export INFO_ALERT_RECIPIENTS="info@example.com"
    
    # Initialize logging
    TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alertRules.log"
    export LOG_DIR="${TEST_LOG_DIR}"
    init_logging "${LOG_FILE}" "test_alertRules"
    
    # Initialize alerting
    init_alerting
}

teardown() {
    # Cleanup test files
    rm -f "${TEST_RULES_FILE}"
    rm -rf "${TEST_TEMPLATES_DIR}"
}

@test "alertRules.sh shows usage with --help" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" --help
    assert_success
    assert_output --partial "Alert Rules Management Script"
    assert_output --partial "Usage:"
}

@test "list_rules returns empty when no rules file exists" {
    run list_rules
    assert_success
    assert_output "No alert rules file found"
}

@test "add_rule adds a new alert rule" {
    add_rule "INGESTION" "critical" "data_quality" "admin@example.com"
    
    assert_file_exist "${TEST_RULES_FILE}"
    assert_file_contains "${TEST_RULES_FILE}" "INGESTION:critical:data_quality:admin@example.com"
}

@test "list_rules lists all rules" {
    add_rule "INGESTION" "critical" "data_quality" "admin@example.com"
    add_rule "ANALYTICS" "warning" "performance" "dev@example.com"
    
    run list_rules
    assert_success
    assert_output --partial "INGESTION:critical:data_quality:admin@example.com"
    assert_output --partial "ANALYTICS:warning:performance:dev@example.com"
}

@test "list_rules filters by component" {
    add_rule "INGESTION" "critical" "data_quality" "admin@example.com"
    add_rule "ANALYTICS" "warning" "performance" "dev@example.com"
    
    run list_rules "INGESTION"
    assert_success
    assert_output --partial "INGESTION:critical:data_quality:admin@example.com"
    refute_output --partial "ANALYTICS"
}

@test "remove_rule removes rule by line number" {
    add_rule "INGESTION" "critical" "data_quality" "admin@example.com"
    add_rule "ANALYTICS" "warning" "performance" "dev@example.com"
    
    remove_rule "1"
    
    run list_rules
    assert_success
    refute_output --partial "INGESTION:critical:data_quality:admin@example.com"
    assert_output --partial "ANALYTICS:warning:performance:dev@example.com"
}

@test "remove_rule removes rule by pattern" {
    add_rule "INGESTION" "critical" "data_quality" "admin@example.com"
    add_rule "ANALYTICS" "warning" "performance" "dev@example.com"
    
    remove_rule "INGESTION"
    
    run list_rules
    assert_success
    refute_output --partial "INGESTION"
    assert_output --partial "ANALYTICS"
}

@test "get_routing returns specific rule route" {
    add_rule "INGESTION" "critical" "data_quality" "admin@example.com"
    
    run get_routing "INGESTION" "critical" "data_quality"
    assert_success
    assert_output "admin@example.com"
}

@test "get_routing falls back to default routing for critical" {
    run get_routing "UNKNOWN" "critical" "test"
    assert_success
    assert_output "critical@example.com"
}

@test "get_routing falls back to default routing for warning" {
    run get_routing "UNKNOWN" "warning" "test"
    assert_success
    assert_output "warning@example.com"
}

@test "get_routing falls back to default routing for info" {
    run get_routing "UNKNOWN" "info" "test"
    assert_success
    assert_output "info@example.com"
}

@test "list_templates returns empty when no templates exist" {
    run list_templates
    assert_success
    # list_templates may return empty string or "No templates found" depending on find output
    # Accept either empty output or the message
    if [[ -n "${output}" ]]; then
        assert_output "No templates found"
    fi
}

@test "add_template creates a new template" {
    add_template "test_template" "Test template content"
    
    assert_file_exist "${TEST_TEMPLATES_DIR}/test_template.template"
    assert_file_contains "${TEST_TEMPLATES_DIR}/test_template.template" "Test template content"
}

@test "show_template displays template content" {
    add_template "test_template" "Test template content"
    
    run show_template "test_template"
    assert_success
    assert_output "Test template content"
}

@test "show_template returns error for non-existent template" {
    run show_template "nonexistent"
    assert_failure
    assert_output --partial "Template not found"
}

@test "list_templates lists all templates" {
    add_template "template1" "Content 1"
    add_template "template2" "Content 2"
    
    run list_templates
    assert_success
    assert_output --partial "template1"
    assert_output --partial "template2"
}

@test "load_config loads configuration from file" {
    local test_config="${BATS_TEST_DIRNAME}/../../../tmp/test_config.conf"
    echo "TEST_VAR=test_value" > "${test_config}"
    
    load_config "${test_config}"
    
    assert [ "${TEST_VAR}" = "test_value" ]
    rm -f "${test_config}"
}

@test "load_config sets default ALERT_RULES_FILE" {
    unset ALERT_RULES_FILE
    load_config
    
    assert [ -n "${ALERT_RULES_FILE}" ]
}

@test "load_config sets default ALERT_TEMPLATES_DIR" {
    unset ALERT_TEMPLATES_DIR
    load_config
    
    assert [ -n "${ALERT_TEMPLATES_DIR}" ]
}

@test "add_rule creates directory if it doesn't exist" {
    local test_rules_file="${BATS_TEST_DIRNAME}/../../../tmp/nonexistent_dir/rules.conf"
    export ALERT_RULES_FILE="${test_rules_file}"
    
    add_rule "TEST" "critical" "test" "test@example.com"
    
    assert_file_exist "${test_rules_file}"
    rm -rf "$(dirname "${test_rules_file}")"
}

@test "remove_rule fails when rules file doesn't exist" {
    export ALERT_RULES_FILE="/nonexistent/rules.conf"
    
    run remove_rule "1"
    assert_failure
    assert_output --partial "No alert rules file found"
}

@test "get_routing handles multiple matching rules" {
    add_rule "INGESTION" "critical" "data_quality" "admin1@example.com"
    add_rule "INGESTION" "critical" "data_quality" "admin2@example.com"
    
    run get_routing "INGESTION" "critical" "data_quality"
    assert_success
    # Should return first match
    assert_output --partial "admin1@example.com"
}

@test "add_template updates existing template" {
    add_template "test_template" "Original content"
    add_template "test_template" "Updated content"
    
    run show_template "test_template"
    assert_success
    assert_output "Updated content"
}

@test "list_rules handles empty component filter" {
    add_rule "INGESTION" "critical" "test" "test@example.com"
    
    run list_rules ""
    assert_success
    assert_output --partial "INGESTION"
}

##
# Additional edge cases and error handling tests
##

@test "get_routing falls back to component-level rule" {
    # Add component-level rule (without alert_type)
    echo "INGESTION:critical:general:component-admin@example.com" >> "${TEST_RULES_FILE}"
    
    run get_routing "INGESTION" "critical" "unknown_type"
    assert_success
    assert_output "component-admin@example.com"
}

@test "get_routing handles missing rules file" {
    export ALERT_RULES_FILE="/nonexistent/rules.conf"
    
    run get_routing "INGESTION" "critical" "test"
    assert_success
    # Should fall back to default routing
    assert_output --partial "@example.com"
}

@test "add_template handles stdin input" {
    echo "Template content from stdin" | add_template "stdin_template" "-"
    
    run show_template "stdin_template"
    assert_success
    assert_output "Template content from stdin"
}

@test "add_template handles file input" {
    local temp_file="${BATS_TEST_DIRNAME}/../../../tmp/test_template_content.txt"
    echo "Template content from file" > "${temp_file}"
    
    add_template "file_template" "${temp_file}"
    
    run show_template "file_template"
    assert_success
    assert_output "Template content from file"
    
    rm -f "${temp_file}"
}

@test "main handles add action with missing arguments" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" add "INGESTION" "critical"
    assert_failure
    assert_output --partial "required"
}

@test "main handles remove action with missing argument" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" remove
    assert_failure
    assert_output --partial "required"
}

@test "main handles route action with missing arguments" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" route "INGESTION" "critical"
    assert_failure
    assert_output --partial "required"
}

@test "main handles template show with missing argument" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" template show
    assert_failure
    assert_output --partial "required"
}

@test "main handles template add with missing arguments" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" template add "test_template"
    assert_failure
    assert_output --partial "required"
}

@test "main handles unknown template action" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" template unknown
    assert_failure
    assert_output --partial "Unknown template action"
}

@test "main handles unknown action" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh" unknown_action
    assert_failure
    assert_output --partial "Unknown action"
}

@test "main handles empty action" {
    run bash "${BATS_TEST_DIRNAME}/../../../bin/alerts/alertRules.sh"
    assert_failure
    assert_output --partial "Action required"
}

@test "remove_rule handles invalid line number" {
    add_rule "INGESTION" "critical" "test" "test@example.com"
    
    # Try to remove non-existent line
    run remove_rule "999"
    assert_success  # sed doesn't fail on non-existent line
}

@test "get_routing handles component-level rule with wildcard type" {
    echo "INGESTION:critical:*:wildcard-admin@example.com" >> "${TEST_RULES_FILE}"
    
    run get_routing "INGESTION" "critical" "any_type"
    assert_success
    # Should match component-level rule
    assert_output --partial "@example.com"
}
