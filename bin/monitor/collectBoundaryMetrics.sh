#!/usr/bin/env bash
#
# Boundary Metrics Collection Script
# Collects metrics about country and maritime boundary processing
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

# Initialize logging
init_logging "${LOG_DIR}/boundary_metrics.log" "collectBoundaryMetrics"

# Component name
readonly COMPONENT="INGESTION"

##
# Get last update timestamp for countries table
##
get_countries_last_update() {
 log_info "${COMPONENT}: Getting countries last update timestamp"

 local query="SELECT EXTRACT(EPOCH FROM MAX(updated_at))::bigint FROM countries WHERE updated_at IS NOT NULL;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]] && [[ ${result} -gt 0 ]]; then
  record_metric "${COMPONENT}" "boundary_countries_last_update_timestamp" "${result}" "component=ingestion"
  log_debug "${COMPONENT}: Countries last update: ${result}"
 else
  log_debug "${COMPONENT}: No countries update timestamp found"
 fi

 return 0
}

##
# Get last update timestamp for maritime boundaries table
##
get_maritime_boundaries_last_update() {
 log_info "${COMPONENT}: Getting maritime boundaries last update timestamp"

 local query="SELECT EXTRACT(EPOCH FROM MAX(updated_at))::bigint FROM maritime_boundaries WHERE updated_at IS NOT NULL;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]] && [[ ${result} -gt 0 ]]; then
  record_metric "${COMPONENT}" "boundary_maritime_last_update_timestamp" "${result}" "component=ingestion"
  log_debug "${COMPONENT}: Maritime boundaries last update: ${result}"
 else
  log_debug "${COMPONENT}: No maritime boundaries update timestamp found"
 fi

 return 0
}

##
# Calculate update frequency
##
calculate_update_frequency() {
 log_info "${COMPONENT}: Calculating boundary update frequency"

 # Get countries last update
 local countries_query="SELECT EXTRACT(EPOCH FROM MAX(updated_at))::bigint FROM countries WHERE updated_at IS NOT NULL;"
 local countries_timestamp
 countries_timestamp=$(execute_sql_query "${countries_query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 # Get maritime boundaries last update
 local maritime_query="SELECT EXTRACT(EPOCH FROM MAX(updated_at))::bigint FROM maritime_boundaries WHERE updated_at IS NOT NULL;"
 local maritime_timestamp
 maritime_timestamp=$(execute_sql_query "${maritime_query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 local current_timestamp
 current_timestamp=$(date +%s)

 # Calculate frequency for countries (hours since last update)
 if [[ -n "${countries_timestamp}" ]] && [[ "${countries_timestamp}" =~ ^[0-9]+$ ]] && [[ ${countries_timestamp} -gt 0 ]]; then
  local countries_age_hours=0
  countries_age_hours=$(((current_timestamp - countries_timestamp) / 3600))
  record_metric "${COMPONENT}" "boundary_update_frequency_hours" "${countries_age_hours}" "component=ingestion,type=countries"
  log_debug "${COMPONENT}: Countries update frequency: ${countries_age_hours} hours"
 fi

 # Calculate frequency for maritime boundaries (hours since last update)
 if [[ -n "${maritime_timestamp}" ]] && [[ "${maritime_timestamp}" =~ ^[0-9]+$ ]] && [[ ${maritime_timestamp} -gt 0 ]]; then
  local maritime_age_hours=0
  maritime_age_hours=$(((current_timestamp - maritime_timestamp) / 3600))
  record_metric "${COMPONENT}" "boundary_update_frequency_hours" "${maritime_age_hours}" "component=ingestion,type=maritime"
  log_debug "${COMPONENT}: Maritime boundaries update frequency: ${maritime_age_hours} hours"
 fi

 return 0
}

##
# Count notes without country assignment
##
count_notes_without_country() {
 log_info "${COMPONENT}: Counting notes without country assignment"

 local query="SELECT COUNT(*) FROM notes WHERE country_id IS NULL;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]]; then
  record_metric "${COMPONENT}" "boundary_notes_without_country_count" "${result}" "component=ingestion"
  log_debug "${COMPONENT}: Notes without country: ${result}"
 fi

 return 0
}

##
# Count notes with country assignment
##
count_notes_with_country() {
 log_info "${COMPONENT}: Counting notes with country assignment"

 local query="SELECT COUNT(*) FROM notes WHERE country_id IS NOT NULL;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]]; then
  record_metric "${COMPONENT}" "boundary_notes_with_country_count" "${result}" "component=ingestion"
  log_debug "${COMPONENT}: Notes with country: ${result}"
 fi

 return 0
}

##
# Detect notes with coordinates out of bounds
##
detect_notes_out_of_bounds() {
 log_info "${COMPONENT}: Detecting notes with coordinates out of bounds"

 # Check for notes with invalid coordinates (outside valid lat/lon ranges)
 local query="SELECT COUNT(*) FROM notes 
                 WHERE latitude < -90 OR latitude > 90 
                    OR longitude < -180 OR longitude > 180;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]]; then
  record_metric "${COMPONENT}" "boundary_notes_out_of_bounds_count" "${result}" "component=ingestion"
  log_debug "${COMPONENT}: Notes out of bounds: ${result}"
 fi

 return 0
}

##
# Detect notes with potentially wrong country assignment
# This includes:
# 1. Notes with country_id that doesn't exist in countries table (referential integrity)
# 2. Notes that are geographically outside their assigned country (spatial check)
#    This is particularly important when boundary data is updated and countries change
##
detect_wrong_country_assignments() {
 log_info "${COMPONENT}: Detecting notes with potentially wrong country assignment"

 # Check 1: Notes with country_id that doesn't exist in countries table
 local query_invalid_ref="SELECT COUNT(*) FROM notes n 
                             WHERE n.country_id IS NOT NULL 
                               AND NOT EXISTS (
                                   SELECT 1 FROM countries c WHERE c.id = n.country_id
                               );"
 local result_invalid_ref
 result_invalid_ref=$(execute_sql_query "${query_invalid_ref}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 # Check 2: Notes that are geographically outside their assigned country
 # This detects notes that need reassignment after boundary updates
 # We check if PostGIS is available, otherwise use a simplified check
 local query_spatial=""
 local result_spatial="0"

 # Try PostGIS spatial query first (if PostGIS extension is available)
 query_spatial="SELECT COUNT(*) FROM notes n
                   WHERE n.country_id IS NOT NULL
                     AND n.latitude IS NOT NULL
                     AND n.longitude IS NOT NULL
                     AND EXISTS (
                         SELECT 1 FROM countries c 
                         WHERE c.id = n.country_id
                           AND (
                               -- Check if note coordinates are outside country bounding box
                               -- This is a simplified check - full implementation would use ST_Contains
                               n.latitude < COALESCE(c.min_latitude, -90)
                               OR n.latitude > COALESCE(c.max_latitude, 90)
                               OR n.longitude < COALESCE(c.min_longitude, -180)
                               OR n.longitude > COALESCE(c.max_longitude, 180)
                           )
                     );"

 # If countries table has spatial columns (geometry), use PostGIS query
 local has_postgis_query="SELECT COUNT(*) FROM pg_extension WHERE extname = 'postgis';"
 local has_postgis
 has_postgis=$(execute_sql_query "${has_postgis_query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ "${has_postgis}" == "1" ]]; then
  # Try PostGIS spatial query with ST_Contains if geometry column exists
  query_spatial="SELECT COUNT(*) FROM notes n
                       WHERE n.country_id IS NOT NULL
                         AND n.latitude IS NOT NULL
                         AND n.longitude IS NOT NULL
                         AND EXISTS (
                             SELECT 1 FROM countries c 
                             WHERE c.id = n.country_id
                               AND c.geometry IS NOT NULL
                               AND NOT ST_Contains(
                                   c.geometry,
                                   ST_SetSRID(ST_MakePoint(n.longitude, n.latitude), 4326)
                               )
                         );"
 fi

 result_spatial=$(execute_sql_query "${query_spatial}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 # Total wrong country assignments = invalid references + spatial mismatches
 local total_wrong=0
 local invalid_ref_count=0
 local spatial_mismatch_count=0

 if [[ -n "${result_invalid_ref}" ]] && [[ "${result_invalid_ref}" =~ ^[0-9]+$ ]]; then
  invalid_ref_count=${result_invalid_ref}
 fi

 if [[ -n "${result_spatial}" ]] && [[ "${result_spatial}" =~ ^[0-9]+$ ]]; then
  spatial_mismatch_count=${result_spatial}
 fi

 total_wrong=$((invalid_ref_count + spatial_mismatch_count))

 if [[ ${total_wrong} -gt 0 ]]; then
  record_metric "${COMPONENT}" "boundary_notes_wrong_country_count" "${total_wrong}" "component=ingestion"
  log_debug "${COMPONENT}: Notes with wrong country: ${total_wrong} (invalid refs: ${invalid_ref_count}, spatial mismatches: ${spatial_mismatch_count})"

  # Record spatial mismatches separately for monitoring
  if [[ ${spatial_mismatch_count} -gt 0 ]]; then
   record_metric "${COMPONENT}" "boundary_notes_spatial_mismatch_count" "${spatial_mismatch_count}" "component=ingestion"
   log_debug "${COMPONENT}: Notes with spatial mismatch (need reassignment after boundary update): ${spatial_mismatch_count}"
  fi
 else
  record_metric "${COMPONENT}" "boundary_notes_wrong_country_count" "0" "component=ingestion"
  record_metric "${COMPONENT}" "boundary_notes_spatial_mismatch_count" "0" "component=ingestion"
 fi

 return 0
}

##
# Detect notes affected by boundary changes
# These are notes that were assigned to a country before a boundary update,
# but after the update, their coordinates fall outside the updated country boundaries
# This metric helps track how many notes need reassignment after boundary updates
##
detect_notes_affected_by_boundary_changes() {
 log_info "${COMPONENT}: Detecting notes affected by boundary changes"

 # Get the last boundary update timestamp
 local last_update_query="SELECT MAX(updated_at) FROM countries WHERE updated_at IS NOT NULL;"
 local last_update
 last_update=$(execute_sql_query "${last_update_query}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -z "${last_update}" ]] || [[ "${last_update}" == "" ]]; then
  log_debug "${COMPONENT}: No boundary update timestamp found, skipping affected notes detection"
  record_metric "${COMPONENT}" "boundary_notes_affected_by_changes_count" "0" "component=ingestion"
  return 0
 fi

 # Count notes that were created/updated before the last boundary update
 # and might need reassignment (simplified check - full implementation would compare geometries)
 local query="SELECT COUNT(*) FROM notes n
                 WHERE n.country_id IS NOT NULL
                   AND n.latitude IS NOT NULL
                   AND n.longitude IS NOT NULL
                   AND n.updated_at < (SELECT MAX(updated_at) FROM countries WHERE updated_at IS NOT NULL)
                   AND EXISTS (
                       SELECT 1 FROM countries c 
                       WHERE c.id = n.country_id
                         AND c.updated_at > n.updated_at
                   );"

 local result
 result=$(execute_sql_query "${query}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]]; then
  record_metric "${COMPONENT}" "boundary_notes_affected_by_changes_count" "${result}" "component=ingestion"
  log_debug "${COMPONENT}: Notes potentially affected by boundary changes: ${result}"
 else
  record_metric "${COMPONENT}" "boundary_notes_affected_by_changes_count" "0" "component=ingestion"
 fi

 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting boundary metrics collection"

 # Load configuration
 if ! load_all_configs; then
  log_error "${COMPONENT}: Failed to load configuration"
  return 1
 fi

 # Collect all metrics
 get_countries_last_update
 get_maritime_boundaries_last_update
 calculate_update_frequency
 count_notes_without_country
 count_notes_with_country
 detect_notes_out_of_bounds
 detect_wrong_country_assignments
 detect_notes_affected_by_boundary_changes

 log_info "${COMPONENT}: Boundary metrics collection completed"

 return 0
}

# Export functions for testing
export -f get_countries_last_update get_maritime_boundaries_last_update
export -f calculate_update_frequency count_notes_without_country count_notes_with_country
export -f detect_notes_out_of_bounds detect_wrong_country_assignments detect_notes_affected_by_boundary_changes

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
