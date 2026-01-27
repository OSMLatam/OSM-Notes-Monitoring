#!/usr/bin/env bash
#
# Database Metrics Collection Script
# Collects database performance and size metrics from PostgreSQL
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
 init_logging "${LOG_DIR}/database_metrics.log" "collectDatabaseMetrics"
fi

# Component name
readonly COMPONENT="ANALYTICS"

# SQL query files (for reference, may be used in future)
# readonly DB_PERFORMANCE_SQL="${PROJECT_ROOT}/sql/analytics/database_performance.sql"
# readonly DB_SIZES_SQL="${PROJECT_ROOT}/sql/analytics/database_sizes.sql"

##
# Show usage
##
usage() {
 cat << EOF
Database Metrics Collection Script

Collects database performance and size metrics from PostgreSQL for the Analytics data warehouse.

Usage: $0 [OPTIONS]

Options:
    -h, --help            Show this help message

Examples:
    # Collect all database metrics
    $0
EOF
}

##
# Collect cache hit ratio
##
collect_cache_hit_ratio() {
 log_info "${COMPONENT}: Collecting cache hit ratio"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot collect cache hit ratio - database connection failed"
  return 1
 fi

 local query="SELECT ROUND(SUM(heap_blks_hit)::numeric / NULLIF(SUM(heap_blks_hit) + SUM(heap_blks_read), 0) * 100, 2) AS cache_hit_ratio_percent FROM pg_statio_user_tables WHERE schemaname = 'dwh';"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local cache_hit_ratio
  cache_hit_ratio=$(echo "${result}" | tr -d '[:space:]' || echo "0")
  record_metric "${COMPONENT}" "db_cache_hit_ratio_percent" "${cache_hit_ratio}" "component=analytics"
  log_info "${COMPONENT}: Cache hit ratio: ${cache_hit_ratio}%"
 else
  log_warning "${COMPONENT}: Could not retrieve cache hit ratio"
 fi

 return 0
}

##
# Collect active connections
##
collect_active_connections() {
 log_info "${COMPONENT}: Collecting active connections"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot collect connections - database connection failed"
  return 1
 fi

 local query="SELECT application_name, COUNT(*) AS active_connections FROM pg_stat_activity WHERE datname = current_database() GROUP BY application_name;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local total_connections=0
  while IFS='|' read -r app_name conn_count; do
   app_name=$(echo "${app_name}" | xargs)
   conn_count=$(echo "${conn_count}" | tr -d '[:space:]' || echo "0")
   if [[ -n "${app_name}" ]] && [[ "${conn_count}" =~ ^[0-9]+$ ]]; then
    record_metric "${COMPONENT}" "db_active_connections" "${conn_count}" "component=analytics,application=\"${app_name}\""
    total_connections=$((total_connections + conn_count))
   fi
  done <<< "${result}"

  record_metric "${COMPONENT}" "db_total_connections" "${total_connections}" "component=analytics"
  log_info "${COMPONENT}: Total active connections: ${total_connections}"
 else
  log_warning "${COMPONENT}: Could not retrieve connection statistics"
 fi

 return 0
}

##
# Collect slow queries
##
collect_slow_queries() {
 log_info "${COMPONENT}: Collecting slow queries"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot collect slow queries - database connection failed"
  return 1
 fi

 local query="SELECT COUNT(*) FROM pg_stat_activity WHERE datname = current_database() AND state != 'idle' AND query_start < NOW() - INTERVAL '30 seconds';"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local slow_query_count
  slow_query_count=$(echo "${result}" | tr -d '[:space:]' || echo "0")
  record_metric "${COMPONENT}" "db_slow_queries_count" "${slow_query_count}" "component=analytics"
  log_info "${COMPONENT}: Slow queries (>30s): ${slow_query_count}"
 fi

 return 0
}

##
# Collect active locks
##
collect_active_locks() {
 log_info "${COMPONENT}: Collecting active locks"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot collect locks - database connection failed"
  return 1
 fi

 local query="SELECT COUNT(*) FROM pg_locks WHERE database = (SELECT oid FROM pg_database WHERE datname = current_database());"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local lock_count
  lock_count=$(echo "${result}" | tr -d '[:space:]' || echo "0")
  record_metric "${COMPONENT}" "db_active_locks_count" "${lock_count}" "component=analytics"
  log_info "${COMPONENT}: Active locks: ${lock_count}"
 fi

 return 0
}

##
# Collect table bloat
##
collect_table_bloat() {
 log_info "${COMPONENT}: Collecting table bloat"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot collect bloat - database connection failed"
  return 1
 fi

 local query="SELECT schemaname, tablename, n_dead_tup, n_live_tup, CASE WHEN n_live_tup > 0 THEN ROUND((n_dead_tup::numeric / n_live_tup) * 100, 2) ELSE 0 END AS dead_tuple_percent FROM pg_stat_user_tables WHERE schemaname = 'dwh' ORDER BY n_dead_tup DESC LIMIT 10;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local total_dead_tuples=0
  local total_live_tuples=0
  while IFS='|' read -r _ table dead_tup live_tup _; do
   dead_tup=$(echo "${dead_tup}" | tr -d '[:space:]' || echo "0")
   live_tup=$(echo "${live_tup}" | tr -d '[:space:]' || echo "0")
   if [[ "${dead_tup}" =~ ^[0-9]+$ ]] && [[ "${live_tup}" =~ ^[0-9]+$ ]]; then
    total_dead_tuples=$((total_dead_tuples + dead_tup))
    total_live_tuples=$((total_live_tuples + live_tup))
    record_metric "${COMPONENT}" "db_table_dead_tuples" "${dead_tup}" "component=analytics,table=\"${table}\""
   fi
  done <<< "${result}"

  local overall_bloat_percent=0
  if [[ ${total_live_tuples} -gt 0 ]]; then
   overall_bloat_percent=$((total_dead_tuples * 100 / total_live_tuples))
  fi
  record_metric "${COMPONENT}" "db_overall_bloat_percent" "${overall_bloat_percent}" "component=analytics"
  log_info "${COMPONENT}: Overall bloat: ${overall_bloat_percent}%"
 fi

 return 0
}

##
# Collect schema size
##
collect_schema_size() {
 log_info "${COMPONENT}: Collecting schema size"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot collect schema size - database connection failed"
  return 1
 fi

 local query="SELECT schemaname, SUM(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size_bytes FROM pg_tables WHERE schemaname = 'dwh' GROUP BY schemaname;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local schema_size_bytes
  schema_size_bytes=$(echo "${result}" | cut -d'|' -f2 | tr -d '[:space:]' || echo "0")
  if [[ "${schema_size_bytes}" =~ ^[0-9]+$ ]]; then
   record_metric "${COMPONENT}" "db_schema_size_bytes" "${schema_size_bytes}" "component=analytics,schema=dwh"
   log_info "${COMPONENT}: DWH schema size: ${schema_size_bytes} bytes"
  fi
 fi

 return 0
}

##
# Collect facts table size by partition
##
collect_facts_partition_sizes() {
 log_info "${COMPONENT}: Collecting facts partition sizes"

 if ! check_database_connection; then
  log_warning "${COMPONENT}: Cannot collect partition sizes - database connection failed"
  return 1
 fi

 local query="SELECT tablename, pg_total_relation_size(schemaname||'.'||tablename) AS size_bytes FROM pg_tables WHERE schemaname = 'dwh' AND (tablename = 'facts' OR tablename LIKE 'facts_%') ORDER BY tablename;"
 local result
 result=$(execute_sql_query "${query}" 2> /dev/null || echo "")

 if [[ -n "${result}" ]]; then
  local total_facts_size=0
  while IFS='|' read -r table_name size_bytes; do
   size_bytes=$(echo "${size_bytes}" | tr -d '[:space:]' || echo "0")
   if [[ "${size_bytes}" =~ ^[0-9]+$ ]]; then
    local partition_year="unknown"
    if [[ "${table_name}" =~ facts_([0-9]{4}) ]]; then
     partition_year="${BASH_REMATCH[1]}"
    fi
    record_metric "${COMPONENT}" "db_facts_partition_size_bytes" "${size_bytes}" "component=analytics,partition=\"${table_name}\",year=\"${partition_year}\""
    total_facts_size=$((total_facts_size + size_bytes))
   fi
  done <<< "${result}"

  record_metric "${COMPONENT}" "db_facts_total_size_bytes" "${total_facts_size}" "component=analytics"
  log_info "${COMPONENT}: Total facts table size: ${total_facts_size} bytes"
 fi

 return 0
}

##
# Main function
##
main() {
 log_info "${COMPONENT}: Starting database metrics collection"

 # Load configuration
 if ! load_monitoring_config; then
  log_error "${COMPONENT}: Failed to load monitoring configuration"
  exit 1
 fi

 # Check database connection
 if ! check_database_connection; then
  log_error "${COMPONENT}: Database connection failed, cannot collect metrics"
  exit 1
 fi

 # Collect all metrics
 collect_cache_hit_ratio
 collect_active_connections
 collect_slow_queries
 collect_active_locks
 collect_table_bloat
 collect_schema_size
 collect_facts_partition_sizes

 log_info "${COMPONENT}: Database metrics collection completed"
 return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 main "$@"
fi
