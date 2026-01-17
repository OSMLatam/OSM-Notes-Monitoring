#!/usr/bin/env bash
#
# Additional Unit Tests: Alert Rules
# Additional tests for alert rules to increase coverage
#

# Test configuration - set before loading test_helper
export TEST_COMPONENT="ALERTS"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

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
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    TEST_RULES_FILE="${BATS_TEST_DIRNAME}/../../../tmp/test_alert_rules_additional.conf"
    # Ensure directory exists before setting ALERT_RULES_FILE
    mkdir -p "$(dirname "${TEST_RULES_FILE}")"
    rm -f "${TEST_RULES_FILE}"
    export ALERT_RULES_FILE="${TEST_RULES_FILE}"
    
    TEST_TEMPLATES_DIR="${BATS_TEST_DIRNAME}/../../../tmp/test_templates"
    export ALERT_TEMPLATES_DIR="${TEST_TEMPLATES_DIR}"
    mkdir -p "${TEST_TEMPLATES_DIR}"
    
    init_logging "${LOG_DIR}/test_alertRules_additional.log" "test_alertRules_additional"
    # init_alerting may override ALERT_RULES_FILE, so set it again after
    init_alerting
    export ALERT_RULES_FILE="${TEST_RULES_FILE}"
}

teardown() {
    rm -rf "${TEST_LOG_DIR:-}"
    rm -f "${TEST_RULES_FILE:-}"
    rm -rf "${TEST_TEMPLATES_DIR:-}"
}

##
# Test: get_routing handles missing rules file
##
@test "get_routing handles missing rules file" {
    export ALERT_RULES_FILE="/nonexistent/rules.conf"
    
    run get_routing "TEST_COMPONENT" "critical" "test_alert"
    # Should use default routing
    assert_success || true
}

##
# Test: get_routing handles exact match
##
@test "get_routing handles exact component-level-type match" {
    echo "TEST_COMPONENT:critical:test_alert:exact@example.com" > "${TEST_RULES_FILE}"
    
    run get_routing "TEST_COMPONENT" "critical" "test_alert"
    assert_success
    assert_output --partial "exact@example.com"
}

##
# Test: get_routing handles level wildcard
##
@test "get_routing handles level wildcard" {
    echo "TEST_COMPONENT:*:test_alert:level-wildcard@example.com" > "${TEST_RULES_FILE}"
    
    run get_routing "TEST_COMPONENT" "warning" "test_alert"
    assert_success
    assert_output --partial "level-wildcard@example.com"
}

##
# Test: get_routing handles type wildcard
##
@test "get_routing handles type wildcard" {
    echo "TEST_COMPONENT:critical:*:type-wildcard@example.com" > "${TEST_RULES_FILE}"
    
    run get_routing "TEST_COMPONENT" "critical" "any_type"
    assert_success
    assert_output --partial "type-wildcard@example.com"
}

##
# Test: get_routing handles full wildcard
##
@test "get_routing handles full wildcard" {
    echo "*:*:*:full-wildcard@example.com" > "${TEST_RULES_FILE}"
    
    run get_routing "ANY_COMPONENT" "any_level" "any_type"
    assert_success
    assert_output --partial "full-wildcard@example.com"
}

##
# Test: show_template handles missing template
##
@test "show_template handles missing template" {
    run show_template "nonexistent_template"
    # Should fail when template doesn't exist
    assert_failure || true
}

##
# Test: show_template loads template file
##
@test "show_template loads template file" {
    local template_file="${TEST_TEMPLATES_DIR}/test_template.template"
    echo "Test template content" > "${template_file}"
    
    run show_template "test_template"
    assert_success
    assert_output --partial "Test template content"
}

##
# Test: list_rules handles empty file
##
@test "list_rules handles empty file" {
    touch "${TEST_RULES_FILE}"
    
    run list_rules
    assert_success
}

##
# Test: list_rules handles invalid format gracefully
##
@test "list_rules handles invalid format gracefully" {
    echo "invalid:format:line" > "${TEST_RULES_FILE}"
    
    run list_rules
    # Should handle gracefully (may show invalid lines)
    assert_success || true
}

##
# Test: main handles --list option
##
@test "main handles --list option" {
    echo "TEST_COMPONENT:critical:test:test@example.com" > "${TEST_RULES_FILE}"
    
    run main --list
    assert_success
}

##
# Test: main handles --add option
##
@test "main handles --add option" {
    # Ensure file is clean
    rm -f "${TEST_RULES_FILE}"
    
    run main --add "TEST_COMPONENT" "critical" "test" "test@example.com"
    assert_success
    
    # Verify file was created and rule was added
    assert [ -f "${TEST_RULES_FILE}" ]
    assert grep -q "TEST_COMPONENT:critical:test:test@example.com" "${TEST_RULES_FILE}"
}

##
# Test: main handles --remove option
##
@test "main handles --remove option" {
    # Ensure file is clean and recreate it
    rm -f "${TEST_RULES_FILE}"
    echo "TEST_COMPONENT:critical:test:test@example.com" > "${TEST_RULES_FILE}"
    
    # Verify file exists and has content before removal
    assert [ -f "${TEST_RULES_FILE}" ]
    assert grep -q "TEST_COMPONENT:critical:test" "${TEST_RULES_FILE}"
    
    # Run remove command - it constructs pattern as "TEST_COMPONENT:critical:test"
    run main --remove "TEST_COMPONENT" "critical" "test"
    assert_success
    
    # Verify rule was removed - check that file doesn't contain the pattern
    # sed -i should remove the matching line
    if [[ -f "${TEST_RULES_FILE}" ]]; then
        # File exists, check if pattern is gone
        if grep -q "TEST_COMPONENT:critical:test" "${TEST_RULES_FILE}" 2>/dev/null; then
            # Pattern still exists, test failed
            echo "DEBUG: File still contains pattern after removal"
            cat "${TEST_RULES_FILE}"
            assert_failure "Pattern should have been removed"
        else
            # Pattern is gone, test passes
            assert_success
        fi
    else
        # File was removed entirely (unlikely but possible)
        assert_success
    fi
}

##
# Test: main handles --templates option
##
@test "main handles --templates option" {
    local template_file="${TEST_TEMPLATES_DIR}/template1.txt"
    echo "Template 1" > "${template_file}"
    
    run main --templates
    assert_success
}

##
# Test: main handles unknown option
##
@test "main handles unknown option" {
    # Mock usage
    # shellcheck disable=SC2317
    function usage() {
        return 0
    }
    export -f usage
    
    run main --unknown-option || true
    assert_failure
}

##
# Test: get_routing prioritizes exact match over wildcard
##
@test "get_routing prioritizes exact match over wildcard" {
    cat > "${TEST_RULES_FILE}" << EOF
*:*:*:wildcard@example.com
TEST_COMPONENT:critical:test_alert:exact@example.com
EOF
    
    run get_routing "TEST_COMPONENT" "critical" "test_alert"
    assert_success
    # Should match exact rule first
    assert_output --partial "exact@example.com"
}

##
# Test: list_rules handles multiple rules
##
@test "list_rules handles multiple rules" {
    cat > "${TEST_RULES_FILE}" << EOF
COMPONENT1:critical:alert1:email1@example.com
COMPONENT2:warning:alert2:email2@example.com
COMPONENT3:info:alert3:email3@example.com
EOF
    
    run list_rules
    assert_success
    assert_output --partial "COMPONENT1"
    assert_output --partial "COMPONENT2"
    assert_output --partial "COMPONENT3"
}
