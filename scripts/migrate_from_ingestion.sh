#!/usr/bin/env bash
#
# Migration Script from OSM-Notes-Ingestion
# Migrates monitoring scripts and updates references
#
# Version: 1.0.0
# Date: 2026-01-01
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly PROJECT_ROOT

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
# Print usage
##
usage() {
    cat << EOF
Usage: $0 [OPTIONS] INGESTION_REPO_PATH

Migrate monitoring scripts from OSM-Notes-Ingestion.

Options:
    --dry-run                Show what would be migrated without making changes
    --update-references      Update script references in OSM-Notes-Ingestion
    --backup                 Create backup before migration
    -h, --help               Show this help message

Arguments:
    INGESTION_REPO_PATH      Path to OSM-Notes-Ingestion repository

Examples:
    $0 /path/to/OSM-Notes-Ingestion
    $0 --dry-run /path/to/OSM-Notes-Ingestion
    $0 --update-references /path/to/OSM-Notes-Ingestion

EOF
}

##
# Check if ingestion repo exists
##
check_ingestion_repo() {
    local repo_path="${1}"
    
    if [[ ! -d "${repo_path}" ]]; then
        print_message "${RED}" "ERROR: Ingestion repository not found: ${repo_path}"
        return 1
    fi
    
    if [[ ! -d "${repo_path}/bin/monitor" ]]; then
        print_message "${YELLOW}" "WARNING: bin/monitor directory not found in ingestion repo"
        return 1
    fi
    
    return 0
}

##
# List scripts to migrate
##
list_scripts_to_migrate() {
    local ingestion_repo="${1}"
    
    print_message "${BLUE}" "Scripts found in OSM-Notes-Ingestion:"
    
    local scripts=(
        "${ingestion_repo}/bin/monitor/notesCheckVerifier.sh"
        "${ingestion_repo}/bin/monitor/processCheckPlanetNotes.sh"
        "${ingestion_repo}/bin/monitor/analyzeDatabasePerformance.sh"
    )
    
    local found=0
    for script in "${scripts[@]}"; do
        if [[ -f "${script}" ]]; then
            print_message "${GREEN}" "  ✓ ${script}"
            ((found++))
        else
            print_message "${YELLOW}" "  ⚠ Not found: ${script}"
        fi
    done
    
    echo
    print_message "${BLUE}" "Total scripts found: ${found}"
    
    return ${found}
}

##
# Create backup
##
create_backup() {
    local ingestion_repo="${1}"
    
    print_message "${BLUE}" "Creating backup of ingestion repository..."
    
    local backup_dir
    backup_dir="${PROJECT_ROOT}/tmp/migration_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${backup_dir}"
    
    # Backup monitoring scripts
    if [[ -d "${ingestion_repo}/bin/monitor" ]]; then
        cp -r "${ingestion_repo}/bin/monitor" "${backup_dir}/" 2>/dev/null || true
        print_message "${GREEN}" "✓ Backup created: ${backup_dir}"
        return 0
    else
        print_message "${YELLOW}" "⚠ No monitoring scripts to backup"
        return 1
    fi
}

##
# Update script references
##
update_references() {
    local ingestion_repo="${1}"
    
    print_message "${BLUE}" "Updating script references in OSM-Notes-Ingestion..."
    
    # This would update references to point to OSM-Notes-Monitoring
    # For now, just document what needs to be updated
    
    print_message "${YELLOW}" "Manual steps required:"
    echo "  1. Update script calls to use OSM-Notes-Monitoring scripts"
    echo "  2. Update configuration references if needed"
    echo "  3. Test updated scripts"
    echo ""
    print_message "${BLUE}" "See docs/INTEGRATION_CHANGES.md for recommended changes"
}

##
# Generate migration report
##
generate_migration_report() {
    local ingestion_repo="${1}"
    local report_file
    report_file="${PROJECT_ROOT}/reports/migration_$(date +%Y%m%d_%H%M%S).txt"
    
    print_message "${BLUE}" "Generating migration report..."
    
    mkdir -p "$(dirname "${report_file}")" 2>/dev/null || true
    
    {
        echo "Migration Report from OSM-Notes-Ingestion"
        echo "Generated: $(date)"
        echo "Source: ${ingestion_repo}"
        echo "Target: ${PROJECT_ROOT}"
        echo "=========================================="
        echo ""
        
        echo "Scripts Status:"
        list_scripts_to_migrate "${ingestion_repo}"
        echo ""
        
        echo "Integration Status:"
        echo "OSM-Notes-Monitoring can call OSM-Notes-Ingestion scripts directly"
        echo "No migration of scripts is required - they are called as-is"
        echo ""
        
        echo "Recommended Changes:"
        echo "See docs/INTEGRATION_CHANGES.md for integration recommendations"
        echo ""
        
    } | tee "${report_file}"
    
    print_message "${GREEN}" "✓ Report saved to: ${report_file}"
}

##
# Main
##
main() {
    local dry_run=false
    local update_references_flag=false
    local backup_flag=false
    local ingestion_repo=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --update-references)
                update_references_flag=true
                shift
                ;;
            --backup)
                backup_flag=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_message "${RED}" "Unknown option: ${1}"
                usage
                exit 1
                ;;
            *)
                ingestion_repo="${1}"
                shift
                ;;
        esac
    done
    
    if [[ -z "${ingestion_repo}" ]]; then
        # Try to get from properties
        if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
            # shellcheck source=/dev/null
            source "${PROJECT_ROOT}/etc/properties.sh"
            ingestion_repo="${INGESTION_REPO_PATH:-}"
        fi
        
        if [[ -z "${ingestion_repo}" ]]; then
            print_message "${RED}" "ERROR: Ingestion repository path required"
            usage
            exit 1
        fi
    fi
    
    print_message "${GREEN}" "Migration from OSM-Notes-Ingestion"
    print_message "${BLUE}" "==================================="
    echo
    
    if [[ "${dry_run}" == "true" ]]; then
        print_message "${YELLOW}" "DRY RUN MODE - No changes will be made"
        echo
    fi
    
    # Check ingestion repo
    if ! check_ingestion_repo "${ingestion_repo}"; then
        exit 1
    fi
    
    echo
    
    # List scripts
    if ! list_scripts_to_migrate "${ingestion_repo}"; then
        print_message "${YELLOW}" "No scripts found to migrate"
    fi
    
    echo
    
    # Create backup if requested
    if [[ "${backup_flag}" == "true" && "${dry_run}" != "true" ]]; then
        create_backup "${ingestion_repo}"
        echo
    fi
    
    # Update references if requested
    if [[ "${update_references_flag}" == "true" ]]; then
        update_references "${ingestion_repo}"
        echo
    fi
    
    # Generate report
    generate_migration_report "${ingestion_repo}"
    
    echo
    print_message "${GREEN}" "Migration analysis complete"
    print_message "${BLUE}" "Note: OSM-Notes-Monitoring calls OSM-Notes-Ingestion scripts directly"
    print_message "${BLUE}" "No script migration is required - see docs/INTEGRATION_CHANGES.md"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
