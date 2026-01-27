#!/usr/bin/env bash
#
# Data Freshness Monitoring Script
# Monitors data backups, repository sync status, file integrity, and storage availability
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
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# Only initialize logging if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 # Initialize logging
 init_logging "${LOG_DIR}/data.log" "monitorData"
fi

# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]] || [[ "${TEST_MODE:-false}" == "true" ]]; then
 COMPONENT="${COMPONENT:-DATA}"
fi
readonly COMPONENT

##
# Show usage
##
usage() {
 cat << EOF
Data Freshness Monitoring Script

Usage: ${0} [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file
    --check CHECK       Run specific check only
                        Available checks: backup_freshness, repo_sync, file_integrity, storage_availability

Examples:
    ${0}                          # Run all checks
    ${0} --check backup_freshness # Run only backup freshness check
    ${0} -v                       # Run with verbose logging

EOF
}

##
# Load configuration
##
load_config() {
 local config_file="${1:-${PROJECT_ROOT}/config/monitoring.conf}"

 if [[ -f "${config_file}" ]]; then
  # shellcheck disable=SC1090
  source "${config_file}"
 elif [[ -f "${PROJECT_ROOT}/config/monitoring.conf.example" ]]; then
  log_warning "${COMPONENT}: Configuration file not found, using defaults"
 fi

 # Set defaults
 export DATA_ENABLED="${DATA_ENABLED:-true}"
 export DATA_BACKUP_DIR="${DATA_BACKUP_DIR:-/var/backups/osm-notes}"
 export DATA_BACKUP_FRESHNESS_THRESHOLD="${DATA_BACKUP_FRESHNESS_THRESHOLD:-86400}"
 export DATA_REPO_SYNC_CHECK_ENABLED="${DATA_REPO_SYNC_CHECK_ENABLED:-true}"
 export DATA_REPO_PATH="${DATA_REPO_PATH:-}"
 export DATA_STORAGE_CHECK_ENABLED="${DATA_STORAGE_CHECK_ENABLED:-true}"
 export DATA_STORAGE_PATH="${DATA_STORAGE_PATH:-/var/data/osm-notes}"
 export DATA_CHECK_TIMEOUT="${DATA_CHECK_TIMEOUT:-60}"
}

##
# Check backup file freshness
##
check_backup_freshness() {
 log_info "${COMPONENT}: Starting backup file freshness check"

 if [[ "${DATA_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Data monitoring is disabled"
  return 0
 fi

 local backup_dir="${DATA_BACKUP_DIR}"
 local threshold="${DATA_BACKUP_FRESHNESS_THRESHOLD}"
 local current_time
 current_time=$(date +%s)
 local oldest_backup_age=0
 local newest_backup_age=0
 local backup_count=0
 local backup_files=()

 if [[ ! -d "${backup_dir}" ]]; then
  log_warning "${COMPONENT}: Backup directory does not exist: ${backup_dir}"
  send_alert "${COMPONENT}" "WARNING" "backup_directory_missing" "Backup directory does not exist: ${backup_dir}"
  return 1
 fi

 # Find backup files (common patterns: *.sql, *.sql.gz, *.dump, *.tar.gz, *.backup)
 while IFS= read -r -d '' file; do
  backup_files+=("${file}")
 done < <(find "${backup_dir}" -type f \( -name "*.sql" -o -name "*.sql.gz" -o -name "*.dump" -o -name "*.tar.gz" -o -name "*.backup" -o -name "backup_*" \) -print0 2> /dev/null || true)

 backup_count=${#backup_files[@]}

 if [[ ${backup_count} -eq 0 ]]; then
  log_warning "${COMPONENT}: No backup files found in ${backup_dir}"
  send_alert "${COMPONENT}" "WARNING" "no_backups_found" "No backup files found in backup directory: ${backup_dir}"
  return 1
 fi

 # Calculate ages of backups
 local oldest_backup_time=${current_time}
 local newest_backup_time=0

 for backup_file in "${backup_files[@]}"; do
  if [[ -f "${backup_file}" ]]; then
   local file_time
   file_time=$(stat -c %Y "${backup_file}" 2> /dev/null || echo "0")

   if [[ ${file_time} -lt ${oldest_backup_time} ]]; then
    oldest_backup_time=${file_time}
   fi

   if [[ ${file_time} -gt ${newest_backup_time} ]]; then
    newest_backup_time=${file_time}
   fi
  fi
 done

 oldest_backup_age=$((current_time - oldest_backup_time))
 newest_backup_age=$((current_time - newest_backup_time))

 # Record metrics
 record_metric "${COMPONENT}" "backup_count" "${backup_count}" "component=data,dir=${backup_dir}"
 record_metric "${COMPONENT}" "backup_newest_age_seconds" "${newest_backup_age}" "component=data,dir=${backup_dir}"
 record_metric "${COMPONENT}" "backup_oldest_age_seconds" "${oldest_backup_age}" "component=data,dir=${backup_dir}"

 log_info "${COMPONENT}: Backup freshness - Count: ${backup_count}, Newest: ${newest_backup_age}s, Oldest: ${oldest_backup_age}s (threshold: ${threshold}s)"

 # Alert if newest backup is too old
 if [[ ${newest_backup_age} -gt ${threshold} ]]; then
  log_warning "${COMPONENT}: Newest backup is ${newest_backup_age}s old (threshold: ${threshold}s)"
  send_alert "${COMPONENT}" "WARNING" "backup_freshness_exceeded" "Newest backup is ${newest_backup_age}s old (threshold: ${threshold}s, directory: ${backup_dir})"
  return 1
 fi

 return 0
}

##
# Check repository sync status
##
check_repository_sync_status() {
 log_info "${COMPONENT}: Starting repository sync status check"

 if [[ "${DATA_ENABLED:-false}" != "true" ]] || [[ "${DATA_REPO_SYNC_CHECK_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Repository sync check is disabled"
  return 0
 fi

 local repo_path="${DATA_REPO_PATH}"

 if [[ -z "${repo_path}" ]] || [[ ! -d "${repo_path}" ]]; then
  log_warning "${COMPONENT}: Repository path not configured or does not exist: ${repo_path:-not set}"
  return 0
 fi

 # Check if it's a git repository
 if [[ ! -d "${repo_path}/.git" ]]; then
  log_info "${COMPONENT}: Directory is not a git repository: ${repo_path}"
  return 0
 fi

 local sync_status="unknown"
 local behind_count=0
 local ahead_count=0

 # Check git sync status
 if command -v git > /dev/null 2>&1; then
  cd "${repo_path}" || return 1

  # Fetch latest changes (non-blocking)
  git fetch --quiet 2> /dev/null || true

  # Check if behind/ahead of remote
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || echo "main")
  local remote_branch="origin/${branch}"

  if git rev-parse --verify "${remote_branch}" > /dev/null 2>&1; then
   behind_count=$(git rev-list --count HEAD.."${remote_branch}" 2> /dev/null || echo "0")
   ahead_count=$(git rev-list --count "${remote_branch}"..HEAD 2> /dev/null || echo "0")

   if [[ ${behind_count} -eq 0 ]] && [[ ${ahead_count} -eq 0 ]]; then
    sync_status="synced"
   elif [[ ${behind_count} -gt 0 ]]; then
    sync_status="behind"
   elif [[ ${ahead_count} -gt 0 ]]; then
    sync_status="ahead"
   fi
  else
   sync_status="no_remote"
  fi

  cd - > /dev/null || true
 else
  log_warning "${COMPONENT}: git not available, skipping repository sync check"
  return 0
 fi

 # Record metrics
 local sync_value=0
 if [[ "${sync_status}" == "synced" ]]; then
  sync_value=1
 fi

 record_metric "${COMPONENT}" "repo_sync_status" "${sync_value}" "component=data,repo=${repo_path},status=${sync_status}"
 record_metric "${COMPONENT}" "repo_behind_count" "${behind_count}" "component=data,repo=${repo_path}"
 record_metric "${COMPONENT}" "repo_ahead_count" "${ahead_count}" "component=data,repo=${repo_path}"

 log_info "${COMPONENT}: Repository sync status - Status: ${sync_status}, Behind: ${behind_count}, Ahead: ${ahead_count}"

 # Alert if repository is behind
 if [[ "${sync_status}" == "behind" ]] && [[ ${behind_count} -gt 0 ]]; then
  log_warning "${COMPONENT}: Repository is ${behind_count} commits behind remote"
  send_alert "${COMPONENT}" "WARNING" "repo_sync_behind" "Repository is ${behind_count} commits behind remote (repo: ${repo_path})"
  return 1
 fi

 return 0
}

##
# Check file integrity
##
check_file_integrity() {
 log_info "${COMPONENT}: Starting file integrity check"

 if [[ "${DATA_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Data monitoring is disabled"
  return 0
 fi

 local backup_dir="${DATA_BACKUP_DIR}"
 local integrity_failures=0
 local files_checked=0

 if [[ ! -d "${backup_dir}" ]]; then
  log_warning "${COMPONENT}: Backup directory does not exist: ${backup_dir}"
  return 0
 fi

 # Check integrity of backup files
 # For SQL dumps, check if file is readable and not corrupted
 # For compressed files, check if they can be decompressed
 local backup_files=()
 while IFS= read -r -d '' file; do
  backup_files+=("${file}")
 done < <(find "${backup_dir}" -type f \( -name "*.sql" -o -name "*.sql.gz" -o -name "*.dump" -o -name "*.tar.gz" -o -name "*.backup" \) -print0 2> /dev/null || true)

 for backup_file in "${backup_files[@]}"; do
  files_checked=$((files_checked + 1))

  # Check file readability
  if [[ ! -r "${backup_file}" ]]; then
   log_warning "${COMPONENT}: Backup file is not readable: ${backup_file}"
   integrity_failures=$((integrity_failures + 1))
   continue
  fi

  # Check file size (should be > 0)
  local file_size
  file_size=$(stat -c %s "${backup_file}" 2> /dev/null || echo "0")
  if [[ ${file_size} -eq 0 ]]; then
   log_warning "${COMPONENT}: Backup file is empty: ${backup_file}"
   integrity_failures=$((integrity_failures + 1))
   continue
  fi

  # Check if file is currently being written (modified in last 60 seconds)
  # This prevents false positives when backup is still being created
  local file_mtime
  file_mtime=$(stat -c %Y "${backup_file}" 2> /dev/null || echo "0")
  local current_time
  current_time=$(date +%s)
  local file_age=$((current_time - file_mtime))

  if [[ ${file_age} -lt 60 ]]; then
   log_debug "${COMPONENT}: Backup file is very recent (${file_age}s old), skipping integrity check (may still be writing): ${backup_file}"
   files_checked=$((files_checked - 1)) # Don't count files being written
   continue
  fi

  # Check compressed files
  if [[ "${backup_file}" == *.tar.gz ]] || [[ "${backup_file}" == *.gz ]]; then
   if ! gzip -t "${backup_file}" > /dev/null 2>&1; then
    log_warning "${COMPONENT}: Compressed backup file is corrupted: ${backup_file}"
    integrity_failures=$((integrity_failures + 1))
    continue
   fi
  fi

  # Check SQL dump files (basic check - file should start with SQL-like content)
  if [[ "${backup_file}" == *.sql ]] || [[ "${backup_file}" == *.dump ]]; then
   if ! head -1 "${backup_file}" 2> /dev/null | grep -qiE "(postgresql|mysql|sql|dump|backup)"; then
    log_debug "${COMPONENT}: SQL dump file may be corrupted (doesn't start with expected header): ${backup_file}"
    # Don't fail on this, just log
   fi
  fi
 done

 # Record metrics
 record_metric "${COMPONENT}" "files_checked" "${files_checked}" "component=data,dir=${backup_dir}"
 record_metric "${COMPONENT}" "integrity_failures" "${integrity_failures}" "component=data,dir=${backup_dir}"

 log_info "${COMPONENT}: File integrity check - Checked: ${files_checked}, Failures: ${integrity_failures}"

 # Alert if integrity failures detected
 if [[ ${integrity_failures} -gt 0 ]]; then
  log_warning "${COMPONENT}: File integrity check found ${integrity_failures} failure(s)"
  send_alert "${COMPONENT}" "WARNING" "file_integrity_failure" "File integrity check found ${integrity_failures} failure(s) out of ${files_checked} files checked (directory: ${backup_dir})"
  return 1
 fi

 return 0
}

##
# Check storage availability
##
check_storage_availability() {
 log_info "${COMPONENT}: Starting storage availability check"

 if [[ "${DATA_ENABLED:-false}" != "true" ]] || [[ "${DATA_STORAGE_CHECK_ENABLED:-false}" != "true" ]]; then
  log_info "${COMPONENT}: Storage availability check is disabled"
  return 0
 fi

 local storage_path="${DATA_STORAGE_PATH}"
 local disk_usage_threshold="${DATA_DISK_USAGE_THRESHOLD:-90}"

 if [[ -z "${storage_path}" ]] || [[ ! -d "${storage_path}" ]]; then
  log_warning "${COMPONENT}: Storage path not configured or does not exist: ${storage_path:-not set}"
  return 0
 fi

 # Check disk space
 local disk_usage=0
 local disk_available=0
 local disk_total=0

 if command -v df > /dev/null 2>&1; then
  local df_output
  df_output=$(df -h "${storage_path}" 2> /dev/null | tail -1 || echo "")

  if [[ -n "${df_output}" ]]; then
   # Parse df output (format: Filesystem Size Used Avail Use% Mounted)
   local usage_percent
   usage_percent=$(echo "${df_output}" | awk '{print $5}' | sed 's/%//' || echo "0")
   disk_usage=${usage_percent}

   # Get available and total in bytes
   local df_bytes_output
   df_bytes_output=$(df "${storage_path}" 2> /dev/null | tail -1 || echo "")
   if [[ -n "${df_bytes_output}" ]]; then
    disk_total=$(echo "${df_bytes_output}" | awk '{print $2}' || echo "0")
    disk_available=$(echo "${df_bytes_output}" | awk '{print $4}' || echo "0")
   fi
  fi
 else
  log_warning "${COMPONENT}: df command not available, skipping storage check"
  return 0
 fi

 # Record metrics
 record_metric "${COMPONENT}" "storage_disk_usage_percent" "${disk_usage}" "component=data,path=${storage_path}"
 record_metric "${COMPONENT}" "storage_disk_available_bytes" "${disk_available}" "component=data,path=${storage_path}"
 record_metric "${COMPONENT}" "storage_disk_total_bytes" "${disk_total}" "component=data,path=${storage_path}"

 log_info "${COMPONENT}: Storage availability - Usage: ${disk_usage}%, Available: ${disk_available} bytes, Total: ${disk_total} bytes"

 # Alert if disk usage exceeds threshold
 if [[ ${disk_usage} -gt ${disk_usage_threshold} ]]; then
  local alert_level="WARNING"
  if [[ ${disk_usage} -gt 95 ]]; then
   alert_level="CRITICAL"
  fi

  log_warning "${COMPONENT}: Disk usage (${disk_usage}%) exceeds threshold (${disk_usage_threshold}%)"
  send_alert "${COMPONENT}" "${alert_level}" "storage_disk_usage_high" "Disk usage (${disk_usage}%) exceeds threshold (${disk_usage_threshold}%, path: ${storage_path})"

  if [[ "${alert_level}" == "CRITICAL" ]]; then
   return 1
  fi
 fi

 # Check if storage path is writable
 if [[ ! -w "${storage_path}" ]]; then
  log_warning "${COMPONENT}: Storage path is not writable: ${storage_path}"
  send_alert "${COMPONENT}" "CRITICAL" "storage_not_writable" "Storage path is not writable: ${storage_path}"
  return 1
 fi

 return 0
}

##
# Main monitoring function
##
main() {
 local specific_check="${1:-}"
 local overall_result=0

 # Load configuration
 load_config "${CONFIG_FILE:-}"

 # Initialize alerting
 init_alerting

 log_info "${COMPONENT}: Starting data freshness monitoring"

 # Run checks
 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "backup_freshness" ]]; then
  if ! check_backup_freshness; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "repo_sync" ]]; then
  if ! check_repository_sync_status; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "file_integrity" ]]; then
  if ! check_file_integrity; then
   overall_result=1
  fi
 fi

 if [[ -z "${specific_check}" ]] || [[ "${specific_check}" == "storage_availability" ]]; then
  if ! check_storage_availability; then
   overall_result=1
  fi
 fi

 if [[ ${overall_result} -eq 0 ]]; then
  log_info "${COMPONENT}: All data checks passed"
 else
  log_warning "${COMPONENT}: Some data checks failed"
 fi

 return ${overall_result}
}

# Parse command line arguments only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 SPECIFIC_CHECK=""
 while [[ $# -gt 0 ]]; do
  case $1 in
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
   export CONFIG_FILE="$2"
   shift 2
   ;;
  --check)
   SPECIFIC_CHECK="$2"
   shift 2
   ;;
  *)
   log_error "Unknown option: $1"
   usage
   exit 1
   ;;
  esac
 done

 # Run main function
 main "${SPECIFIC_CHECK}"
fi
