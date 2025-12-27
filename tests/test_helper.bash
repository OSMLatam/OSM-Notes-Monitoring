#!/usr/bin/env bash
#
# Test Helper Functions for BATS
# Provides common test utilities
#

# Load BATS helper functions (if available)
# Try multiple common locations for bats-support and bats-assert
# Priority: local project > /usr/local > /usr
if [[ -f "${BATS_TEST_DIRNAME}/../bats-support/load.bash" ]]; then
    load "${BATS_TEST_DIRNAME}/../bats-support/load.bash"
elif [[ -f '/usr/local/lib/bats-support/load.bash' ]]; then
    load '/usr/local/lib/bats-support/load.bash'
elif [[ -f '/usr/lib/bats-support/load.bash' ]]; then
    load '/usr/lib/bats-support/load.bash'
fi

if [[ -f "${BATS_TEST_DIRNAME}/../bats-assert/load.bash" ]]; then
    load "${BATS_TEST_DIRNAME}/../bats-assert/load.bash"
elif [[ -f '/usr/local/lib/bats-assert/load.bash' ]]; then
    load '/usr/local/lib/bats-assert/load.bash'
elif [[ -f '/usr/lib/bats-assert/load.bash' ]]; then
    load '/usr/lib/bats-assert/load.bash'
fi

# If bats-support/assert are not available, provide minimal compatibility
if ! command -v assert_success > /dev/null 2>&1; then
    # Minimal assert_success implementation
    assert_success() {
        if ! "$@"; then
            echo "Assertion failed: command '$*' returned non-zero exit code" >&2
            return 1
        fi
    }
fi

if ! command -v assert_failure > /dev/null 2>&1; then
    # Minimal assert_failure implementation
    assert_failure() {
        if "$@"; then
            echo "Assertion failed: command '$*' succeeded but should have failed" >&2
            return 1
        fi
    }
fi

if ! command -v assert > /dev/null 2>&1; then
    # Minimal assert implementation
    assert() {
        if ! "$@"; then
            echo "Assertion failed: $*" >&2
            return 1
        fi
    }
fi

# Test configuration
readonly TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
readonly TEST_ROOT="$(dirname "${TEST_DIR}")"
readonly TEST_DB_NAME="osm_notes_monitoring_test"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

##
# Setup function run before each test
##
setup() {
    # Set test environment variables
    export TEST_MODE=true
    export LOG_LEVEL="DEBUG"
    
    # Create test directories
    mkdir -p "${TEST_ROOT}/tests/tmp"
    mkdir -p "${TEST_ROOT}/tests/output"
    
    # Source library functions if they exist
    if [[ -f "${TEST_ROOT}/bin/lib/monitoringFunctions.sh" ]]; then
        source "${TEST_ROOT}/bin/lib/monitoringFunctions.sh"
    fi
}

##
# Teardown function run after each test
##
teardown() {
    # Cleanup test files
    rm -rf "${TEST_ROOT}/tests/tmp"/*
    rm -rf "${TEST_ROOT}/tests/output"/*
}

##
# Assert that a command succeeds
# Usage: assert_success command [args...]
##
assert_success() {
    if ! "$@"; then
        echo -e "${RED}Command failed: $*${NC}" >&2
        return 1
    fi
}

##
# Assert that a command fails
# Usage: assert_failure command [args...]
##
assert_failure() {
    if "$@"; then
        echo -e "${RED}Command succeeded but should have failed: $*${NC}" >&2
        return 1
    fi
}

##
# Assert two values are equal
# Usage: assert_equal expected actual
##
assert_equal() {
    local expected="${1}"
    local actual="${2}"
    
    if [[ "${expected}" != "${actual}" ]]; then
        echo -e "${RED}Assertion failed:${NC}" >&2
        echo -e "  Expected: ${expected}" >&2
        echo -e "  Actual:   ${actual}" >&2
        return 1
    fi
}

##
# Assert a file exists
# Usage: assert_file_exists filepath
##
assert_file_exists() {
    local filepath="${1}"
    
    if [[ ! -f "${filepath}" ]]; then
        echo -e "${RED}File does not exist: ${filepath}${NC}" >&2
        return 1
    fi
}

##
# Assert a directory exists
# Usage: assert_dir_exists dirpath
##
assert_dir_exists() {
    local dirpath="${1}"
    
    if [[ ! -d "${dirpath}" ]]; then
        echo -e "${RED}Directory does not exist: ${dirpath}${NC}" >&2
        return 1
    fi
}

##
# Skip test if command is not available
# Usage: skip_if_command_not_found command_name
##
skip_if_command_not_found() {
    local command_name="${1}"
    
    if ! command -v "${command_name}" > /dev/null 2>&1; then
        skip "${command_name} not found"
    fi
}

##
# Skip test if database is not available
# Usage: skip_if_database_not_available
##
skip_if_database_not_available() {
    if ! command -v psql > /dev/null 2>&1; then
        skip "PostgreSQL client not found"
    fi
    
    if ! PGPASSWORD="${PGPASSWORD:-postgres}" psql -h "${PGHOST:-localhost}" \
         -U "${PGUSER:-postgres}" -d "${TEST_DB_NAME}" -c "SELECT 1" > /dev/null 2>&1; then
        skip "Test database not available"
    fi
}

##
# Create a test database connection string
# Usage: get_test_db_connection
##
get_test_db_connection() {
    echo "postgresql://${PGUSER:-postgres}:${PGPASSWORD:-postgres}@${PGHOST:-localhost}:${PGPORT:-5432}/${TEST_DB_NAME}"
}

##
# Run a SQL query in test database
# Usage: run_sql_query "SELECT * FROM table"
##
run_sql_query() {
    local query="${1}"
    
    PGPASSWORD="${PGPASSWORD:-postgres}" psql \
        -h "${PGHOST:-localhost}" \
        -U "${PGUSER:-postgres}" \
        -d "${TEST_DB_NAME}" \
        -t -A \
        -c "${query}"
}

##
# Load test data into database
# Usage: load_test_data sql_file
##
load_test_data() {
    local sql_file="${1}"
    
    if [[ ! -f "${sql_file}" ]]; then
        echo -e "${RED}Test data file not found: ${sql_file}${NC}" >&2
        return 1
    fi
    
    PGPASSWORD="${PGPASSWORD:-postgres}" psql \
        -h "${PGHOST:-localhost}" \
        -U "${PGUSER:-postgres}" \
        -d "${TEST_DB_NAME}" \
        -f "${sql_file}"
}

##
# Clean test database
# Usage: clean_test_database
##
clean_test_database() {
    PGPASSWORD="${PGPASSWORD:-postgres}" psql \
        -h "${PGHOST:-localhost}" \
        -U "${PGUSER:-postgres}" \
        -d "${TEST_DB_NAME}" \
        -c "TRUNCATE TABLE metrics, alerts, security_events, ip_management CASCADE;" \
        > /dev/null 2>&1 || true
}

##
# Assert file contains text
# Usage: assert_file_contains filepath text
##
assert_file_contains() {
    local filepath="${1}"
    local text="${2}"
    
    if [[ ! -f "${filepath}" ]]; then
        echo -e "${RED}File does not exist: ${filepath}${NC}" >&2
        return 1
    fi
    
    if ! grep -q "${text}" "${filepath}"; then
        echo -e "${RED}File does not contain text: ${text}${NC}" >&2
        echo -e "File: ${filepath}" >&2
        return 1
    fi
}

##
# Assert file matches pattern
# Usage: assert_file_matches filepath pattern
##
assert_file_matches() {
    local filepath="${1}"
    local pattern="${2}"
    
    if [[ ! -f "${filepath}" ]]; then
        echo -e "${RED}File does not exist: ${filepath}${NC}" >&2
        return 1
    fi
    
    if ! grep -qE "${pattern}" "${filepath}"; then
        echo -e "${RED}File does not match pattern: ${pattern}${NC}" >&2
        echo -e "File: ${filepath}" >&2
        return 1
    fi
}

##
# Refute file contains text (opposite of assert_file_contains)
# Usage: refute_file_contains filepath text
##
refute_file_contains() {
    local filepath="${1}"
    local text="${2}"
    
    if [[ -f "${filepath}" ]] && grep -q "${text}" "${filepath}"; then
        echo -e "${RED}File should not contain text: ${text}${NC}" >&2
        echo -e "File: ${filepath}" >&2
        return 1
    fi
}

