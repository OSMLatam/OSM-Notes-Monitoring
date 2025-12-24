#!/usr/bin/env bash
#
# Development Environment Setup Script
# Sets up the development environment for OSM-Notes-Monitoring
#
# Version: 1.0.0
# Date: 2025-01-23
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

##
# Print colored message
##
print_message() {
    local color="${1}"
    shift
    echo -e "${color}$*${NC}"
}

##
# Check if command exists
##
command_exists() {
    command -v "${1}" > /dev/null 2>&1
}

##
# Check prerequisites
##
check_prerequisites() {
    print_message "${BLUE}" "Checking prerequisites..."
    
    local missing=()
    
    # Check required commands
    local required_commands=(
        "bash"
        "psql"
        "curl"
        "shellcheck"
        "bats"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "${cmd}"; then
            missing+=("${cmd}")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "${RED}" "Missing required commands: ${missing[*]}"
        return 1
    fi
    
    print_message "${GREEN}" "✓ All prerequisites met"
    return 0
}

##
# Setup configuration files
##
setup_config() {
    print_message "${BLUE}" "Setting up configuration files..."
    
    local config_files=(
        "etc/properties.sh"
        "config/monitoring.conf"
        "config/alerts.conf"
        "config/security.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        local example_file="${config_file}.example"
        local full_path="${PROJECT_ROOT}/${config_file}"
        local example_path="${PROJECT_ROOT}/${example_file}"
        
        if [[ ! -f "${full_path}" && -f "${example_path}" ]]; then
            cp "${example_path}" "${full_path}"
            print_message "${YELLOW}" "  Created ${config_file} from example"
            print_message "${YELLOW}" "  Please edit ${config_file} with your configuration"
        elif [[ -f "${full_path}" ]]; then
            print_message "${GREEN}" "  ✓ ${config_file} already exists"
        else
            print_message "${RED}" "  ✗ Example file not found: ${example_file}"
        fi
    done
}

##
# Setup test database
##
setup_test_database() {
    print_message "${BLUE}" "Setting up test database..."
    
    local test_db="osm_notes_monitoring_test"
    local init_sql="${PROJECT_ROOT}/sql/init.sql"
    
    # Check if database exists
    if psql -lqt | cut -d \| -f 1 | grep -qw "${test_db}"; then
        print_message "${YELLOW}" "  Test database ${test_db} already exists"
        read -p "  Drop and recreate? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "${BLUE}" "  Skipping database setup"
            return 0
        fi
        dropdb "${test_db}" || true
    fi
    
    # Create database
    if createdb "${test_db}"; then
        print_message "${GREEN}" "  ✓ Created test database: ${test_db}"
    else
        print_message "${RED}" "  ✗ Failed to create test database"
        return 1
    fi
    
    # Initialize schema
    if [[ -f "${init_sql}" ]]; then
        if psql -d "${test_db}" -f "${init_sql}" > /dev/null 2>&1; then
            print_message "${GREEN}" "  ✓ Initialized database schema"
        else
            print_message "${RED}" "  ✗ Failed to initialize schema"
            return 1
        fi
    else
        print_message "${YELLOW}" "  ⚠ SQL init file not found: ${init_sql}"
    fi
}

##
# Setup Git hooks
##
setup_git_hooks() {
    print_message "${BLUE}" "Setting up Git hooks..."
    
    local hooks_dir="${PROJECT_ROOT}/.git/hooks"
    local pre_commit_hook="${hooks_dir}/pre-commit"
    
    if [[ ! -d "${hooks_dir}" ]]; then
        print_message "${RED}" "  ✗ .git/hooks directory not found (not a git repository?)"
        return 1
    fi
    
    # Create pre-commit hook
    cat > "${pre_commit_hook}" << 'EOF'
#!/usr/bin/env bash
# Pre-commit hook: Run shellcheck on staged bash files

set -e

# Find staged bash files
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' || true)

if [[ -z "${staged_files}" ]]; then
    exit 0
fi

# Run shellcheck
errors=0
for file in ${staged_files}; do
    if shellcheck "${file}"; then
        echo "✓ ${file}"
    else
        echo "✗ ${file} failed shellcheck"
        errors=$((errors + 1))
    fi
done

if [[ ${errors} -gt 0 ]]; then
    echo "Please fix shellcheck errors before committing"
    exit 1
fi

exit 0
EOF
    
    chmod +x "${pre_commit_hook}"
    print_message "${GREEN}" "  ✓ Created pre-commit hook"
}

##
# Main
##
main() {
    print_message "${GREEN}" "OSM-Notes-Monitoring Development Setup"
    echo
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    echo
    setup_config
    echo
    
    read -p "Setup test database? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_test_database
        echo
    fi
    
    read -p "Setup Git hooks? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_git_hooks
        echo
    fi
    
    print_message "${GREEN}" "Setup complete!"
    print_message "${YELLOW}" "Next steps:"
    echo "  1. Edit configuration files in etc/ and config/"
    echo "  2. Run tests: ./tests/run_unit_tests.sh"
    echo "  3. Start implementing monitoring scripts"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

