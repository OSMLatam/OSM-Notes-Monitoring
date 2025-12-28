# Analytics Monitoring Guide

> **Purpose:** Comprehensive guide for monitoring the OSM-Notes-Analytics component  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
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

The Analytics Monitoring system provides comprehensive monitoring for the OSM-Notes-Analytics component, tracking:

- **ETL Job Execution**: Verifies that ETL scripts are present, executable, and running correctly
- **Data Warehouse Freshness**: Monitors data freshness and recent update activity
- **ETL Processing Duration**: Tracks ETL job execution times and identifies long-running jobs
- **Data Mart Status**: Monitors data mart update frequency and staleness
- **Query Performance**: Tracks slow queries and query execution times
- **Storage Growth**: Monitors database size, table sizes, and disk usage

### Key Features

- **Automated Monitoring**: Run checks on a schedule (e.g., via cron)
- **Metrics Collection**: All metrics are stored in PostgreSQL for historical analysis
- **Alerting**: Configurable alerts for critical issues (WARNING, ERROR, CRITICAL, INFO)
- **Dashboards**: View metrics in Grafana or custom dashboards
- **Low Overhead**: Designed to minimize impact on the monitored system
- **Data Warehouse Integration**: Direct queries to analytics database for real-time status

---

## Prerequisites

Before setting up analytics monitoring, ensure you have:

1. **PostgreSQL Database**: A PostgreSQL database for storing metrics and alerts
   - Version 12 or higher recommended
   - Database created and accessible
   - User with appropriate permissions
   - Analytics database accessible (separate from monitoring database)

2. **OSM-Notes-Analytics Repository**: The analytics repository must be accessible
   - Repository cloned locally
   - ETL scripts present in `bin/` directory
   - Log files accessible (typically in `logs/` directory)

3. **Bash Environment**: Bash 4.0 or higher

4. **PostgreSQL Client Tools**: `psql` command-line tool available

5. **System Tools**: Standard Unix utilities (`find`, `grep`, `awk`, `df`, `ps`)

6. **Optional**: `pg_stat_statements` extension enabled for query performance monitoring

---

## Quick Start

### 1. Configure Database Connection

Edit `config/monitoring.conf`:

```bash
# Monitoring database
DBNAME=osm_notes_monitoring
DBHOST=localhost
DBPORT=5432
DBUSER=monitoring_user

# Analytics database (for querying data warehouse)
ANALYTICS_DBNAME=analytics_db
```

### 2. Configure Analytics Paths

```bash
# Analytics repository path
ANALYTICS_REPO_PATH=/path/to/OSM-Notes-Analytics

# Analytics log directory (optional, defaults to ANALYTICS_REPO_PATH/logs)
ANALYTICS_LOG_DIR=/path/to/OSM-Notes-Analytics/logs
```

### 3. Enable Analytics Monitoring

```bash
# Enable analytics monitoring
ANALYTICS_ENABLED=true
```

### 4. Run Monitoring

```bash
# Run analytics monitoring manually
./bin/monitor/monitorAnalytics.sh

# Or run all monitoring
./bin/monitor/monitorAll.sh
```

### 5. Verify Metrics

```bash
# Check metrics in database
psql -d osm_notes_monitoring -c "SELECT * FROM metrics WHERE component = 'analytics' ORDER BY timestamp DESC LIMIT 10;"
```

---

## Configuration

### Required Configuration

#### Database Configuration

```bash
# Monitoring database (stores metrics and alerts)
DBNAME=osm_notes_monitoring
DBHOST=localhost
DBPORT=5432
DBUSER=monitoring_user

# Analytics database (data warehouse being monitored)
ANALYTICS_DBNAME=analytics_db
```

#### Analytics Paths

```bash
# Path to analytics repository
ANALYTICS_REPO_PATH=/path/to/OSM-Notes-Analytics

# Log directory (optional)
ANALYTICS_LOG_DIR=/path/to/OSM-Notes-Analytics/logs
```

#### Enable Monitoring

```bash
ANALYTICS_ENABLED=true
```

### Optional Configuration

#### ETL Monitoring Thresholds

```bash
# Minimum number of ETL scripts expected
ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD=2

# Maximum age of last ETL execution (seconds)
ANALYTICS_ETL_LAST_EXECUTION_AGE_THRESHOLD=3600

# Maximum duration for running ETL jobs (seconds)
ANALYTICS_ETL_DURATION_THRESHOLD=3600

# Average ETL processing duration threshold (seconds)
ANALYTICS_ETL_AVG_DURATION_THRESHOLD=1800

# Maximum ETL processing duration threshold (seconds)
ANALYTICS_ETL_MAX_DURATION_THRESHOLD=7200
```

#### Data Warehouse Thresholds

```bash
# Maximum data freshness age (seconds)
ANALYTICS_DATA_FRESHNESS_THRESHOLD=3600
```

#### Data Mart Thresholds

```bash
# Maximum data mart update age (seconds)
ANALYTICS_DATA_MART_UPDATE_AGE_THRESHOLD=3600

# Average data mart update age threshold (seconds)
ANALYTICS_DATA_MART_AVG_UPDATE_AGE_THRESHOLD=1800
```

#### Query Performance Thresholds

```bash
# Slow query threshold (milliseconds)
ANALYTICS_SLOW_QUERY_THRESHOLD=1000

# Average query time threshold (milliseconds)
ANALYTICS_AVG_QUERY_TIME_THRESHOLD=500

# Maximum query time threshold (milliseconds)
ANALYTICS_MAX_QUERY_TIME_THRESHOLD=5000
```

#### Storage Thresholds

```bash
# Database size threshold (bytes)
ANALYTICS_DB_SIZE_THRESHOLD=107374182400  # 100GB

# Largest table size threshold (bytes)
ANALYTICS_LARGEST_TABLE_SIZE_THRESHOLD=10737418240  # 10GB

# Disk usage threshold (percentage)
ANALYTICS_DISK_USAGE_THRESHOLD=85
```

### Configuration File Example

See `config/monitoring.conf.example` for a complete configuration example.

---

## Running Monitoring

### Manual Execution

```bash
# Run analytics monitoring
./bin/monitor/monitorAnalytics.sh

# Run with debug logging
LOG_LEVEL=DEBUG ./bin/monitor/monitorAnalytics.sh
```

### Scheduled Execution (Cron)

Add to crontab for regular monitoring:

```bash
# Run every 15 minutes
*/15 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorAnalytics.sh >> /var/log/monitoring/analytics.log 2>&1

# Run every hour
0 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorAnalytics.sh >> /var/log/monitoring/analytics.log 2>&1
```

### Systemd Timer (Alternative)

Create `/etc/systemd/system/analytics-monitoring.timer`:

```ini
[Unit]
Description=Analytics Monitoring Timer
Requires=analytics-monitoring.service

[Timer]
OnCalendar=*-*-* *:00,15,30,45:00
Persistent=true

[Install]
WantedBy=timers.target
```

Create `/etc/systemd/system/analytics-monitoring.service`:

```ini
[Unit]
Description=Analytics Monitoring Service

[Service]
Type=oneshot
ExecStart=/path/to/OSM-Notes-Monitoring/bin/monitor/monitorAnalytics.sh
User=monitoring
```

Enable and start:

```bash
sudo systemctl enable analytics-monitoring.timer
sudo systemctl start analytics-monitoring.timer
```

---

## Understanding Metrics

### Metric Categories

#### 1. ETL Job Execution Metrics

- **`etl_scripts_found`**: Number of ETL scripts found
- **`etl_scripts_executable`**: Number of executable ETL scripts
- **`etl_scripts_running`**: Number of currently running ETL scripts
- **`etl_last_execution_age_seconds`**: Age of last ETL execution

#### 2. ETL Processing Duration Metrics

- **`etl_processing_duration_avg_seconds`**: Average ETL processing duration
- **`etl_processing_duration_max_seconds`**: Maximum ETL processing duration
- **`etl_processing_duration_min_seconds`**: Minimum ETL processing duration
- **`etl_running_jobs_duration_seconds`**: Duration of currently running jobs
- **`etl_long_running_jobs_count`**: Number of long-running jobs

#### 3. Data Warehouse Metrics

- **`data_warehouse_freshness_seconds`**: Data freshness (time since last update)
- **`data_warehouse_recent_updates_count`**: Number of recent updates (last hour)

#### 4. Data Mart Metrics

- **`data_mart_update_age_seconds`**: Age of data mart updates
- **`data_mart_avg_update_age_seconds`**: Average update age across all marts
- **`data_mart_stale_count`**: Number of stale data marts
- **`data_mart_failure_count`**: Number of data marts with update failures

#### 5. Query Performance Metrics

- **`slow_query_count`**: Number of slow queries detected
- **`query_avg_time_ms`**: Average query execution time
- **`query_max_time_ms`**: Maximum query execution time
- **`query_total_calls`**: Total number of query calls

#### 6. Storage Metrics

- **`database_size_bytes`**: Total database size
- **`total_table_size_bytes`**: Total size of all tables
- **`largest_table_size_bytes`**: Size of largest table
- **`table_size_bytes`**: Size of individual tables
- **`disk_usage_percent`**: Disk usage percentage

### Querying Metrics

```bash
# View all analytics metrics
psql -d osm_notes_monitoring -c "
  SELECT metric_name, metric_value, timestamp 
  FROM metrics 
  WHERE component = 'analytics' 
  ORDER BY timestamp DESC 
  LIMIT 20;
"

# View specific metric over time
psql -d osm_notes_monitoring -c "
  SELECT timestamp, metric_value 
  FROM metrics 
  WHERE component = 'analytics' 
    AND metric_name = 'data_warehouse_freshness_seconds'
  ORDER BY timestamp DESC 
  LIMIT 100;
"

# Calculate average metric value
psql -d osm_notes_monitoring -c "
  SELECT AVG(metric_value::numeric) as avg_value
  FROM metrics 
  WHERE component = 'analytics' 
    AND metric_name = 'etl_processing_duration_avg_seconds'
    AND timestamp > NOW() - INTERVAL '24 hours';
"
```

For complete metric definitions, see **[ANALYTICS_METRICS.md](./ANALYTICS_METRICS.md)**.

---

## Alerting

### Alert Levels

- **CRITICAL**: Immediate action required (e.g., disk usage > 90%, database connection failure)
- **ERROR**: Error condition detected (e.g., data mart update failures)
- **WARNING**: Warning condition detected (e.g., data freshness exceeded, slow queries)
- **INFO**: Informational alerts (e.g., unused indexes found)

### Alert Types

#### ETL Alerts

- **`etl_scripts_found`**: Low number of ETL scripts found
- **`etl_scripts_executable`**: Some ETL scripts are not executable
- **`etl_last_execution_age`**: Last ETL execution is too old
- **`etl_error_count`**: ETL job errors detected
- **`etl_failure_count`**: ETL job failures detected
- **`etl_duration`**: Long-running ETL job detected
- **`etl_avg_duration`**: Average ETL processing duration exceeded
- **`etl_max_duration`**: Maximum ETL processing duration exceeded

#### Data Warehouse Alerts

- **`data_warehouse_freshness`**: Data warehouse freshness exceeded
- **`data_warehouse_recent_updates`**: No recent updates in data warehouse

#### Data Mart Alerts

- **`data_mart_update_age`**: Data mart update age exceeded
- **`data_mart_recent_updates`**: No recent updates in data mart
- **`data_mart_stale_count`**: Stale data marts detected
- **`data_mart_failure`**: Data mart update failures detected
- **`data_mart_avg_update_age`**: Average data mart update age exceeded

#### Query Performance Alerts

- **`slow_queries`**: Slow queries detected
- **`slow_query`**: Individual slow query detected
- **`query_avg_time`**: Average query time exceeded
- **`query_max_time`**: Maximum query time exceeded

#### Storage Alerts

- **`database_size`**: Database size exceeded
- **`table_size`**: Largest table size exceeded
- **`disk_usage`**: Disk usage exceeded (WARNING at 85%, CRITICAL at 90%)
- **`database_connection`**: Database connection failed (CRITICAL)

#### Optimization Alerts

- **`unused_index_count`**: Potentially unused indexes found (INFO)

### Viewing Alerts

```bash
# View active alerts
psql -d osm_notes_monitoring -c "
  SELECT component, alert_level, alert_type, message, created_at 
  FROM alerts 
  WHERE component = 'ANALYTICS' 
    AND status = 'active'
  ORDER BY created_at DESC;
"

# View alerts by level
psql -d osm_notes_monitoring -c "
  SELECT alert_level, COUNT(*) 
  FROM alerts 
  WHERE component = 'ANALYTICS' 
    AND created_at > NOW() - INTERVAL '24 hours'
  GROUP BY alert_level;
"
```

For complete alert threshold definitions, see **[ANALYTICS_ALERT_THRESHOLDS.md](./ANALYTICS_ALERT_THRESHOLDS.md)**.

---

## Troubleshooting

### Common Issues

#### Database Connection Failures

**Symptoms**: Monitoring script fails with database connection errors

**Solutions**:
1. Verify database credentials in `config/monitoring.conf`
2. Test connection: `psql -h $DBHOST -p $DBPORT -U $DBUSER -d $DBNAME`
3. Check firewall rules and network connectivity
4. Verify PostgreSQL is running: `systemctl status postgresql`
5. Check PostgreSQL logs: `tail -f /var/log/postgresql/postgresql-*.log`

#### Analytics Database Not Found

**Symptoms**: Errors querying analytics database

**Solutions**:
1. Verify `ANALYTICS_DBNAME` is correct
2. Test connection: `psql -d $ANALYTICS_DBNAME -c "SELECT 1;"`
3. Check database exists: `psql -l | grep $ANALYTICS_DBNAME`
4. Verify user has access: `psql -d $ANALYTICS_DBNAME -c "\du"`

#### ETL Scripts Not Found

**Symptoms**: Alerts about low number of ETL scripts

**Solutions**:
1. Verify `ANALYTICS_REPO_PATH` is correct
2. Check script locations: `ls -la $ANALYTICS_REPO_PATH/bin/`
3. Verify scripts have execute permissions: `chmod +x $ANALYTICS_REPO_PATH/bin/*.sh`
4. Check for path issues (symlinks, mount points)

#### Metrics Not Being Collected

**Symptoms**: No metrics in database

**Solutions**:
1. Check monitoring script logs: `tail -f logs/monitorAnalytics.log`
2. Verify `ANALYTICS_ENABLED=true` in configuration
3. Test database write permissions
4. Check for errors in monitoring script execution
5. Verify monitoring script is being executed

#### High Query Times

**Symptoms**: Slow query alerts or high query performance metrics

**Solutions**:
1. Review slow queries: Check `pg_stat_statements` if available
2. Analyze query execution plans: `EXPLAIN ANALYZE <query>`
3. Check for missing indexes
4. Review table statistics: `ANALYZE <table>`
5. Consider query optimization or indexing

#### Data Warehouse Freshness Issues

**Symptoms**: Alerts about stale data

**Solutions**:
1. Check ETL job execution status
2. Review ETL logs for errors
3. Verify ETL jobs are scheduled correctly
4. Check for blocking locks: `SELECT * FROM pg_locks WHERE NOT granted;`
5. Review data warehouse update procedures

#### Disk Usage Alerts

**Symptoms**: CRITICAL or WARNING disk usage alerts

**Solutions**:
1. Check actual disk usage: `df -h`
2. Identify large tables: Query `pg_total_relation_size()`
3. Review data retention policies
4. Consider archiving old data
5. Check for table bloat: `VACUUM ANALYZE <table>`

---

## Best Practices

### 1. Monitoring Frequency

- **Production Systems**: Run every 15-30 minutes
- **Development/Testing**: Run hourly or on-demand
- **Critical Systems**: Consider more frequent monitoring (every 5-10 minutes)

### 2. Threshold Tuning

- Start with default thresholds
- Monitor for 1-2 weeks to understand normal behavior
- Adjust thresholds based on your system's patterns
- Document threshold changes and reasons
- Review thresholds quarterly

### 3. Alert Management

- Use alert deduplication to avoid alert fatigue
- Set up alert escalation for critical issues
- Review and acknowledge alerts promptly
- Document alert responses for future reference
- Create runbooks for common alert scenarios

### 4. Database Maintenance

- Regularly clean old metrics (older than 90 days)
- Monitor database size and growth
- Create indexes on frequently queried columns:
  ```sql
  CREATE INDEX idx_metrics_component_timestamp 
    ON metrics(component, timestamp DESC);
  CREATE INDEX idx_alerts_component_status 
    ON alerts(component, status, created_at DESC);
  ```
- Set up database backups
- Monitor query performance and optimize slow queries

### 5. ETL Monitoring

- Monitor ETL job execution patterns
- Track ETL duration trends over time
- Set up alerts for ETL failures
- Review ETL logs regularly
- Document ETL job schedules and dependencies

### 6. Data Warehouse Monitoring

- Monitor data freshness trends
- Track update frequency patterns
- Set up alerts for stale data
- Review data warehouse query performance
- Monitor data warehouse growth

### 7. Query Performance

- Enable `pg_stat_statements` extension if available
- Monitor slow query trends
- Review query execution plans regularly
- Optimize frequently executed queries
- Consider query caching for expensive queries

### 8. Storage Management

- Monitor database and table growth trends
- Set up alerts before reaching capacity
- Plan for storage expansion
- Archive old data regularly
- Monitor disk I/O performance

### 9. Log Management

- Rotate monitoring logs regularly
- Archive old logs for historical analysis
- Monitor log file sizes
- Use log aggregation tools if available
- Review logs for patterns and anomalies

### 10. Performance Monitoring

- Run performance tests periodically
- Monitor monitoring system overhead
- Optimize slow monitoring queries
- Review and update monitoring scripts as needed
- Document performance baselines

---

## Reference Documentation

### Core Documentation

- **[ANALYTICS_METRICS.md](./ANALYTICS_METRICS.md)**: Complete metric definitions
- **[ANALYTICS_ALERT_THRESHOLDS.md](./ANALYTICS_ALERT_THRESHOLDS.md)**: All alert thresholds
- **[CONFIGURATION_REFERENCE.md](./CONFIGURATION_REFERENCE.md)**: Complete configuration reference

### Related Documentation

- **[Monitoring_SETUP_Guide.md](./Monitoring_SETUP_Guide.md)**: Initial setup guide
- **[DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)**: Database schema documentation
- **[Monitoring_Architecture_Proposal.md](./Monitoring_Architecture_Proposal.md)**: System architecture overview

### Scripts

- **`bin/monitor/monitorAnalytics.sh`**: Main analytics monitoring script
- **`bin/lib/monitoringFunctions.sh`**: Core monitoring functions
- **`bin/lib/metricsFunctions.sh`**: Metrics collection functions
- **`bin/lib/alertFunctions.sh`**: Alerting functions

### Testing

- **`tests/unit/monitor/test_monitorAnalytics.sh`**: Unit tests
- **`tests/integration/test_monitorAnalytics_integration.sh`**: Integration tests
- **`tests/integration/test_analytics_alert_delivery.sh`**: Alert delivery tests
- **`tests/performance/test_analytics_query_performance.sh`**: Performance tests

---

## Getting Help

If you encounter issues or have questions:

1. **Check Documentation**: Review this guide and related documentation
2. **Review Logs**: Check monitoring logs for error messages
3. **Run Tests**: Execute test suites to verify functionality
4. **Check Issues**: Review GitHub issues for known problems
5. **Create Issue**: Open a new issue with detailed information

---

**Last Updated**: 2025-12-27  
**Version**: 1.0.0

