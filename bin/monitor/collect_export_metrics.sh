#!/usr/bin/env bash
#
# Export Metrics Collection Script
# Collects metrics from Analytics export processes (JSON, CSV, GitHub pushes)
#
# Version: 1.0.0
# Date: 2026-01-10
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
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Initialize logging only if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 init_logging "${LOG_DIR}/export_metrics.log" "collectExportMetrics"
fi

# Component name
readonly COMPONENT="ANALYTICS"

# Export directories (allow override in test mode)
if [[ "${TEST_MODE:-false}" != "true" ]]; then
 readonly JSON_EXPORT_DIR="${JSON_EXPORT_DIR:-output/json}"
 readonly CSV_EXPORT_DIR="${CSV_EXPORT_DIR:-exports/csv}"
 readonly EXPORT_LOG_DIR="${EXPORT_LOG_DIR:-logs}"
else
 JSON_EXPORT_DIR="${JSON_EXPORT_DIR:-output/json}"
 CSV_EXPORT_DIR="${CSV_EXPORT_DIR:-exports/csv}"
 EXPORT_LOG_DIR="${EXPORT_LOG_DIR:-logs}"
fi

##
# Show usage
##
usage() {
 cat << EOF
Export Metrics Collection Script

Collects metrics from Analytics export processes (JSON, CSV, GitHub pushes).

Usage: $0 [OPTIONS]

Options:
    -h, --help            Show this help message

Examples:
    # Collect all export metrics
    $0
EOF
}

##
# Collect JSON export metrics
##
collect_json_export_metrics() {
 log_info "${COMPONENT}: Collecting JSON export metrics"

 local json_dir="${JSON_EXPORT_DIR}"
 local file_count=0
 local total_size_bytes=0
 local last_export_timestamp=0

 if [[ -d "${json_dir}" ]]; then
  # Count JSON files
  if command -v find > /dev/null 2>&1; then
   file_count=$(find "${json_dir}" -type f -name "*.json" 2> /dev/null | wc -l | tr -d '[:space:]' || echo "0")

   # Calculate total size
   if command -v du > /dev/null 2>&1; then
    total_size_bytes=$(du -sb "${json_dir}" 2> /dev/null | awk '{print $1}' || echo "0")
   fi

   # Find most recent file modification time
   if command -v find > /dev/null 2>&1 && command -v stat > /dev/null 2>&1; then
    local latest_file
    latest_file=$(find "${json_dir}" -type f -name "*.json" -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | awk '{print $2}' || echo "")
    if [[ -n "${latest_file}" ]] && [[ -f "${latest_file}" ]]; then
     last_export_timestamp=$(stat -c %Y "${latest_file}" 2> /dev/null || echo "0")
    fi
   fi
  fi
 fi

 record_metric "${COMPONENT}" "export_files_total" "${file_count}" "component=analytics,type=json"
 record_metric "${COMPONENT}" "export_size_bytes" "${total_size_bytes}" "component=analytics,type=json"
 if [[ ${last_export_timestamp} -gt 0 ]]; then
  local seconds_since_export
  seconds_since_export=$(($(date +%s) - last_export_timestamp))
  record_metric "${COMPONENT}" "export_last_export_seconds" "${seconds_since_export}" "component=analytics,type=json"
 fi

 log_info "${COMPONENT}: JSON exports - Files: ${file_count}, Size: ${total_size_bytes} bytes"
 return 0
}

##
# Collect CSV export metrics
##
collect_csv_export_metrics() {
 log_info "${COMPONENT}: Collecting CSV export metrics"

 local csv_dir="${CSV_EXPORT_DIR}"
 local file_count=0
 local total_size_bytes=0
 local last_export_timestamp=0

 if [[ -d "${csv_dir}" ]]; then
  # Count CSV files
  if command -v find > /dev/null 2>&1; then
   file_count=$(find "${csv_dir}" -type f -name "*.csv" 2> /dev/null | wc -l | tr -d '[:space:]' || echo "0")

   # Calculate total size
   if command -v du > /dev/null 2>&1; then
    total_size_bytes=$(du -sb "${csv_dir}" 2> /dev/null | awk '{print $1}' || echo "0")
   fi

   # Find most recent file modification time
   if command -v find > /dev/null 2>&1 && command -v stat > /dev/null 2>&1; then
    local latest_file
    latest_file=$(find "${csv_dir}" -type f -name "*.csv" -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | awk '{print $2}' || echo "")
    if [[ -n "${latest_file}" ]] && [[ -f "${latest_file}" ]]; then
     last_export_timestamp=$(stat -c %Y "${latest_file}" 2> /dev/null || echo "0")
    fi
   fi
  fi
 fi

 record_metric "${COMPONENT}" "export_files_total" "${file_count}" "component=analytics,type=csv"
 record_metric "${COMPONENT}" "export_size_bytes" "${total_size_bytes}" "component=analytics,type=csv"
 if [[ ${last_export_timestamp} -gt 0 ]]; then
  local seconds_since_export
  seconds_since_export=$(($(date +%s) - last_export_timestamp))
  record_metric "${COMPONENT}" "export_last_export_seconds" "${seconds_since_export}" "component=analytics,type=csv"
 fi

 log_info "${COMPONENT}: CSV exports - Files: ${file_count}, Size: ${total_size_bytes} bytes"
 return 0
}

##
# Validate JSON schema (basic validation)
##
validate_json_schema() {
 local json_file="${1}"
 local validation_status=0

 if [[ ! -f "${json_file}" ]]; then
  return 1
 fi

 # Basic JSON validation using Python or jq if available
 if command -v python3 > /dev/null 2>&1; then
  if python3 -m json.tool "${json_file}" > /dev/null 2>&1; then
   validation_status=1
  fi
 elif command -v jq > /dev/null 2>&1; then
  if jq empty "${json_file}" > /dev/null 2>&1; then
   validation_status=1
  fi
 else
  # Fallback: check if file is not empty and contains basic JSON structure
  if [[ -s "${json_file}" ]] && grep -q "{" "${json_file}" && grep -q "}" "${json_file}"; then
   validation_status=1
  fi
 fi

 return $((1 - validation_status))
}

##
# Collect JSON schema validation metrics
##
collect_json_validation_metrics() {
 log_info "${COMPONENT}: Collecting JSON schema validation metrics"

 local json_dir="${JSON_EXPORT_DIR}"
 local total_files=0
 local valid_files=0
 local invalid_files=0

 if [[ -d "${json_dir}" ]]; then
  if command -v find > /dev/null 2>&1; then
   while IFS= read -r json_file; do
    if [[ -n "${json_file}" ]] && [[ -f "${json_file}" ]]; then
     total_files=$((total_files + 1))
     if validate_json_schema "${json_file}"; then
      valid_files=$((valid_files + 1))
     else
      invalid_files=$((invalid_files + 1))
     fi
    fi
   done < <(find "${json_dir}" -type f -name "*.json" 2> /dev/null | head -100 || true) # Limit to 100 files for performance
  fi
 fi

 local validation_rate=0
 if [[ ${total_files} -gt 0 ]]; then
  validation_rate=$((valid_files * 100 / total_files))
 fi

 record_metric "${COMPONENT}" "export_validation_total" "${total_files}" "component=analytics,type=json,status=checked"
 record_metric "${COMPONENT}" "export_validation_valid" "${valid_files}" "component=analytics,type=json,status=valid"
 record_metric "${COMPONENT}" "export_validation_invalid" "${invalid_files}" "component=analytics,type=json,status=invalid"
 record_metric "${COMPONENT}" "export_validation_rate" "${validation_rate}" "component=analytics,type=json"

 log_info "${COMPONENT}: JSON validation - Total: ${total_files}, Valid: ${valid_files}, Invalid: ${invalid_files}, Rate: ${validation_rate}%"
 return 0
}

##
# Check GitHub push status
##
check_github_push_status() {
 log_info "${COMPONENT}: Checking GitHub push status"

 local push_success=0
 local last_push_timestamp=0

 # Check if we're in a git repository
 if ! command -v git > /dev/null 2>&1; then
  log_debug "${COMPONENT}: git command not available"
  record_metric "${COMPONENT}" "export_github_push_status" "0" "component=analytics,status=unknown"
  return 0
 fi

 # Try to find git repository (could be in parent directories)
 local git_dir
 git_dir=$(git rev-parse --git-dir 2> /dev/null || echo "")

 if [[ -z "${git_dir}" ]]; then
  log_debug "${COMPONENT}: Not in a git repository"
  record_metric "${COMPONENT}" "export_github_push_status" "0" "component=analytics,status=no_repo"
  return 0
 fi

 # Check if remote 'origin' exists and points to GitHub
 local remote_url
 remote_url=$(git remote get-url origin 2> /dev/null || echo "")
 if [[ -z "${remote_url}" ]] || [[ "${remote_url}" != *"github.com"* ]]; then
  log_debug "${COMPONENT}: Remote origin is not GitHub"
  record_metric "${COMPONENT}" "export_github_push_status" "0" "component=analytics,status=no_github_remote"
  return 0
 fi

 # Check last push timestamp by looking at reflog or last commit
 local last_commit_timestamp
 last_commit_timestamp=$(git log -1 --format=%ct 2> /dev/null || echo "0")

 if [[ ${last_commit_timestamp} -gt 0 ]]; then
  # Check if there are unpushed commits (simplified check)
  local unpushed_commits
  unpushed_commits=$(git log origin/main..HEAD --oneline 2> /dev/null | wc -l | tr -d '[:space:]' || echo "0")

  if [[ ${unpushed_commits} -eq 0 ]]; then
   push_success=1
   last_push_timestamp=${last_commit_timestamp}
  fi

  local seconds_since_push
  seconds_since_push=$(($(date +%s) - last_commit_timestamp))
  record_metric "${COMPONENT}" "export_github_push_last_seconds" "${seconds_since_push}" "component=analytics"
 fi

 record_metric "${COMPONENT}" "export_github_push_status" "${push_success}" "component=analytics,status=$([ ${push_success} -eq 1 ] && echo "success" || echo "pending")"

 log_info "${COMPONENT}: GitHub push status - Success: ${push_success}, Last push: ${last_push_timestamp}"
 return 0
}

##
# Parse export logs (if they exist)
##
parse_export_logs() {
 log_info "${COMPONENT}: Parsing export logs"

 local log_dir="${EXPORT_LOG_DIR}"
 local last_export_duration=0
 local last_export_status=0

 if [[ -d "${log_dir}" ]]; then
  # Look for export-related log files
  local export_logs
  export_logs=$(find "${log_dir}" -type f -name "*export*.log" -o -name "*json*.log" -o -name "*csv*.log" 2> /dev/null | head -5 || true)

  if [[ -n "${export_logs}" ]]; then
   local latest_log
   latest_log=$(echo "${export_logs}" | xargs ls -t 2> /dev/null | head -1 || echo "")

   if [[ -n "${latest_log}" ]] && [[ -f "${latest_log}" ]]; then
    # Try to extract duration and status from log
    # This is a simplified parser - adjust based on actual log format
    if grep -q "completed successfully\|finished successfully" "${latest_log}" 2> /dev/null; then
     last_export_status=1

     # Try to extract duration (look for patterns like "Duration: 300s" or "took 300 seconds")
     local duration_match
     duration_match=$(grep -oE "Duration:? [0-9]+|took [0-9]+" "${latest_log}" 2> /dev/null | head -1 | grep -oE "[0-9]+" || echo "0")
     if [[ -n "${duration_match}" ]] && [[ "${duration_match}" =~ ^[0-9]+$ ]]; then
      last_export_duration=${duration_match}
     fi
    fi
   fi
  fi
 fi

 if [[ ${last_export_duration} -gt 0 ]]; then
  record_metric "${COMPONENT}" "export_duration_seconds" "${last_export_duration}" "component=analytics"
 fi
 record_metric "${COMPONENT}" "export_status" "${last_export_status}" "component=analytics,status=$([ ${last_export_status} -eq 1 ] && echo "success" || echo "unknown")"

 log_info "${COMPONENT}: Export logs - Status: ${last_export_status}, Duration: ${last_export_duration}s"
 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting export metrics collection"

 # Load configuration
 if ! load_monitoring_config; then
  log_error "${COMPONENT}: Failed to load monitoring configuration"
  exit 1
 fi

 # Collect JSON export metrics
 collect_json_export_metrics || true

 # Collect CSV export metrics
 collect_csv_export_metrics || true

 # Collect JSON validation metrics
 collect_json_validation_metrics || true

 # Check GitHub push status
 check_github_push_status || true

 # Parse export logs
 parse_export_logs || true

 log_info "${COMPONENT}: Export metrics collection completed"
 return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
