---
title: "ETL Monitoring Runbook"
description: "This runbook provides detailed information about each ETL monitoring alert type for the OSM-Notes-Analytics component, including:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "etl"
  - "monitoring"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# ETL Monitoring Runbook

> **Purpose:** Comprehensive guide for understanding and responding to ETL monitoring alerts  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This runbook provides detailed information about each ETL monitoring alert type for the
OSM-Notes-Analytics component, including:

- What the alert means
- What causes it
- How to investigate
- How to resolve
- Prevention strategies

## Alert Severity Levels

### CRITICAL

- **Response Time:** Immediate (within 15 minutes)
- **Impact:** System is non-functional or data is at risk
- **Action:** Escalate immediately, investigate root cause

### ERROR

- **Response Time:** Within 30 minutes
- **Impact:** Error condition detected, may affect data quality
- **Action:** Investigate and resolve promptly

### WARNING

- **Response Time:** Within 1 hour
- **Impact:** Performance degradation or potential issues
- **Action:** Investigate and resolve, monitor closely

### INFO

- **Response Time:** Within 24 hours
- **Impact:** Informational, no immediate action required
- **Action:** Review and document, may indicate trends

## Alert Categories

### 1. ETL Job Execution Alerts

#### Alert: Low number of ETL scripts found

**Alert Message:** `Low number of ETL scripts found: X (threshold: Y)`

**Severity:** WARNING

**Alert Type:** `etl_scripts_found`

**What it means:**

- Fewer ETL scripts than expected are found in the analytics repository
- Expected minimum scripts based on `ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD` (default: 2)

**Common Causes:**

- Scripts were deleted or moved
- Repository path is incorrect
- File system issues
- Repository not properly cloned/updated
- Scripts renamed or restructured

**Investigation Steps:**

1. Check `ANALYTICS_REPO_PATH` configuration:
   ```bash
   echo $ANALYTICS_REPO_PATH
   ```
2. Verify repository exists:
   ```bash
   ls -la ${ANALYTICS_REPO_PATH}/bin
   ```
3. Count actual scripts:
   ```bash
   find ${ANALYTICS_REPO_PATH}/bin -name "*.sh" -type f | wc -l
   ```
4. Check if scripts are in expected location
5. Verify repository was not accidentally deleted
6. Check file system health

**Resolution:**

1. Restore missing scripts from backup or version control
2. Update repository:
   ```bash
   cd ${ANALYTICS_REPO_PATH} && git pull
   ```
3. Verify script permissions:
   ```bash
   chmod +x ${ANALYTICS_REPO_PATH}/bin/*.sh
   ```
4. Update `ANALYTICS_REPO_PATH` if scripts moved
5. Adjust threshold if legitimate reduction in scripts:
   ```bash
   # Edit config/monitoring.conf
   ANALYTICS_ETL_SCRIPTS_FOUND_THRESHOLD=1
   ```
6. Restart monitoring after fixing

**Prevention:**

- Use version control for all ETL scripts
- Regular backups of repository
- Monitor repository path configuration
- Automated deployment checks
- Document script changes

---

#### Alert: ETL scripts executable count is less than scripts found

**Alert Message:** `ETL scripts executable count (X) is less than scripts found (Y)`

**Severity:** WARNING

**Alert Type:** `etl_scripts_executable`

**What it means:**

- Some ETL scripts exist but are not executable
- Scripts cannot be run due to missing execute permissions

**Common Causes:**

- File permissions changed accidentally
- Scripts copied without preserving permissions
- File system issues
- Manual permission changes
- Deployment process issues

**Investigation Steps:**

1. Check script permissions:
   ```bash
   ls -la ${ANALYTICS_REPO_PATH}/bin/*.sh
   ```
2. Identify which scripts are not executable
3. Check if scripts were recently modified
4. Review file system logs
5. Check deployment logs

**Resolution:**

1. Make scripts executable:
   ```bash
   chmod +x ${ANALYTICS_REPO_PATH}/bin/*.sh
   ```
2. Verify permissions:
   ```bash
   ls -la ${ANALYTICS_REPO_PATH}/bin/*.sh
   ```
3. Check specific script:
   ```bash
   test -x ${ANALYTICS_REPO_PATH}/bin/etl_job.sh && echo "Executable" || echo "Not executable"
   ```
4. Fix deployment process to preserve permissions
5. Restart monitoring after fixing

**Prevention:**

- Use deployment scripts that preserve permissions
- Document permission requirements
- Regular permission audits
- Automated permission checks in CI/CD

---

#### Alert: Last ETL execution is too old

**Alert Message:** `Last ETL execution is Xs old (threshold: Ys)`

**Severity:** WARNING

**Alert Type:** `etl_last_execution_age`

**What it means:**

- No ETL jobs have executed recently
- Last execution exceeds `ANALYTICS_ETL_LAST_EXECUTION_AGE_THRESHOLD` (default: 3600s = 1 hour)

**Common Causes:**

- ETL jobs not scheduled or scheduled incorrectly
- ETL jobs failing silently
- Scheduler service down
- Job dependencies blocking execution
- Resource constraints preventing execution

**Investigation Steps:**

1. Check ETL job logs:
   ```bash
   ls -lt ${ANALYTICS_LOG_DIR}/*.log | head -5
   ```
2. Check for running ETL processes:
   ```bash
   ps aux | grep -E "etl|extract|load|transform" | grep -v grep
   ```
3. Check cron/scheduler:
   ```bash
   crontab -l | grep -i etl
   # Or check systemd timers
   systemctl list-timers | grep etl
   ```
4. Review recent log entries:
   ```bash
   tail -100 ${ANALYTICS_LOG_DIR}/etl_job*.log
   ```
5. Check for errors in logs:
   ```bash
   grep -i error ${ANALYTICS_LOG_DIR}/*.log | tail -20
   ```
6. Verify ETL job configuration

**Resolution:**

1. Manually trigger ETL job to test:
   ```bash
   ${ANALYTICS_REPO_PATH}/bin/etl_job.sh
   ```
2. Fix scheduler configuration if needed
3. Restart scheduler service:
   ```bash
   systemctl restart cron
   # Or restart systemd timer
   systemctl restart etl-job.timer
   ```
4. Check and resolve job dependencies
5. Verify resource availability (CPU, memory, disk)
6. Review and fix ETL job errors
7. Adjust threshold if legitimate longer intervals:
   ```bash
   ANALYTICS_ETL_LAST_EXECUTION_AGE_THRESHOLD=7200  # 2 hours
   ```

**Prevention:**

- Monitor ETL job execution regularly
- Set up alerts for ETL job failures
- Document ETL job schedules
- Regular scheduler health checks
- Monitor resource usage

---

### 2. ETL Error and Failure Alerts

#### Alert: ETL job errors detected

**Alert Message:** `ETL job errors detected: X errors in last 24 hours`

**Severity:** WARNING

**Alert Type:** `etl_error_count`

**What it means:**

- ETL jobs are encountering errors during execution
- Error count exceeds acceptable threshold

**Common Causes:**

- Data quality issues
- Database connection problems
- Resource constraints (memory, disk)
- Code bugs in ETL scripts
- External service failures
- Network issues

**Investigation Steps:**

1. Check ETL error logs:
   ```bash
   grep -i error ${ANALYTICS_LOG_DIR}/*.log | tail -50
   ```
2. Identify error patterns:
   ```bash
   grep -i error ${ANALYTICS_LOG_DIR}/*.log | cut -d: -f4- | sort | uniq -c | sort -rn
   ```
3. Check database connection:
   ```bash
   psql -d $ANALYTICS_DBNAME -c "SELECT 1;"
   ```
4. Check system resources:
   ```bash
   df -h
   free -h
   top -bn1 | head -20
   ```
5. Review recent ETL job executions
6. Check external service status

**Resolution:**

1. Fix data quality issues if identified
2. Resolve database connection problems
3. Free up resources if constrained
4. Fix code bugs in ETL scripts
5. Resolve external service issues
6. Review and improve error handling in ETL scripts
7. Add retry logic for transient failures

**Prevention:**

- Implement robust error handling
- Add data validation checks
- Monitor resource usage
- Regular code reviews
- Comprehensive testing
- Set up alerts for external dependencies

---

#### Alert: ETL job failures detected

**Alert Message:** `ETL job failures detected: X failures in last 24 hours`

**Severity:** WARNING

**Alert Type:** `etl_failure_count`

**What it means:**

- ETL jobs are failing completely (not just errors, but job failures)
- Failure count exceeds acceptable threshold

**Common Causes:**

- Critical errors causing job termination
- Script syntax errors
- Missing dependencies
- Permission issues
- Resource exhaustion
- Database locks

**Investigation Steps:**

1. Check ETL failure logs:
   ```bash
   grep -i "failed\|failure\|fatal" ${ANALYTICS_LOG_DIR}/*.log | tail -50
   ```
2. Check exit codes:
   ```bash
   # Check last ETL job exit code
   echo $?
   ```
3. Review full error stack traces
4. Check for syntax errors:
   ```bash
   bash -n ${ANALYTICS_REPO_PATH}/bin/etl_job.sh
   ```
5. Verify dependencies:
   ```bash
   ldd ${ANALYTICS_REPO_PATH}/bin/etl_job.sh  # If binary
   ```
6. Check database locks:
   ```sql
   SELECT * FROM pg_locks WHERE NOT granted;
   ```

**Resolution:**

1. Fix critical errors identified in logs
2. Correct syntax errors
3. Install missing dependencies
4. Fix permission issues
5. Resolve resource constraints
6. Release database locks if blocking
7. Improve error handling and logging
8. Add monitoring for critical dependencies

**Prevention:**

- Comprehensive testing before deployment
- Code review process
- Dependency management
- Resource monitoring
- Database lock monitoring
- Graceful error handling

---

### 3. ETL Duration Alerts

#### Alert: Long-running ETL job detected

**Alert Message:**
`Long-running ETL job detected: script.sh has been running for Xs (threshold: Ys)`

**Severity:** WARNING

**Alert Type:** `etl_duration`

**What it means:**

- An ETL job has been running longer than `ANALYTICS_ETL_DURATION_THRESHOLD` (default: 3600s = 1
  hour)
- Job may be stuck or processing large data volumes

**Common Causes:**

- Large data volumes to process
- Inefficient queries or processing
- Resource constraints slowing execution
- Deadlocks or blocking locks
- Infinite loops or hanging processes
- Network latency issues

**Investigation Steps:**

1. Check running ETL processes:
   ```bash
   ps aux | grep -E "etl|extract|load|transform" | grep -v grep
   ```
2. Check process runtime:
   ```bash
   ps -o pid,etime,cmd -p <PID>
   ```
3. Check resource usage:
   ```bash
   top -p <PID>
   ```
4. Review ETL job logs for progress:
   ```bash
   tail -f ${ANALYTICS_LOG_DIR}/etl_job.log
   ```
5. Check database activity:
   ```sql
   SELECT pid, state, query, query_start
   FROM pg_stat_activity
   WHERE application_name LIKE '%etl%';
   ```
6. Check for blocking locks:
   ```sql
   SELECT * FROM pg_locks WHERE NOT granted;
   ```

**Resolution:**

1. If legitimate long-running job:
   - Increase threshold: `ANALYTICS_ETL_DURATION_THRESHOLD=7200`
   - Optimize job for better performance
   - Consider splitting into smaller jobs
2. If stuck/hanging:
   - Kill stuck process: `kill -9 <PID>`
   - Investigate root cause
   - Restart job after fixing
3. If resource constrained:
   - Free up resources
   - Scale up resources if needed
4. If inefficient:
   - Optimize queries
   - Review processing logic
   - Add indexes if needed

**Prevention:**

- Set realistic duration thresholds
- Monitor job performance trends
- Optimize queries regularly
- Review and optimize processing logic
- Set up alerts for resource usage
- Regular performance reviews

---

#### Alert: Average ETL processing duration exceeded

**Alert Message:** `Average ETL processing duration exceeded: Xs (threshold: Ys)`

**Severity:** WARNING

**Alert Type:** `etl_avg_duration`

**What it means:**

- Average ETL processing duration over recent period exceeds `ANALYTICS_ETL_AVG_DURATION_THRESHOLD`
  (default: 1800s = 30 minutes)
- Indicates overall performance degradation

**Common Causes:**

- Increasing data volumes
- System performance degradation
- Inefficient queries becoming slower
- Resource constraints
- Database performance issues
- Network latency

**Investigation Steps:**

1. Check average duration trend:
   ```sql
   SELECT
     DATE_TRUNC('hour', timestamp) as hour,
     AVG(metric_value::numeric) as avg_duration
   FROM metrics
   WHERE component = 'analytics'
     AND metric_name = 'etl_processing_duration_avg_seconds'
     AND timestamp > NOW() - INTERVAL '7 days'
   GROUP BY hour
   ORDER BY hour DESC;
   ```
2. Check data volume trends
3. Review system performance metrics
4. Check database performance:
   ```sql
   SELECT * FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 10;
   ```
5. Review resource usage trends

**Resolution:**

1. Optimize slow queries
2. Add indexes if needed
3. Scale up resources if constrained
4. Optimize ETL processing logic
5. Review and improve data processing algorithms
6. Consider partitioning large tables
7. Adjust threshold if legitimate increase:
   ```bash
   ANALYTICS_ETL_AVG_DURATION_THRESHOLD=2400  # 40 minutes
   ```

**Prevention:**

- Regular performance monitoring
- Query optimization reviews
- Capacity planning
- Performance testing
- Regular system maintenance

---

#### Alert: Maximum ETL processing duration exceeded

**Alert Message:** `Maximum ETL processing duration exceeded: Xs (threshold: Ys)`

**Severity:** WARNING

**Alert Type:** `etl_max_duration`

**What it means:**

- Maximum ETL processing duration exceeds `ANALYTICS_ETL_MAX_DURATION_THRESHOLD` (default: 7200s = 2
  hours)
- Indicates at least one job is taking very long

**Common Causes:**

- Very large data volumes
- Complex transformations
- Inefficient processing
- Resource constraints
- Database performance issues

**Investigation Steps:**

1. Identify which job is taking longest:
   ```bash
   grep -i "duration" ${ANALYTICS_LOG_DIR}/*.log | sort -k2 -rn | head -10
   ```
2. Check specific job logs
3. Review job configuration
4. Check data volumes being processed
5. Review processing complexity

**Resolution:**

1. Optimize longest-running job
2. Split large jobs into smaller batches
3. Optimize queries and transformations
4. Scale resources if needed
5. Review and simplify processing logic
6. Adjust threshold if legitimate:
   ```bash
   ANALYTICS_ETL_MAX_DURATION_THRESHOLD=10800  # 3 hours
   ```

**Prevention:**

- Regular job performance reviews
- Optimize before deploying
- Monitor data volume growth
- Set up alerts for individual jobs
- Regular optimization reviews

---

### 4. Data Warehouse Freshness Alerts

#### Alert: Data warehouse freshness exceeded

**Alert Message:** `Data warehouse freshness exceeded: Xs (threshold: Ys)`

**Severity:** WARNING

**Alert Type:** `data_warehouse_freshness`

**What it means:**

- Data warehouse data is stale
- Time since last update exceeds `ANALYTICS_DATA_FRESHNESS_THRESHOLD` (default: 3600s = 1 hour)

**Common Causes:**

- ETL jobs not running
- ETL jobs failing
- Data source issues
- Database connection problems
- Processing delays

**Investigation Steps:**

1. Check last update timestamp:
   ```sql
   SELECT MAX(updated_at) as last_update,
          EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(updated_at)))::bigint as freshness_seconds
   FROM <data_warehouse_table>;
   ```
2. Check ETL job execution status
3. Review ETL job logs for errors
4. Check data source availability
5. Verify database connectivity

**Resolution:**

1. Trigger ETL job manually if needed
2. Fix ETL job failures
3. Resolve data source issues
4. Fix database connection problems
5. Review and optimize ETL processing
6. Adjust threshold if legitimate longer intervals:
   ```bash
   ANALYTICS_DATA_FRESHNESS_THRESHOLD=7200  # 2 hours
   ```

**Prevention:**

- Monitor ETL job execution
- Set up alerts for ETL failures
- Monitor data source availability
- Regular data freshness checks
- Document expected update frequency

---

#### Alert: No recent updates in data warehouse

**Alert Message:** `No recent updates in data warehouse detected`

**Severity:** WARNING

**Alert Type:** `data_warehouse_recent_updates`

**What it means:**

- No updates detected in data warehouse in the last hour
- Indicates ETL jobs may not be processing data

**Common Causes:**

- ETL jobs not running
- ETL jobs processing but not updating warehouse
- Data source empty
- Filtering out all data

**Investigation Steps:**

1. Check recent update count:
   ```sql
   SELECT COUNT(*)
   FROM <data_warehouse_table>
   WHERE updated_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';
   ```
2. Check ETL job execution
3. Review ETL job logs
4. Check data source

**Resolution:**

1. Trigger ETL job
2. Fix ETL job issues
3. Verify data source has data
4. Review ETL filtering logic

**Prevention:**

- Monitor update frequency
- Set up alerts for ETL execution
- Regular data source checks

---

### 5. Data Mart Status Alerts

#### Alert: Data mart update age exceeded

**Alert Message:** `Data mart update age exceeded: Xs (threshold: Ys)`

**Severity:** WARNING

**Alert Type:** `data_mart_update_age`

**What it means:**

- A data mart has not been updated recently
- Update age exceeds `ANALYTICS_DATA_MART_UPDATE_AGE_THRESHOLD` (default: 3600s = 1 hour)

**Common Causes:**

- ETL jobs not updating data mart
- Data mart ETL job failures
- Dependencies blocking updates
- Resource constraints

**Investigation Steps:**

1. Identify stale data mart:
   ```sql
   SELECT mart_name,
          last_update,
          EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - last_update))::bigint as age_seconds
   FROM <data_mart_table>
   ORDER BY age_seconds DESC;
   ```
2. Check data mart ETL job status
3. Review ETL job logs
4. Check dependencies

**Resolution:**

1. Trigger data mart update
2. Fix ETL job failures
3. Resolve dependencies
4. Fix resource constraints
5. Adjust threshold if needed

**Prevention:**

- Monitor data mart update frequency
- Set up alerts for ETL failures
- Document dependencies
- Regular health checks

---

#### Alert: Stale data marts detected

**Alert Message:** `Stale data marts detected: X mart(s) exceed freshness threshold`

**Severity:** WARNING

**Alert Type:** `data_mart_stale_count`

**What it means:**

- Multiple data marts are stale
- Number exceeds acceptable threshold

**Common Causes:**

- Widespread ETL job failures
- System-wide issues
- Resource constraints affecting all marts

**Investigation Steps:**

1. Count stale marts:
   ```sql
   SELECT COUNT(*)
   FROM <data_mart_table>
   WHERE last_update < CURRENT_TIMESTAMP - INTERVAL '1 hour';
   ```
2. Check system-wide ETL status
3. Review system resources
4. Check for system-wide issues

**Resolution:**

1. Fix system-wide issues
2. Trigger updates for all marts
3. Resolve resource constraints
4. Review ETL job scheduling

**Prevention:**

- Monitor system health
- Set up alerts for system issues
- Regular resource monitoring
- Capacity planning

---

#### Alert: Data mart update failures detected

**Alert Message:** `Data mart update failures detected: X mart(s) have update failures`

**Severity:** ERROR

**Alert Type:** `data_mart_failure`

**What it means:**

- Data mart update jobs are failing
- Failures detected in update process

**Common Causes:**

- Data quality issues
- Database errors
- Code bugs
- Resource constraints

**Investigation Steps:**

1. Identify failing marts
2. Review error logs
3. Check database errors
4. Review update job code

**Resolution:**

1. Fix data quality issues
2. Resolve database errors
3. Fix code bugs
4. Resolve resource constraints

**Prevention:**

- Comprehensive testing
- Data validation
- Error handling
- Resource monitoring

---

## General Troubleshooting

### Database Connection Issues

**Symptoms:**

- Alerts about database connection failures
- Metrics not being collected
- Queries timing out

**Investigation:**

1. Test connection:
   ```bash
   psql -h $DBHOST -p $DBPORT -U $DBUSER -d $ANALYTICS_DBNAME -c "SELECT 1;"
   ```
2. Check PostgreSQL status:
   ```bash
   systemctl status postgresql
   ```
3. Review PostgreSQL logs:
   ```bash
   tail -f /var/log/postgresql/postgresql-*.log
   ```

**Resolution:**

1. Restart PostgreSQL if needed
2. Fix network connectivity
3. Verify credentials
4. Check firewall rules

---

### Performance Issues

**Symptoms:**

- Slow query alerts
- High duration metrics
- System resource alerts

**Investigation:**

1. Check query performance:
   ```sql
   SELECT * FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 10;
   ```
2. Check system resources:
   ```bash
   top
   df -h
   free -h
   ```
3. Review slow queries

**Resolution:**

1. Optimize slow queries
2. Add indexes
3. Scale resources
4. Optimize ETL logic

---

## Alert Response Checklist

### For CRITICAL Alerts:

- [ ] Acknowledge alert immediately
- [ ] Escalate to on-call engineer
- [ ] Check system status
- [ ] Review recent changes
- [ ] Investigate root cause
- [ ] Implement fix
- [ ] Verify resolution
- [ ] Document incident

### For ERROR Alerts:

- [ ] Acknowledge alert within 30 minutes
- [ ] Check error logs
- [ ] Identify affected components
- [ ] Investigate cause
- [ ] Implement fix
- [ ] Verify resolution
- [ ] Document resolution

### For WARNING Alerts:

- [ ] Acknowledge alert within 1 hour
- [ ] Review metrics and trends
- [ ] Investigate if needed
- [ ] Implement fix if necessary
- [ ] Monitor resolution
- [ ] Document if recurring

### For INFO Alerts:

- [ ] Review within 24 hours
- [ ] Document trends
- [ ] Take action if needed
- [ ] Update documentation

---

## Prevention Strategies

### 1. Proactive Monitoring

- Set up dashboards for key metrics
- Regular review of trends
- Capacity planning
- Performance monitoring

### 2. Regular Maintenance

- Database maintenance (VACUUM, ANALYZE)
- Log rotation
- Old data archival
- Index optimization

### 3. Testing

- Test ETL jobs before deployment
- Performance testing
- Load testing
- Failure scenario testing

### 4. Documentation

- Document ETL job schedules
- Document dependencies
- Document thresholds
- Document resolution procedures

### 5. Automation

- Automated deployment
- Automated testing
- Automated monitoring
- Automated alerting

---

## Reference

### Related Documentation

- **[ANALYTICS_MONITORING_GUIDE.md](./Analytics_Monitoring_Guide.md)**: Complete monitoring guide
- **[ANALYTICS_METRICS.md](./Analytics_Metrics.md)**: Metric definitions
- **[ANALYTICS_ALERT_THRESHOLDS.md](./Analytics_Alert_Thresholds.md)**: Alert thresholds

### Useful Commands

```bash
# Check ETL scripts
ls -la ${ANALYTICS_REPO_PATH}/bin/*.sh

# Check ETL logs
tail -f ${ANALYTICS_LOG_DIR}/*.log

# Check running ETL processes
ps aux | grep -E "etl|extract|load|transform" | grep -v grep

# Check database connection
psql -d $ANALYTICS_DBNAME -c "SELECT 1;"

# Check recent metrics
psql -d osm_notes_monitoring -c "
  SELECT metric_name, metric_value, timestamp
  FROM metrics
  WHERE component = 'analytics'
  ORDER BY timestamp DESC
  LIMIT 20;
"

# Check active alerts
psql -d osm_notes_monitoring -c "
  SELECT alert_level, alert_type, message, created_at
  FROM alerts
  WHERE component = 'ANALYTICS'
    AND status = 'active'
  ORDER BY created_at DESC;
"
```

---

**Last Updated**: 2025-12-27  
**Version**: 1.0.0
