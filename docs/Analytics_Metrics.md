---
title: "Analytics Metrics Definition"
description: "This document defines all metrics collected for the OSM-Notes-Analytics component. These metrics are"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "performance"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Analytics Metrics Definition

> **Purpose:** Comprehensive definition of all analytics-specific metrics  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document defines all metrics collected for the OSM-Notes-Analytics component. These metrics are
stored in the `metrics` table of the monitoring database and are used for:

- Health monitoring
- Performance analysis
- Alerting
- Capacity planning
- Troubleshooting

## Metric Naming Convention

All analytics metrics follow this naming pattern:

- **Format:** `{category}_{metric_name}_{unit_suffix}`
- **Category:** Groups related metrics (e.g., `etl`, `data_warehouse`, `data_mart`, `query`,
  `storage`)
- **Unit Suffix:** Indicates unit type (`_count`, `_percent`, `_ms`, `_seconds`, `_bytes`)

## Metric Categories

### 1. ETL Job Execution Metrics

Metrics related to ETL job execution status, availability, and errors.

#### `etl_scripts_found`

- **Description:** Number of ETL scripts found in the analytics repository
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_etl_job_execution_status()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by deployment (typically 3-10 scripts)
- **Alert Threshold:** < 3 scripts found
- **Metadata:** `component=analytics`

#### `etl_scripts_executable`

- **Description:** Number of ETL scripts that are executable
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_etl_job_execution_status()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Should equal `etl_scripts_found`
- **Alert Threshold:** < `etl_scripts_found`
- **Metadata:** `component=analytics`

#### `etl_scripts_running`

- **Description:** Number of ETL scripts currently running
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_etl_job_execution_status()` by checking process list
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to `etl_scripts_found`
- **Alert Threshold:** > `etl_scripts_found` (indicates duplicate executions)
- **Metadata:** `component=analytics`

#### `last_etl_execution_age_seconds`

- **Description:** Age of the last ETL job execution in seconds
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_etl_job_execution_status()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to 86400 (24 hours)
- **Alert Threshold:** > configured threshold (default: 24 hours)
- **Metadata:** `component=analytics`

#### `etl_error_count`

- **Description:** Number of ETL errors in the last 24 hours
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_etl_job_execution_status()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no errors expected)
- **Alert Threshold:** > 0 errors
- **Metadata:** `component=analytics,period=24h`

#### `etl_failure_count`

- **Description:** Number of ETL job failures in the last 24 hours
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_etl_job_execution_status()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no failures expected)
- **Alert Threshold:** > 0 failures
- **Metadata:** `component=analytics,period=24h`

### 2. ETL Processing Duration Metrics

Metrics related to ETL job processing duration and performance.

#### `etl_processing_duration_avg_seconds`

- **Description:** Average ETL processing duration over the last 7 days
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_etl_processing_duration()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by job type (typically 100-3600 seconds)
- **Alert Threshold:** > configured threshold (default: varies by job)
- **Metadata:** `component=analytics,period=7days`

#### `etl_processing_duration_max_seconds`

- **Description:** Maximum ETL processing duration over the last 7 days
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_etl_processing_duration()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by job type
- **Alert Threshold:** > configured threshold
- **Metadata:** `component=analytics,period=7days`

#### `etl_processing_duration_min_seconds`

- **Description:** Minimum ETL processing duration over the last 7 days
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_etl_processing_duration()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by job type
- **Alert Threshold:** None (informational)
- **Metadata:** `component=analytics,period=7days`

#### `etl_processing_duration_total_seconds`

- **Description:** Total ETL processing duration over the last 7 days
- **Type:** Counter
- **Unit:** `seconds`
- **Collection:** Collected during `check_etl_processing_duration()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by job count and frequency
- **Alert Threshold:** None (informational)
- **Metadata:** `component=analytics,period=7days`

#### `etl_job_count`

- **Description:** Number of ETL jobs executed in the last 7 days
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_etl_processing_duration()` by analyzing log files
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by job schedule (typically 7-49 for daily jobs)
- **Alert Threshold:** < expected count (indicates missed executions)
- **Metadata:** `component=analytics,period=7days`

#### `etl_running_jobs_duration_seconds`

- **Description:** Total duration of currently running ETL jobs
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_etl_processing_duration()` by checking process start times
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to job-specific maximum
- **Alert Threshold:** > configured threshold (indicates stuck jobs)
- **Metadata:** `component=analytics`

#### `etl_long_running_jobs_count`

- **Description:** Number of ETL jobs that have been running longer than expected
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_etl_processing_duration()` by comparing current duration
  to historical average
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no long-running jobs expected)
- **Alert Threshold:** > 0 (indicates performance degradation or stuck jobs)
- **Metadata:** `component=analytics`

### 3. Data Warehouse Freshness Metrics

Metrics related to data warehouse data freshness and update activity.

#### `data_warehouse_freshness_seconds`

- **Description:** Age of the most recent data update in the data warehouse
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_data_warehouse_freshness()` by querying database or
  analyzing logs
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to 3600 (1 hour) for frequently updated tables
- **Alert Threshold:** > configured threshold (default: 3600 seconds)
- **Metadata:** `component=analytics` or `component=analytics,source=pg_stat` or
  `component=analytics,source=log_age`

#### `data_warehouse_recent_updates_count`

- **Description:** Number of recent updates in the data warehouse in the last hour
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_data_warehouse_freshness()` by querying database
- **Frequency:** Every monitoring cycle
- **Expected Range:** > 0 for active systems
- **Alert Threshold:** 0 (indicates no recent activity)
- **Metadata:** `component=analytics,period=1hour`

### 4. Data Mart Metrics

Metrics related to data mart update status and freshness.

#### `data_mart_update_age_seconds`

- **Description:** Age of the most recent update for a specific data mart
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_data_mart_update_status()` by querying database or
  analyzing logs
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to 86400 (24 hours) depending on update frequency
- **Alert Threshold:** > configured threshold (default: 24 hours)
- **Metadata:** `component=analytics,mart=data_mart` or `component=analytics,source=log_age`

#### `data_mart_recent_updates_count`

- **Description:** Number of recent updates in a data mart in the last hour
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_data_mart_update_status()` by querying database
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by mart update frequency
- **Alert Threshold:** 0 for frequently updated marts
- **Metadata:** `component=analytics,mart=data_mart,period=1hour`

#### `data_mart_total_records`

- **Description:** Total number of records in a data mart
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_data_mart_update_status()` by querying database
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by mart
- **Alert Threshold:** None (informational, used for capacity planning)
- **Metadata:** `component=analytics,mart=data_mart`

#### `data_mart_count`

- **Description:** Number of data marts checked
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_data_mart_update_status()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by deployment
- **Alert Threshold:** None (informational)
- **Metadata:** `component=analytics`

#### `data_mart_avg_update_age_seconds`

- **Description:** Average update age across all data marts
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_data_mart_update_status()` by aggregating individual mart
  ages
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to 86400 (24 hours)
- **Alert Threshold:** > configured threshold
- **Metadata:** `component=analytics`

#### `data_mart_max_update_age_seconds`

- **Description:** Maximum update age across all data marts
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_data_mart_update_status()` by finding the maximum age
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to 86400 (24 hours)
- **Alert Threshold:** > configured threshold
- **Metadata:** `component=analytics`

#### `data_mart_stale_count`

- **Description:** Number of data marts that are stale (exceed freshness threshold)
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_data_mart_update_status()` by counting marts exceeding
  threshold
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no stale marts expected)
- **Alert Threshold:** > 0
- **Metadata:** `component=analytics`

#### `data_mart_failed_count`

- **Description:** Number of data marts that failed to update
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_data_mart_update_status()` by checking for failure
  indicators
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no failures expected)
- **Alert Threshold:** > 0
- **Metadata:** `component=analytics`

### 5. Query Performance Metrics

Metrics related to query performance and database optimization.

#### `slow_query_count`

- **Description:** Number of slow queries detected (exceeding threshold)
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_query_performance()` by analyzing pg_stat_statements or
  test queries
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no slow queries expected)
- **Alert Threshold:** > 0
- **Metadata:** `component=analytics`

#### `query_max_time_ms`

- **Description:** Maximum query execution time in milliseconds
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_query_performance()` by analyzing pg_stat_statements or
  test queries
- **Frequency:** Every monitoring cycle
- **Expected Range:** < 1000ms for most queries
- **Alert Threshold:** > configured threshold (default: 1000ms)
- **Metadata:** `component=analytics` or `component=analytics,source=test_queries`

#### `query_avg_time_ms`

- **Description:** Average query execution time in milliseconds
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_query_performance()` by analyzing pg_stat_statements or
  test queries
- **Frequency:** Every monitoring cycle
- **Expected Range:** < 500ms for most queries
- **Alert Threshold:** > configured threshold (default: 500ms)
- **Metadata:** `component=analytics` or `component=analytics,source=test_queries`

#### `query_total_calls`

- **Description:** Total number of query calls analyzed
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_query_performance()` from pg_stat_statements
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by system activity
- **Alert Threshold:** None (informational)
- **Metadata:** `component=analytics`

#### `query_time_ms`

- **Description:** Execution time for a specific query (identified by hash)
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_query_performance()` by executing test queries
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by query type
- **Alert Threshold:** > configured threshold
- **Metadata:** `component=analytics,query_hash={hash}`

#### `queries_checked_count`

- **Description:** Number of queries checked during performance analysis
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_query_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by configuration
- **Alert Threshold:** None (informational)
- **Metadata:** `component=analytics`

#### `unused_index_count`

- **Description:** Number of potentially unused indexes (no scans)
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_query_performance()` by querying pg_stat_user_indexes
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (all indexes should be used)
- **Alert Threshold:** > 0 (indicates optimization opportunity)
- **Metadata:** `component=analytics`

### 6. Storage Metrics

Metrics related to database and storage growth.

#### `database_size_bytes`

- **Description:** Total size of the analytics database in bytes
- **Type:** Gauge
- **Unit:** `bytes`
- **Collection:** Collected during `check_storage_growth()` by querying pg_database_size()
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by data volume
- **Alert Threshold:** > configured threshold (default: 100GB)
- **Metadata:** `component=analytics`

#### `table_size_bytes`

- **Description:** Size of a specific table in bytes
- **Type:** Gauge
- **Unit:** `bytes`
- **Collection:** Collected during `check_storage_growth()` by querying pg_total_relation_size()
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by table
- **Alert Threshold:** > configured threshold per table
- **Metadata:** `component=analytics,table={table_name}`

#### `total_table_size_bytes`

- **Description:** Total size of all tables in the analytics database
- **Type:** Gauge
- **Unit:** `bytes`
- **Collection:** Collected during `check_storage_growth()` by summing table sizes
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by data volume
- **Alert Threshold:** > configured threshold
- **Metadata:** `component=analytics`

#### `largest_table_size_bytes`

- **Description:** Size of the largest table in bytes
- **Type:** Gauge
- **Unit:** `bytes`
- **Collection:** Collected during `check_storage_growth()` by finding the maximum table size
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by data distribution
- **Alert Threshold:** > configured threshold
- **Metadata:** `component=analytics,table={table_name}`

#### `tables_checked_count`

- **Description:** Number of tables checked during storage analysis
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_storage_growth()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by schema
- **Alert Threshold:** None (informational)
- **Metadata:** `component=analytics`

#### `disk_usage_percent`

- **Description:** Disk usage percentage for the database directory
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Collected during `check_storage_growth()` by checking filesystem usage
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-90%
- **Alert Threshold:** > 90% (critical), > 80% (warning)
- **Metadata:** `component=analytics,directory=database`

## Metric Collection Summary

### Collection Frequency

All metrics are collected during each monitoring cycle, which runs:

- **Default:** Every 5 minutes (configurable)
- **On-demand:** Via command-line execution
- **Scheduled:** Via cron job

### Collection Methods

1. **Database Queries:** Direct SQL queries to PostgreSQL
2. **Log Analysis:** Parsing log files for execution times and status
3. **Process Monitoring:** Checking running processes
4. **Filesystem Checks:** Checking disk usage and file ages
5. **pg_stat Views:** Using PostgreSQL statistics views

### Metric Storage

All metrics are stored in the `metrics` table with the following structure:

- `component`: Always "ANALYTICS" for analytics metrics
- `metric_name`: One of the metric names defined above
- `metric_value`: Numeric value of the metric
- `metadata`: JSON string with additional context (period, source, table name, etc.)
- `timestamp`: When the metric was collected

## Alert Thresholds

Default alert thresholds are defined in `config/monitoring.conf`. These can be overridden per
deployment:

- **ETL Scripts:** < 3 scripts found
- **ETL Errors:** > 0 errors
- **ETL Failures:** > 0 failures
- **Data Freshness:** > 3600 seconds (1 hour)
- **Data Mart Staleness:** > 86400 seconds (24 hours)
- **Slow Queries:** > 1000ms
- **Average Query Time:** > 500ms
- **Database Size:** > 100GB
- **Disk Usage:** > 90% (critical), > 80% (warning)

## Usage Examples

### Querying Metrics

```sql
-- Get latest ETL execution age
SELECT metric_value
FROM metrics
WHERE component = 'ANALYTICS'
  AND metric_name = 'last_etl_execution_age_seconds'
ORDER BY timestamp DESC
LIMIT 1;

-- Get average query time over last hour
SELECT AVG(metric_value) as avg_query_time
FROM metrics
WHERE component = 'ANALYTICS'
  AND metric_name = 'query_avg_time_ms'
  AND timestamp > NOW() - INTERVAL '1 hour';

-- Get data mart update ages
SELECT metric_value, metadata->>'mart' as mart_name
FROM metrics
WHERE component = 'ANALYTICS'
  AND metric_name = 'data_mart_update_age_seconds'
ORDER BY timestamp DESC;
```

### Monitoring Dashboards

These metrics can be used to create Grafana dashboards showing:

- ETL job execution status and duration trends
- Data warehouse and data mart freshness
- Query performance over time
- Storage growth trends
- Error and failure rates

## Related Documentation

- [Analytics Monitoring Guide](Analytics_Monitoring_Guide.md) - How to use analytics monitoring
- [ETL Monitoring Runbook](ETL_MONITORING_Runbook.md) - Troubleshooting ETL issues
- [Performance Tuning Guide](PERFORMANCE_TUNING_GUIDE.md) - Optimizing analytics performance
