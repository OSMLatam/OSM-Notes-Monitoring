# Analytics Alert Thresholds

> **Purpose:** Comprehensive documentation of all alert thresholds for analytics monitoring  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document defines all alert thresholds for the OSM-Notes-Analytics component. These thresholds are used to determine when alerts should be triggered based on metric values.

## Configuration

All thresholds are configurable via `config/monitoring.conf`. Default values are defined in `config/monitoring.conf.example`.

## Alert Thresholds by Category

### 1. ETL Job Execution Thresholds

#### `ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD`
- **Default:** `2`
- **Unit:** Count
- **Metric:** `etl_scripts_found`
- **Alert Condition:** `< threshold`
- **Description:** Minimum number of ETL scripts that should be found in the analytics repository
- **Severity:** WARNING
- **Action:** Check repository structure and script availability
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_ETL_SCRIPTS_EXECUTABLE_THRESHOLD`
- **Default:** Same as `ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD`
- **Unit:** Count
- **Metric:** `etl_scripts_executable`
- **Alert Condition:** `< etl_scripts_found`
- **Description:** Number of executable ETL scripts should equal scripts found
- **Severity:** WARNING
- **Action:** Check script permissions, ensure all scripts are executable
- **Configuration:** Derived from `ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD`

#### `ANALYTICS_ETL_SCRIPTS_RUNNING_THRESHOLD`
- **Default:** Same as `ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD`
- **Unit:** Count
- **Metric:** `etl_scripts_running`
- **Alert Condition:** `> threshold` (indicates duplicate executions)
- **Description:** Maximum number of ETL scripts that should be running simultaneously
- **Severity:** WARNING
- **Action:** Check for duplicate job executions, verify job scheduling
- **Configuration:** Derived from `ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD`

#### `ANALYTICS_ETL_LAST_EXECUTION_AGE_THRESHOLD`
- **Default:** `3600` (1 hour)
- **Unit:** Seconds
- **Metric:** `last_etl_execution_age_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum age of last ETL execution before alerting
- **Severity:** WARNING
- **Action:** Check if ETL jobs are running, verify cron jobs or scheduling system
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_ETL_ERROR_COUNT_THRESHOLD`
- **Default:** `0` (any error triggers alert)
- **Unit:** Count (24 hours)
- **Metric:** `etl_error_count`
- **Alert Condition:** `> threshold`
- **Description:** Maximum number of ETL errors in 24 hours before alerting
- **Severity:** WARNING
- **Action:** Review ETL error logs, check for systemic issues
- **Configuration:** Hardcoded (alert on any error)

#### `ANALYTICS_ETL_FAILURE_COUNT_THRESHOLD`
- **Default:** `0` (any failure triggers alert)
- **Unit:** Count (24 hours)
- **Metric:** `etl_failure_count`
- **Alert Condition:** `> threshold`
- **Description:** Maximum number of ETL job failures in 24 hours before alerting
- **Severity:** WARNING
- **Action:** Investigate failed ETL jobs, check dependencies and data sources
- **Configuration:** Hardcoded (alert on any failure)

### 2. ETL Processing Duration Thresholds

#### `ANALYTICS_ETL_DURATION_THRESHOLD`
- **Default:** `3600` (1 hour)
- **Unit:** Seconds
- **Metric:** `etl_running_jobs_duration_seconds` (for running jobs)
- **Alert Condition:** `> threshold`
- **Description:** Maximum duration for a single ETL job execution
- **Severity:** WARNING
- **Action:** Check for stuck or slow-running ETL jobs, investigate performance issues
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_ETL_AVG_DURATION_THRESHOLD`
- **Default:** `1800` (30 minutes)
- **Unit:** Seconds
- **Metric:** `etl_processing_duration_avg_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable average ETL processing duration over 7 days
- **Severity:** WARNING
- **Action:** Review ETL performance trends, optimize slow jobs
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_ETL_MAX_DURATION_THRESHOLD`
- **Default:** `7200` (2 hours)
- **Unit:** Seconds
- **Metric:** `etl_processing_duration_max_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable maximum ETL processing duration over 7 days
- **Severity:** WARNING
- **Action:** Investigate longest-running ETL jobs, optimize or split large jobs
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_ETL_LONG_RUNNING_JOBS_THRESHOLD`
- **Default:** Derived from `ANALYTICS_ETL_AVG_DURATION_THRESHOLD` (1.5x average)
- **Unit:** Seconds
- **Metric:** `etl_long_running_jobs_count`
- **Alert Condition:** `> 0`
- **Description:** Number of jobs running longer than expected (based on historical average)
- **Severity:** WARNING
- **Action:** Check for performance degradation or stuck jobs
- **Configuration:** Calculated dynamically

### 3. Data Warehouse Freshness Thresholds

#### `ANALYTICS_DATA_FRESHNESS_THRESHOLD`
- **Default:** `3600` (1 hour)
- **Unit:** Seconds
- **Metric:** `data_warehouse_freshness_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum age of most recent data update in the data warehouse
- **Severity:** WARNING
- **Action:** Check ETL job execution, verify data pipeline is running
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_DATA_WAREHOUSE_RECENT_UPDATES_THRESHOLD`
- **Default:** `0` (any updates expected)
- **Unit:** Count (1 hour)
- **Metric:** `data_warehouse_recent_updates_count`
- **Alert Condition:** `= 0` (no recent updates)
- **Description:** Minimum number of recent updates expected in the last hour
- **Severity:** WARNING
- **Action:** Verify ETL jobs are running and updating data warehouse
- **Configuration:** Hardcoded (alert if no updates)

### 4. Data Mart Thresholds

#### `ANALYTICS_DATA_MART_UPDATE_AGE_THRESHOLD`
- **Default:** `3600` (1 hour)
- **Unit:** Seconds
- **Metric:** `data_mart_update_age_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum age of most recent update for a data mart
- **Severity:** WARNING
- **Action:** Check data mart update jobs, verify ETL pipeline
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_DATA_MART_AVG_UPDATE_AGE_THRESHOLD`
- **Default:** `1800` (30 minutes)
- **Unit:** Seconds
- **Metric:** `data_mart_avg_update_age_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable average update age across all data marts
- **Severity:** WARNING
- **Action:** Review data mart update frequency, optimize update jobs
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_DATA_MART_RECENT_UPDATES_THRESHOLD`
- **Default:** `0` (any updates expected for frequently updated marts)
- **Unit:** Count (1 hour)
- **Metric:** `data_mart_recent_updates_count`
- **Alert Condition:** `= 0` for frequently updated marts
- **Description:** Minimum number of recent updates expected in the last hour
- **Severity:** WARNING
- **Action:** Verify data mart update jobs are running
- **Configuration:** Hardcoded (alert if no updates for frequently updated marts)

#### `ANALYTICS_DATA_MART_STALE_COUNT_THRESHOLD`
- **Default:** `0` (no stale marts expected)
- **Unit:** Count
- **Metric:** `data_mart_stale_count`
- **Alert Condition:** `> threshold`
- **Description:** Maximum number of stale data marts (exceeding freshness threshold)
- **Severity:** WARNING
- **Action:** Review stale data marts, check update jobs
- **Configuration:** Hardcoded (alert if any stale marts)

#### `ANALYTICS_DATA_MART_FAILED_COUNT_THRESHOLD`
- **Default:** `0` (no failures expected)
- **Unit:** Count
- **Metric:** `data_mart_failed_count`
- **Alert Condition:** `> threshold`
- **Description:** Maximum number of data marts with update failures
- **Severity:** ERROR
- **Action:** Investigate failed data mart updates, check error logs
- **Configuration:** Hardcoded (alert on any failure)

### 5. Query Performance Thresholds

#### `ANALYTICS_SLOW_QUERY_THRESHOLD`
- **Default:** `1000` (1 second)
- **Unit:** Milliseconds
- **Metric:** `slow_query_count`, `query_time_ms`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable query execution time
- **Severity:** WARNING
- **Action:** Optimize slow queries, check indexes, review query plans
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_AVG_QUERY_TIME_THRESHOLD`
- **Default:** `500` (0.5 seconds)
- **Unit:** Milliseconds
- **Metric:** `query_avg_time_ms`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable average query execution time
- **Severity:** WARNING
- **Action:** Review query performance trends, optimize frequently executed queries
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_MAX_QUERY_TIME_THRESHOLD`
- **Default:** `5000` (5 seconds)
- **Unit:** Milliseconds
- **Metric:** `query_max_time_ms`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable maximum query execution time
- **Severity:** WARNING
- **Action:** Investigate longest-running queries, optimize or add indexes
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_UNUSED_INDEX_COUNT_THRESHOLD`
- **Default:** `0` (all indexes should be used)
- **Unit:** Count
- **Metric:** `unused_index_count`
- **Alert Condition:** `> threshold`
- **Description:** Maximum number of potentially unused indexes
- **Severity:** INFO/WARNING
- **Action:** Review unused indexes, consider removing to improve write performance
- **Configuration:** Hardcoded (informational, not critical)

### 6. Storage Thresholds

#### `ANALYTICS_DB_SIZE_THRESHOLD`
- **Default:** `107374182400` (100 GB)
- **Unit:** Bytes
- **Metric:** `database_size_bytes`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable total database size
- **Severity:** WARNING
- **Action:** Review data retention policies, archive old data, plan for capacity expansion
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_LARGEST_TABLE_SIZE_THRESHOLD`
- **Default:** `10737418240` (10 GB)
- **Unit:** Bytes
- **Metric:** `largest_table_size_bytes`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable size for the largest table
- **Severity:** WARNING
- **Action:** Review table partitioning, consider archiving old data, optimize table structure
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_DISK_USAGE_THRESHOLD`
- **Default:** `85` (85%)
- **Unit:** Percentage
- **Metric:** `disk_usage_percent`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable disk usage percentage
- **Severity:** WARNING (> 85%), CRITICAL (> 90%)
- **Action:** Free up disk space, archive old data, expand storage
- **Configuration:** `config/monitoring.conf`

#### `ANALYTICS_DISK_CRITICAL_THRESHOLD`
- **Default:** `90` (90%)
- **Unit:** Percentage
- **Metric:** `disk_usage_percent`
- **Alert Condition:** `> threshold`
- **Description:** Critical disk usage threshold (higher than warning)
- **Severity:** CRITICAL
- **Action:** Immediate action required - free disk space, stop non-critical processes
- **Configuration:** Hardcoded (90% critical, 85% warning)

## Threshold Configuration

### Setting Thresholds

Thresholds can be configured in `config/monitoring.conf`:

```bash
# ETL Thresholds
ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD=2
ANALYTICS_ETL_LAST_EXECUTION_AGE_THRESHOLD=3600
ANALYTICS_ETL_DURATION_THRESHOLD=3600
ANALYTICS_ETL_AVG_DURATION_THRESHOLD=1800
ANALYTICS_ETL_MAX_DURATION_THRESHOLD=7200

# Data Freshness Thresholds
ANALYTICS_DATA_FRESHNESS_THRESHOLD=3600
ANALYTICS_DATA_MART_UPDATE_AGE_THRESHOLD=3600
ANALYTICS_DATA_MART_AVG_UPDATE_AGE_THRESHOLD=1800

# Query Performance Thresholds
ANALYTICS_SLOW_QUERY_THRESHOLD=1000
ANALYTICS_AVG_QUERY_TIME_THRESHOLD=500
ANALYTICS_MAX_QUERY_TIME_THRESHOLD=5000

# Storage Thresholds
ANALYTICS_DB_SIZE_THRESHOLD=107374182400
ANALYTICS_LARGEST_TABLE_SIZE_THRESHOLD=10737418240
ANALYTICS_DISK_USAGE_THRESHOLD=85
```

### Threshold Validation

Thresholds are validated when the monitoring script starts:
- Numeric values must be positive integers or floats
- Units must match the metric type (seconds, milliseconds, bytes, percentage, count)
- Thresholds are loaded from configuration or use defaults if not specified

## Alert Severity Levels

### WARNING
- Indicates a potential issue that should be investigated
- System is still functional but may degrade
- Examples: Slow queries, stale data, approaching capacity limits

### ERROR
- Indicates a problem that needs immediate attention
- System functionality may be impacted
- Examples: Failed ETL jobs, data mart update failures

### CRITICAL
- Indicates a critical issue requiring immediate action
- System functionality is severely impacted
- Examples: Disk usage > 90%, database connection failures

## Best Practices

### Threshold Tuning

1. **Start Conservative:** Begin with default thresholds and adjust based on observed behavior
2. **Monitor Trends:** Review metrics over time to identify patterns
3. **Adjust Gradually:** Change thresholds incrementally to avoid alert fatigue
4. **Document Changes:** Record threshold changes and reasons in configuration comments
5. **Review Regularly:** Periodically review thresholds based on system capacity and requirements

### Alert Fatigue Prevention

1. **Use Appropriate Severity:** Don't set all alerts to CRITICAL
2. **Implement Deduplication:** Use alert deduplication to prevent spam
3. **Set Reasonable Thresholds:** Avoid thresholds that trigger too frequently
4. **Review Alert History:** Periodically review which alerts fire most often

### Capacity Planning

Use storage and performance thresholds to plan for growth:
- Monitor trends in database size and query performance
- Set thresholds that provide advance warning before capacity limits
- Review thresholds quarterly or when system load changes significantly

## Related Documentation

- [Analytics Metrics Definition](ANALYTICS_METRICS.md) - Complete list of analytics metrics
- [Analytics Monitoring Guide](ANALYTICS_MONITORING_GUIDE.md) - How to use analytics monitoring
- [ETL Monitoring Runbook](ETL_MONITORING_RUNBOOK.md) - Troubleshooting ETL issues
- [Performance Tuning Guide](PERFORMANCE_TUNING_GUIDE.md) - Optimizing analytics performance

