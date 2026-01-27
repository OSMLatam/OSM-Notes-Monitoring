#!/usr/bin/env bash
#
# Import Dashboard Script
# Imports dashboard configurations and data
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
 init_logging "${LOG_DIR}/import_dashboard.log" "importDashboard"
fi

##
# Show usage
##
usage() {
 cat << EOF
Import Dashboard Script

Usage: ${0} [OPTIONS] [INPUT_FILE] [DASHBOARD_TYPE]

Arguments:
    INPUT_FILE        Input file or directory to import from
    DASHBOARD_TYPE    Dashboard type (grafana, html, or 'all') (default: all)

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    -d, --dashboard DIR Dashboard directory (default: dashboards/)
    --backup            Create backup before importing
    --overwrite         Overwrite existing dashboards

Examples:
    ${0} dashboards_backup.tar grafana    # Import Grafana dashboards from tar
    ${0} backup/ all --backup              # Import all with backup
    ${0} dashboards.zip html --overwrite  # Import HTML dashboards from zip

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
# Create backup
##
create_backup() {
 local backup_dir
 backup_dir="${DASHBOARD_OUTPUT_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
 local dashboard_dir="${DASHBOARD_OUTPUT_DIR}"

 log_info "Creating backup to ${backup_dir}"
 mkdir -p "${backup_dir}"

 if [[ -d "${dashboard_dir}/grafana" ]]; then
  cp -r "${dashboard_dir}/grafana" "${backup_dir}/" 2> /dev/null || true
 fi

 if [[ -d "${dashboard_dir}/html" ]]; then
  cp -r "${dashboard_dir}/html" "${backup_dir}/" 2> /dev/null || true
 fi

 log_info "Backup created successfully"
}

##
# Import Grafana dashboard
#
# Arguments:
#   $1 - Input file or directory
#   $2 - Overwrite flag
##
import_grafana_dashboard() {
 local input="${1:?Input file or directory required}"
 local overwrite="${2:-false}"
 local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/grafana"

 log_info "Importing Grafana dashboards from ${input}"

 # Create dashboard directory
 mkdir -p "${dashboard_dir}"

 # Extract if archive
 local extract_dir
 if [[ -f "${input}" ]]; then
  extract_dir=$(mktemp -d)

  case "${input}" in
  *.tar.gz | *.tgz)
   tar -xzf "${input}" -C "${extract_dir}" 2> /dev/null || {
    log_error "Failed to extract tar archive"
    rm -rf "${extract_dir}"
    return 1
   }
   ;;
  *.zip)
   unzip -q "${input}" -d "${extract_dir}" 2> /dev/null || {
    log_error "Failed to extract zip archive"
    rm -rf "${extract_dir}"
    return 1
   }
   ;;
  *.json)
   cp "${input}" "${dashboard_dir}/" 2> /dev/null || true
   rm -rf "${extract_dir}"
   return 0
   ;;
  *)
   log_error "Unsupported file format: ${input}"
   rm -rf "${extract_dir}"
   return 1
   ;;
  esac

  # Find grafana directory in extracted files
  if [[ -d "${extract_dir}/grafana" ]]; then
   extract_dir="${extract_dir}/grafana"
  fi
 else
  # Input is a directory
  extract_dir="${input}"
  # Check if input contains grafana subdirectory
  if [[ -d "${extract_dir}/grafana" ]]; then
   extract_dir="${extract_dir}/grafana"
  fi
 fi

 # Copy files
 if [[ "${overwrite}" == "true" ]]; then
  rm -rf "${dashboard_dir:?}"/*
 fi

 # Ensure dashboard directory exists
 mkdir -p "${dashboard_dir}"

 # Copy files (handle both directory and file cases)
 if [[ -d "${extract_dir}" ]]; then
  # Check if extract_dir contains files directly or in a subdirectory
  if [[ -f "${extract_dir}/import.json" ]] || [[ -f "${extract_dir}/dashboard.json" ]]; then
   # Files are directly in extract_dir
   cp -r "${extract_dir}"/* "${dashboard_dir}/" 2> /dev/null || {
    log_warning "Some files may not have been copied"
   }
  elif [[ -d "${extract_dir}/grafana" ]]; then
   # Files are in grafana subdirectory
   cp -r "${extract_dir}/grafana"/* "${dashboard_dir}/" 2> /dev/null || {
    log_warning "Some files may not have been copied"
   }
  else
   # Try to copy everything
   cp -r "${extract_dir}"/* "${dashboard_dir}/" 2> /dev/null || {
    log_warning "Some files may not have been copied"
   }
  fi
 elif [[ -f "${extract_dir}" ]]; then
  cp "${extract_dir}" "${dashboard_dir}/" 2> /dev/null || {
   log_warning "File may not have been copied"
  }
 fi

 # Cleanup temp directory if created
 if [[ -f "${input}" ]] && [[ -d "${extract_dir}" ]] && [[ "${extract_dir}" != "${dashboard_dir}" ]]; then
  rm -rf "${extract_dir}"
 fi

 log_info "Grafana dashboards imported successfully"
}

##
# Import HTML dashboard
#
# Arguments:
#   $1 - Input file or directory
#   $2 - Overwrite flag
##
import_html_dashboard() {
 local input="${1:?Input file or directory required}"
 local overwrite="${2:-false}"
 local dashboard_dir="${DASHBOARD_OUTPUT_DIR}/html"

 log_info "Importing HTML dashboards from ${input}"

 # Create dashboard directory
 mkdir -p "${dashboard_dir}"

 # Extract if archive
 local extract_dir="${dashboard_dir}"
 if [[ -f "${input}" ]]; then
  extract_dir=$(mktemp -d)

  case "${input}" in
  *.tar.gz | *.tgz)
   tar -xzf "${input}" -C "${extract_dir}" 2> /dev/null || {
    log_error "Failed to extract tar archive"
    rm -rf "${extract_dir}"
    return 1
   }
   ;;
  *.zip)
   unzip -q "${input}" -d "${extract_dir}" 2> /dev/null || {
    log_error "Failed to extract zip archive"
    rm -rf "${extract_dir}"
    return 1
   }
   ;;
  *.html)
   cp "${input}" "${dashboard_dir}/" 2> /dev/null || true
   rm -rf "${extract_dir}"
   return 0
   ;;
  *)
   log_error "Unsupported file format: ${input}"
   rm -rf "${extract_dir}"
   return 1
   ;;
  esac

  # Find html directory in extracted files
  if [[ -d "${extract_dir}/html" ]]; then
   extract_dir="${extract_dir}/html"
  fi
 fi

 # Copy files
 if [[ "${overwrite}" == "true" ]]; then
  rm -rf "${dashboard_dir:?}"/*
 fi

 cp -r "${extract_dir}"/* "${dashboard_dir}/" 2> /dev/null || {
  log_warning "Some files may not have been copied"
 }

 # Cleanup temp directory if created
 if [[ -f "${input}" ]] && [[ -d "${extract_dir}" ]]; then
  rm -rf "${extract_dir}"
 fi

 log_info "HTML dashboards imported successfully"
}

##
# Main function
##
main() {
 local input="${1:?Input file or directory required}"
 local dashboard_type="${2:-all}"
 local create_backup_flag="${3:-false}"
 local overwrite="${4:-false}"

 # Validate input file/directory exists
 if [[ ! -f "${input}" ]] && [[ ! -d "${input}" ]]; then
  log_error "Input file or directory does not exist: ${input}"
  return 1
 fi

 # Load configuration
 load_config "${CONFIG_FILE:-}"

 # Create backup if requested
 if [[ "${create_backup_flag}" == "true" ]]; then
  create_backup
 fi

 # Import dashboards based on type
 case "${dashboard_type}" in
 grafana)
  import_grafana_dashboard "${input}" "${overwrite}"
  ;;
 html)
  import_html_dashboard "${input}" "${overwrite}"
  ;;
 all)
  import_grafana_dashboard "${input}" "${overwrite}"
  import_html_dashboard "${input}" "${overwrite}"
  ;;
 *)
  log_error "Unknown dashboard type: ${dashboard_type}"
  usage
  exit 1
  ;;
 esac

 log_info "Dashboard import completed"
}

# Parse command line arguments
INPUT_FILE=""
DASHBOARD_TYPE="all"
CREATE_BACKUP="false"
OVERWRITE="false"

while [[ $# -gt 0 ]]; do
 case "${1}" in
 -h | --help)
  usage
  exit 0
  ;;
 -v | --verbose)
  export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
  shift
  ;;
 -q | --quiet)
  export LOG_LEVEL="${LOG_LEVEL_ERROR}"
  shift
  ;;
 -c | --config)
  export CONFIG_FILE="${2}"
  shift 2
  ;;
 -d | --dashboard)
  export DASHBOARD_OUTPUT_DIR="${2}"
  shift 2
  ;;
 --backup)
  CREATE_BACKUP="true"
  shift
  ;;
 --overwrite)
  OVERWRITE="true"
  shift
  ;;
 *)
  if [[ -z "${INPUT_FILE}" ]]; then
   INPUT_FILE="${1}"
  elif [[ -z "${DASHBOARD_TYPE}" ]] || [[ "${DASHBOARD_TYPE}" == "all" ]]; then
   DASHBOARD_TYPE="${1}"
  fi
  shift
  ;;
 esac
done

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 if [[ -z "${INPUT_FILE}" ]]; then
  log_error "Input file or directory is required"
  usage
  exit 1
 fi

 main "${INPUT_FILE}" "${DASHBOARD_TYPE}" "${CREATE_BACKUP}" "${OVERWRITE}"
fi
