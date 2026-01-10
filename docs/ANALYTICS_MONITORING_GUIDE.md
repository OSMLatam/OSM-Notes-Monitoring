# Analytics Monitoring Guide

> **Purpose:** Comprehensive guide for monitoring the OSM-Notes-Analytics component  
> **Version:** 2.0.0  
> **Date:** 2026-01-10  
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
- **ETL Log Analysis**: Parses structured ETL logs to extract detailed execution metrics
- **Data Warehouse Performance**: Monitors database performance (cache hit ratio, connections, slow queries, locks, bloat)
- **Data Warehouse Sizes**: Tracks database and table sizes, partition sizes, and growth trends
- **Data Mart Status**: Monitors datamart update frequency, staleness, and execution metrics
- **Data Quality Validation**: Executes MON-001 and MON-002 validations, tracks data quality scores
- **System Resources**: Monitors CPU, memory, disk I/O, and load for ETL and PostgreSQL processes
- **Export Processes**: Tracks JSON/CSV exports, file sizes, validation status, and GitHub push status
- **Cron Job Monitoring**: Verifies scheduled job executions (ETL, datamarts, exports) and detects gaps
- **Data Warehouse Freshness**: Monitors data freshness and recent update activity
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

#### System Resources Thresholds

```bash
# ETL CPU usage threshold (percentage)
ANALYTICS_ETL_CPU_THRESHOLD=80

# ETL memory usage threshold (MB)
ANALYTICS_ETL_MEMORY_THRESHOLD=2048  # 2GB

# PostgreSQL CPU usage threshold (percentage)
ANALYTICS_POSTGRESQL_CPU_THRESHOLD=80

# PostgreSQL memory usage threshold (MB)
ANALYTICS_POSTGRESQL_MEMORY_THRESHOLD=4096  # 4GB

# System load average threshold
ANALYTICS_LOAD_AVERAGE_THRESHOLD=5.0

# ETL log disk usage threshold (bytes)
ANALYTICS_ETL_LOG_DISK_USAGE_THRESHOLD=5368709120  # 5GB
```

#### Export Thresholds

```bash
# Export file staleness threshold (seconds)
ANALYTICS_EXPORT_STALENESS_THRESHOLD=86400  # 24 hours

# Export file count threshold
ANALYTICS_EXPORT_FILES_MIN_THRESHOLD=1
```

#### Cron Job Thresholds

```bash
# ETL cron execution gap threshold (seconds)
ANALYTICS_ETL_CRON_GAP_THRESHOLD=1800  # 30 minutes

# Datamart cron execution gap threshold (seconds)
ANALYTICS_DATAMART_CRON_GAP_THRESHOLD=90000  # 25 hours

# Export cron execution gap threshold (seconds)
ANALYTICS_EXPORT_CRON_GAP_THRESHOLD=90000  # 25 hours
```

#### Validation Thresholds

```bash
# Data quality score threshold (percentage)
ANALYTICS_DATA_QUALITY_SCORE_THRESHOLD=70

# Validation issues threshold
ANALYTICS_VALIDATION_ISSUES_THRESHOLD=10

# Orphaned facts threshold
ANALYTICS_ORPHANED_FACTS_THRESHOLD=0
```

### Configuration File Example

See `config/monitoring.conf.example` for a complete configuration example.

---

## Running Monitoring

### Manual Execution

```bash
# Run all analytics monitoring checks
./bin/monitor/monitorAnalytics.sh

# Run specific check
./bin/monitor/monitorAnalytics.sh --check etl-status
./bin/monitor/monitorAnalytics.sh --check etl-log-analysis
./bin/monitor/monitorAnalytics.sh --check database-performance
./bin/monitor/monitorAnalytics.sh --check datamart-status
./bin/monitor/monitorAnalytics.sh --check validation-status
./bin/monitor/monitorAnalytics.sh --check system-resources
./bin/monitor/monitorAnalytics.sh --check export-status
./bin/monitor/monitorAnalytics.sh --check cron-jobs
./bin/monitor/monitorAnalytics.sh --check data-quality
./bin/monitor/monitorAnalytics.sh --check query-performance
./bin/monitor/monitorAnalytics.sh --check storage

# Run with debug logging
LOG_LEVEL=DEBUG ./bin/monitor/monitorAnalytics.sh

# Run with verbose output
./bin/monitor/monitorAnalytics.sh --verbose
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

#### 2. ETL Log Analysis Metrics (Phase 1)

- **`etl_execution_time_seconds`**: Total execution time from logs
- **`etl_facts_processed_total`**: Total facts processed (new + updated)
- **`etl_facts_new_total`**: New facts processed
- **`etl_facts_updated_total`**: Updated facts processed
- **`etl_dimensions_updated_total`**: Dimensions updated
- **`etl_processing_rate_facts_per_sec`**: Facts processing rate
- **`etl_stage_duration_seconds`**: Duration per stage (copy_base_tables, load_facts, etc.)
- **`etl_validation_status`**: Validation status (PASS/FAIL)
- **`etl_errors_total`**: Total errors detected
- **`etl_execution_mode`**: Execution mode (initial/incremental)
- **`etl_success_rate`**: Success rate of executions

#### 3. Database Performance Metrics (Phase 2)

- **`database_cache_hit_ratio`**: Cache hit ratio percentage
- **`database_active_connections`**: Number of active connections
- **`database_slow_queries_count`**: Number of slow queries
- **`database_active_locks_count`**: Number of active locks
- **`database_table_bloat_bytes`**: Table bloat size
- **`database_schema_size_bytes`**: Total schema size
- **`database_facts_partition_size_bytes`**: Facts partition sizes
- **`database_total_size_bytes`**: Total database size

#### 4. Database Size Metrics (Phase 2)

- **`database_size_bytes`**: Total database size
- **`total_table_size_bytes`**: Total size of all tables
- **`largest_table_size_bytes`**: Size of largest table
- **`table_size_bytes`**: Size of individual tables
- **`facts_partition_size_bytes`**: Size of facts partitions

#### 5. Datamart Metrics (Phase 3)

- **`datamart_last_update_seconds`**: Time since last update per datamart
- **`datamart_execution_duration_seconds`**: Execution duration per datamart
- **`datamart_records_total`**: Record count per datamart
- **`datamart_countries_processed_total`**: Countries processed (datamart countries)
- **`datamart_users_processed_total`**: Users processed (datamart users)
- **`datamart_countries_parallel_workers`**: Parallel workers used
- **`datamart_process_running`**: Process running status
- **`datamart_execution_status`**: Execution status (SUCCESS/FAIL)
- **`datamart_staleness_detected`**: Staleness detection flag

#### 6. Validation Metrics (Phase 4)

- **`data_validation_status`**: Validation status (PASS/FAIL) for MON-001, MON-002
- **`data_validation_issues`**: Number of issues found per validation
- **`data_validation_duration_seconds`**: Validation execution time
- **`data_orphaned_facts_count`**: Count of orphaned facts
- **`data_quality_score`**: Overall data quality score (0-100)

#### 7. System Resources Metrics (Phase 5)

- **`etl_cpu_usage_percent`**: ETL process CPU usage
- **`etl_memory_usage_mb`**: ETL process memory usage
- **`etl_disk_read_bytes_total`**: ETL disk read bytes
- **`etl_disk_write_bytes_total`**: ETL disk write bytes
- **`etl_log_disk_usage_bytes`**: ETL log directory disk usage
- **`postgresql_cpu_usage_percent`**: PostgreSQL CPU usage
- **`postgresql_memory_usage_mb`**: PostgreSQL memory usage
- **`system_load_average_1min`**: 1-minute load average
- **`system_load_average_5min`**: 5-minute load average
- **`system_load_average_15min`**: 15-minute load average
- **`system_disk_usage_percent`**: Root filesystem disk usage
- **`system_disk_total_bytes`**: Total disk space
- **`system_disk_used_bytes`**: Used disk space
- **`system_disk_available_bytes`**: Available disk space

#### 8. Export Metrics (Phase 6)

- **`export_files_total`**: Total export files (JSON/CSV)
- **`export_files_size_bytes`**: Total export file sizes
- **`export_last_successful_timestamp`**: Last successful export timestamp
- **`export_validation_status`**: JSON schema validation status
- **`export_github_push_status`**: GitHub push status
- **`export_duration_seconds`**: Export execution duration
- **`export_status`**: Export status (SUCCESS/FAIL)

#### 9. Cron Job Metrics (Phase 7)

- **`cron_etl_last_execution_seconds`**: Time since last ETL cron execution
- **`cron_etl_execution_count_24h`**: ETL executions in last 24 hours
- **`cron_etl_execution_gap`**: Missing executions count
- **`cron_datamart_last_execution_seconds`**: Time since last datamart cron execution
- **`cron_datamart_execution_count_24h`**: Datamart executions in last 24 hours
- **`cron_export_last_execution_seconds`**: Time since last export cron execution
- **`cron_export_execution_count_24h`**: Export executions in last 24 hours
- **`cron_lock_files_total`**: Total lock files found
- **`cron_etl_lock_exists`**: ETL lock file exists
- **`cron_datamart_lock_exists`**: Datamart lock file exists
- **`cron_export_lock_exists`**: Export lock file exists
- **`cron_etl_gap_detected`**: ETL execution gap detected
- **`cron_datamart_gap_detected`**: Datamart execution gap detected
- **`cron_export_gap_detected`**: Export execution gap detected

#### 10. Data Warehouse Freshness Metrics

- **`data_warehouse_freshness_seconds`**: Data freshness (time since last update)
- **`data_warehouse_recent_updates_count`**: Number of recent updates (last hour)

#### 11. Query Performance Metrics

- **`slow_query_count`**: Number of slow queries detected
- **`query_avg_time_ms`**: Average query execution time
- **`query_max_time_ms`**: Maximum query execution time
- **`query_total_calls`**: Total number of query calls

#### 12. Storage Metrics

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
- **`etl_validation_failed`**: ETL validation failed
- **`etl_log_unavailable`**: ETL log files unavailable

#### Database Performance Alerts

- **`database_cache_hit_ratio_low`**: Cache hit ratio below threshold
- **`database_slow_queries`**: Slow queries detected
- **`database_high_connections`**: High number of active connections
- **`database_deadlocks`**: Deadlocks detected
- **`database_table_bloat`**: Table bloat detected
- **`database_connection_failure`**: Database connection failed (CRITICAL)

#### Data Warehouse Alerts

- **`data_warehouse_freshness`**: Data warehouse freshness exceeded
- **`data_warehouse_recent_updates`**: No recent updates in data warehouse

#### Datamart Alerts

- **`datamart_stale`**: Datamart is stale (last update > 24 hours)
- **`datamart_failed_execution`**: Datamart execution failed
- **`datamart_long_execution`**: Datamart execution taking too long
- **`datamart_no_recent_executions`**: No recent executions detected
- **`datamart_record_count_stagnant`**: Record count not changing

#### Validation Alerts

- **`validation_mon001_failed`**: MON-001 validation failed
- **`validation_mon002_failed`**: MON-002 validation failed
- **`validation_high_issues`**: High number of validation issues
- **`orphaned_facts_detected`**: Orphaned facts detected
- **`data_quality_score_low`**: Data quality score below threshold

#### System Resources Alerts

- **`etl_high_cpu_usage`**: ETL process high CPU usage
- **`etl_high_memory_usage`**: ETL process high memory usage
- **`postgresql_high_cpu_usage`**: PostgreSQL high CPU usage
- **`postgresql_high_memory_usage`**: PostgreSQL high memory usage
- **`system_load_average_high`**: System load average high
- **`disk_usage_warning`**: Disk usage warning (85%)
- **`disk_usage_critical`**: Disk usage critical (95%)
- **`etl_log_disk_usage_high`**: ETL log directory disk usage high

#### Export Alerts

- **`export_failed`**: Export process failed
- **`export_files_stale`**: Export files are stale
- **`export_github_push_failed`**: GitHub push failed
- **`export_validation_failed`**: JSON schema validation failed
- **`export_no_recent_files`**: No recent export files

#### Cron Job Alerts

- **`cron_etl_not_running`**: ETL cron job not running according to schedule
- **`cron_datamart_not_running`**: Datamart cron job not running
- **`cron_export_not_running`**: Export cron job not running
- **`cron_execution_gap`**: Execution gap detected
- **`cron_lock_files_stale`**: Stale lock files detected
- **`cron_log_unavailable`**: Cron log files unavailable

#### Query Performance Alerts

- **`slow_queries`**: Slow queries detected
- **`slow_query`**: Individual slow query detected
- **`query_avg_time`**: Average query time exceeded
- **`query_max_time`**: Maximum query time exceeded

#### Storage Alerts

- **`database_size`**: Database size exceeded
- **`table_size`**: Largest table size exceeded
- **`disk_usage`**: Disk usage exceeded (WARNING at 85%, CRITICAL at 90%)

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
- **`bin/monitor/collect_etl_metrics.sh`**: ETL metrics collection (Phase 1)
- **`bin/monitor/collect_database_metrics.sh`**: Database performance metrics (Phase 2)
- **`bin/monitor/collect_datamart_metrics.sh`**: Datamart metrics (Phase 3)
- **`bin/monitor/collect_validation_metrics.sh`**: Validation metrics (Phase 4)
- **`bin/monitor/collect_analytics_system_metrics.sh`**: System resources metrics (Phase 5)
- **`bin/monitor/collect_export_metrics.sh`**: Export metrics (Phase 6)
- **`bin/monitor/collect_cron_metrics.sh`**: Cron job metrics (Phase 7)
- **`bin/lib/etlLogParser.sh`**: ETL log parsing library (Phase 1)
- **`bin/lib/datamartLogParser.sh`**: Datamart log parsing library (Phase 3)
- **`bin/lib/monitoringFunctions.sh`**: Core monitoring functions
- **`bin/lib/metricsFunctions.sh`**: Metrics collection functions
- **`bin/lib/alertFunctions.sh`**: Alerting functions

### Dashboards

- **`dashboards/grafana/analytics_etl_overview.json`**: ETL monitoring dashboard (Phase 1)
- **`dashboards/grafana/analytics_dwh_performance.json`**: Database performance dashboard (Phase 2)
- **`dashboards/grafana/analytics_datamarts_overview.json`**: Datamarts dashboard (Phase 3)
- **`dashboards/grafana/analytics_data_quality.json`**: Data quality dashboard (Phase 4)
- **`dashboards/grafana/analytics_system_resources.json`**: System resources dashboard (Phase 5)
- **`dashboards/grafana/analytics_export_status.json`**: Export status dashboard (Phase 6)

### Alert Rules

- **`config/alerts/analytics_etl_alerts.yml`**: ETL alert rules (Phase 1)
- **`config/alerts/analytics_db_alerts.yml`**: Database alert rules (Phase 2)
- **`config/alerts/analytics_datamart_alerts.yml`**: Datamart alert rules (Phase 3)
- **`config/alerts/analytics_quality_alerts.yml`**: Data quality alert rules (Phase 4)
- **`config/alerts/analytics_system_alerts.yml`**: System resources alert rules (Phase 5)
- **`config/alerts/analytics_export_alerts.yml`**: Export alert rules (Phase 6)
- **`config/alerts/analytics_cron_alerts.yml`**: Cron job alert rules (Phase 7)

### Testing

- **`tests/unit/monitor/test_collect_etl_metrics.sh`**: ETL metrics unit tests
- **`tests/unit/lib/test_etlLogParser.sh`**: ETL parser unit tests
- **`tests/unit/monitor/test_collect_database_metrics.sh`**: Database metrics unit tests
- **`tests/unit/monitor/test_collect_datamart_metrics.sh`**: Datamart metrics unit tests
- **`tests/unit/lib/test_datamartLogParser.sh`**: Datamart parser unit tests
- **`tests/unit/monitor/test_collect_validation_metrics.sh`**: Validation metrics unit tests
- **`tests/unit/monitor/test_collect_analytics_system_metrics.sh`**: System metrics unit tests
- **`tests/unit/monitor/test_collect_export_metrics.sh`**: Export metrics unit tests
- **`tests/unit/monitor/test_collect_cron_metrics.sh`**: Cron metrics unit tests
- **`tests/integration/test_etl_monitoring.sh`**: ETL monitoring integration tests
- **`tests/integration/test_database_monitoring.sh`**: Database monitoring integration tests
- **`tests/integration/test_datamart_monitoring.sh`**: Datamart monitoring integration tests
- **`tests/integration/test_validation_monitoring.sh`**: Validation monitoring integration tests
- **`tests/integration/test_system_resources.sh`**: System resources integration tests
- **`tests/integration/test_export_monitoring.sh`**: Export monitoring integration tests
- **`tests/integration/test_cron_monitoring.sh`**: Cron monitoring integration tests

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

