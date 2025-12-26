# Ingestion Alert Thresholds

> **Purpose:** Comprehensive documentation of all alert thresholds for ingestion monitoring  
> **Version:** 1.0.0  
> **Date:** 2025-12-25  
> **Status:** Active

## Overview

This document defines all alert thresholds for the OSM-Notes-Ingestion component. These thresholds are used to determine when alerts should be triggered based on metric values.

## Configuration

All thresholds are configurable via `config/monitoring.conf`. Default values are defined in `config/monitoring.conf.example`.

## Alert Thresholds by Category

### 1. Script Execution Thresholds

#### `INGESTION_SCRIPTS_FOUND_THRESHOLD`
- **Default:** `3`
- **Unit:** Count
- **Metric:** `scripts_found`
- **Alert Condition:** `< threshold`
- **Description:** Minimum number of ingestion scripts that should be found in the repository
- **Severity:** WARNING
- **Action:** Check repository structure and script availability

#### `INGESTION_LAST_LOG_AGE_THRESHOLD`
- **Default:** `24`
- **Unit:** Hours
- **Metric:** `last_log_age_hours`
- **Alert Condition:** `> threshold`
- **Description:** Maximum age of most recent log file before alerting
- **Severity:** WARNING
- **Action:** Check if ingestion scripts are running, verify cron jobs

### 2. Error and Logging Thresholds

#### `INGESTION_MAX_ERROR_RATE`
- **Default:** `5`
- **Unit:** Percentage
- **Metric:** `error_rate_percent`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable error rate percentage
- **Severity:** WARNING
- **Action:** Review error logs, check system health

#### `INGESTION_ERROR_COUNT_THRESHOLD`
- **Default:** `1000`
- **Unit:** Count (24 hours)
- **Metric:** `error_count`
- **Alert Condition:** `> threshold`
- **Description:** Maximum number of errors in 24 hours before alerting
- **Severity:** WARNING
- **Action:** Investigate error patterns, check for systemic issues

#### `INGESTION_WARNING_COUNT_THRESHOLD`
- **Default:** `2000`
- **Unit:** Count (24 hours)
- **Metric:** `warning_count`
- **Alert Condition:** `> threshold`
- **Description:** Maximum number of warnings in 24 hours before alerting
- **Severity:** INFO/WARNING
- **Action:** Review warnings, check for configuration issues

#### `INGESTION_WARNING_RATE_THRESHOLD`
- **Default:** `15`
- **Unit:** Percentage
- **Metric:** `warning_rate_percent`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable warning rate percentage
- **Severity:** WARNING
- **Action:** Review warning patterns, check configuration

#### `INGESTION_ERROR_SPIKE_MULTIPLIER`
- **Default:** `2`
- **Unit:** Multiplier
- **Metric:** `recent_error_rate_percent`
- **Alert Condition:** `> (INGESTION_MAX_ERROR_RATE * multiplier)`
- **Description:** Multiplier for detecting error spikes in recent period (last hour)
- **Severity:** WARNING
- **Action:** Investigate recent errors, check for incidents

### 3. Database Performance Thresholds

#### `INGESTION_DB_CONNECTION_TIME_THRESHOLD`
- **Default:** `1000`
- **Unit:** Milliseconds
- **Metric:** `db_connection_time_ms`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable database connection time
- **Severity:** WARNING
- **Action:** Check database server health, network connectivity, connection pool

#### `INGESTION_DB_QUERY_TIME_THRESHOLD`
- **Default:** `1000` (uses `PERFORMANCE_SLOW_QUERY_THRESHOLD`)
- **Unit:** Milliseconds
- **Metric:** `db_query_time_ms`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable query execution time
- **Severity:** WARNING
- **Action:** Optimize queries, check indexes, review database performance

### 4. Performance Check Thresholds

#### `INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD`
- **Default:** `300`
- **Unit:** Seconds (5 minutes)
- **Metric:** `performance_check_duration`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable duration for performance check execution
- **Severity:** WARNING
- **Action:** Review performance check script, check system resources

#### `INGESTION_PERFORMANCE_CHECK_WARNINGS_THRESHOLD`
- **Default:** `10`
- **Unit:** Count
- **Metric:** `performance_check_warnings`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable number of warnings in performance check
- **Severity:** WARNING
- **Action:** Review performance check warnings, investigate issues

**Note:** `performance_check_failures` threshold is `> 0` (any failure triggers alert)

### 5. Data Quality Thresholds

#### `INGESTION_DATA_QUALITY_THRESHOLD`
- **Default:** `95`
- **Unit:** Percentage
- **Metric:** `data_quality_score`
- **Alert Condition:** `< threshold`
- **Description:** Minimum acceptable data quality score
- **Severity:** WARNING
- **Action:** Review data quality issues, check data validation processes

#### `INGESTION_DATA_QUALITY_CHECK_DURATION_THRESHOLD`
- **Default:** `600`
- **Unit:** Seconds (10 minutes)
- **Metric:** `data_quality_check_duration`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable duration for data quality check
- **Severity:** WARNING
- **Action:** Optimize data quality check, review data volume

#### `INGESTION_DATA_FRESHNESS_THRESHOLD`
- **Default:** `3600`
- **Unit:** Seconds (1 hour)
- **Metric:** `data_freshness_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable age of most recent data update
- **Severity:** WARNING
- **Action:** Check processing pipeline, verify data ingestion is running

### 6. Processing Latency Thresholds

#### `INGESTION_LATENCY_THRESHOLD`
- **Default:** `300`
- **Unit:** Seconds (5 minutes)
- **Metric:** `processing_latency_seconds`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable processing latency (time between data arrival and processing)
- **Severity:** WARNING
- **Action:** Check processing queue, review processing performance

#### `INGESTION_PROCESSING_FREQUENCY_THRESHOLD`
- **Default:** `24`
- **Unit:** Hours
- **Metric:** `processing_frequency_hours`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable time between processing cycles
- **Severity:** WARNING
- **Action:** Check cron jobs, verify processing schedule

### 7. Planet Notes Check Thresholds

#### `INGESTION_PLANET_CHECK_DURATION_THRESHOLD`
- **Default:** `600`
- **Unit:** Seconds (10 minutes)
- **Metric:** `planet_check_duration`
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable duration for Planet Notes check
- **Severity:** WARNING
- **Action:** Review Planet Notes processing, check file sizes

**Note:** `planet_check_status` threshold is `= 0` (any failure triggers alert)

### 8. API Download Thresholds

#### `INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD`
- **Default:** `95`
- **Unit:** Percentage
- **Metric:** `api_download_success_rate_percent`
- **Alert Condition:** `< threshold`
- **Description:** Minimum acceptable API download success rate
- **Severity:** WARNING
- **Action:** Check API connectivity, review download logs, verify API availability

#### `INGESTION_API_DOWNLOAD_DURATION_THRESHOLD`
- **Default:** `600`
- **Unit:** Seconds (10 minutes)
- **Metric:** `api_download_duration_seconds` (to be implemented)
- **Alert Condition:** `> threshold`
- **Description:** Maximum acceptable duration for API download operations
- **Severity:** WARNING
- **Action:** Check network connectivity, review API response times

**Note:** `api_download_status` threshold is `= 0` (any failure triggers alert)

### 9. Disk Space Thresholds

#### `INFRASTRUCTURE_DISK_THRESHOLD`
- **Default:** `90`
- **Unit:** Percentage
- **Metric:** `disk_usage_percent`
- **Alert Condition:** `>= threshold`
- **Description:** Maximum acceptable disk usage percentage
- **Severity:** WARNING
- **Action:** Clean up old files, expand disk space, review log retention

**Note:** Warning is also triggered when usage is `>= (threshold - 10)` (approaching threshold)

### 10. Health Status Thresholds

#### Health Status
- **Threshold:** `= 0` (unhealthy)
- **Metric:** `health_status`
- **Alert Condition:** `= 0`
- **Description:** Component is unhealthy
- **Severity:** CRITICAL
- **Action:** Investigate component health, check all dependencies

## Threshold Configuration Example

```bash
# config/monitoring.conf

# Ingestion Monitoring
INGESTION_ENABLED=true
INGESTION_CHECK_TIMEOUT=300

# Script Execution Thresholds
INGESTION_SCRIPTS_FOUND_THRESHOLD=3
INGESTION_LAST_LOG_AGE_THRESHOLD=24

# Error and Logging Thresholds
INGESTION_MAX_ERROR_RATE=5
INGESTION_ERROR_COUNT_THRESHOLD=1000
INGESTION_WARNING_COUNT_THRESHOLD=2000
INGESTION_WARNING_RATE_THRESHOLD=15
INGESTION_ERROR_SPIKE_MULTIPLIER=2

# Database Performance Thresholds
INGESTION_DB_CONNECTION_TIME_THRESHOLD=1000
INGESTION_DB_QUERY_TIME_THRESHOLD=1000

# Performance Check Thresholds
INGESTION_PERFORMANCE_CHECK_DURATION_THRESHOLD=300
INGESTION_PERFORMANCE_CHECK_WARNINGS_THRESHOLD=10

# Data Quality Thresholds
INGESTION_DATA_QUALITY_THRESHOLD=95
INGESTION_DATA_QUALITY_CHECK_DURATION_THRESHOLD=600
INGESTION_DATA_FRESHNESS_THRESHOLD=3600

# Processing Latency Thresholds
INGESTION_LATENCY_THRESHOLD=300
INGESTION_PROCESSING_FREQUENCY_THRESHOLD=24

# Planet Notes Check Thresholds
INGESTION_PLANET_CHECK_DURATION_THRESHOLD=600

# API Download Thresholds
INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD=95
INGESTION_API_DOWNLOAD_DURATION_THRESHOLD=600
```

## Alert Severity Levels

### CRITICAL
- Component health is down
- System is non-functional
- Immediate action required

### WARNING
- Performance degradation
- Threshold exceeded
- Action may be required

### INFO
- Informational alerts
- Status changes
- No immediate action required

## Best Practices

1. **Start Conservative:** Begin with higher thresholds and adjust based on actual system behavior
2. **Monitor Trends:** Review metrics over time to set appropriate thresholds
3. **Avoid Alert Fatigue:** Set thresholds high enough to catch real issues, not noise
4. **Document Changes:** Update this document when thresholds are modified
5. **Test Thresholds:** Verify alerts trigger correctly when thresholds are exceeded
6. **Review Regularly:** Periodically review and adjust thresholds based on system evolution

## Threshold Tuning Guide

### When to Lower Thresholds
- System is stable and performing well
- Want to catch issues earlier
- Have capacity to handle more alerts

### When to Raise Thresholds
- Too many false positives
- System behavior has changed
- Alert fatigue is occurring

### How to Tune
1. Review historical metrics
2. Identify normal operating ranges
3. Set thresholds slightly outside normal range
4. Monitor alert frequency
5. Adjust based on feedback

## References

- [Ingestion Metrics Definition](INGESTION_METRICS.md)
- [Configuration Reference](CONFIGURATION_REFERENCE.md)
- [Monitoring Architecture](Monitoring_Architecture_Proposal.md)

---

**Last Updated:** 2025-12-25  
**Version:** 1.0.0  
**Status:** Active

