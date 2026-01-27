#!/usr/bin/env bash
#
# Planet Notes Check Integration
# Wrapper to integrate processCheckPlanetNotes.sh from OSM-Notes-Ingestion
#
# Version: 1.0.0
# Date: 2025-12-24
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
readonly PROJECT_ROOT

# Set default LOG_DIR if not set
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

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

# Only initialize logging if not in test mode or if script is executed directly
if [[ "${TEST_MODE:-false}" != "true" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 # Initialize logging
 init_logging "${LOG_DIR}/ingestion.log" "checkPlanetNotes"
fi

# Component name
# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]] || [[ "${TEST_MODE:-false}" == "true" ]]; then
 COMPONENT="${COMPONENT:-INGESTION}"
fi
readonly COMPONENT

##
# Run Planet Notes check using processCheckPlanetNotes.sh
##
run_planet_check() {
 log_info "${COMPONENT}: Starting Planet Notes check"

 # Check if ingestion repository exists
 if [[ ! -d "${INGESTION_REPO_PATH}" ]]; then
  log_error "${COMPONENT}: Ingestion repository not found: ${INGESTION_REPO_PATH}"
  return 1
 fi

 # Path to processCheckPlanetNotes.sh
 local planet_check_script="${INGESTION_REPO_PATH}/bin/monitor/processCheckPlanetNotes.sh"

 if [[ ! -f "${planet_check_script}" ]]; then
  log_warning "${COMPONENT}: processCheckPlanetNotes.sh not found: ${planet_check_script}"
  log_info "${COMPONENT}: Skipping Planet Notes check (script not available)"
  return 0
 fi

 if [[ ! -x "${planet_check_script}" ]]; then
  log_error "${COMPONENT}: processCheckPlanetNotes.sh is not executable: ${planet_check_script}"
  return 1
 fi

 log_info "${COMPONENT}: Running processCheckPlanetNotes.sh"

 # Ensure PATH includes standard binary directories for psql and other tools
 # This is important when script runs from cron or with limited PATH
 local saved_path="${PATH:-}"
 export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

 # Run the Planet check script
 local start_time
 start_time=$(date +%s)

 local exit_code=0
 local output
 output=$(cd "${INGESTION_REPO_PATH}" && bash "${planet_check_script}" 2>&1) || exit_code=$?

 # Restore original PATH
 export PATH="${saved_path}"

 local end_time
 end_time=$(date +%s)
 local duration=$((end_time - start_time))

 # Log the output
 log_debug "${COMPONENT}: processCheckPlanetNotes.sh output:\n${output}"

 # Check exit code
 if [[ ${exit_code} -eq 0 ]]; then
  log_info "${COMPONENT}: Planet Notes check passed (duration: ${duration}s)"
  record_metric "${COMPONENT}" "planet_check_status" "1" "component=ingestion,check=processCheckPlanetNotes"
  record_metric "${COMPONENT}" "planet_check_duration" "${duration}" "component=ingestion,check=processCheckPlanetNotes"

  # Check planet check duration threshold
  local planet_duration_threshold="${INGESTION_PLANET_CHECK_DURATION_THRESHOLD:-600}"
  if [[ ${duration} -gt ${planet_duration_threshold} ]]; then
   log_warning "${COMPONENT}: Planet check duration (${duration}s) exceeds threshold (${planet_duration_threshold}s)"
   send_alert "WARNING" "${COMPONENT}" "Planet Notes check took too long: ${duration}s (threshold: ${planet_duration_threshold}s)"
  fi

  return 0
 else
  log_error "${COMPONENT}: Planet Notes check failed (exit_code: ${exit_code}, duration: ${duration}s)"
  record_metric "${COMPONENT}" "planet_check_status" "0" "component=ingestion,check=processCheckPlanetNotes"
  record_metric "${COMPONENT}" "planet_check_duration" "${duration}" "component=ingestion,check=processCheckPlanetNotes"
  send_alert "ERROR" "${COMPONENT}" "Planet Notes check failed: exit_code=${exit_code}"
  return 1
 fi
}

##
# Main
##
main() {
 # Load configuration
 if ! load_all_configs; then
  log_error "${COMPONENT}: Failed to load configuration"
  exit 1
 fi

 # Validate configuration
 if ! validate_all_configs; then
  log_error "${COMPONENT}: Configuration validation failed"
  exit 1
 fi

 # Run Planet check
 if run_planet_check; then
  exit 0
 else
  exit 1
 fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
