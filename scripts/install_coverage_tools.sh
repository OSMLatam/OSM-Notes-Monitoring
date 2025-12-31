#!/usr/bin/env bash
#
# Install Code Coverage Tools
# Installs kcov or bashcov for code coverage measurement
#
# Version: 1.0.0
# Date: 2025-12-31
#

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Tool to install
TOOL="${1:-auto}"

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
# Install kcov from source
##
install_kcov_from_source() {
    print_message "${BLUE}" "Installing kcov from source..."
    
    # Check dependencies
    local missing_deps=()
    
    if ! command_exists cmake; then
        missing_deps+=("cmake")
    fi
    
    if ! command_exists g++; then
        missing_deps+=("g++")
    fi
    
    if ! command_exists make; then
        missing_deps+=("make")
    fi
    
    if ! command_exists git; then
        missing_deps+=("git")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_message "${YELLOW}" "Missing dependencies: ${missing_deps[*]}"
        print_message "${YELLOW}" "Install with: sudo apt-get install ${missing_deps[*]}"
        return 1
    fi
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    print_message "${BLUE}" "Cloning kcov repository..."
    if ! git clone https://github.com/SimonKagstrom/kcov.git; then
        print_message "${RED}" "Failed to clone kcov repository"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    cd kcov
    
    print_message "${BLUE}" "Building kcov..."
    mkdir build
    cd build
    
    if ! cmake ..; then
        print_message "${RED}" "CMake configuration failed"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    if ! make; then
        print_message "${RED}" "Build failed"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    print_message "${BLUE}" "Installing kcov..."
    if sudo make install; then
        print_message "${GREEN}" "✓ kcov installed successfully"
        rm -rf "${temp_dir}"
        return 0
    else
        print_message "${RED}" "Installation failed"
        rm -rf "${temp_dir}"
        return 1
    fi
}

##
# Install kcov using package manager
##
install_kcov_package() {
    print_message "${BLUE}" "Attempting to install kcov from package manager..."
    
    if command_exists apt-get; then
        # Try to add PPA or use alternative method
        print_message "${YELLOW}" "kcov not available in default repositories"
        print_message "${YELLOW}" "Trying to install from source..."
        install_kcov_from_source
    elif command_exists dnf; then
        if sudo dnf install -y kcov; then
            print_message "${GREEN}" "✓ kcov installed successfully"
            return 0
        else
            print_message "${YELLOW}" "Package not found, trying from source..."
            install_kcov_from_source
        fi
    elif command_exists brew; then
        if brew install kcov; then
            print_message "${GREEN}" "✓ kcov installed successfully"
            return 0
        else
            print_message "${RED}" "Failed to install kcov via Homebrew"
            return 1
        fi
    else
        print_message "${YELLOW}" "No supported package manager found, installing from source..."
        install_kcov_from_source
    fi
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
# Check what's already installed
##
check_installed() {
    local installed=()
    
    if command_exists kcov; then
        installed+=("kcov")
        print_message "${GREEN}" "✓ kcov is already installed: $(kcov --version 2>&1 | head -1 || echo 'unknown version')"
    fi
    
    if command_exists bashcov; then
        installed+=("bashcov")
        print_message "${GREEN}" "✓ bashcov is already installed: $(bashcov --version 2>&1 || echo 'unknown version')"
    fi
    
    if [[ ${#installed[@]} -eq 0 ]]; then
        print_message "${YELLOW}" "No coverage tools found"
        return 1
    else
        print_message "${GREEN}" "Installed tools: ${installed[*]}"
        return 0
    fi
}

##
# Main
##
main() {
    print_message "${GREEN}" "Code Coverage Tools Installer"
    echo
    
    # Check what's already installed
    if check_installed; then
        print_message "${BLUE}" ""
        print_message "${BLUE}" "Coverage tools are already installed!"
        print_message "${YELLOW}" "You can use: ./scripts/generate_coverage_instrumented.sh"
        exit 0
    fi
    
    echo
    print_message "${BLUE}" "Available tools:"
    echo "  1. kcov (recommended) - Fast, good HTML reports"
    echo "  2. bashcov - Ruby-based, alternative option"
    echo ""
    
    if [[ "${TOOL}" == "auto" ]]; then
        print_message "${BLUE}" "Auto-detecting best option..."
        
        # Try kcov first
        if install_kcov_package; then
            print_message "${GREEN}" ""
            print_message "${GREEN}" "✓ kcov installed successfully!"
            print_message "${YELLOW}" "You can now use: ./scripts/generate_coverage_instrumented.sh"
            exit 0
        fi
        
        # Fallback to bashcov
        print_message "${YELLOW}" ""
        print_message "${YELLOW}" "kcov installation failed, trying bashcov..."
        if install_bashcov; then
            print_message "${GREEN}" ""
            print_message "${GREEN}" "✓ bashcov installed successfully!"
            print_message "${YELLOW}" "You can now use: ./scripts/generate_coverage_instrumented.sh"
            exit 0
        fi
        
        print_message "${RED}" ""
        print_message "${RED}" "Failed to install any coverage tool"
        print_message "${YELLOW}" ""
        print_message "${YELLOW}" "Manual installation options:"
        echo "  1. Install kcov from source:"
        echo "     git clone https://github.com/SimonKagstrom/kcov.git"
        echo "     cd kcov && mkdir build && cd build"
        echo "     cmake .. && make && sudo make install"
        echo ""
        echo "  2. Install bashcov (requires Ruby):"
        echo "     sudo apt-get install ruby ruby-dev"
        echo "     gem install bashcov"
        exit 1
    elif [[ "${TOOL}" == "kcov" ]]; then
        if install_kcov_package; then
            print_message "${GREEN}" ""
            print_message "${GREEN}" "✓ kcov installed successfully!"
            exit 0
        else
            exit 1
        fi
    elif [[ "${TOOL}" == "bashcov" ]]; then
        if install_bashcov; then
            print_message "${GREEN}" ""
            print_message "${GREEN}" "✓ bashcov installed successfully!"
            exit 0
        else
            exit 1
        fi
    else
        print_message "${RED}" "Unknown tool: ${TOOL}"
        print_message "${YELLOW}" "Usage: $0 [kcov|bashcov|auto]"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
