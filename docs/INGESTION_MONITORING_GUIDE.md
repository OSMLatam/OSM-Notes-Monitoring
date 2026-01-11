# Ingestion Monitoring Guide

> **Purpose:** Comprehensive guide for monitoring the OSM-Notes-Ingestion component  
> **Version:** 1.0.0  
> **Date:** 2025-12-26  
> **Status:** Active

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Running Monitoring](#running-monitoring)
6. [Understanding Metrics](#understanding-metrics)
7. [Alerting](#alerting)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Reference Documentation](#reference-documentation)

---

## Overview

The Ingestion Monitoring system provides comprehensive monitoring for the OSM-Notes-Ingestion component, tracking:

- **Script Execution Status**: Verifies that ingestion scripts are present, executable, and running
- **Error Rates**: Monitors error and warning rates from log files
- **Data Quality**: Checks data freshness, completeness, and integrity
- **Performance**: Tracks processing latency, database performance, and API download success rates
- **Infrastructure**: Monitors disk space usage and system health

### Key Features

- **Automated Monitoring**: Run checks on a schedule (e.g., via cron)
- **Metrics Collection**: All metrics are stored in PostgreSQL for historical analysis
- **Alerting**: Configurable alerts for critical issues
- **Dashboards**: View metrics in Grafana or custom dashboards
- **Low Overhead**: Designed to minimize impact on the monitored system

---

## Prerequisites

Before setting up ingestion monitoring, ensure you have:

1. **PostgreSQL Database**: A PostgreSQL database for storing metrics and alerts
   - Version 12 or higher recommended
   - Database created and accessible
   - User with appropriate permissions

2. **OSM-Notes-Ingestion Repository**: The ingestion repository must be accessible
   - Repository cloned locally
   - Scripts present in `bin/` directory
   - Log files accessible (typically in `logs/` directory)

3. **Bash Environment**: Bash 4.0 or higher
   - Standard Unix utilities (grep, awk, date, ps, etc.)
   - PostgreSQL client tools (`psql`)

4. **Configuration Files**: Monitoring configuration files set up
   - `etc/properties.sh` - Database connection settings
   - `config/monitoring.conf` - Monitoring thresholds and settings
   - `config/alerts.conf` - Alert configuration

---

## Quick Start

### 1. Configure Database Connection

Edit `etc/properties.sh`:

```bash
DBNAME="osm_notes_monitoring"
DBHOST="localhost"
DBPORT="5432"
DBUSER="postgres"
```

Set database password via environment variable:

```bash
export PGPASSWORD="your_password"
```

### 2. Configure Ingestion Repository Path

Edit `config/monitoring.conf`:

```bash
INGESTION_ENABLED="true"
INGESTION_REPO_PATH="/path/to/OSM-Notes-Ingestion"
INGESTION_LOG_DIR="/path/to/OSM-Notes-Ingestion/logs"
```

### 3. Run Monitoring Checks

Execute the monitoring script:

```bash
./bin/monitor/monitorIngestion.sh
```

Or run specific checks:

```bash
# Check script execution status
./bin/monitor/monitorIngestion.sh --check execution-status

# Check error rates
./bin/monitor/monitorIngestion.sh --check error-rate

# Check all metrics
./bin/monitor/monitorIngestion.sh --check all
```

### 4. Verify Metrics Are Stored

Query the database to verify metrics:

```sql
SELECT * FROM metrics 
WHERE component = 'ingestion' 
ORDER BY timestamp DESC 
LIMIT 10;
```

---

## Configuration

### Monitoring Configuration (`config/monitoring.conf`)

Key configuration options for ingestion monitoring:

#### Repository Settings

```bash
# Enable/disable ingestion monitoring
INGESTION_ENABLED="true"

# Path to OSM-Notes-Ingestion repository
INGESTION_REPO_PATH="/path/to/OSM-Notes-Ingestion"

# Path to ingestion log directory
INGESTION_LOG_DIR="/path/to/OSM-Notes-Ingestion/logs"
```

#### Alert Thresholds

```bash
# Script execution thresholds
INGESTION_SCRIPTS_FOUND_THRESHOLD=7
INGESTION_LAST_LOG_AGE_THRESHOLD=24

# Error rate thresholds
INGESTION_MAX_ERROR_RATE=5
INGESTION_ERROR_COUNT_THRESHOLD=1000
INGESTION_WARNING_COUNT_THRESHOLD=2000
INGESTION_WARNING_RATE_THRESHOLD=15

# Data quality thresholds
INGESTION_DATA_FRESHNESS_THRESHOLD=3600
INGESTION_LATENCY_THRESHOLD=300
INGESTION_DATA_QUALITY_THRESHOLD=95

# API download thresholds
INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD=95

# Infrastructure thresholds
INFRASTRUCTURE_DISK_THRESHOLD=90
```

For complete threshold documentation, see [INGESTION_ALERT_THRESHOLDS.md](./INGESTION_ALERT_THRESHOLDS.md).

### Alert Configuration (`config/alerts.conf`)

Configure alert delivery:

```bash
# Email alerts
SEND_ALERT_EMAIL="true"
ADMIN_EMAIL="admin@example.com"

# Slack alerts (optional)
SLACK_ENABLED="true"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."

# Alert deduplication
ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW=3600
```

For complete alert configuration, see [CONFIGURATION_REFERENCE.md](./CONFIGURATION_REFERENCE.md).

---

## Running Monitoring

### Manual Execution

Run all monitoring checks:

```bash
./bin/monitor/monitorIngestion.sh
```

Run specific checks:

```bash
# Health checks
./bin/monitor/monitorIngestion.sh --check health

# Performance checks
./bin/monitor/monitorIngestion.sh --check performance

# Data quality checks
./bin/monitor/monitorIngestion.sh --check data-quality

# Specific checks
./bin/monitor/monitorIngestion.sh --check execution-status
./bin/monitor/monitorIngestion.sh --check error-rate
./bin/monitor/monitorIngestion.sh --check disk-space
./bin/monitor/monitorIngestion.sh --check api-download
```

### Dry Run Mode

Test monitoring without writing to database:

```bash
./bin/monitor/monitorIngestion.sh --dry-run
```

### Verbose Output

Enable verbose logging:

```bash
./bin/monitor/monitorIngestion.sh --verbose
```

### Automated Execution (Cron)

Set up cron job to run monitoring checks periodically:

```bash
# Run every 15 minutes
*/15 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorIngestion.sh

# Run every hour
0 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorIngestion.sh

# Run daily at 2 AM
0 2 * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorIngestion.sh
```

**Recommended Frequency**: Run every 15-30 minutes for active monitoring, or hourly for less critical systems.

---

## Understanding Metrics

### Metric Categories

#### 1. Script Execution Metrics

**`scripts_found`**
- **Description**: Number of ingestion scripts found in repository
- **Expected Range**: 7 scripts
- **Expected Scripts**:
  1. `process/processAPINotes.sh` - Processes API notes
  2. `process/processAPINotesDaemon.sh` - Daemon wrapper for API notes processing
  3. `process/processPlanetNotes.sh` - Processes planet notes
  4. `process/updateCountries.sh` - Updates country boundary data
  5. `monitor/notesCheckVerifier.sh` - Verifies notes data quality
  6. `monitor/processCheckPlanetNotes.sh` - Checks planet notes processing
  7. `monitor/analyzeDatabasePerformance.sh` - Analyzes database performance (ingestion-specific)
- **Alert**: Triggered if ≠ 7 scripts found (must be exactly 7)
- **Interpretation**: 
  - Normal: 7 scripts found
  - Warning: < 7 scripts (scripts may be missing or repository path incorrect)

**`scripts_executable`**
- **Description**: Number of scripts with execute permissions
- **Expected Range**: Must equal 7 (all scripts must be executable)
- **Alert**: Triggered if ≠ 7 scripts executable (must be exactly 7)
- **Interpretation**: All 7 scripts must be executable. If less than 7, some scripts are missing execute permissions.

**`scripts_running`**
- **Description**: Number of scripts currently running
- **Expected Range**: 0-7 (depends on scheduled execution)
- **Interpretation**: 
  - 0: No scripts running (normal if not scheduled)
  - 1-7: Scripts actively processing (normal during execution)

**`last_log_age_hours`**
- **Description**: Age of most recent log file
- **Expected Range**: < 24 hours
- **Alert**: Triggered if > 24 hours
- **Interpretation**: Indicates when ingestion scripts last ran

#### 2. Error and Warning Metrics

**`error_count`**
- **Description**: Total number of errors in last 24 hours
- **Expected Range**: < 1000 errors
- **Alert**: Triggered if > 1000 errors
- **Interpretation**: High error count indicates systemic issues

**`error_rate_percent`**
- **Description**: Percentage of log entries that are errors
- **Expected Range**: < 5%
- **Alert**: Triggered if > 5%
- **Interpretation**: High error rate indicates processing problems

**`warning_count`**
- **Description**: Total number of warnings in last 24 hours
- **Expected Range**: < 2000 warnings
- **Alert**: Triggered if > 2000 warnings
- **Interpretation**: High warning count may indicate issues

**`warning_rate_percent`**
- **Description**: Percentage of log entries that are warnings
- **Expected Range**: < 15%
- **Alert**: Triggered if > 15%
- **Interpretation**: High warning rate may indicate configuration issues

#### 3. Data Quality Metrics

**`data_freshness_seconds`**
- **Description**: Time since last data update
- **Expected Range**: < 3600 seconds (1 hour)
- **Alert**: Triggered if > 3600 seconds
- **Interpretation**: Indicates data staleness

**`data_quality_score`**
- **Description**: Data quality score (0-100)
- **Expected Range**: > 95%
- **Alert**: Triggered if < 95%
- **Interpretation**: Lower scores indicate data quality issues

#### 4. Performance Metrics

**`processing_latency_seconds`**
- **Description**: Time to process updates
- **Expected Range**: < 300 seconds (5 minutes)
- **Alert**: Triggered if > 300 seconds
- **Interpretation**: High latency indicates performance issues

**`api_download_success_rate_percent`**
- **Description**: Success rate of API downloads
- **Expected Range**: > 95%
- **Alert**: Triggered if < 95%
- **Interpretation**: Low success rate indicates API connectivity issues

#### 5. Infrastructure Metrics

**`disk_usage_percent`**
- **Description**: Disk space usage percentage
- **Expected Range**: < 90%
- **Alert**: Triggered if >= 90%
- **Interpretation**: High disk usage may cause processing failures

### Querying Metrics

View recent metrics:

```sql
-- Latest metrics for ingestion component
SELECT metric_name, metric_value, unit, timestamp
FROM metrics
WHERE component = 'ingestion'
ORDER BY timestamp DESC
LIMIT 20;
```

View specific metric over time:

```sql
-- Error rate over last 24 hours
SELECT timestamp, metric_value
FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'error_rate_percent'
  AND timestamp > NOW() - INTERVAL '24 hours'
ORDER BY timestamp;
```

Calculate averages:

```sql
-- Average error rate over last 7 days
SELECT AVG(metric_value::numeric) as avg_error_rate
FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'error_rate_percent'
  AND timestamp > NOW() - INTERVAL '7 days';
```

For complete metric definitions, see [INGESTION_METRICS.md](./INGESTION_METRICS.md).

---

## Alerting

### Alert Levels

- **CRITICAL**: Immediate response required (within 15 minutes)
- **WARNING**: Response within 1 hour
- **INFO**: Review within 24 hours

### Common Alerts

#### Low Number of Scripts Found

**Alert**: `Low number of scripts found: X (threshold: Y)`

**Severity**: WARNING

**What to do**:
1. Check `INGESTION_REPO_PATH` configuration
2. Verify repository exists: `ls -la ${INGESTION_REPO_PATH}/bin`
3. Check if scripts are in expected location
4. Restore missing scripts from version control

#### High Error Rate

**Alert**: `High error rate: X% (threshold: Y%)`

**Severity**: WARNING

**What to do**:
1. Review error logs: `tail -f ${INGESTION_LOG_DIR}/ingestion.log`
2. Check for common error patterns
3. Verify system resources (disk space, memory)
4. Check database connectivity

#### Stale Data

**Alert**: `Data freshness exceeds threshold: X seconds (threshold: Y seconds)`

**Severity**: WARNING

**What to do**:
1. Check if ingestion scripts are running
2. Verify cron jobs are scheduled correctly
3. Check for script execution failures
4. Review processing logs

#### High Disk Usage

**Alert**: `High disk usage: X% (threshold: Y%)`

**Severity**: WARNING

**What to do**:
1. Identify large files: `du -sh ${INGESTION_REPO_PATH}/*`
2. Clean up old log files
3. Archive old data files
4. Consider expanding disk space

For complete alert documentation, see [INGESTION_ALERT_RUNBOOK.md](./INGESTION_ALERT_RUNBOOK.md).

### Viewing Alerts

Query active alerts:

```sql
-- Active alerts (last 24 hours)
SELECT alert_level, component, message, timestamp
FROM alerts
WHERE component = 'INGESTION'
  AND timestamp > NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC;
```

View alert history:

```sql
-- Alert history
SELECT alert_level, COUNT(*) as count
FROM alerts
WHERE component = 'INGESTION'
GROUP BY alert_level
ORDER BY count DESC;
```

---

## Troubleshooting

### Monitoring Script Not Running

**Symptoms**: No metrics being collected, no logs generated

**Solutions**:
1. Check script permissions: `chmod +x bin/monitor/monitorIngestion.sh`
2. Verify database connection: `psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1;"`
3. Check configuration files exist and are readable
4. Review monitoring logs: `tail -f ${LOG_DIR}/monitoring.log`

### Database Connection Errors

**Symptoms**: Errors like "could not connect to database" or "authentication failed"

**Solutions**:
1. Verify database is running: `pg_isready -h ${DBHOST} -p ${DBPORT}`
2. Check credentials in `etc/properties.sh`
3. Verify `PGPASSWORD` environment variable is set
4. Check `.pgpass` file permissions: `chmod 600 ~/.pgpass`
5. Verify database user has required permissions

### Metrics Not Being Stored

**Symptoms**: Script runs successfully but no metrics in database

**Solutions**:
1. Verify database connection works: Run `check_database_connection`
2. Check database schema: `\d metrics` in psql
3. Verify user has INSERT permissions on `metrics` table
4. Check monitoring logs for errors
5. Run with `--verbose` flag to see detailed output

### High Monitoring Overhead

**Symptoms**: Monitoring checks take too long or consume too many resources

**Solutions**:
1. Reduce monitoring frequency (run less often)
2. Disable non-critical checks
3. Optimize database queries (add indexes)
4. Review performance test results: `tests/performance/test_monitoring_overhead.sh`

### False Positive Alerts

**Symptoms**: Alerts triggered but system is actually healthy

**Solutions**:
1. Review alert thresholds in `config/monitoring.conf`
2. Adjust thresholds based on your system's normal behavior
3. Check if metrics are being collected correctly
4. Review alert conditions in monitoring script

### Script Execution Status Checks Fail

**Symptoms**: Scripts exist but are not detected

**Solutions**:
1. Verify `INGESTION_REPO_PATH` is correct
2. Check script locations match expected paths
3. Verify scripts have execute permissions: `chmod +x bin/*.sh`
4. Check for path issues (symlinks, mount points)

---

## Best Practices

### 1. Monitoring Frequency

- **Active Systems**: Run every 15-30 minutes
- **Less Critical Systems**: Run hourly
- **Development/Testing**: Run on-demand or daily

### 2. Threshold Tuning

- Start with default thresholds
- Monitor for 1-2 weeks to understand normal behavior
- Adjust thresholds based on your system's patterns
- Document threshold changes and reasons

### 3. Alert Management

- Use alert deduplication to avoid alert fatigue
- Set up alert escalation for critical issues
- Review and acknowledge alerts promptly
- Document alert responses for future reference

### 4. Database Maintenance

- Regularly clean old metrics (older than 90 days)
- Monitor database size and growth
- Create indexes on frequently queried columns
- Set up database backups

### 5. Log Management

- Rotate monitoring logs regularly
- Archive old logs for historical analysis
- Monitor log file sizes
- Use log aggregation tools if available

### 6. Performance Monitoring

- Run performance tests periodically
- Monitor monitoring system overhead
- Optimize slow queries
- Review and update monitoring scripts as needed

---

## Reference Documentation

### Core Documentation

- **[INGESTION_METRICS.md](./INGESTION_METRICS.md)**: Complete metric definitions
- **[INGESTION_ALERT_THRESHOLDS.md](./INGESTION_ALERT_THRESHOLDS.md)**: All alert thresholds
- **[INGESTION_ALERT_RUNBOOK.md](./INGESTION_ALERT_RUNBOOK.md)**: Detailed alert response procedures
- **[CONFIGURATION_REFERENCE.md](./CONFIGURATION_REFERENCE.md)**: Complete configuration reference

### Related Documentation

- **[Monitoring_SETUP_Guide.md](./Monitoring_SETUP_Guide.md)**: Initial setup guide
- **[DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)**: Database schema documentation
- **[Monitoring_Architecture_Proposal.md](./Monitoring_Architecture_Proposal.md)**: System architecture overview

### Scripts

- **`bin/monitor/monitorIngestion.sh`**: Main monitoring script
- **`bin/lib/monitoringFunctions.sh`**: Core monitoring functions
- **`bin/lib/metricsFunctions.sh`**: Metrics collection functions
- **`bin/lib/alertFunctions.sh`**: Alerting functions

### Testing

- **`tests/unit/monitor/test_monitorIngestion.sh`**: Unit tests
- **`tests/integration/test_monitorIngestion_integration.sh`**: Integration tests
- **`tests/e2e/test_monitoring_workflow.sh`**: End-to-end tests
- **`tests/performance/test_monitoring_overhead.sh`**: Performance tests

---

## Getting Help

If you encounter issues or have questions:

1. **Check Documentation**: Review this guide and related documentation
2. **Review Logs**: Check monitoring logs for error messages
3. **Run Tests**: Execute test suites to verify functionality
4. **Check Issues**: Review GitHub issues for known problems
5. **Create Issue**: Open a new issue with detailed information

---

**Last Updated**: 2025-12-26  
**Version**: 1.0.0

