#!/usr/bin/env bash
#
# Export Dashboard Script
# Exports dashboard configurations and data
#
# Version: 1.0.0
# Date: 2025-12-27
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Only initialize logging if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Initialize logging
    init_logging "${LOG_DIR}/export_dashboard.log" "exportDashboard"
fi

##
# Show usage
##
usage() {
    cat << EOF
Export Dashboard Script

Usage: ${0} [OPTIONS] [DASHBOARD_TYPE] [OUTPUT_FILE]

Arguments:
    DASHBOARD_TYPE    Dashboard type (grafana, html, or 'all') (default: all)
    OUTPUT_FILE       Output file or directory (default: stdout or dashboards/)

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    -d, --dashboard DIR Dashboard directory (default: dashboards/)
    --format FORMAT     Export format (json, tar, zip) (default: json)
    --component COMP     Export specific component only
    --include-data       Include metrics data in export

Examples:
    ${0} grafana dashboards_backup.tar    # Export Grafana dashboards as tar
    ${0} html --format zip                 # Export HTML dashboards as zip
    ${0} all backup/ --include-data        # Export all with data

EOF
}

##
# Load configuration
##
load_config() {
    local config_file="${1:-${PROJECT_ROOT}/config/monitoring.conf}"
    
    if [[ -f "${config_file}" ]]; then
        # shellcheck disable=SC1090
        source "${config_file}" || true
    fi
    
    # Set defaults
    export DASHBOARD_OUTPUT_DIR="${DASHBOARD_OUTPUT_DIR:-${PROJECT_ROOT}/dashboards}"
}

##
# Export Grafana dashboard
#
# Arguments:
#   $1 - Output file or directory
#   $2 - Include data flag
#   $3 - Export format (tar, zip) (optional)
##
export_grafana_dashboard() {
    local output="${1:-}"
    local include_data="${2:-false}"
    local export_format="${3:-tar}"
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/grafana"
    
    if [[ ! -d "${dashboard_dir}" ]]; then
        log_warning "Grafana dashboard directory not found: ${dashboard_dir}"
        return 0  # Return success with warning
    fi
    
    if [[ -z "${output}" ]]; then
        output="${dashboard_dir}"
    fi
    
    log_info "Exporting Grafana dashboards to ${output}"
    
    # Check if output is a directory or should be treated as directory path
    # If output ends with /grafana or /html, and parent directory exists and is a directory, treat as directory
    local output_parent
    output_parent=$(dirname "${output}")
    local should_copy_to_dir=false
    if [[ -d "${output}" ]]; then
        should_copy_to_dir=true
    elif [[ -d "${output_parent}" ]]; then
        if [[ "${output}" == */grafana ]] || [[ "${output}" == */html ]]; then
            should_copy_to_dir=true
        fi
    fi
    
    if [[ "${should_copy_to_dir}" == "true" ]]; then
        # Copy to directory
        # If output already ends with /grafana, don't add another grafana subdirectory
        if [[ "${output}" == */grafana ]]; then
            mkdir -p "${output}"
            cp -r "${dashboard_dir}"/* "${output}/" 2>/dev/null || true
        else
            mkdir -p "${output}/grafana"
            cp -r "${dashboard_dir}"/* "${output}/grafana/" 2>/dev/null || true
        fi
        
        if [[ "${include_data}" == "true" ]]; then
            # Export metrics data
            local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
            mkdir -p "${output}/metrics"
            local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
            for comp in "${components[@]}"; do
                "${metrics_script}" "${comp}" json > "${output}/metrics/${comp}_metrics.json" 2>/dev/null || true
            done
        fi
    else
        # Export as archive
        local temp_dir
        temp_dir=$(mktemp -d)
        cp -r "${dashboard_dir}"/* "${temp_dir}/" 2>/dev/null || true
        
        if [[ "${include_data}" == "true" ]]; then
            local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
            mkdir -p "${temp_dir}/metrics"
            local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
            for comp in "${components[@]}"; do
                "${metrics_script}" "${comp}" json > "${temp_dir}/metrics/${comp}_metrics.json" 2>/dev/null || true
            done
        fi
        
        # Create archive based on format
        case "${export_format}" in
            zip)
                (cd "${temp_dir}" && zip -r "${output}.zip" .) 2>/dev/null || {
                    log_error "Failed to create zip archive"
                    rm -rf "${temp_dir}"
                    return 1
                }
                ;;
            tar|*)
                tar -czf "${output}.tar.gz" -C "${temp_dir}" . 2>/dev/null || {
                    log_error "Failed to create tar archive"
                    rm -rf "${temp_dir}"
                    return 1
                }
                ;;
        esac
        
        rm -rf "${temp_dir}"
    fi
    
    log_info "Grafana dashboards exported successfully"
}

##
# Export HTML dashboard
#
# Arguments:
#   $1 - Output file or directory
#   $2 - Include data flag
#   $3 - Export format (tar, zip) (optional)
##
export_html_dashboard() {
    local output="${1:-}"
    local include_data="${2:-false}"
    local export_format="${3:-tar}"
    local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/html"
    
    if [[ ! -d "${dashboard_dir}" ]]; then
        log_warning "HTML dashboard directory not found: ${dashboard_dir}"
        return 0  # Return success with warning
    fi
    
    if [[ -z "${output}" ]]; then
        output="${dashboard_dir}"
    fi
    
    log_info "Exporting HTML dashboards to ${output}"
    
    # Check if output is a directory or should be treated as directory path
    # If output ends with /grafana or /html, and parent directory exists and is a directory, treat as directory
    local output_parent
    output_parent=$(dirname "${output}")
    local should_copy_to_dir=false
    if [[ -d "${output}" ]]; then
        should_copy_to_dir=true
    elif [[ -d "${output_parent}" ]]; then
        if [[ "${output}" == */grafana ]] || [[ "${output}" == */html ]]; then
            should_copy_to_dir=true
        fi
    fi
    
    if [[ "${should_copy_to_dir}" == "true" ]]; then
        # Copy to directory
        # If output already ends with /html, don't add another html subdirectory
        if [[ "${output}" == */html ]]; then
            mkdir -p "${output}"
            cp -r "${dashboard_dir}"/* "${output}/" 2>/dev/null || true
        else
            mkdir -p "${output}/html"
            cp -r "${dashboard_dir}"/* "${output}/html/" 2>/dev/null || true
        fi
        
        if [[ "${include_data}" == "true" ]]; then
            # Export metrics data
            local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
            mkdir -p "${output}/metrics"
            local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
            for comp in "${components[@]}"; do
                "${metrics_script}" "${comp}" json > "${output}/metrics/${comp}_metrics.json" 2>/dev/null || true
            done
        fi
    else
        # Export as archive
        local temp_dir
        temp_dir=$(mktemp -d)
        cp -r "${dashboard_dir}"/* "${temp_dir}/" 2>/dev/null || true
        
        if [[ "${include_data}" == "true" ]]; then
            local metrics_script="${SCRIPT_DIR}/generateMetrics.sh"
            mkdir -p "${temp_dir}/metrics"
            local components=("ingestion" "analytics" "wms" "api" "infrastructure" "data")
            for comp in "${components[@]}"; do
                "${metrics_script}" "${comp}" json > "${temp_dir}/metrics/${comp}_metrics.json" 2>/dev/null || true
            done
        fi
        
        # Create archive based on format
        case "${EXPORT_FORMAT:-tar}" in
            zip)
                (cd "${temp_dir}" && zip -r "${output}.zip" .) 2>/dev/null || {
                    log_error "Failed to create zip archive"
                    rm -rf "${temp_dir}"
                    return 1
                }
                ;;
            tar|*)
                tar -czf "${output}.tar.gz" -C "${temp_dir}" . 2>/dev/null || {
                    log_error "Failed to create tar archive"
                    rm -rf "${temp_dir}"
                    return 1
                }
                ;;
        esac
        
        rm -rf "${temp_dir}"
    fi
    
    log_info "HTML dashboards exported successfully"
}

##
# Main function
##
main() {
    local dashboard_type="${1:-all}"
    local output="${2:-}"
    local include_data="${3:-false}"
    
    # Load configuration
    load_config "${CONFIG_FILE:-}"
    
    # Export dashboards based on type
    case "${dashboard_type}" in
        grafana)
            export_grafana_dashboard "${output}" "${include_data}" "${EXPORT_FORMAT:-tar}"
            ;;
        html)
            export_html_dashboard "${output}" "${include_data}" "${EXPORT_FORMAT:-tar}"
            ;;
        all)
            export_grafana_dashboard "${output}/grafana" "${include_data}" "${EXPORT_FORMAT:-tar}"
            export_html_dashboard "${output}/html" "${include_data}" "${EXPORT_FORMAT:-tar}"
            ;;
        *)
            echo "ERROR: Unknown dashboard type: ${dashboard_type}" >&2
            echo "Valid types are: grafana, html, all" >&2
            usage
            exit 1
            ;;
    esac
    
    log_info "Dashboard export completed"
}

# Parse command line arguments only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    DASHBOARD_TYPE="all"
    OUTPUT_FILE=""
    INCLUDE_DATA="false"
    EXPORT_FORMAT="tar"

    while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
            shift
            ;;
        -q|--quiet)
            export LOG_LEVEL="${LOG_LEVEL_ERROR}"
            shift
            ;;
        -c|--config)
            export CONFIG_FILE="${2}"
            shift 2
            ;;
        -d|--dashboard)
            export DASHBOARD_OUTPUT_DIR="${2}"
            shift 2
            ;;
        --format)
            EXPORT_FORMAT="${2}"
            shift 2
            ;;
        --component)
            # Component filtering not yet implemented
            shift 2
            ;;
        --include-data)
            INCLUDE_DATA="true"
            shift
            ;;
        *)
            # First non-option argument is dashboard type
            if [[ "${DASHBOARD_TYPE}" == "all" ]]; then
                # Check if it's a valid dashboard type
                case "${1}" in
                    grafana|html|all)
                        DASHBOARD_TYPE="${1}"
                        ;;
                    *)
                        # If it's not a valid type and no output file specified, it's an error
                        # Otherwise, treat it as output file
                        if [[ -z "${OUTPUT_FILE}" ]]; then
                            # Check if it looks like a file path (contains / or .) or if it's clearly not a type
                            if [[ "${1}" =~ / ]] || [[ "${1}" =~ \. ]]; then
                                OUTPUT_FILE="${1}"
                            else
                                # Invalid dashboard type
                                echo "ERROR: Unknown dashboard type: ${1}" >&2
                                echo "Valid types are: grafana, html, all" >&2
                                usage
                                exit 1
                            fi
                        else
                            # Already have output file, so this must be an invalid type
                            echo "ERROR: Unknown dashboard type: ${1}" >&2
                            echo "Valid types are: grafana, html, all" >&2
                            usage
                            exit 1
                        fi
                        ;;
                esac
            elif [[ -z "${DASHBOARD_TYPE}" ]]; then
                # Check if it's a valid dashboard type
                case "${1}" in
                    grafana|html|all)
                        DASHBOARD_TYPE="${1}"
                        ;;
                    *)
                        # If it's not a valid type, treat it as output
                        OUTPUT_FILE="${1}"
                        ;;
                esac
            elif [[ -z "${OUTPUT_FILE}" ]]; then
                OUTPUT_FILE="${1}"
            fi
            shift
            ;;
    esac
    done

    # Run main
    main "${DASHBOARD_TYPE}" "${OUTPUT_FILE}" "${INCLUDE_DATA}"
fi
