#!/usr/bin/env bash
#
# Monitoring Functions Library
# Provides core monitoring utilities for OSM-Notes-Monitoring
#
# Version: 1.0.0
# Date: 2025-12-24
#

##
# Initialize monitoring functions
# Sources configuration and sets up environment
##
init_monitoring() {
 local script_dir
 script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 local project_root
 project_root="$(dirname "$(dirname "${script_dir}")")"

 # Save LOG_DIR if already set (e.g., by tests) before loading properties
 local saved_log_dir="${LOG_DIR:-}"

 # Source configuration if available
 # shellcheck disable=SC1091
 if [[ -f "${project_root}/etc/properties.sh" ]]; then
  source "${project_root}/etc/properties.sh"
 fi

 # Restore LOG_DIR if it was set before loading properties (test mode takes precedence)
 if [[ -n "${saved_log_dir}" ]] && [[ "${TEST_MODE:-false}" == "true" ]]; then
  export LOG_DIR="${saved_log_dir}"
 fi

 # Set defaults if not configured (only if not already set)
 # This ensures init_monitoring always sets these variables
 : "${DBNAME:=osm_notes_monitoring}"
 : "${DBHOST:=localhost}"
 : "${DBPORT:=5432}"
 : "${DBUSER:=postgres}"

 # Export them
 export DBNAME DBHOST DBPORT DBUSER

 return 0
}

##
# Get database connection string
#
# Arguments:
#   None
#
# Returns:
#   Connection string via stdout
##
get_db_connection_string() {
 local password="${PGPASSWORD:-}"
 if [[ -n "${password}" ]]; then
  echo "postgresql://${DBUSER}@${DBHOST}:${DBPORT}/${DBNAME}"
 else
  echo "postgresql://${DBUSER}:${password}@${DBHOST}:${DBPORT}/${DBNAME}"
 fi
}

##
# Execute SQL query and return result
#
# Arguments:
#   $1 - SQL query to execute
#   $2 - Database name (optional, defaults to DBNAME)
#
# Returns:
#   0 on success, 1 on failure
#   Result via stdout
##
execute_sql_query() {
 local query="${1:?SQL query required}"
 local dbname="${2:-${DBNAME}}"
 local result

 # Build psql command
 # For localhost, use socket (peer auth) if user matches, otherwise use TCP with password
 local psql_cmd="psql"
 local current_user="${USER:-$(whoami)}"

 # Set PGPASSFILE if not already set and .pgpass exists in home directory
 if [[ -z "${PGPASSFILE:-}" ]] && [[ -f "${HOME}/.pgpass" ]]; then
  export PGPASSFILE="${HOME}/.pgpass"
 fi

 # If DBUSER matches current user and DBHOST is localhost, use peer authentication (socket)
 if [[ "${DBUSER}" == "${current_user}" ]] && [[ "${DBHOST}" == "localhost" || "${DBHOST}" == "127.0.0.1" || -z "${DBHOST}" ]]; then
  # Peer authentication - don't specify user or host
  if [[ -n "${DBPORT}" && "${DBPORT}" != "5432" ]]; then
   psql_cmd="${psql_cmd} -p ${DBPORT}"
  fi
 else
  # Password authentication - specify user and use TCP
  # Always use -h localhost when DBUSER != current_user to force TCP and use .pgpass
  psql_cmd="${psql_cmd} -U ${DBUSER}"
  if [[ "${DBHOST}" == "localhost" || "${DBHOST}" == "127.0.0.1" || -z "${DBHOST}" ]]; then
   # Force TCP connection to use .pgpass instead of peer auth
   psql_cmd="${psql_cmd} -h localhost"
  else
   psql_cmd="${psql_cmd} -h ${DBHOST}"
  fi
  if [[ -n "${DBPORT}" && "${DBPORT}" != "5432" ]]; then
   psql_cmd="${psql_cmd} -p ${DBPORT}"
  fi
  # Use PGPASSWORD if set, otherwise rely on .pgpass
  if [[ -n "${PGPASSWORD:-}" ]]; then
   psql_cmd="PGPASSWORD=\"${PGPASSWORD}\" ${psql_cmd}"
  elif [[ -n "${PGPASSFILE:-}" ]]; then
   # Ensure PGPASSFILE is exported for psql to use
   psql_cmd="PGPASSFILE=\"${PGPASSFILE}\" ${psql_cmd}"
  fi
 fi

 # Execute query
 # Use printf %q to properly escape the query for eval, or pass it differently
 # For now, use a temporary approach: write query to a variable and use it carefully
 local query_escaped
 query_escaped=$(printf '%q' "${query}")

 # Export PGPASSFILE if set, so psql can use it
 # Also ensure HOME is set so psql can find .pgpass in home directory
 if [[ -n "${PGPASSFILE:-}" ]]; then
  export PGPASSFILE
 elif [[ -f "${HOME}/.pgpass" ]]; then
  export PGPASSFILE="${HOME}/.pgpass"
 fi

 # Ensure HOME is exported for psql to find .pgpass
 if [[ -z "${HOME:-}" ]]; then
  local home_dir
  home_dir=$(getent passwd "${USER:-$(whoami)}" | cut -d: -f6)
  export HOME="${home_dir}"
 fi

 # Build environment variables for psql
 local env_vars=""
 if [[ -n "${PGPASSFILE:-}" ]]; then
  env_vars="PGPASSFILE=\"${PGPASSFILE}\" "
 fi
 if [[ -n "${PGPASSWORD:-}" ]]; then
  env_vars="${env_vars}PGPASSWORD=\"${PGPASSWORD}\" "
 fi

 # Execute query with environment variables
 if ! result=$(eval "${env_vars}${psql_cmd} -d ${dbname} -t -A -c ${query_escaped}" 2>&1); then
  echo "Error executing query: ${result}" >&2
  return 1
 fi

 echo "${result}"
 return 0
}

##
# Execute SQL file
#
# Arguments:
#   $1 - Path to SQL file
#   $2 - Database name (optional)
#
# Returns:
#   0 on success, 1 on failure
##
execute_sql_file() {
 local sql_file="${1:?SQL file required}"
 local dbname="${2:-${DBNAME}}"

 if [[ ! -f "${sql_file}" ]]; then
  echo "SQL file not found: ${sql_file}" >&2
  return 1
 fi

 # Build psql command (same logic as execute_sql_query)
 local psql_cmd="psql"
 local current_user="${USER:-$(whoami)}"

 if [[ "${DBUSER}" == "${current_user}" ]] && [[ "${DBHOST}" == "localhost" || "${DBHOST}" == "127.0.0.1" || -z "${DBHOST}" ]]; then
  # Peer authentication
  if [[ -n "${DBPORT}" && "${DBPORT}" != "5432" ]]; then
   psql_cmd="${psql_cmd} -p ${DBPORT}"
  fi
 else
  # Password authentication
  psql_cmd="${psql_cmd} -U ${DBUSER}"
  if [[ -n "${DBHOST}" && "${DBHOST}" != "localhost" && "${DBHOST}" != "127.0.0.1" ]]; then
   psql_cmd="${psql_cmd} -h ${DBHOST}"
  fi
  if [[ -n "${DBPORT}" && "${DBPORT}" != "5432" ]]; then
   psql_cmd="${psql_cmd} -p ${DBPORT}"
  fi
  if [[ -n "${PGPASSWORD:-}" ]]; then
   psql_cmd="PGPASSWORD=\"${PGPASSWORD}\" ${psql_cmd}"
  fi
 fi

 if ! eval "${psql_cmd} -d ${dbname} -f \"${sql_file}\"" > /dev/null 2>&1; then
  echo "Error executing SQL file: ${sql_file}" >&2
  return 1
 fi

 return 0
}

##
# Check if database is accessible
#
# Arguments:
#   $1 - Database name (optional)
#
# Returns:
#   0 if accessible, 1 if not
##
check_database_connection() {
 local dbname="${1:-${DBNAME:-notes_monitoring}}"

 # Build psql command (same logic as execute_sql_query)
 local psql_cmd="psql"
 local current_user="${USER:-$(whoami)}"

 # Set PGPASSFILE if not already set and .pgpass exists in home directory
 if [[ -z "${PGPASSFILE:-}" ]] && [[ -f "${HOME}/.pgpass" ]]; then
  export PGPASSFILE="${HOME}/.pgpass"
 fi

 if [[ "${DBUSER}" == "${current_user}" ]] && [[ "${DBHOST}" == "localhost" || "${DBHOST}" == "127.0.0.1" || -z "${DBHOST}" ]]; then
  # Peer authentication
  if [[ -n "${DBPORT}" && "${DBPORT}" != "5432" ]]; then
   psql_cmd="${psql_cmd} -p ${DBPORT}"
  fi
 else
  # Password authentication - specify user and use TCP
  # Always use -h localhost when DBUSER != current_user to force TCP and use .pgpass
  psql_cmd="${psql_cmd} -U ${DBUSER}"
  if [[ "${DBHOST}" == "localhost" || "${DBHOST}" == "127.0.0.1" || -z "${DBHOST}" ]]; then
   # Force TCP connection to use .pgpass instead of peer auth
   psql_cmd="${psql_cmd} -h localhost"
  else
   psql_cmd="${psql_cmd} -h ${DBHOST}"
  fi
  if [[ -n "${DBPORT}" && "${DBPORT}" != "5432" ]]; then
   psql_cmd="${psql_cmd} -p ${DBPORT}"
  fi
  # Use PGPASSWORD if set, otherwise rely on .pgpass
  if [[ -n "${PGPASSWORD:-}" ]]; then
   psql_cmd="PGPASSWORD=\"${PGPASSWORD}\" ${psql_cmd}"
  elif [[ -n "${PGPASSFILE:-}" ]]; then
   # Ensure PGPASSFILE is exported for psql to use
   psql_cmd="PGPASSFILE=\"${PGPASSFILE}\" ${psql_cmd}"
  fi
 fi

 if eval "${psql_cmd} -d ${dbname} -c \"SELECT 1\"" > /dev/null 2>&1; then
  return 0
 else
  return 1
 fi
}

##
# Store metric in database
#
# Arguments:
#   $1 - Component name (ingestion, analytics, wms, api, data, infrastructure)
#   $2 - Metric name
#   $3 - Metric value (numeric)
#   $4 - Metric unit (optional)
#   $5 - Metadata JSON (optional)
#
# Returns:
#   0 on success, 1 on failure
##
store_metric() {
 local component="${1:?Component required}"
 local metric_name="${2:?Metric name required}"
 local metric_value="${3:?Metric value required}"
 local metric_unit="${4:-}"
 local metadata="${5:-null}"

 # Validate component
 case "${component}" in
 ingestion | analytics | wms | api | data | infrastructure) ;;
 *)
  echo "Invalid component: ${component}" >&2
  return 1
  ;;
 esac

 # Build SQL query
 # Escape single quotes in metadata JSON for SQL
 # PostgreSQL requires single quotes to be doubled in string literals
 local metadata_escaped="${metadata}"
 # Escape single quotes by doubling them (PostgreSQL escaping)
 metadata_escaped="${metadata_escaped//\'/\'\'}"

 # Build query - wrap JSON in single quotes and cast to jsonb
 # The JSON should already be properly formatted from record_metric
 local query
 query="INSERT INTO metrics (component, metric_name, metric_value, metric_unit, metadata)
           VALUES ('${component}', '${metric_name}', ${metric_value}, '${metric_unit}', '${metadata_escaped}'::jsonb);"

 if ! execute_sql_query "${query}" > /dev/null; then
  return 1
 fi

 return 0
}

##
# Get component health status
#
# Arguments:
#   $1 - Component name
#
# Returns:
#   Health status via stdout (healthy, degraded, down, unknown)
##
get_component_health() {
 local component="${1:?Component required}"
 local status

 status=$(execute_sql_query \
  "SELECT status FROM component_health WHERE component = '${component}';" 2> /dev/null)

 if [[ -z "${status}" ]]; then
  echo "unknown"
  return 1
 fi

 echo "${status}"
 return 0
}

##
# Update component health status
#
# Arguments:
#   $1 - Component name
#   $2 - Status (healthy, degraded, down, unknown)
#   $3 - Error count (optional)
#
# Returns:
#   0 on success, 1 on failure
##
update_component_health() {
 local component="${1:?Component required}"
 local status="${2:?Status required}"
 local error_count="${3:-0}"

 # Validate status
 case "${status}" in
 healthy | degraded | down | unknown) ;;
 *)
  echo "Invalid status: ${status}" >&2
  return 1
  ;;
 esac

 local query
 if [[ "${status}" == "healthy" ]]; then
  query="UPDATE component_health 
               SET status = '${status}', 
                   last_check = CURRENT_TIMESTAMP,
                   last_success = CURRENT_TIMESTAMP,
                   error_count = ${error_count}
               WHERE component = '${component}';"
 else
  query="UPDATE component_health 
               SET status = '${status}', 
                   last_check = CURRENT_TIMESTAMP,
                   error_count = ${error_count}
               WHERE component = '${component}';"
 fi

 if ! execute_sql_query "${query}" > /dev/null; then
  return 1
 fi

 return 0
}

##
# Check if a service is responding via HTTP
#
# Arguments:
#   $1 - Service URL
#   $2 - Timeout in seconds (default: 10)
#
# Returns:
#   0 if healthy, 1 if unhealthy
##
check_http_health() {
 local url="${1:?URL required}"
 local timeout="${2:-10}"

 if curl -f -s --max-time "${timeout}" "${url}" > /dev/null 2>&1; then
  return 0
 else
  return 1
 fi
}

##
# Get HTTP response time
#
# Arguments:
#   $1 - Service URL
#   $2 - Timeout in seconds (default: 10)
#
# Returns:
#   Response time in milliseconds via stdout
##
get_http_response_time() {
 local url="${1:?URL required}"
 local timeout="${2:-10}"
 local start_time
 local end_time
 local duration_ms

 start_time=$(date +%s%N)

 if curl -f -s --max-time "${timeout}" "${url}" > /dev/null 2>&1; then
  end_time=$(date +%s%N)
  duration_ms=$(((end_time - start_time) / 1000000))
  echo "${duration_ms}"
  return 0
 else
  echo "-1"
  return 1
 fi
}

# Initialize on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
 init_monitoring
fi
