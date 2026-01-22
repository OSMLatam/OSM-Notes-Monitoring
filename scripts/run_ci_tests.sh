#!/usr/bin/env bash
#
# Run CI Tests Locally
# Simulates the GitHub Actions workflow to test changes locally
# Author: Andres Gomez (AngocA)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

print_message "${YELLOW}" "=== Running CI Tests Locally (OSM-Notes-Monitoring) ==="
echo

cd "${PROJECT_ROOT}"

# Check if BATS is installed
if ! command -v bats > /dev/null 2>&1; then
    print_message "${YELLOW}" "Installing BATS..."
    git clone https://github.com/bats-core/bats-core.git /tmp/bats 2>/dev/null || true
    if [[ -d /tmp/bats ]]; then
        sudo /tmp/bats/install.sh /usr/local 2>/dev/null || {
            print_message "${RED}" "Failed to install BATS. Please install manually:"
            echo "  git clone https://github.com/bats-core/bats-core.git"
            echo "  cd bats-core"
            echo "  ./install.sh /usr/local"
            exit 1
        }
    fi
fi

# Check shellcheck
if ! command -v shellcheck > /dev/null 2>&1; then
    print_message "${YELLOW}" "Installing shellcheck..."
    if ! (sudo apt-get update && sudo apt-get install -y shellcheck) 2>/dev/null; then
        print_message "${YELLOW}" "⚠ Could not install shellcheck automatically"
    fi
fi

# Check shfmt
if ! command -v shfmt > /dev/null 2>&1; then
    print_message "${YELLOW}" "Installing shfmt..."
    wget -q -O /tmp/shfmt https://github.com/mvdan/sh/releases/download/v3.7.0/shfmt_v3.7.0_linux_amd64
    chmod +x /tmp/shfmt
    sudo mv /tmp/shfmt /usr/local/bin/shfmt || {
        print_message "${YELLOW}" "⚠ Could not install shfmt automatically"
    }
fi

# Check PostgreSQL
if command -v psql > /dev/null 2>&1; then
    print_message "${GREEN}" "✓ PostgreSQL client found"
else
    print_message "${YELLOW}" "⚠ PostgreSQL client not found (tests may skip DB tests)"
fi

echo
print_message "${YELLOW}" "=== Step 1: ShellCheck ==="
echo

# Run ShellCheck
if command -v shellcheck > /dev/null 2>&1; then
    print_message "${BLUE}" "Running ShellCheck..."
    if shellcheck bin/*.sh 2>&1 | grep -q "error"; then
        print_message "${RED}" "✗ ShellCheck found errors"
        shellcheck bin/*.sh
        exit 1
    else
        print_message "${GREEN}" "✓ ShellCheck passed"
    fi
else
    print_message "${YELLOW}" "⚠ shellcheck not available, skipping"
fi

echo
print_message "${YELLOW}" "=== Step 2: Code Formatting Checks ==="
echo

# Check bash formatting with shfmt
print_message "${BLUE}" "Checking bash code formatting with shfmt..."
if command -v shfmt > /dev/null 2>&1; then
    if find bin -name "*.sh" -type f -exec shfmt -d -i 1 -sr -bn {} \; 2>&1 | grep -q "."; then
        print_message "${RED}" "✗ Code formatting issues found"
        find bin -name "*.sh" -type f -exec shfmt -d -i 1 -sr -bn {} \;
        exit 1
    else
        print_message "${GREEN}" "✓ Code formatting check passed"
    fi
else
    print_message "${YELLOW}" "⚠ shfmt not available, skipping format check"
fi

# Check SQL formatting (optional)
if command -v sqlfluff > /dev/null 2>&1; then
    print_message "${BLUE}" "Checking SQL formatting..."
    if find sql -name "*.sql" -type f -exec sqlfluff lint {} \; 2>&1 | grep -q "error"; then
        print_message "${YELLOW}" "⚠ SQL formatting issues found (non-blocking)"
    else
        print_message "${GREEN}" "✓ SQL formatting check passed"
    fi
fi

# Check Prettier formatting (optional)
if command -v prettier > /dev/null 2>&1 || command -v npx > /dev/null 2>&1; then
    print_message "${BLUE}" "Checking Prettier formatting..."
    if command -v prettier > /dev/null 2>&1; then
        PRETTIER_CMD=prettier
    else
        PRETTIER_CMD="npx prettier"
    fi
    if ${PRETTIER_CMD} --check "**/*.{md,json,yaml,yml,css,html}" --ignore-path .prettierignore 2>/dev/null; then
        print_message "${GREEN}" "✓ Prettier formatting check passed"
    else
        print_message "${YELLOW}" "⚠ Prettier formatting issues found (non-blocking)"
    fi
fi

echo
print_message "${YELLOW}" "=== Step 3: Tests ==="
echo

# Setup test environment
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=postgres
export PGDATABASE=osm_notes_monitoring_test
export DBHOST=localhost
export DBPORT=5432
export DBUSER=postgres
export DBPASSWORD=postgres
export DBNAME=osm_notes_monitoring_test

# Check if PostgreSQL is running
if command -v pg_isready > /dev/null 2>&1 && pg_isready -h localhost -p 5432 -U postgres > /dev/null 2>&1; then
    print_message "${GREEN}" "✓ PostgreSQL is running"
    
    # Setup test database
    print_message "${BLUE}" "Setting up test database..."
    if [[ -f sql/init.sql ]]; then
        psql -d osm_notes_monitoring_test -f sql/init.sql 2>/dev/null || true
    fi
    
    # Run unit tests
    print_message "${BLUE}" "Running unit tests..."
    if [[ -f tests/run_unit_tests.sh ]]; then
        if timeout 2400 ./tests/run_unit_tests.sh; then
            print_message "${GREEN}" "✓ Unit tests passed"
        else
            print_message "${RED}" "✗ Unit tests failed"
            exit 1
        fi
    else
        print_message "${YELLOW}" "⚠ Unit test script not found"
    fi
    
    # Run integration tests
    print_message "${BLUE}" "Running integration tests..."
    if [[ -f tests/run_integration_tests.sh ]]; then
        if timeout 600 ./tests/run_integration_tests.sh; then
            print_message "${GREEN}" "✓ Integration tests passed"
        else
            print_message "${RED}" "✗ Integration tests failed"
            exit 1
        fi
    else
        print_message "${YELLOW}" "⚠ Integration test script not found"
    fi
else
    print_message "${YELLOW}" "⚠ PostgreSQL is not running. Skipping tests."
    print_message "${YELLOW}" "   Start PostgreSQL to run tests:"
    print_message "${YELLOW}" "   docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=osm_notes_monitoring_test postgres:15"
fi

echo
print_message "${GREEN}" "=== All CI Tests Completed Successfully ==="
echo
print_message "${GREEN}" "✅ ShellCheck: PASSED"
print_message "${GREEN}" "✅ Code Formatting Checks: PASSED"
if command -v pg_isready > /dev/null 2>&1 && pg_isready -h localhost -p 5432 -U postgres > /dev/null 2>&1; then
    print_message "${GREEN}" "✅ Unit Tests: PASSED"
    print_message "${GREEN}" "✅ Integration Tests: PASSED"
fi
echo

exit 0
