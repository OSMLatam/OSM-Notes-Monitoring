#!/usr/bin/env bash
#
# Complete Alert Delivery Tests
# Tests email and Slack alert delivery with mocks
#
# Version: 1.0.0
# Date: 2025-12-31
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
# Remove trailing slash if present
PROJECT_ROOT="${PROJECT_ROOT%/}"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test database
TEST_DBNAME="${TEST_DBNAME:-osm_notes_monitoring_test}"
TESTS_PASSED=0
TESTS_FAILED=0

# Mock directories
MOCK_BIN_DIR="${SCRIPT_DIR}/../tmp/mock_bin"
mkdir -p "${MOCK_BIN_DIR}"

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Create mock mutt
##
create_mock_mutt() {
    cat > "${MOCK_BIN_DIR}/mutt" << 'EOF'
#!/usr/bin/env bash
# Mock mutt for testing
MOCK_EMAIL_LOG="${MOCK_EMAIL_LOG:-/tmp/mock_email.log}"
echo "MOCK_EMAIL_SENT" > "${MOCK_EMAIL_LOG}"
echo "Subject: $2" >> "${MOCK_EMAIL_LOG}"
echo "To: $3" >> "${MOCK_EMAIL_LOG}"
# Discard stdin immediately to avoid blocking
cat > /dev/null 2>&1 || true
exit 0
EOF
    chmod +x "${MOCK_BIN_DIR}/mutt"
}

##
# Create mock curl
##
create_mock_curl() {
    cat > "${MOCK_BIN_DIR}/curl" << 'EOF'
#!/usr/bin/env bash
# Mock curl for testing Slack
MOCK_SLACK_LOG="${MOCK_SLACK_LOG:-/tmp/mock_slack.log}"
if [[ "${1}" == "-X" && "${2}" == "POST" ]]; then
    echo "MOCK_SLACK_SENT" > "${MOCK_SLACK_LOG}"
    # Read POST data from --data argument or stdin
    shift 2  # Skip -X POST
    while [[ $# -gt 0 ]]; do
        if [[ "${1}" == "--data" ]]; then
            echo "${2}" >> "${MOCK_SLACK_LOG}"
            shift 2
        else
            shift
        fi
    done
    # Also read from stdin if available
    if read -t 0; then
        cat >> "${MOCK_SLACK_LOG}"
    fi
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN_DIR}/curl"
}

##
# Setup test environment
##
setup() {
    print_message "${BLUE}" "Setting up test environment..."
    
    # Set test database
    export DBNAME="${TEST_DBNAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Set test email
    export ADMIN_EMAIL="test@example.com"
    export CRITICAL_ALERT_RECIPIENTS="test@example.com"
    export WARNING_ALERT_RECIPIENTS="test@example.com"
    export INFO_ALERT_RECIPIENTS="test@example.com"
    
    # Create mock commands
    create_mock_mutt
    create_mock_curl
    
    # Add mock bin to PATH
    export PATH="${MOCK_BIN_DIR}:${PATH}"
    
    # Initialize logging
    TEST_LOG_DIR="${SCRIPT_DIR}/../tmp/logs"
    mkdir -p "${TEST_LOG_DIR}"
    export LOG_FILE="${TEST_LOG_DIR}/test_alert_delivery_complete.log"
    export LOG_DIR="${TEST_LOG_DIR}"
    export LOG_LEVEL="${LOG_LEVEL_INFO:-1}"
    init_logging "${LOG_FILE}" "test_alert_delivery_complete"
    
    # Initialize alerting
    init_alerting
    
    # Clean up old test logs
    rm -f /tmp/mock_email.log /tmp/mock_slack.log
    
    print_message "${GREEN}" "✓ Test environment ready"
}

##
# Cleanup
##
cleanup() {
    # Remove mock commands
    rm -rf "${MOCK_BIN_DIR}"
    
    # Clean up test logs
    rm -f /tmp/mock_email.log /tmp/mock_slack.log
}

##
# Test: Email alert sent when enabled
##
test_email_alert_enabled() {
    print_message "${BLUE}" "\n=== Test: Email Alert Enabled ==="
    
    export SEND_ALERT_EMAIL="true"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Send alert
    if send_alert "TEST" "critical" "test_type" "Test email alert" 2>&1; then
        sleep 1
        
        # Check if email was sent (mocked)
        if [[ -f /tmp/mock_email.log ]] && grep -q "MOCK_EMAIL_SENT" /tmp/mock_email.log; then
            print_message "${GREEN}" "  ✓ Email alert sent"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_message "${RED}" "  ✗ Email alert not sent"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        print_message "${RED}" "  ✗ Failed to send alert"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Test: Email alert skipped when disabled
##
test_email_alert_disabled() {
    print_message "${BLUE}" "\n=== Test: Email Alert Disabled ==="
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Clean up previous log
    rm -f /tmp/mock_email.log
    
    # Send alert
    if send_alert "TEST" "critical" "test_type" "Test alert" 2>&1; then
        sleep 1
        
        # Check that email was NOT sent
        if [[ ! -f /tmp/mock_email.log ]]; then
            print_message "${GREEN}" "  ✓ Email alert correctly skipped"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_message "${RED}" "  ✗ Email alert sent when disabled"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        print_message "${RED}" "  ✗ Failed to send alert"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Test: Slack alert sent when enabled
##
test_slack_alert_enabled() {
    print_message "${BLUE}" "\n=== Test: Slack Alert Enabled ==="
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/WEBHOOK/URL"
    export SLACK_CHANNEL="#test-channel"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Clean up previous log
    rm -f /tmp/mock_slack.log
    
    # Send alert
    if send_alert "TEST" "warning" "test_type" "Test Slack alert" 2>&1; then
        sleep 1
        
        # Check if Slack was sent (mocked)
        if [[ -f /tmp/mock_slack.log ]] && grep -q "MOCK_SLACK_SENT" /tmp/mock_slack.log; then
            print_message "${GREEN}" "  ✓ Slack alert sent"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_message "${RED}" "  ✗ Slack alert not sent"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        print_message "${RED}" "  ✗ Failed to send alert"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Test: Slack alert skipped when disabled
##
test_slack_alert_disabled() {
    print_message "${BLUE}" "\n=== Test: Slack Alert Disabled ==="
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Clean up previous log
    rm -f /tmp/mock_slack.log
    
    # Send alert
    if send_alert "TEST" "warning" "test_type" "Test alert" 2>&1; then
        sleep 1
        
        # Check that Slack was NOT sent
        if [[ ! -f /tmp/mock_slack.log ]]; then
            print_message "${GREEN}" "  ✓ Slack alert correctly skipped"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_message "${RED}" "  ✗ Slack alert sent when disabled"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        print_message "${RED}" "  ✗ Failed to send alert"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Test: Multi-channel alert delivery
##
test_multi_channel_delivery() {
    print_message "${BLUE}" "\n=== Test: Multi-Channel Delivery ==="
    
    export SEND_ALERT_EMAIL="true"
    export SLACK_ENABLED="true"
    export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST/WEBHOOK/URL"
    export SLACK_CHANNEL="#test-channel"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Clean up previous logs
    rm -f /tmp/mock_email.log /tmp/mock_slack.log
    
    # Send alert
    if send_alert "TEST" "critical" "test_type" "Test multi-channel alert" 2>&1; then
        sleep 1
        
        local email_sent=false
        local slack_sent=false
        
        if [[ -f /tmp/mock_email.log ]] && grep -q "MOCK_EMAIL_SENT" /tmp/mock_email.log; then
            email_sent=true
        fi
        
        if [[ -f /tmp/mock_slack.log ]] && grep -q "MOCK_SLACK_SENT" /tmp/mock_slack.log; then
            slack_sent=true
        fi
        
        if [[ "${email_sent}" == "true" && "${slack_sent}" == "true" ]]; then
            print_message "${GREEN}" "  ✓ Both email and Slack alerts sent"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_message "${RED}" "  ✗ Multi-channel delivery failed (email: ${email_sent}, slack: ${slack_sent})"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        print_message "${RED}" "  ✗ Failed to send alert"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Test: Alert levels route to correct recipients
##
test_alert_level_routing() {
    print_message "${BLUE}" "\n=== Test: Alert Level Routing ==="
    
    export SEND_ALERT_EMAIL="true"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Test critical level
    export CRITICAL_ALERT_RECIPIENTS="critical@example.com"
    rm -f /tmp/mock_email.log /tmp/mock_email.log.body
    send_alert "TEST" "critical" "test_type" "Critical alert" 2>&1
    sleep 1
    if [[ -f /tmp/mock_email.log ]] && grep -q "critical@example.com" /tmp/mock_email.log; then
        print_message "${GREEN}" "  ✓ Critical alerts route correctly"
    else
        print_message "${RED}" "  ✗ Critical alert routing failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Test warning level
    export WARNING_ALERT_RECIPIENTS="warning@example.com"
    rm -f /tmp/mock_email.log /tmp/mock_email.log.body
    send_alert "TEST" "warning" "test_type" "Warning alert" 2>&1
    sleep 1
    if [[ -f /tmp/mock_email.log ]] && grep -q "warning@example.com" /tmp/mock_email.log; then
        print_message "${GREEN}" "  ✓ Warning alerts route correctly"
    else
        print_message "${RED}" "  ✗ Warning alert routing failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

##
# Test: Alert stored in database
##
test_alert_stored_in_database() {
    print_message "${BLUE}" "\n=== Test: Alert Stored in Database ==="
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    # Check database connection
    if ! psql -d "${TEST_DBNAME}" -c "SELECT 1;" > /dev/null 2>&1; then
        print_message "${YELLOW}" "  ⚠ Database not available, skipping"
        return 0
    fi
    
    # Send alert
    local test_message="Database storage test alert"
    if send_alert "TEST" "warning" "db_test" "${test_message}" 2>&1; then
        sleep 1
        
        # Check database
        local count
        count=$(psql -d "${TEST_DBNAME}" -t -A -c \
            "SELECT COUNT(*) FROM alerts WHERE component = 'TEST' AND message = '${test_message}';" 2>/dev/null | tr -d '[:space:]' || echo "0")
        
        if [[ "${count}" -ge 1 ]]; then
            print_message "${GREEN}" "  ✓ Alert stored in database"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_message "${RED}" "  ✗ Alert not found in database"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        print_message "${RED}" "  ✗ Failed to send alert"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Test: Alert deduplication
##
test_alert_deduplication() {
    print_message "${BLUE}" "\n=== Test: Alert Deduplication ==="
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="true"
    export ALERT_DEDUPLICATION_WINDOW_MINUTES=60
    
    # Check database connection
    if ! psql -d "${TEST_DBNAME}" -c "SELECT 1;" > /dev/null 2>&1; then
        print_message "${YELLOW}" "  ⚠ Database not available, skipping"
        return 0
    fi
    
    # Clean up old alerts
    psql -d "${TEST_DBNAME}" -c "DELETE FROM alerts WHERE component = 'TEST' AND alert_type = 'dedup_test';" > /dev/null 2>&1 || true
    
    # Send same alert twice
    local test_message="Deduplication test alert"
    send_alert "TEST" "warning" "dedup_test" "${test_message}" 2>&1
    sleep 1
    send_alert "TEST" "warning" "dedup_test" "${test_message}" 2>&1
    sleep 1
    
    # Check database
    local count
    count=$(psql -d "${TEST_DBNAME}" -t -A -c \
        "SELECT COUNT(*) FROM alerts WHERE component = 'TEST' AND alert_type = 'dedup_test';" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    if [[ "${count}" -eq 1 ]]; then
        print_message "${GREEN}" "  ✓ Alert deduplication works"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_message "${RED}" "  ✗ Alert deduplication failed (found ${count} alerts, expected 1)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

##
# Print summary
##
print_summary() {
    echo
    print_message "${BLUE}" "=== Test Summary ==="
    print_message "${GREEN}" "Tests passed: ${TESTS_PASSED}"
    
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        print_message "${RED}" "Tests failed: ${TESTS_FAILED}"
        echo
        return 1
    else
        print_message "${GREEN}" "Tests failed: ${TESTS_FAILED}"
        echo
        print_message "${GREEN}" "✓ All tests passed!"
        return 0
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Complete Alert Delivery Test Suite"
    print_message "${BLUE}" "Test database: ${TEST_DBNAME}"
    echo
    
    # Setup
    setup
    
    # Run tests
    test_email_alert_enabled
    test_email_alert_disabled
    test_slack_alert_enabled
    test_slack_alert_disabled
    test_multi_channel_delivery
    test_alert_level_routing
    test_alert_stored_in_database
    test_alert_deduplication
    
    # Cleanup
    cleanup
    
    # Summary
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
