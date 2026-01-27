#!/usr/bin/env bash
#
# Validation Metrics Collection Script
# Collects validation metrics from the OSM-Notes-Analytics data warehouse
#
# Version: 1.0.0
# Date: 2026-01-09
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
 init_logging "${LOG_DIR}/validation_metrics.log" "collectValidationMetrics"
fi

# Component name
readonly COMPONENT="ANALYTICS"

##
# Show usage
##
usage() {
 cat << EOF
Validation Metrics Collection Script

Collects validation metrics from the OSM-Notes-Analytics data warehouse.

Usage: $0 [OPTIONS]

Options:
    -h, --help            Show this help message

Examples:
    # Collect all validation metrics
    $0
EOF
}

##
# Execute MON-001 validation (validate_note_current_status)
##
execute_mon001_validation() {
 log_info "${COMPONENT}: Executing MON-001 validation (validate_note_current_status)"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot execute MON-001 validation - database connection failed"
  return 1
 fi

 local start_time
 start_time=$(date +%s)

 # Execute validation function
 local query="SELECT * FROM dwh.validate_note_current_status();"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 local end_time
 end_time=$(date +%s)
 local duration=$((end_time - start_time))

 if [[ -z "${result}" ]]; then
  log_warning "${COMPONENT}: MON-001 validation returned no results"
  record_metric "${COMPONENT}" "validation_status" "0" "component=analytics,validation=MON-001,status=UNKNOWN"
  record_metric "${COMPONENT}" "validation_issues_count" "0" "component=analytics,validation=MON-001"
  record_metric "${COMPONENT}" "validation_duration_seconds" "${duration}" "component=analytics,validation=MON-001"
  return 1
 fi

 # Parse validation result
 # Expected format: status (PASS/FAIL), issues_count (integer)
 local validation_status="UNKNOWN"
 local issues_count=0

 # Check if result contains PASS or FAIL
 if echo "${result}" | grep -qi "PASS\|SUCCESS\|OK"; then
  validation_status="PASS"
 elif echo "${result}" | grep -qi "FAIL\|ERROR"; then
  validation_status="FAIL"
 fi

 # Extract issues count (look for numbers in the result)
 local issues_match
 issues_match=$(echo "${result}" | grep -oE "[0-9]+" | head -1 || echo "0")
 issues_count=$((issues_match + 0))

 # Record metrics
 local status_value=0
 if [[ "${validation_status}" == "PASS" ]]; then
  status_value=1
 fi

 record_metric "${COMPONENT}" "validation_status" "${status_value}" "component=analytics,validation=MON-001,status=${validation_status}"
 record_metric "${COMPONENT}" "validation_issues_count" "${issues_count}" "component=analytics,validation=MON-001"
 record_metric "${COMPONENT}" "validation_duration_seconds" "${duration}" "component=analytics,validation=MON-001"

 log_info "${COMPONENT}: MON-001 validation - Status: ${validation_status}, Issues: ${issues_count}, Duration: ${duration}s"

 return 0
}

##
# Execute MON-002 validation (validate_comment_counts)
##
execute_mon002_validation() {
 log_info "${COMPONENT}: Executing MON-002 validation (validate_comment_counts)"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot execute MON-002 validation - database connection failed"
  return 1
 fi

 local start_time
 start_time=$(date +%s)

 # Execute validation function
 local query="SELECT * FROM dwh.validate_comment_counts();"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 local end_time
 end_time=$(date +%s)
 local duration=$((end_time - start_time))

 if [[ -z "${result}" ]]; then
  log_warning "${COMPONENT}: MON-002 validation returned no results"
  record_metric "${COMPONENT}" "validation_status" "0" "component=analytics,validation=MON-002,status=UNKNOWN"
  record_metric "${COMPONENT}" "validation_issues_count" "0" "component=analytics,validation=MON-002"
  record_metric "${COMPONENT}" "validation_duration_seconds" "${duration}" "component=analytics,validation=MON-002"
  return 1
 fi

 # Parse validation result
 local validation_status="UNKNOWN"
 local issues_count=0

 # Check if result contains PASS or FAIL
 if echo "${result}" | grep -qi "PASS\|SUCCESS\|OK"; then
  validation_status="PASS"
 elif echo "${result}" | grep -qi "FAIL\|ERROR"; then
  validation_status="FAIL"
 fi

 # Extract issues count
 local issues_match
 issues_match=$(echo "${result}" | grep -oE "[0-9]+" | head -1 || echo "0")
 issues_count=$((issues_match + 0))

 # Record metrics
 local status_value=0
 if [[ "${validation_status}" == "PASS" ]]; then
  status_value=1
 fi

 record_metric "${COMPONENT}" "validation_status" "${status_value}" "component=analytics,validation=MON-002,status=${validation_status}"
 record_metric "${COMPONENT}" "validation_issues_count" "${issues_count}" "component=analytics,validation=MON-002"
 record_metric "${COMPONENT}" "validation_duration_seconds" "${duration}" "component=analytics,validation=MON-002"

 log_info "${COMPONENT}: MON-002 validation - Status: ${validation_status}, Issues: ${issues_count}, Duration: ${duration}s"

 return 0
}

##
# Check for orphaned facts (facts without valid dimension)
##
check_orphaned_facts() {
 log_info "${COMPONENT}: Checking for orphaned facts"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot check orphaned facts - database connection failed"
  return 1
 fi

 # Query to find orphaned facts (facts without matching dimension)
 local query="SELECT COUNT(*) FROM dwh.facts f LEFT JOIN dwh.dimension_countries d ON f.country_id = d.country_id WHERE d.country_id IS NULL;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local orphaned_count
  orphaned_count=$(echo "${result}" | tr -d '[:space:]' || echo "0")
  if [[ "${orphaned_count}" =~ ^[0-9]+$ ]]; then
   record_metric "${COMPONENT}" "orphaned_facts_count" "${orphaned_count}" "component=analytics"
   log_info "${COMPONENT}: Orphaned facts count: ${orphaned_count}"
  fi
 else
  log_warning "${COMPONENT}: Could not retrieve orphaned facts count"
 fi

 return 0
}

##
# Calculate data quality score
##
calculate_data_quality_score() {
 log_info "${COMPONENT}: Calculating data quality score"

 # Quality score is calculated based on:
 # - Validation results (MON-001, MON-002): 50% weight
 # - Orphaned facts: 30% weight
 # - Data freshness: 20% weight

 local quality_score=100
 local validation_score=100
 local orphaned_score=100
 local freshness_score=100

 # Get latest validation results from metrics table
 if check_database_connection; then
  # Get MON-001 status (1=PASS, 0=FAIL)
  local mon001_query="SELECT metric_value FROM metrics WHERE component = 'ANALYTICS' AND metric_name = 'validation_status' AND metadata->>'validation' = 'MON-001' ORDER BY timestamp DESC LIMIT 1;"
  local mon001_result
  mon001_result=$(execute_sql_query "${mon001_query}" 2> /dev/null || echo "")

  # Get MON-002 status
  local mon002_query="SELECT metric_value FROM metrics WHERE component = 'ANALYTICS' AND metric_name = 'validation_status' AND metadata->>'validation' = 'MON-002' ORDER BY timestamp DESC LIMIT 1;"
  local mon002_result
  mon002_result=$(execute_sql_query "${mon002_query}" 2> /dev/null || echo "")

  # Calculate validation score (average of MON-001 and MON-002)
  local mon001_status=0
  local mon002_status=0
  if [[ -n "${mon001_result}" ]]; then
   mon001_status=$(echo "${mon001_result}" | tr -d '[:space:]' || echo "0")
  fi
  if [[ -n "${mon002_result}" ]]; then
   mon002_status=$(echo "${mon002_result}" | tr -d '[:space:]' || echo "0")
  fi

  validation_score=$(((mon001_status + mon002_status) * 50))

  # Get orphaned facts count
  local orphaned_query="SELECT metric_value FROM metrics WHERE component = 'ANALYTICS' AND metric_name = 'orphaned_facts_count' ORDER BY timestamp DESC LIMIT 1;"
  local orphaned_result
  orphaned_result=$(execute_sql_query "${orphaned_query}" 2> /dev/null || echo "")

  if [[ -n "${orphaned_result}" ]]; then
   local orphaned_count
   orphaned_count=$(echo "${orphaned_result}" | tr -d '[:space:]' || echo "0")
   # Score decreases with orphaned facts (max 30 points deduction)
   if [[ ${orphaned_count} -gt 0 ]]; then
    orphaned_score=$((100 - (orphaned_count / 100)))
    if [[ ${orphaned_score} -lt 70 ]]; then
     orphaned_score=70
    fi
   fi
  fi

  # Get data freshness (from previous checks)
  local freshness_query="SELECT metric_value FROM metrics WHERE component = 'ANALYTICS' AND metric_name = 'dwh_freshness_seconds' ORDER BY timestamp DESC LIMIT 1;"
  local freshness_result
  freshness_result=$(execute_sql_query "${freshness_query}" 2> /dev/null || echo "")

  if [[ -n "${freshness_result}" ]]; then
   local freshness_seconds
   freshness_seconds=$(echo "${freshness_result}" | tr -d '[:space:]' || echo "0")
   # Score decreases if data is stale (> 1 hour)
   if [[ ${freshness_seconds} -gt 3600 ]]; then
    freshness_score=$((100 - ((freshness_seconds - 3600) / 360)))
    if [[ ${freshness_score} -lt 80 ]]; then
     freshness_score=80
    fi
   fi
  fi
 fi

 # Calculate weighted quality score
 quality_score=$(((validation_score * 50 + orphaned_score * 30 + freshness_score * 20) / 100))

 record_metric "${COMPONENT}" "data_quality_score" "${quality_score}" "component=analytics"
 log_info "${COMPONENT}: Data quality score: ${quality_score}% (Validation: ${validation_score}%, Orphaned: ${orphaned_score}%, Freshness: ${freshness_score}%)"

 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting validation metrics collection"

 # Load configuration
 if ! load_monitoring_config; then
  log_error "${COMPONENT}: Failed to load monitoring configuration"
  exit 1
 fi

 # Execute validations
 execute_mon001_validation || true
 execute_mon002_validation || true

 # Check for orphaned facts
 check_orphaned_facts || true

 # Calculate data quality score
 calculate_data_quality_score || true

 log_info "${COMPONENT}: Validation metrics collection completed"
 return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
