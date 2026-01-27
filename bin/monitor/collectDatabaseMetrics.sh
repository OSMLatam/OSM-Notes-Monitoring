#!/usr/bin/env bash
#
# Database Metrics Collection Script
# Collects advanced database performance metrics for ingestion monitoring
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
init_logging "${LOG_DIR}/database_metrics.log" "collectDatabaseMetrics"

# Component name
readonly COMPONENT="INGESTION"

# Database name (can be overridden)
readonly INGESTION_DBNAME="${INGESTION_DBNAME:-notes}"

##
# Get table sizes for main tables
##
collect_table_sizes() {
 log_info "${COMPONENT}: Collecting table sizes"

 local query="
        SELECT 
            tablename,
            pg_total_relation_size('public.'||tablename) AS total_size_bytes,
            pg_relation_size('public.'||tablename) AS table_size_bytes,
            pg_total_relation_size('public.'||tablename) - pg_relation_size('public.'||tablename) AS indexes_size_bytes
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename IN ('notes', 'note_comments', 'note_comment_texts', 'countries', 'maritime_boundaries')
        ORDER BY pg_total_relation_size('public.'||tablename) DESC;
    "

 local result
 result=$(execute_sql_query "${query}" "${INGESTION_DBNAME}" 2> /dev/null || echo "")

 if [[ -z "${result}" ]]; then
  log_debug "${COMPONENT}: No table size data available"
  return 0
 fi

 # Parse results and record metrics
 while IFS='|' read -r tablename total_size table_size indexes_size; do
  # Remove whitespace
  tablename=$(echo "${tablename}" | tr -d '[:space:]')
  total_size=$(echo "${total_size}" | tr -d '[:space:]')
  table_size=$(echo "${table_size}" | tr -d '[:space:]')
  indexes_size=$(echo "${indexes_size}" | tr -d '[:space:]')

  if [[ -n "${tablename}" ]] && [[ -n "${total_size}" ]] && [[ "${total_size}" =~ ^[0-9]+$ ]]; then
   record_metric "${COMPONENT}" "db_table_size_bytes" "${total_size}" "component=ingestion,table=${tablename}"
   record_metric "${COMPONENT}" "db_table_data_size_bytes" "${table_size}" "component=ingestion,table=${tablename}"
   record_metric "${COMPONENT}" "db_index_size_bytes" "${indexes_size}" "component=ingestion,table=${tablename}"

   log_debug "${COMPONENT}: Table ${tablename} - Total: ${total_size} bytes, Data: ${table_size} bytes, Indexes: ${indexes_size} bytes"
  fi
 done <<< "${result}"

 return 0
}

##
# Get table bloat ratio
##
collect_table_bloat() {
 log_info "${COMPONENT}: Collecting table bloat metrics"

 local query="
        SELECT 
            tablename,
            n_live_tup AS live_tuples,
            n_dead_tup AS dead_tuples,
            ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS bloat_ratio_percent
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND tablename IN ('notes', 'note_comments', 'note_comment_texts')
        ORDER BY n_dead_tup DESC;
    "

 local result
 local error_output
 error_output=$(execute_sql_query "${query}" "${INGESTION_DBNAME}" 2>&1)
 local exit_code=$?

 if [[ ${exit_code} -ne 0 ]]; then
  log_warning "${COMPONENT}: Failed to collect bloat data: ${error_output}"
  return 0
 fi

 result="${error_output}"

 if [[ -z "${result}" ]]; then
  log_debug "${COMPONENT}: No bloat data available"
  return 0
 fi

 # Parse results and record metrics
 local metrics_recorded=0
 while IFS='|' read -r tablename _live_tuples _dead_tuples bloat_ratio; do
  tablename=$(echo "${tablename}" | tr -d '[:space:]')
  bloat_ratio=$(echo "${bloat_ratio}" | tr -d '[:space:]')

  if [[ -n "${tablename}" ]] && [[ -n "${bloat_ratio}" ]] && [[ "${bloat_ratio}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
   record_metric "${COMPONENT}" "db_table_bloat_ratio" "${bloat_ratio}" "component=ingestion,table=${tablename}"
   log_debug "${COMPONENT}: Table ${tablename} - Bloat ratio: ${bloat_ratio}%"
   metrics_recorded=$((metrics_recorded + 1))
  else
   log_debug "${COMPONENT}: Skipping invalid bloat data: tablename='${tablename}', bloat_ratio='${bloat_ratio}'"
  fi
 done <<< "${result}"

 if [[ ${metrics_recorded} -eq 0 ]]; then
  log_debug "${COMPONENT}: No valid bloat metrics recorded (result: '${result}')"
 fi

 return 0
}

##
# Get index usage statistics
##
collect_index_usage() {
 log_info "${COMPONENT}: Collecting index usage metrics"

 local query="
        SELECT 
            t.tablename,
            COALESCE(SUM(i.idx_scan), 0) AS total_index_scans,
            t.seq_scan AS sequential_scans,
            CASE 
                WHEN t.seq_scan + COALESCE(SUM(i.idx_scan), 0) > 0 
                THEN ROUND(COALESCE(SUM(i.idx_scan), 0) * 100.0 / (t.seq_scan + COALESCE(SUM(i.idx_scan), 0)), 2)
                ELSE 0
            END AS index_scan_ratio_percent
        FROM pg_stat_user_tables t
        LEFT JOIN pg_stat_user_indexes i ON t.schemaname = i.schemaname AND t.tablename = i.tablename
        WHERE t.schemaname = 'public'
          AND t.tablename IN ('notes', 'note_comments', 'note_comment_texts')
        GROUP BY t.schemaname, t.tablename, t.seq_scan
        ORDER BY sequential_scans DESC;
    "

 local result
 local error_output
 error_output=$(execute_sql_query "${query}" "${INGESTION_DBNAME}" 2>&1)
 local exit_code=$?

 if [[ ${exit_code} -ne 0 ]]; then
  log_warning "${COMPONENT}: Failed to collect index usage data: ${error_output}"
  return 0
 fi

 result="${error_output}"

 if [[ -z "${result}" ]]; then
  log_debug "${COMPONENT}: No index usage data available"
  return 0
 fi

 # Parse results and record metrics
 local metrics_recorded=0
 while IFS='|' read -r tablename _index_scans _seq_scans index_ratio; do
  tablename=$(echo "${tablename}" | tr -d '[:space:]')
  index_ratio=$(echo "${index_ratio}" | tr -d '[:space:]')

  if [[ -n "${tablename}" ]] && [[ -n "${index_ratio}" ]] && [[ "${index_ratio}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
   record_metric "${COMPONENT}" "db_index_scan_ratio" "${index_ratio}" "component=ingestion,table=${tablename}"
   log_debug "${COMPONENT}: Table ${tablename} - Index scan ratio: ${index_ratio}%"
   metrics_recorded=$((metrics_recorded + 1))
  else
   log_debug "${COMPONENT}: Skipping invalid index usage data: tablename='${tablename}', index_ratio='${index_ratio}'"
  fi
 done <<< "${result}"

 if [[ ${metrics_recorded} -eq 0 ]]; then
  log_debug "${COMPONENT}: No valid index usage metrics recorded (result: '${result}')"
 fi

 return 0
}

##
# Get unused indexes count
##
collect_unused_indexes() {
 log_info "${COMPONENT}: Collecting unused indexes metrics"

 local query="
        SELECT 
            COUNT(*) AS unused_index_count,
            SUM(pg_relation_size(indexrelid)) AS unused_index_size_bytes
        FROM pg_stat_user_indexes
        WHERE schemaname = 'public'
          AND idx_scan = 0
          AND tablename IN ('notes', 'note_comments', 'note_comment_texts');
    "

 local result
 result=$(execute_sql_query "${query}" "${INGESTION_DBNAME}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local unused_count=0
  local unused_size=0

  # Parse result (format: count|size_bytes)
  if [[ "${result}" =~ ^([0-9]+)\|([0-9]+)$ ]]; then
   unused_count="${BASH_REMATCH[1]}"
   unused_size="${BASH_REMATCH[2]}"
  elif [[ "${result}" =~ ^([0-9]+)\|$ ]]; then
   unused_count="${BASH_REMATCH[1]}"
  fi

  record_metric "${COMPONENT}" "db_unused_indexes_count" "${unused_count}" "component=ingestion"
  if [[ ${unused_size} -gt 0 ]]; then
   record_metric "${COMPONENT}" "db_unused_indexes_size_bytes" "${unused_size}" "component=ingestion"
  fi

  log_info "${COMPONENT}: Unused indexes - Count: ${unused_count}, Size: ${unused_size} bytes"
 fi

 return 0
}

##
# Get slow queries count (if pg_stat_statements is enabled)
##
collect_slow_queries() {
 log_info "${COMPONENT}: Collecting slow queries metrics"

 # Check if pg_stat_statements extension is available
 local check_query="SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements';"
 local ext_count
 ext_count=$(execute_sql_query "${check_query}" "${INGESTION_DBNAME}" 2> /dev/null | tr -d '[:space:]' || echo "0")

 if [[ "${ext_count}" == "0" ]]; then
  log_debug "${COMPONENT}: pg_stat_statements extension not available, skipping slow queries check"
  return 0
 fi

 local query="
        SELECT 
            COUNT(*) AS slow_query_count
        FROM pg_stat_statements
        WHERE mean_exec_time > 1000
          AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database());
    "

 local result
 result=$(execute_sql_query "${query}" "${INGESTION_DBNAME}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+$ ]]; then
  record_metric "${COMPONENT}" "db_slow_queries_count" "${result}" "component=ingestion"
  log_info "${COMPONENT}: Slow queries count: ${result}"
 fi

 return 0
}

##
# Get cache hit ratio
##
collect_cache_hit_ratio() {
 log_info "${COMPONENT}: Collecting cache hit ratio"

 local query="
        SELECT 
            ROUND(blks_hit * 100.0 / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_ratio_percent
        FROM pg_stat_database
        WHERE datname = current_database();
    "

 local result
 result=$(execute_sql_query "${query}" "${INGESTION_DBNAME}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${result}" ]] && [[ "${result}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  record_metric "${COMPONENT}" "db_cache_hit_ratio" "${result}" "component=ingestion"
  log_info "${COMPONENT}: Cache hit ratio: ${result}%"
 fi

 return 0
}

##
# Get connection statistics
##
collect_connection_stats() {
 log_info "${COMPONENT}: Collecting connection statistics"

 # Active connections by application
 local app_query="
        SELECT 
            application_name,
            COUNT(*) AS connection_count
        FROM pg_stat_activity
        WHERE datname = current_database()
          AND application_name IS NOT NULL
        GROUP BY application_name
        ORDER BY connection_count DESC;
    "

 local app_result
 app_result=$(execute_sql_query "${app_query}" "${INGESTION_DBNAME}" 2> /dev/null || echo "")

 if [[ -n "${app_result}" ]]; then
  while IFS='|' read -r app_name conn_count; do
   app_name=$(echo "${app_name}" | tr -d '[:space:]')
   conn_count=$(echo "${conn_count}" | tr -d '[:space:]')

   if [[ -n "${app_name}" ]] && [[ -n "${conn_count}" ]] && [[ "${conn_count}" =~ ^[0-9]+$ ]]; then
    record_metric "${COMPONENT}" "db_connections_active_by_app" "${conn_count}" "component=ingestion,application=${app_name}"
   fi
  done <<< "${app_result}"
 fi

 # Overall connection statistics
 local conn_query="
        SELECT 
            COUNT(*) AS total_connections,
            COUNT(*) FILTER (WHERE state = 'active') AS active_connections,
            COUNT(*) FILTER (WHERE state = 'idle') AS idle_connections,
            COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction_connections,
            COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting_connections
        FROM pg_stat_activity
        WHERE datname = current_database();
    "

 local conn_result
 conn_result=$(execute_sql_query "${conn_query}" "${INGESTION_DBNAME}" 2> /dev/null || echo "")

 if [[ -n "${conn_result}" ]]; then
  # Parse result (format: total|active|idle|idle_in_trans|waiting)
  local total=0 active=0 idle=0 idle_in_trans=0 waiting=0

  if [[ "${conn_result}" =~ ^([0-9]+)\|([0-9]+)\|([0-9]+)\|([0-9]+)\|([0-9]+)$ ]]; then
   total="${BASH_REMATCH[1]}"
   active="${BASH_REMATCH[2]}"
   idle="${BASH_REMATCH[3]}"
   idle_in_trans="${BASH_REMATCH[4]}"
   waiting="${BASH_REMATCH[5]}"
  fi

  record_metric "${COMPONENT}" "db_connections_total" "${total}" "component=ingestion"
  record_metric "${COMPONENT}" "db_connections_active" "${active}" "component=ingestion"
  record_metric "${COMPONENT}" "db_connections_idle" "${idle}" "component=ingestion"
  record_metric "${COMPONENT}" "db_connections_idle_in_transaction" "${idle_in_trans}" "component=ingestion"
  record_metric "${COMPONENT}" "db_connections_waiting" "${waiting}" "component=ingestion"

  log_info "${COMPONENT}: Connections - Total: ${total}, Active: ${active}, Idle: ${idle}, Waiting: ${waiting}"
 fi

 # Connection usage percentage
 local usage_query="
        SELECT 
            COUNT(*) AS current_connections,
            current_setting('max_connections')::integer AS max_connections,
            ROUND(COUNT(*) * 100.0 / current_setting('max_connections')::integer, 2) AS connection_usage_percent
        FROM pg_stat_activity
        WHERE datname = current_database();
    "

 local usage_result
 usage_result=$(execute_sql_query "${usage_query}" "${INGESTION_DBNAME}" 2> /dev/null || echo "")

 if [[ -n "${usage_result}" ]]; then
  # Parse result (format: current|max|percent)
  local current=0 max=0 percent=0

  if [[ "${usage_result}" =~ ^([0-9]+)\|([0-9]+)\|([0-9]+\.?[0-9]*)$ ]]; then
   current="${BASH_REMATCH[1]}"
   max="${BASH_REMATCH[2]}"
   percent="${BASH_REMATCH[3]}"
  fi

  record_metric "${COMPONENT}" "db_connections_max" "${max}" "component=ingestion"
  record_metric "${COMPONENT}" "db_connection_usage_percent" "${percent}" "component=ingestion"

  log_info "${COMPONENT}: Connection usage: ${percent}% (${current}/${max})"
 fi

 return 0
}

##
# Get lock statistics
##
collect_lock_stats() {
 log_info "${COMPONENT}: Collecting lock statistics"

 # Active locks summary
 local lock_query="
        SELECT 
            COUNT(*) AS total_locks,
            COUNT(*) FILTER (WHERE granted = true) AS granted_locks,
            COUNT(*) FILTER (WHERE granted = false) AS waiting_locks
        FROM pg_locks;
    "

 local lock_result
 lock_result=$(execute_sql_query "${lock_query}" "${INGESTION_DBNAME}" 2> /dev/null || echo "")

 if [[ -n "${lock_result}" ]]; then
  local total=0 granted=0 waiting=0

  if [[ "${lock_result}" =~ ^([0-9]+)\|([0-9]+)\|([0-9]+)$ ]]; then
   total="${BASH_REMATCH[1]}"
   granted="${BASH_REMATCH[2]}"
   waiting="${BASH_REMATCH[3]}"
  fi

  record_metric "${COMPONENT}" "db_locks_total" "${total}" "component=ingestion"
  record_metric "${COMPONENT}" "db_locks_granted" "${granted}" "component=ingestion"
  record_metric "${COMPONENT}" "db_locks_waiting" "${waiting}" "component=ingestion"

  log_info "${COMPONENT}: Locks - Total: ${total}, Granted: ${granted}, Waiting: ${waiting}"
 fi

 # Deadlocks count
 local deadlock_query="
        SELECT 
            deadlocks AS deadlocks_count
        FROM pg_stat_database
        WHERE datname = current_database();
    "

 local deadlock_result
 deadlock_result=$(execute_sql_query "${deadlock_query}" "${INGESTION_DBNAME}" 2> /dev/null | tr -d '[:space:]' || echo "")

 if [[ -n "${deadlock_result}" ]] && [[ "${deadlock_result}" =~ ^[0-9]+$ ]]; then
  record_metric "${COMPONENT}" "db_deadlocks_count" "${deadlock_result}" "component=ingestion"
  log_info "${COMPONENT}: Deadlocks count: ${deadlock_result}"
 fi

 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting advanced database metrics collection"

 # Load configuration
 if ! load_all_configs; then
  log_error "${COMPONENT}: Failed to load configuration"
  return 1
 fi

 # Collect all metrics
 collect_table_sizes
 collect_table_bloat
 collect_index_usage
 collect_unused_indexes
 collect_slow_queries
 collect_cache_hit_ratio
 collect_connection_stats
 collect_lock_stats

 log_info "${COMPONENT}: Advanced database metrics collection completed"

 return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
