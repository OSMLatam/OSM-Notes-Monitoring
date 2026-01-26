---
title: "Ingestion Monitoring Troubleshooting Guide"
description: "Use this checklist to quickly identify common issues:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "troubleshooting"
  - "guide"
audience:
  - "users"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Ingestion Monitoring Troubleshooting Guide

> **Purpose:** Comprehensive troubleshooting guide for ingestion monitoring issues  
> **Version:** 1.0.0  
> **Date:** 2025-12-26  
> **Status:** Active

## Table of Contents

1. [Quick Diagnostic Checklist](#quick-diagnostic-checklist)
2. [Common Issues](#common-issues)
3. [Diagnostic Procedures](#diagnostic-procedures)
4. [System Health Checks](#system-health-checks)
5. [Database Troubleshooting](#database-troubleshooting)
6. [Configuration Issues](#configuration-issues)
7. [Performance Issues](#performance-issues)
8. [Alert Issues](#alert-issues)
9. [Log Analysis](#log-analysis)
10. [Recovery Procedures](#recovery-procedures)
11. [Prevention Strategies](#prevention-strategies)

---

## Quick Diagnostic Checklist

Use this checklist to quickly identify common issues:

- [ ] **Monitoring script runs**: `./bin/monitor/monitorIngestion.sh --dry-run`
- [ ] **Database accessible**: `psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1;"`
- [ ] **Configuration loaded**: Check `etc/properties.sh` and `config/monitoring.conf`
- [ ] **Ingestion repository accessible**: `ls -la ${INGESTION_REPO_PATH}/bin`
- [ ] **Logs readable**: `ls -la ${INGESTION_LOG_DIR}`
- [ ] **Scripts executable**: `ls -la ${INGESTION_REPO_PATH}/bin/*.sh`
- [ ] **Disk space available**: `df -h`
- [ ] **Permissions correct**: Check file permissions on scripts and configs
- [ ] **Environment variables set**: `env | grep -E "DB|INGESTION|LOG"`

---

## Common Issues

### Issue 1: Monitoring Script Not Running

**Symptoms:**

- No metrics being collected
- No logs generated
- Cron job not executing

**Diagnostic Steps:**

1. **Check script permissions:**

```bash
ls -la bin/monitor/monitorIngestion.sh
chmod +x bin/monitor/monitorIngestion.sh
```

2. **Test script execution:**

```bash
./bin/monitor/monitorIngestion.sh --dry-run --verbose
```

3. **Check cron job:**

```bash
crontab -l | grep monitorIngestion
```

4. **Check cron service:**

```bash
# Systemd
systemctl status cron
# Or
systemctl status crond

# Check cron logs
journalctl -u cron | tail -50
# Or
tail -50 /var/log/cron
```

5. **Check script syntax:**

```bash
bash -n bin/monitor/monitorIngestion.sh
```

**Solutions:**

- Fix permissions: `chmod +x bin/monitor/monitorIngestion.sh`
- Fix syntax errors if found
- Verify cron job syntax
- Restart cron service if needed
- Check PATH in cron environment

---

### Issue 2: Database Connection Errors

**Symptoms:**

- Errors: "could not connect to database"
- Errors: "authentication failed"
- Errors: "connection refused"

**Diagnostic Steps:**

1. **Check database server status:**

```bash
# Check if PostgreSQL is running
systemctl status postgresql
# Or
pg_isready -h ${DBHOST} -p ${DBPORT}
```

2. **Test database connection:**

```bash
psql -h ${DBHOST} -p ${DBPORT} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1;"
```

3. **Check credentials:**

```bash
# Check configuration
cat etc/properties.sh | grep -E "DBNAME|DBHOST|DBPORT|DBUSER"

# Check environment variable
echo $PGPASSWORD

# Check .pgpass file
cat ~/.pgpass
chmod 600 ~/.pgpass
```

4. **Check network connectivity:**

```bash
# Ping database host
ping -c 3 ${DBHOST}

# Check port accessibility
nc -zv ${DBHOST} ${DBPORT}
# Or
telnet ${DBHOST} ${DBPORT}
```

5. **Check PostgreSQL logs:**

```bash
# Find PostgreSQL log location
sudo find /var/log -name "*postgresql*.log" 2>/dev/null
# Or
sudo journalctl -u postgresql | tail -50
```

**Solutions:**

- Start PostgreSQL if stopped: `systemctl start postgresql`
- Fix credentials in `etc/properties.sh`
- Set `PGPASSWORD` environment variable
- Create/update `.pgpass` file:
  `echo "${DBHOST}:${DBPORT}:${DBNAME}:${DBUSER}:${PASSWORD}" >> ~/.pgpass`
- Fix network connectivity issues
- Check PostgreSQL `pg_hba.conf` for access rules
- Verify database user has required permissions

---

### Issue 3: Metrics Not Being Stored

**Symptoms:**

- Script runs successfully
- No errors in output
- No metrics in database

**Diagnostic Steps:**

1. **Verify database connection:**

```bash
# Test connection
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1;"
```

2. **Check database schema:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "\d metrics"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "\d alerts"
```

3. **Check user permissions:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'metrics';
"
```

4. **Run monitoring with verbose output:**

```bash
./bin/monitor/monitorIngestion.sh --verbose 2>&1 | tee /tmp/monitoring_debug.log
```

5. **Check monitoring logs:**

```bash
tail -100 ${LOG_DIR}/monitoring.log
tail -100 ${LOG_DIR}/ingestion.log
```

6. **Test metric storage manually:**

```bash
# Source monitoring functions
source bin/lib/monitoringFunctions.sh
source bin/lib/metricsFunctions.sh

# Test storing a metric
store_metric "ingestion" "test_metric" "100" "count" "null"

# Verify it was stored
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT * FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'test_metric'
ORDER BY timestamp DESC
LIMIT 1;
"
```

**Solutions:**

- Fix database connection issues
- Create missing tables: Run `sql/schema.sql`
- Grant INSERT permissions: `GRANT INSERT ON metrics TO ${DBUSER};`
- Fix configuration errors
- Check for errors in verbose output
- Verify monitoring functions are sourced correctly

---

### Issue 4: Scripts Not Found

**Symptoms:**

- Alert: "Low number of scripts found"
- `scripts_found` metric is low
- Scripts exist but not detected

**Diagnostic Steps:**

1. **Check repository path:**

```bash
echo $INGESTION_REPO_PATH
ls -la ${INGESTION_REPO_PATH}
```

2. **Check scripts directory:**

```bash
ls -la ${INGESTION_REPO_PATH}/bin/
```

3. **Check expected scripts:**

```bash
# Check scripts in process/ directory
for script in processAPINotes.sh processAPINotesDaemon.sh processPlanetNotes.sh updateCountries.sh; do
    if [ -f "${INGESTION_REPO_PATH}/bin/process/${script}" ]; then
        echo "✓ Found: process/${script}"
    else
        echo "✗ Missing: process/${script}"
    fi
done

# Check scripts in monitor/ directory
for script in notesCheckVerifier.sh processCheckPlanetNotes.sh analyzeDatabasePerformance.sh; do
    if [ -f "${INGESTION_REPO_PATH}/bin/monitor/${script}" ]; then
        echo "✓ Found: monitor/${script}"
    else
        echo "✗ Missing: monitor/${script}"
    fi
done
```

4. **Check script permissions:**

```bash
ls -la ${INGESTION_REPO_PATH}/bin/*.sh
```

5. **Verify configuration:**

```bash
grep INGESTION_REPO_PATH config/monitoring.conf
```

**Solutions:**

- Fix `INGESTION_REPO_PATH` in `config/monitoring.conf`
- Restore missing scripts from version control
- Update repository: `cd ${INGESTION_REPO_PATH} && git pull`
- Fix script permissions: `chmod +x ${INGESTION_REPO_PATH}/bin/*.sh`
- Check for symlink issues
- Verify repository is properly cloned

---

### Issue 5: High Error Rates

**Symptoms:**

- Alert: "High error rate detected"
- `error_rate_percent` metric is high
- Many errors in logs

**Diagnostic Steps:**

1. **Check error count:**

```bash
grep -i error ${INGESTION_LOG_DIR}/*.log | wc -l
```

2. **Review recent errors:**

```bash
grep -i error ${INGESTION_LOG_DIR}/*.log | tail -50
```

3. **Identify error patterns:**

```bash
grep -i error ${INGESTION_LOG_DIR}/*.log | \
    sed 's/.*ERROR: //' | \
    sort | uniq -c | sort -rn | head -20
```

4. **Check database connectivity:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1;"
```

5. **Check system resources:**

```bash
# Disk space
df -h

# Memory
free -h

# CPU
top -bn1 | head -20
```

6. **Check API connectivity (if applicable):**

```bash
curl -I ${API_URL}
```

**Solutions:**

- Fix root cause based on error patterns
- Restart affected services
- Fix database connectivity issues
- Free up disk space
- Fix API connectivity issues
- Update configuration if needed
- Review and fix code issues causing errors

---

### Issue 6: Alerts Not Being Sent

**Symptoms:**

- Alerts stored in database
- No email/Slack notifications received
- Alert delivery failing

**Diagnostic Steps:**

1. **Check alert configuration:**

```bash
grep -E "SEND_ALERT_EMAIL|SLACK_ENABLED|ADMIN_EMAIL" config/alerts.conf
```

2. **Check if alerts are stored:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT alert_level, message, timestamp
FROM alerts
WHERE component = 'INGESTION'
ORDER BY timestamp DESC
LIMIT 10;
"
```

3. **Test email sending:**

```bash
# Test mail command
echo "Test alert" | mail -s "Test Alert" ${ADMIN_EMAIL}

# Test mutt (if configured)
echo "Test alert" | mutt -s "Test Alert" ${ADMIN_EMAIL}
```

4. **Test Slack webhook (if configured):**

```bash
curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test alert"}' \
    ${SLACK_WEBHOOK_URL}
```

5. **Check alert logs:**

```bash
grep -i alert ${LOG_DIR}/*.log | tail -50
```

**Solutions:**

- Enable email alerts: `SEND_ALERT_EMAIL="true"` in `config/alerts.conf`
- Configure email server (SMTP settings)
- Install and configure mail client (`mail` or `mutt`)
- Configure Slack webhook URL
- Check email server connectivity
- Verify email addresses are correct
- Check alert deduplication settings

---

## Diagnostic Procedures

### Procedure 1: Complete System Health Check

Run this comprehensive check to assess overall system health:

```bash
#!/bin/bash
# Complete system health check

echo "=== System Health Check ==="
echo

echo "1. Database Connection:"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1;" && echo "✓ OK" || echo "✗ FAILED"
echo

echo "2. Repository Path:"
[ -d "${INGESTION_REPO_PATH}" ] && echo "✓ OK: ${INGESTION_REPO_PATH}" || echo "✗ FAILED: ${INGESTION_REPO_PATH}"
echo

echo "3. Scripts Found:"
# Check for expected 7 scripts
expected_scripts=(
    "process/processAPINotes.sh"
    "process/processAPINotesDaemon.sh"
    "process/processPlanetNotes.sh"
    "process/updateCountries.sh"
    "monitor/notesCheckVerifier.sh"
    "monitor/processCheckPlanetNotes.sh"
    "monitor/analyzeDatabasePerformance.sh"
)
scripts_found=0
for script in "${expected_scripts[@]}"; do
    if [ -f "${INGESTION_REPO_PATH}/bin/${script}" ]; then
        scripts_found=$((scripts_found + 1))
    fi
done
echo "  Found: ${scripts_found}/7 expected scripts"
[ ${scripts_found} -ge 7 ] && echo "✓ OK" || echo "✗ WARNING: Less than 7 scripts found"
echo

echo "4. Script Permissions:"
non_executable=$(find ${INGESTION_REPO_PATH}/bin -name "*.sh" ! -executable 2>/dev/null | wc -l)
[ ${non_executable} -eq 0 ] && echo "✓ OK" || echo "✗ WARNING: ${non_executable} scripts not executable"
echo

echo "5. Log Directory:"
[ -d "${INGESTION_LOG_DIR}" ] && echo "✓ OK: ${INGESTION_LOG_DIR}" || echo "✗ FAILED: ${INGESTION_LOG_DIR}"
echo

echo "6. Disk Space:"
disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
echo "  Usage: ${disk_usage}%"
[ ${disk_usage} -lt 90 ] && echo "✓ OK" || echo "✗ WARNING: Disk usage above 90%"
echo

echo "7. Recent Metrics:"
recent_metrics=$(psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -t -c "
SELECT COUNT(*) FROM metrics
WHERE component = 'ingestion'
  AND timestamp > NOW() - INTERVAL '1 hour';
" 2>/dev/null | tr -d ' ')
echo "  Metrics in last hour: ${recent_metrics}"
[ -n "${recent_metrics}" ] && [ ${recent_metrics} -gt 0 ] && echo "✓ OK" || echo "✗ WARNING: No recent metrics"
echo

echo "8. Recent Errors:"
error_count=$(grep -i error ${INGESTION_LOG_DIR}/*.log 2>/dev/null | wc -l)
echo "  Errors in logs: ${error_count}"
[ ${error_count} -lt 100 ] && echo "✓ OK" || echo "✗ WARNING: High error count"
echo
```

### Procedure 2: Database Diagnostic

```bash
#!/bin/bash
# Database diagnostic procedure

echo "=== Database Diagnostic ==="
echo

echo "1. Database Server Status:"
pg_isready -h ${DBHOST} -p ${DBPORT} && echo "✓ Ready" || echo "✗ Not ready"
echo

echo "2. Connection Test:"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT version();" && echo "✓ Connected" || echo "✗ Connection failed"
echo

echo "3. Schema Check:"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "\d metrics" > /dev/null 2>&1 && echo "✓ Metrics table exists" || echo "✗ Metrics table missing"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "\d alerts" > /dev/null 2>&1 && echo "✓ Alerts table exists" || echo "✗ Alerts table missing"
echo

echo "4. Permissions Check:"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'metrics' AND grantee = '${DBUSER}';
"
echo

echo "5. Recent Activity:"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    COUNT(*) as total_metrics,
    MAX(timestamp) as latest_metric
FROM metrics
WHERE component = 'ingestion';
"
echo

echo "6. Database Size:"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    pg_size_pretty(pg_database_size('${DBNAME}')) as database_size;
"
echo
```

### Procedure 3: Configuration Validation

```bash
#!/bin/bash
# Configuration validation procedure

echo "=== Configuration Validation ==="
echo

echo "1. Required Files:"
for file in etc/properties.sh config/monitoring.conf config/alerts.conf; do
    [ -f "${file}" ] && echo "✓ ${file}" || echo "✗ Missing: ${file}"
done
echo

echo "2. Database Configuration:"
source etc/properties.sh 2>/dev/null
[ -n "${DBNAME}" ] && echo "✓ DBNAME: ${DBNAME}" || echo "✗ DBNAME not set"
[ -n "${DBHOST}" ] && echo "✓ DBHOST: ${DBHOST}" || echo "✗ DBHOST not set"
[ -n "${DBPORT}" ] && echo "✓ DBPORT: ${DBPORT}" || echo "✗ DBPORT not set"
[ -n "${DBUSER}" ] && echo "✓ DBUSER: ${DBUSER}" || echo "✗ DBUSER not set"
echo

echo "3. Ingestion Configuration:"
source config/monitoring.conf 2>/dev/null
[ -n "${INGESTION_REPO_PATH}" ] && echo "✓ INGESTION_REPO_PATH: ${INGESTION_REPO_PATH}" || echo "✗ INGESTION_REPO_PATH not set"
[ -n "${INGESTION_LOG_DIR}" ] && echo "✓ INGESTION_LOG_DIR: ${INGESTION_LOG_DIR}" || echo "✗ INGESTION_LOG_DIR not set"
[ "${INGESTION_ENABLED}" = "true" ] && echo "✓ Ingestion monitoring enabled" || echo "✗ Ingestion monitoring disabled"
echo

echo "4. Alert Configuration:"
source config/alerts.conf 2>/dev/null
[ "${SEND_ALERT_EMAIL}" = "true" ] && echo "✓ Email alerts enabled" || echo "✗ Email alerts disabled"
[ -n "${ADMIN_EMAIL}" ] && echo "✓ ADMIN_EMAIL: ${ADMIN_EMAIL}" || echo "✗ ADMIN_EMAIL not set"
[ "${SLACK_ENABLED}" = "true" ] && echo "✓ Slack alerts enabled" || echo "✗ Slack alerts disabled"
echo
```

---

## System Health Checks

### Check 1: Verify Monitoring Script Execution

```bash
# Run monitoring script in dry-run mode
./bin/monitor/monitorIngestion.sh --dry-run --verbose

# Check exit code
echo $?
# Should be 0 for success
```

### Check 2: Verify Metrics Collection

```bash
# Check if metrics are being collected
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    metric_name,
    COUNT(*) as count,
    MAX(timestamp) as latest
FROM metrics
WHERE component = 'ingestion'
GROUP BY metric_name
ORDER BY latest DESC;
"
```

### Check 3: Verify Alert Generation

```bash
# Check recent alerts
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    alert_level,
    message,
    timestamp
FROM alerts
WHERE component = 'INGESTION'
ORDER BY timestamp DESC
LIMIT 10;
"
```

---

## Database Troubleshooting

### Issue: Database Connection Timeout

**Symptoms:**

- Connection attempts timeout
- Slow database responses

**Solutions:**

1. **Check database server load:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    count(*) as active_connections,
    count(*) FILTER (WHERE state = 'active') as active_queries
FROM pg_stat_activity;
"
```

2. **Check for locks:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT * FROM pg_locks WHERE NOT granted;
"
```

3. **Check slow queries:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';
"
```

### Issue: Database Performance Degradation

**Solutions:**

1. **Analyze table sizes:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"
```

2. **Check indexes:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
"
```

3. **Vacuum and analyze:**

```bash
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "VACUUM ANALYZE metrics;"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "VACUUM ANALYZE alerts;"
```

---

## Configuration Issues

### Issue: Configuration Not Loading

**Symptoms:**

- Default values being used
- Configuration changes not taking effect

**Solutions:**

1. **Check configuration file syntax:**

```bash
# Check for syntax errors
bash -n etc/properties.sh
bash -n config/monitoring.conf
bash -n config/alerts.conf
```

2. **Verify configuration is sourced:**

```bash
# Add debug output to scripts
set -x
source etc/properties.sh
set +x
```

3. **Check for conflicting environment variables:**

```bash
env | grep -E "DB|INGESTION|LOG|ALERT"
```

---

## Performance Issues

### Issue: Monitoring Overhead Too High

**Solutions:**

1. **Measure execution time:**

```bash
time ./bin/monitor/monitorIngestion.sh
```

2. **Run performance tests:**

```bash
./tests/performance/test_monitoring_overhead.sh
```

3. **Reduce monitoring frequency:**

```bash
# Change cron from every 15 minutes to hourly
# */15 * * * * -> 0 * * * *
```

4. **Disable non-critical checks:**

```bash
# Comment out checks in monitoring script
# Or create a lightweight monitoring script
```

---

## Alert Issues

### Issue: Too Many Alerts (Alert Fatigue)

**Solutions:**

1. **Enable alert deduplication:**

```bash
# In config/alerts.conf
ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW=3600
```

2. **Adjust alert thresholds:**

```bash
# Increase thresholds in config/monitoring.conf
INGESTION_MAX_ERROR_RATE=10  # Was 5
INGESTION_ERROR_COUNT_THRESHOLD=2000  # Was 1000
```

3. **Review and acknowledge alerts:**

```bash
# Mark alerts as acknowledged
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
UPDATE alerts
SET status = 'acknowledged'
WHERE component = 'INGESTION'
  AND status = 'active';
"
```

---

## Log Analysis

### Analyzing Monitoring Logs

```bash
# View recent monitoring logs
tail -100 ${LOG_DIR}/monitoring.log

# Search for errors
grep -i error ${LOG_DIR}/*.log

# Search for warnings
grep -i warning ${LOG_DIR}/*.log

# Count errors by type
grep -i error ${LOG_DIR}/*.log | \
    sed 's/.*ERROR: //' | \
    sort | uniq -c | sort -rn
```

### Analyzing Ingestion Logs

```bash
# View recent ingestion logs
tail -100 ${INGESTION_LOG_DIR}/*.log

# Find most common errors
grep -i error ${INGESTION_LOG_DIR}/*.log | \
    awk -F: '{print $NF}' | \
    sort | uniq -c | sort -rn | head -20

# Check log file sizes
ls -lh ${INGESTION_LOG_DIR}/*.log

# Check log rotation
logrotate -d /etc/logrotate.d/ingestion
```

---

## Recovery Procedures

### Recovery 1: Restore Missing Scripts

```bash
# 1. Check repository status
cd ${INGESTION_REPO_PATH}
git status

# 2. Restore from version control
git checkout HEAD -- bin/processAPINotes.sh
git checkout HEAD -- bin/processPlanetNotes.sh
# ... restore other scripts

# 3. Fix permissions
chmod +x bin/*.sh

# 4. Verify
ls -la bin/*.sh
```

### Recovery 2: Rebuild Database Schema

```bash
# 1. Backup existing data (if needed)
pg_dump -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} > backup_$(date +%Y%m%d).sql

# 2. Drop and recreate tables
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -f sql/schema.sql

# 3. Verify schema
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "\d metrics"
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "\d alerts"
```

### Recovery 3: Reset Monitoring State

```bash
# 1. Stop monitoring (if running via cron)
crontab -l | grep -v monitorIngestion | crontab -

# 2. Clear old metrics (optional, be careful!)
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
DELETE FROM metrics
WHERE component = 'ingestion'
  AND timestamp < NOW() - INTERVAL '90 days';
"

# 3. Clear old alerts (optional)
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
DELETE FROM alerts
WHERE component = 'INGESTION'
  AND status = 'resolved'
  AND timestamp < NOW() - INTERVAL '30 days';
"

# 4. Restart monitoring
crontab -e  # Add monitoring job back
```

---

## Prevention Strategies

### 1. Regular Health Checks

Set up automated health checks:

```bash
# Add to cron: Daily health check
0 2 * * * /path/to/health_check.sh | mail -s "Daily Health Check" ${ADMIN_EMAIL}
```

### 2. Monitoring Monitoring

Monitor the monitoring system itself:

```bash
# Check if monitoring is running
ps aux | grep monitorIngestion

# Check recent metrics
psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "
SELECT COUNT(*)
FROM metrics
WHERE component = 'ingestion'
  AND timestamp > NOW() - INTERVAL '1 hour';
"
```

### 3. Configuration Management

- Use version control for configuration files
- Document all configuration changes
- Test configuration changes in staging first
- Keep configuration backups

### 4. Regular Maintenance

- Clean old metrics regularly
- Rotate logs
- Vacuum database tables
- Review and update thresholds based on trends

---

## Getting Help

If issues persist:

1. **Review Documentation:**
   - [INGESTION_MONITORING_GUIDE.md](./Ingestion_Monitoring_Guide.md)
   - [INGESTION_ALERT_RUNBOOK.md](./INGESTION_ALERT_Runbook.md)
   - [INGESTION_METRICS.md](./Ingestion_Metrics.md)

2. **Check Logs:**
   - Monitoring logs: `${LOG_DIR}/monitoring.log`
   - Ingestion logs: `${INGESTION_LOG_DIR}/*.log`
   - System logs: `journalctl` or `/var/log/syslog`

3. **Run Diagnostics:**
   - Use diagnostic procedures above
   - Run test suites: `./tests/integration/test_monitorIngestion_integration.sh`

4. **Escalate:**
   - Document the issue with diagnostic output
   - Create GitHub issue with details
   - Contact team lead if critical

---

**Last Updated**: 2025-12-26  
**Version**: 1.0.0
