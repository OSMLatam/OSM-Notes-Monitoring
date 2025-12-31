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
    # Minimal assert implementation that handles [[ ]] correctly
    assert() {
        # Check if first argument is [[
        if [[ "${1:-}" == "[[" ]]; then
            # Build condition string preserving all arguments
            shift  # Remove [[
            local condition_parts=()
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == "]]" ]]; then
                    break
                fi
                condition_parts+=("$1")
                shift
            done
            # Join with spaces and evaluate
            # Use printf %q to properly quote each part, then join
            local eval_str=""
            for part in "${condition_parts[@]}"; do
                if [[ -z "${eval_str}" ]]; then
                    eval_str="${part}"
                else
                    eval_str="${eval_str} ${part}"
                fi
            done
            # Evaluate the condition
            # shellcheck disable=SC2086
            if ! eval "[[ ${eval_str} ]]"; then
                echo "Assertion failed: [[ ${eval_str} ]]" >&2
                return 1
            fi
        else
            # For other commands, execute normally
            if ! "$@"; then
                echo "Assertion failed: $*" >&2
                return 1
            fi
        fi
    }
fi

# Test configuration
readonly TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
readonly TEST_ROOT="$(dirname "${TEST_DIR}")"
# Allow override of TEST_DB_NAME in test files before loading
# Only set as readonly if not already set (to allow test files to override)
if [[ -z "${TEST_DB_NAME:-}" ]]; then
readonly TEST_DB_NAME="osm_notes_monitoring_test"
elif [[ "$(declare -p TEST_DB_NAME 2>/dev/null)" != *"readonly"* ]]; then
    # If already set but not readonly, make it readonly
    readonly TEST_DB_NAME
fi

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
# Usage: assert_failure [command [args...]]
# When used after 'run', checks that $status != 0
##
assert_failure() {
    # If used after 'run', check $status variable (BATS convention)
    if [[ -n "${status:-}" ]]; then
        if [[ ${status} -eq 0 ]]; then
            echo -e "${RED}Command succeeded but should have failed (exit code: ${status})${NC}" >&2
            return 1
        fi
        return 0
    fi
    
    # If no arguments, assume checking last command
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}assert_failure: No command to check and \$status not set. Use 'run' command first.${NC}" >&2
        return 1
    fi
    
    # If command is provided, execute it and check it fails
    if "$@"; then
        echo -e "${RED}Command succeeded but should have failed: $*${NC}" >&2
        return 1
    fi
    return 0
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
    
    # Use DB* variables if set (from test setup), otherwise fall back to PG* variables, then system user
    local dbhost="${DBHOST:-${PGHOST:-localhost}}"
    local dbport="${DBPORT:-${PGPORT:-5432}}"
    local dbuser="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
    local dbname="${DBNAME:-${TEST_DB_NAME}}"
    
    # Only use PGPASSWORD if configured, otherwise let psql use .pgpass or other auth methods
    local psql_cmd="psql"
    if [[ -n "${PGPASSWORD:-}" ]]; then
        psql_cmd="PGPASSWORD=\"${PGPASSWORD}\" psql"
    fi
    
    if ! eval "${psql_cmd}" -h "${dbhost}" -p "${dbport}" \
         -U "${dbuser}" -d "${dbname}" -c "SELECT 1" > /dev/null 2>&1; then
        skip "Test database not available (host: ${dbhost}, port: ${dbport}, user: ${dbuser}, db: ${dbname})"
    fi
}

##
# Create a test database connection string
# Usage: get_test_db_connection
##
get_test_db_connection() {
    # Use DB* variables if set (from test setup), otherwise fall back to PG* variables
    local dbhost="${DBHOST:-${PGHOST:-localhost}}"
    local dbport="${DBPORT:-${PGPORT:-5432}}"
    local dbuser="${DBUSER:-${PGUSER:-postgres}}"
    local dbname="${DBNAME:-${TEST_DB_NAME}}"
    local dbpassword="${PGPASSWORD:-postgres}"
    
    echo "postgresql://${dbuser}:${dbpassword}@${dbhost}:${dbport}/${dbname}"
}

##
# Run a SQL query in test database
# Usage: run_sql_query "SELECT * FROM table"
##
run_sql_query() {
    local query="${1}"
    
    # Use DB* variables if set (from test setup), otherwise fall back to PG* variables
    local dbhost="${DBHOST:-${PGHOST:-localhost}}"
    local dbport="${DBPORT:-${PGPORT:-5432}}"
    local dbuser="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
    local dbname="${DBNAME:-${TEST_DB_NAME}}"
    local dbpassword="${PGPASSWORD:-}"
    
    # Use PGPASSWORD if set, otherwise let psql use default authentication
    if [[ -n "${dbpassword}" ]]; then
        PGPASSWORD="${dbpassword}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${query}"
    else
        psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "${query}"
    fi
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
    
    # Use DB* variables if set (from test setup), otherwise fall back to PG* variables
    local dbhost="${DBHOST:-${PGHOST:-localhost}}"
    local dbport="${DBPORT:-${PGPORT:-5432}}"
    local dbuser="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
    local dbname="${DBNAME:-${TEST_DB_NAME}}"
    local dbpassword="${PGPASSWORD:-}"
    
    # Use PGPASSWORD if set, otherwise let psql use default authentication
    if [[ -n "${dbpassword}" ]]; then
        PGPASSWORD="${dbpassword}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -f "${sql_file}"
    else
        psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -f "${sql_file}"
    fi
}

##
# Initialize test database schema if needed
# Usage: initialize_test_database_schema
##
initialize_test_database_schema() {
    # Use DB* variables if set (from test setup), otherwise fall back to PG* variables
    local dbhost="${DBHOST:-${PGHOST:-localhost}}"
    local dbport="${DBPORT:-${PGPORT:-5432}}"
    local dbuser="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
    local dbname="${DBNAME:-${TEST_DB_NAME}}"
    local dbpassword="${PGPASSWORD:-}"
    
    # Check if metrics table exists
    local table_exists
    if [[ -n "${dbpassword}" ]]; then
        table_exists=$(PGPASSWORD="${dbpassword}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT 1 FROM information_schema.tables WHERE table_name = 'metrics';" 2>/dev/null || echo "")
    else
        table_exists=$(psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -t -A \
            -c "SELECT 1 FROM information_schema.tables WHERE table_name = 'metrics';" 2>/dev/null || echo "")
    fi
    
    # If table doesn't exist, initialize schema
    if [[ -z "${table_exists}" ]] || [[ "${table_exists}" != "1" ]]; then
        local init_sql="${TEST_ROOT}/../sql/init.sql"
        if [[ ! -f "${init_sql}" ]]; then
            echo -e "${YELLOW}Warning: Schema initialization file not found: ${init_sql}${NC}" >&2
            return 1
        fi
        
        if [[ -n "${dbpassword}" ]]; then
            PGPASSWORD="${dbpassword}" psql \
                -h "${dbhost}" \
                -p "${dbport}" \
                -U "${dbuser}" \
                -d "${dbname}" \
                -f "${init_sql}" > /dev/null 2>&1
        else
            psql \
                -h "${dbhost}" \
                -p "${dbport}" \
                -U "${dbuser}" \
                -d "${dbname}" \
                -f "${init_sql}" > /dev/null 2>&1
        fi
    fi
}

##
# Clean test database
# Usage: clean_test_database
##
clean_test_database() {
    # Use DB* variables if set (from test setup), otherwise fall back to PG* variables
    local dbhost="${DBHOST:-${PGHOST:-localhost}}"
    local dbport="${DBPORT:-${PGPORT:-5432}}"
    local dbuser="${DBUSER:-${PGUSER:-${USER:-postgres}}}"
    local dbname="${DBNAME:-${TEST_DB_NAME}}"
    local dbpassword="${PGPASSWORD:-}"
    
    # Use PGPASSWORD if set, otherwise let psql use default authentication
    if [[ -n "${dbpassword}" ]]; then
        PGPASSWORD="${dbpassword}" psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "TRUNCATE TABLE metrics, alerts, security_events, ip_management CASCADE;" \
            > /dev/null 2>&1 || true
    else
        psql \
            -h "${dbhost}" \
            -p "${dbport}" \
            -U "${dbuser}" \
            -d "${dbname}" \
            -c "TRUNCATE TABLE metrics, alerts, security_events, ip_management CASCADE;" \
            > /dev/null 2>&1 || true
    fi
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

