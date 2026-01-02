#!/usr/bin/env bash
#
# Install Code Coverage Tool
# Installs bashcov for code coverage measurement
#
# Version: 2.0.0
# Date: 2026-01-02
# Note: kcov removed - doesn't work with source-based tests
#

set -euo pipefail

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
    command -v "${1}" >/dev/null 2>&1
}

##
# Install bashcov
##
install_bashcov() {
    print_message "${BLUE}" "Installing bashcov..."
    
    # Check if Ruby is installed
    if ! command_exists ruby; then
        print_message "${YELLOW}" "Ruby is required for bashcov"
        print_message "${YELLOW}" "Install with: sudo apt-get install ruby ruby-dev"
        return 1
    fi
    
    # Check if gem is available
    if ! command_exists gem; then
        print_message "${YELLOW}" "RubyGems is required for bashcov"
        print_message "${YELLOW}" "Install with: sudo apt-get install ruby-dev"
        return 1
    fi
    
    print_message "${BLUE}" "Installing bashcov via gem..."
    if gem install bashcov; then
        print_message "${GREEN}" "✓ bashcov installed successfully"
        return 0
    else
        print_message "${RED}" "Failed to install bashcov"
        return 1
    fi
}

##
# Check if bashcov is already installed
##
check_installed() {
    if command_exists bashcov; then
        print_message "${GREEN}" "✓ bashcov is already installed: $(bashcov --version 2>&1 || echo 'unknown version')"
        return 0
    else
        print_message "${YELLOW}" "bashcov is not installed"
        return 1
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Code Coverage Tool Installer (bashcov)"
    echo
    
    # Check if already installed
    if check_installed; then
        print_message "${BLUE}" ""
        print_message "${BLUE}" "bashcov is already installed!"
        print_message "${YELLOW}" "You can use: bash scripts/generate_coverage_instrumented_optimized.sh"
        exit 0
    fi
    
    echo
    print_message "${BLUE}" "Installing bashcov..."
    
    if install_bashcov; then
        print_message "${GREEN}" ""
        print_message "${GREEN}" "✓ bashcov installed successfully!"
        print_message "${YELLOW}" "You can now use: bash scripts/generate_coverage_instrumented_optimized.sh"
        exit 0
    else
        print_message "${RED}" ""
        print_message "${RED}" "Failed to install bashcov"
        print_message "${YELLOW}" ""
        print_message "${YELLOW}" "Manual installation:"
        echo "  1. Install Ruby and RubyGems:"
        echo "     sudo apt-get install ruby ruby-dev"
        echo ""
        echo "  2. Install bashcov:"
        echo "     gem install bashcov"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
