---
title: "Performance Analysis Integration Guide"
description: "The `analyzeDatabasePerformance.sh` script is very resource-intensive and should run"
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


# Performance Analysis Integration Guide

> **Purpose:** Guide for integrating monthly performance analysis execution with metrics storage  
> **Version:** 1.0.0  
> **Date:** 2026-01-09  
> **Status:** Active

## Overview

The `analyzeDatabasePerformance.sh` script is very resource-intensive and should run **monthly**
from the ingestion project's cron, not from the monitoring repository. This guide explains how to
set up the integration to store performance metrics in the monitoring database for trend tracking.

## Why Store Metrics in Database?

Storing performance analysis results in the database provides:

1. **Trend Tracking**: Monitor performance degradation over time
2. **Historical Analysis**: Compare current performance with past months
3. **Alerting**: Set up alerts based on performance trends
4. **Visualization**: Create Grafana dashboards showing performance metrics over time
5. **Capacity Planning**: Identify when performance issues are developing

## Architecture

```
┌─────────────────────────────────┐
│  Ingestion Project Cron         │
│  (Monthly: 1st day, 4 AM)      │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  run_and_store_performance_     │
│  analysis.sh                    │
│  (Wrapper script)               │
└──────────────┬──────────────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
┌─────────────┐  ┌──────────────┐
│  analyzeDB  │  │  Monitoring │
│  Performance│  │  Database    │
│  .sh        │  │  (metrics)   │
└─────────────┘  └──────────────┘
```

## Setup Instructions

### 1. Prerequisites

- OSM-Notes-Monitoring repository installed and configured
- OSM-Notes-Ingestion repository accessible
- Monitoring database accessible from ingestion server
- Database credentials configured (via `etc/properties.sh` or environment variables)

### 2. Configure Database Connection

Ensure the monitoring database connection is configured in `etc/properties.sh`:

```bash
# Monitoring database (where metrics are stored)
DBNAME=osm_notes_monitoring
DBHOST=localhost
DBPORT=5432
DBUSER=monitoring_user

# Ingestion database (what we're analyzing)
INGESTION_DBNAME=notes
INGESTION_DBHOST=localhost
INGESTION_DBPORT=5432
INGESTION_DBUSER=ingestion_user
```

Or set via environment variables:

```bash
export DBNAME=osm_notes_monitoring
export DBHOST=localhost
export DBUSER=monitoring_user
export PGPASSWORD=your_password
```

### 3. Set Up Cron Job

You have two options:

#### Option A: Integrate with Existing Cron Entry (Recommended)

If you already have a cron entry that runs `analyzeDatabasePerformance.sh`, integrate the metrics
storage by adding `&&`:

```bash
# Edit crontab
crontab -e

# Integrate with existing cron entry (first day of month at 3 AM)
0 3 1 * * /home/notes/OSM-Notes-Ingestion/bin/monitor/analyzeDatabasePerformance.sh --db notes > /home/notes/logs/db_performance_monthly_$(date +\%Y\%m\%d).log 2>&1 && \
    /path/to/OSM-Notes-Monitoring/scripts/run_and_store_performance_analysis.sh \
        --input-file /home/notes/logs/db_performance_monthly_$(date +\%Y\%m\%d).log \
        --monitoring-db osm_notes_monitoring \
        >> /path/to/logs/performance_analysis_cron.log 2>&1
```

**Note:** The `&&` ensures that the metrics storage script only runs if
`analyzeDatabasePerformance.sh` completes successfully.

#### Option B: Standalone Cron Entry

If you don't have an existing cron entry, create a new one:

```bash
# Edit crontab
crontab -e

# Add monthly job (first day of month at 4 AM)
0 4 1 * * /path/to/OSM-Notes-Monitoring/scripts/run_and_store_performance_analysis.sh \
    --ingestion-repo /path/to/OSM-Notes-Ingestion \
    --monitoring-db osm_notes_monitoring \
    --ingestion-db notes \
    >> /path/to/logs/performance_analysis_cron.log 2>&1
```

### 4. Test Execution

Test the script manually before adding to cron:

```bash
# Test with verbose output
/path/to/OSM-Notes-Monitoring/scripts/run_and_store_performance_analysis.sh \
    --ingestion-repo /path/to/OSM-Notes-Ingestion \
    --verbose

# Check metrics were stored
psql -d osm_notes_monitoring -c "
SELECT metric_name, metric_value, timestamp
FROM metrics
WHERE component = 'ingestion'
  AND metric_name LIKE 'performance_check%'
ORDER BY timestamp DESC
LIMIT 10;
"
```

## Script Usage

### Basic Usage

**Option 1: Execute script and store metrics**

```bash
run_and_store_performance_analysis.sh --ingestion-repo /path/to/OSM-Notes-Ingestion
```

**Option 2: Parse existing output file (for cron integration)**

```bash
run_and_store_performance_analysis.sh --input-file /path/to/db_performance_monthly_20260101.log
```

### Full Options

**Execute script:**

```bash
run_and_store_performance_analysis.sh \
    --ingestion-repo /path/to/OSM-Notes-Ingestion \
    --monitoring-db osm_notes_monitoring \
    --ingestion-db notes \
    --output-dir /path/to/logs/performance_output \
    --verbose
```

**Parse existing file:**

```bash
run_and_store_performance_analysis.sh \
    --input-file /path/to/db_performance_monthly_20260101.log \
    --monitoring-db osm_notes_monitoring \
    --verbose
```

### Options

- `--ingestion-repo PATH`: Path to OSM-Notes-Ingestion repository (required if `--input-file` not
  used)
- `--input-file FILE`: Parse existing output file instead of running script (for cron integration)
- `--monitoring-db DBNAME`: Monitoring database name (default: from `etc/properties.sh`)
- `--ingestion-db DBNAME`: Ingestion database name (default: `notes`)
- `--output-dir DIR`: Directory to save output files (default: `logs/performance_output`)
- `--verbose`: Enable verbose output
- `-h, --help`: Show help message

## Stored Metrics

The script stores the following metrics in the monitoring database:

### Basic Metrics

- `performance_check_status`: Execution status (1=success, 0=failure)
- `performance_check_duration`: Execution duration in seconds
- `performance_check_passes`: Number of passed checks
- `performance_check_failures`: Number of failed checks
- `performance_check_warnings`: Number of warnings

### Detailed Metrics (if available)

- `performance_check_index_checks`: Number of index-related checks
- `performance_check_query_checks`: Number of query-related checks
- `performance_check_table_checks`: Number of table-related checks

All metrics include metadata:

- `component=ingestion`
- `check=analyzeDatabasePerformance`
- `source=monthly_cron`

## Querying Metrics

### Latest Performance Check Status

```sql
SELECT
    metric_name,
    metric_value,
    timestamp
FROM metrics
WHERE component = 'ingestion'
  AND metric_name LIKE 'performance_check%'
  AND metadata->>'source' = 'monthly_cron'
ORDER BY timestamp DESC
LIMIT 10;
```

### Performance Trend Over Time

```sql
SELECT
    DATE_TRUNC('month', timestamp) AS month,
    AVG(CASE WHEN metric_name = 'performance_check_passes' THEN metric_value END) AS avg_passes,
    AVG(CASE WHEN metric_name = 'performance_check_failures' THEN metric_value END) AS avg_failures,
    AVG(CASE WHEN metric_name = 'performance_check_warnings' THEN metric_value END) AS avg_warnings,
    AVG(CASE WHEN metric_name = 'performance_check_duration' THEN metric_value END) AS avg_duration_seconds
FROM metrics
WHERE component = 'ingestion'
  AND metric_name IN ('performance_check_passes', 'performance_check_failures',
                      'performance_check_warnings', 'performance_check_duration')
  AND metadata->>'source' = 'monthly_cron'
GROUP BY DATE_TRUNC('month', timestamp)
ORDER BY month DESC;
```

### Performance Degradation Detection

```sql
-- Compare current month with previous month
WITH monthly_stats AS (
    SELECT
        DATE_TRUNC('month', timestamp) AS month,
        AVG(CASE WHEN metric_name = 'performance_check_failures' THEN metric_value END) AS failures,
        AVG(CASE WHEN metric_name = 'performance_check_warnings' THEN metric_value END) AS warnings
    FROM metrics
    WHERE component = 'ingestion'
      AND metric_name IN ('performance_check_failures', 'performance_check_warnings')
      AND metadata->>'source' = 'monthly_cron'
    GROUP BY DATE_TRUNC('month', timestamp)
)
SELECT
    current.month,
    current.failures AS current_failures,
    previous.failures AS previous_failures,
    current.failures - previous.failures AS failure_delta,
    current.warnings AS current_warnings,
    previous.warnings AS previous_warnings,
    current.warnings - previous.warnings AS warning_delta
FROM monthly_stats current
LEFT JOIN monthly_stats previous
    ON previous.month = current.month - INTERVAL '1 month'
ORDER BY current.month DESC
LIMIT 12;
```

## Grafana Dashboard

Create a Grafana dashboard to visualize performance trends:

1. **Panel 1: Performance Check Status Over Time**
   - Query: `performance_check_status` over last 12 months
   - Visualization: Time series showing 1 (success) or 0 (failure)

2. **Panel 2: Pass/Fail/Warning Counts**
   - Query: `performance_check_passes`, `performance_check_failures`, `performance_check_warnings`
   - Visualization: Stacked bar chart by month

3. **Panel 3: Execution Duration Trend**
   - Query: `performance_check_duration` over time
   - Visualization: Line chart showing duration trend

4. **Panel 4: Performance Degradation Alert**
   - Query: Compare current month failures with previous month
   - Visualization: Stat panel with alert if degradation detected

## Troubleshooting

### Script Fails to Connect to Database

**Error:** `Cannot connect to monitoring database`

**Solution:**

1. Check database credentials in `etc/properties.sh`
2. Verify database is accessible: `psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1;"`
3. Check firewall rules if database is remote
4. Verify `PGPASSWORD` environment variable is set if using password authentication

### Script Cannot Find analyzeDatabasePerformance.sh

**Error:** `analyzeDatabasePerformance.sh not found`

**Solution:**

1. Verify `--ingestion-repo` path is correct
2. Check that the ingestion repository has the script:
   `ls -la ${INGESTION_REPO_PATH}/bin/monitor/analyzeDatabasePerformance.sh`
3. Ensure script has execute permissions

### Metrics Not Stored

**Symptom:** Script runs successfully but no metrics appear in database

**Solution:**

1. Check script output for errors: `tail -f logs/performance_analysis.log`
2. Verify database connection is working: Test `record_metric` function
3. Check database permissions: User must have INSERT permission on `metrics` table
4. Review logs for parsing errors

### Script Times Out

**Error:** `Script execution timed out`

**Solution:**

1. Increase timeout: Set `PERFORMANCE_ANALYSIS_TIMEOUT` environment variable (default: 3600 seconds)
2. Check if database is under heavy load
3. Consider running during off-peak hours
4. Review `analyzeDatabasePerformance.sh` performance

## Best Practices

1. **Schedule During Off-Peak Hours**: Run at 4 AM on the first day of the month
2. **Monitor Execution**: Set up alerts if the script fails
3. **Review Trends Monthly**: Check Grafana dashboard monthly for performance trends
4. **Keep Output Files**: Output files are kept for 12 months for reference
5. **Document Changes**: Note any schema changes that might affect performance metrics

## Related Documentation

- [Existing_Monitoring_Components.md](./Existing_Monitoring_Components.md): Details about
  `analyzeDatabasePerformance.sh`
- [INGESTION_METRICS.md](./Ingestion_Metrics.md): Complete list of ingestion metrics
- [INGESTION_ALERT_THRESHOLDS.md](./Ingestion_Alert_Thresholds.md): Alert thresholds for performance
  metrics
- [DATABASE_SCHEMA.md](./Database_Schema.md): Database schema for metrics table

## Support

For issues or questions:

1. Check script logs: `logs/performance_analysis.log`
2. Review cron logs if running from cron
3. Test script manually with `--verbose` flag
4. Verify database connectivity and permissions
