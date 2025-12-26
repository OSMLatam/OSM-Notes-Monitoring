# Ingestion Metrics Definition

> **Purpose:** Comprehensive definition of all ingestion-specific metrics  
> **Version:** 1.0.0  
> **Date:** 2025-12-25  
> **Status:** Active

## Overview

This document defines all metrics collected for the OSM-Notes-Ingestion component. These metrics are stored in the `metrics` table of the monitoring database and are used for:

- Health monitoring
- Performance analysis
- Alerting
- Capacity planning
- Troubleshooting

## Metric Naming Convention

All ingestion metrics follow this naming pattern:
- **Format:** `{category}_{metric_name}_{unit_suffix}`
- **Category:** Groups related metrics (e.g., `script`, `db`, `data`, `error`)
- **Unit Suffix:** Indicates unit type (`_count`, `_percent`, `_ms`, `_seconds`, `_hours`, `_bytes`)

## Metric Categories

### 1. Script Execution Metrics

Metrics related to script execution status and availability.

#### `scripts_found`
- **Description:** Number of ingestion scripts found in the repository
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_script_execution_status()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 3-5 scripts
- **Alert Threshold:** < 3 scripts found
- **Metadata:** `component=ingestion`

#### `scripts_executable`
- **Description:** Number of ingestion scripts that are executable
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_script_execution_status()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Should equal `scripts_found`
- **Alert Threshold:** < `scripts_found`
- **Metadata:** `component=ingestion`

#### `scripts_running`
- **Description:** Number of ingestion scripts currently running
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_script_execution_status()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-5 (depends on scheduled execution)
- **Alert Threshold:** Unexpected number of running scripts
- **Metadata:** `component=ingestion`

#### `last_log_age_hours`
- **Description:** Age of the most recent log file in hours
- **Type:** Gauge
- **Unit:** `hours`
- **Collection:** Collected during `check_last_execution_time()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-24 hours
- **Alert Threshold:** > 24 hours (no recent activity)
- **Metadata:** `component=ingestion`

### 2. Error and Logging Metrics

Metrics related to errors, warnings, and log analysis.

#### `error_count`
- **Description:** Total number of error lines found in log files (last 24 hours)
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_error_rate()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-100 (depends on system load)
- **Alert Threshold:** > 1000 errors in 24 hours
- **Metadata:** `component=ingestion`

#### `warning_count`
- **Description:** Total number of warning lines found in log files (last 24 hours)
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_error_rate()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-500
- **Alert Threshold:** > 2000 warnings in 24 hours
- **Metadata:** `component=ingestion`

#### `error_rate_percent`
- **Description:** Percentage of error lines relative to total log lines
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Calculated during `check_error_rate()`
- **Frequency:** Every monitoring cycle
- **Calculation:** `(error_lines / total_lines) * 100`
- **Expected Range:** 0-5%
- **Alert Threshold:** > 5% (configurable via `INGESTION_MAX_ERROR_RATE`)
- **Metadata:** `component=ingestion`

#### `warning_rate_percent`
- **Description:** Percentage of warning lines relative to total log lines
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Calculated during `check_error_rate()`
- **Frequency:** Every monitoring cycle
- **Calculation:** `(warning_lines / total_lines) * 100`
- **Expected Range:** 0-10%
- **Alert Threshold:** > 15%
- **Metadata:** `component=ingestion`

#### `log_lines_total`
- **Description:** Total number of log lines analyzed
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_error_rate()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies with system activity
- **Metadata:** `component=ingestion`

#### `recent_error_rate_percent`
- **Description:** Error rate in the last hour (for spike detection)
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Collected during `check_recent_error_spikes()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-5%
- **Alert Threshold:** > 2x `INGESTION_MAX_ERROR_RATE` (spike detection)
- **Metadata:** `component=ingestion,period=1hour`

### 3. Database Performance Metrics

Metrics related to database connectivity and performance.

#### `db_connection_time_ms`
- **Description:** Time taken to establish database connection
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_database_connection_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 10-100ms
- **Alert Threshold:** > 1000ms (slow connection)
- **Metadata:** `component=ingestion`

#### `db_query_time_ms`
- **Description:** Time taken to execute a test query (COUNT on notes table)
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_database_query_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 50-500ms (depends on table size)
- **Alert Threshold:** > 1000ms (configurable via `PERFORMANCE_SLOW_QUERY_THRESHOLD`)
- **Metadata:** `component=ingestion,query=count_notes`

### 4. Performance Check Metrics

Metrics from performance analysis scripts.

#### `performance_check_status`
- **Description:** Status of performance check execution (1=success, 0=failure)
- **Type:** Gauge
- **Unit:** `boolean` (0 or 1)
- **Collection:** Collected during `check_ingestion_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 1 (success)
- **Alert Threshold:** 0 (failure)
- **Metadata:** `component=ingestion,check=analyzeDatabasePerformance`

#### `performance_check_duration`
- **Description:** Duration of performance check execution
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_ingestion_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 5-60 seconds
- **Alert Threshold:** > 300 seconds (5 minutes)
- **Metadata:** `component=ingestion,check=analyzeDatabasePerformance`

#### `performance_check_passes`
- **Description:** Number of passed checks in performance analysis
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_ingestion_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies with check suite
- **Metadata:** `component=ingestion`

#### `performance_check_failures`
- **Description:** Number of failed checks in performance analysis
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_ingestion_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0
- **Alert Threshold:** > 0
- **Metadata:** `component=ingestion`

#### `performance_check_warnings`
- **Description:** Number of warnings in performance analysis
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_ingestion_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-5
- **Alert Threshold:** > 10
- **Metadata:** `component=ingestion`

### 5. Data Quality Metrics

Metrics related to data quality and integrity.

#### `data_quality_check_status`
- **Description:** Status of data quality check execution (1=success, 0=failure)
- **Type:** Gauge
- **Unit:** `boolean` (0 or 1)
- **Collection:** Collected during `check_ingestion_data_quality()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 1 (success)
- **Alert Threshold:** 0 (failure)
- **Metadata:** `component=ingestion,check=notesCheckVerifier`

#### `data_quality_check_duration`
- **Description:** Duration of data quality check execution
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during `check_ingestion_data_quality()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 10-120 seconds
- **Alert Threshold:** > 600 seconds (10 minutes)
- **Metadata:** `component=ingestion,check=notesCheckVerifier`

#### `data_quality_score`
- **Description:** Overall data quality score (0-100)
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Calculated during `check_ingestion_data_quality()`
- **Frequency:** Every monitoring cycle
- **Calculation:** Starts at 100, decreases based on issues found
- **Expected Range:** 95-100%
- **Alert Threshold:** < 95% (configurable via `INGESTION_DATA_QUALITY_THRESHOLD`)
- **Metadata:** `component=ingestion`

### 6. Planet Notes Check Metrics

Metrics from Planet Notes processing checks.

#### `planet_check_status`
- **Description:** Status of Planet Notes check execution (1=success, 0=failure)
- **Type:** Gauge
- **Unit:** `boolean` (0 or 1)
- **Collection:** Collected during Planet Notes check
- **Frequency:** Every monitoring cycle (if enabled)
- **Expected Range:** 1 (success)
- **Alert Threshold:** 0 (failure)
- **Metadata:** `component=ingestion,check=processCheckPlanetNotes`

#### `planet_check_duration`
- **Description:** Duration of Planet Notes check execution
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Collected during Planet Notes check
- **Frequency:** Every monitoring cycle (if enabled)
- **Expected Range:** 30-300 seconds
- **Alert Threshold:** > 600 seconds (10 minutes)
- **Metadata:** `component=ingestion,check=processCheckPlanetNotes`

### 7. Disk Space Metrics

Metrics related to disk usage.

#### `disk_usage_percent`
- **Description:** Disk usage percentage for a specific directory
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Collected during `check_disk_space()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-80%
- **Alert Threshold:** > 90% (configurable via `INFRASTRUCTURE_DISK_THRESHOLD`)
- **Metadata:** `component=ingestion,directory={dir_name}`

**Note:** This metric is collected for multiple directories:
- Ingestion repository root
- Logs directory
- Monitoring logs directory
- Temporary files directory
- Root filesystem

### 8. Health Status Metrics

Metrics related to component health.

#### `health_status`
- **Description:** Component health status (1=healthy, 0=unhealthy)
- **Type:** Gauge
- **Unit:** `boolean` (0 or 1)
- **Collection:** Collected during `check_ingestion_health()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 1 (healthy)
- **Alert Threshold:** 0 (unhealthy)
- **Metadata:** `component=ingestion`

## Metrics Collection Implementation

### Current Implementation

Metrics are collected using the `record_metric()` function (which should map to `store_metric()` from `monitoringFunctions.sh`). The function signature is:

```bash
record_metric component metric_name metric_value metadata
```

**Example:**
```bash
record_metric "INGESTION" "error_rate_percent" "${error_rate}" "component=ingestion"
```

### Storage Format

All metrics are stored in the `metrics` table with the following structure:

```sql
INSERT INTO metrics (component, metric_name, metric_value, metric_unit, metadata)
VALUES ('ingestion', 'error_rate_percent', 2.5, 'percent', '{"component":"ingestion"}'::jsonb);
```

### Metadata Format

Metadata is stored as JSONB and should include:
- `component`: Always "ingestion"
- `check`: Name of the check function (if applicable)
- `directory`: Directory name (for disk metrics)
- `period`: Time period (for aggregated metrics)
- `query`: Query name (for database metrics)

## Metrics Collection Schedule

### High-Frequency Metrics (Every Cycle)
- Script execution metrics
- Error and logging metrics
- Database performance metrics
- Health status metrics

### Medium-Frequency Metrics (Every Cycle)
- Performance check metrics
- Data quality metrics
- Disk space metrics

### Low-Frequency Metrics (On-Demand)
- Planet Notes check metrics (when script is executed)

## Metric Aggregation

Metrics can be aggregated using the `aggregate_metrics()` function from `metricsFunctions.sh`:

```bash
# Aggregate by hour
aggregate_metrics "ingestion" "error_rate_percent" "hour"

# Aggregate by day
aggregate_metrics "ingestion" "error_rate_percent" "day"
```

## Querying Metrics

### Get Latest Metric Value

```bash
get_latest_metric_value "ingestion" "error_rate_percent" 24
```

### Get Metrics Summary

```bash
get_metrics_summary "ingestion" 24
```

### SQL Queries

```sql
-- Get latest error rate
SELECT metric_value 
FROM metrics 
WHERE component = 'ingestion' 
  AND metric_name = 'error_rate_percent'
ORDER BY timestamp DESC 
LIMIT 1;

-- Get average error rate in last 24 hours
SELECT AVG(metric_value) as avg_error_rate
FROM metrics 
WHERE component = 'ingestion' 
  AND metric_name = 'error_rate_percent'
  AND timestamp > NOW() - INTERVAL '24 hours';

-- Get metrics by category
SELECT metric_name, AVG(metric_value) as avg_value, COUNT(*) as samples
FROM metrics 
WHERE component = 'ingestion'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY metric_name
ORDER BY metric_name;
```

## Missing Metrics (To Be Implemented)

The following metrics are referenced in the code but functions are not yet implemented:

### Processing Latency Metrics

#### `processing_latency_seconds`
- **Description:** Time between data arrival and processing completion
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Should be collected during `check_processing_latency()`
- **Expected Range:** 0-300 seconds
- **Alert Threshold:** > 300 seconds (configurable via `INGESTION_LATENCY_THRESHOLD`)

#### `processing_frequency_hours`
- **Description:** Frequency of processing cycles
- **Type:** Gauge
- **Unit:** `hours`
- **Collection:** Should be collected during `check_processing_frequency()`
- **Expected Range:** 1-24 hours
- **Alert Threshold:** > 24 hours

### API Download Metrics

#### `api_download_status`
- **Description:** Status of last API download (1=success, 0=failure)
- **Type:** Gauge
- **Unit:** `boolean` (0 or 1)
- **Collection:** Should be collected during `check_api_download_status()`
- **Expected Range:** 1 (success)
- **Alert Threshold:** 0 (failure)

#### `api_download_success_rate_percent`
- **Description:** Success rate of API downloads over time period
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Should be collected during `check_api_download_success_rate()`
- **Expected Range:** 95-100%
- **Alert Threshold:** < 95%

#### `api_download_duration_seconds`
- **Description:** Duration of API download operations
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Should be collected during API download checks
- **Expected Range:** 10-300 seconds
- **Alert Threshold:** > 600 seconds

#### `api_download_size_bytes`
- **Description:** Size of downloaded data
- **Type:** Gauge
- **Unit:** `bytes`
- **Collection:** Should be collected during API download checks
- **Expected Range:** Varies
- **Alert Threshold:** Unexpected size changes

### Data Processing Metrics

#### `records_processed_count`
- **Description:** Number of records processed in last cycle
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Should be collected during processing checks
- **Expected Range:** Varies with data volume
- **Alert Threshold:** 0 (no records processed)

#### `processing_duration_seconds`
- **Description:** Duration of processing cycle
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Should be collected during processing checks
- **Expected Range:** 30-600 seconds
- **Alert Threshold:** > 1800 seconds (30 minutes)

#### `data_freshness_seconds`
- **Description:** Age of most recent data update
- **Type:** Gauge
- **Unit:** `seconds`
- **Collection:** Should be collected during `check_data_freshness()`
- **Expected Range:** 0-3600 seconds (1 hour)
- **Alert Threshold:** > 3600 seconds

## Metric Retention

- **Default Retention:** 90 days (configurable via `METRICS_RETENTION_DAYS`)
- **Cleanup Schedule:** Daily at 2 AM (configurable via `METRICS_CLEANUP_SCHEDULE`)
- **Cleanup Function:** `cleanup_old_metrics(retention_days)`

## Best Practices

1. **Consistent Naming:** Always use the defined metric names
2. **Metadata:** Include relevant metadata for filtering and grouping
3. **Units:** Always specify correct units
4. **Frequency:** Collect metrics at appropriate intervals
5. **Alerting:** Set thresholds based on expected ranges
6. **Documentation:** Update this document when adding new metrics

## References

- [Monitoring Architecture Proposal](Monitoring_Architecture_Proposal.md)
- [Database Schema](DATABASE_SCHEMA.md)
- [Configuration Reference](CONFIGURATION_REFERENCE.md)
- [Implementation Plan](IMPLEMENTATION_PLAN.md)

---

**Last Updated:** 2025-12-25  
**Version:** 1.0.0  
**Status:** Active

