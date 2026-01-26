---
title: "Production Troubleshooting Guide"
description: "Comprehensive troubleshooting guide for OSM-Notes-Monitoring production issues."
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


# Production Troubleshooting Guide

> **Last Updated:** 2026-01-01  
> **Version:** 1.0.0

Comprehensive troubleshooting guide for OSM-Notes-Monitoring production issues.

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Common Issues](#common-issues)
3. [Database Issues](#database-issues)
4. [Monitoring Issues](#monitoring-issues)
5. [Alert Issues](#alert-issues)
6. [Performance Issues](#performance-issues)
7. [Recovery Procedures](#recovery-procedures)

---

## Quick Diagnostics

### System Health Check

Run comprehensive validation:

```bash
./scripts/validate_production.sh
```

### Quick Status Check

```bash
# Check database
psql -d notes_monitoring -c "SELECT 1;"

# Check cron jobs
crontab -l | grep OSM-Notes-Monitoring

# Check recent logs
tail -20 /var/log/osm-notes-monitoring/*.log

# Check disk space
df -h

# Check recent alerts
psql -d notes_monitoring -c "SELECT * FROM alerts ORDER BY created_at DESC LIMIT 10;"
```

---

## Common Issues

### Issue: Scripts Not Executing

**Symptoms**: No metrics, empty logs, cron jobs not running

**Diagnosis**:

```bash
# Check cron service
systemctl status cron

# Check cron jobs
crontab -l

# Check cron logs
grep CRON /var/log/syslog | tail -20

# Test script manually
./bin/monitor/monitorIngestion.sh
```

**Solutions**:

1. **Cron Service Down**:

   ```bash
   sudo systemctl start cron
   sudo systemctl enable cron
   ```

2. **Script Permissions**:

   ```bash
   chmod +x bin/monitor/*.sh
   ```

3. **Path Issues**:

   ```bash
   # Verify paths in cron jobs
   crontab -e
   # Use absolute paths
   ```

4. **Environment Variables**:
   ```bash
   # Add environment variables to cron
   crontab -e
   # Add: PATH=/usr/local/bin:/usr/bin:/bin
   ```

### Issue: Database Connection Failed

**Symptoms**: `Cannot connect to database`, `Connection refused`

**Diagnosis**:

```bash
# Test connection
psql -d notes_monitoring -c "SELECT 1;"

# Check PostgreSQL status
systemctl status postgresql

# Check PostgreSQL logs
tail -50 /var/log/postgresql/postgresql-*.log

# Verify credentials
cat etc/properties.sh | grep DB
```

**Solutions**:

1. **PostgreSQL Not Running**:

   ```bash
   sudo systemctl start postgresql
   sudo systemctl enable postgresql
   ```

2. **Wrong Credentials**:

   ```bash
   # Update etc/properties.sh
   nano etc/properties.sh
   ```

3. **Database Doesn't Exist**:

   ```bash
   # Create database
   createdb notes_monitoring

   # Initialize schema
   psql -d notes_monitoring -f sql/init.sql
   ```

4. **Connection Limits**:
   ```bash
   # Check PostgreSQL max_connections
   psql -d notes_monitoring -c "SHOW max_connections;"
   ```

### Issue: Configuration Errors

**Symptoms**: `Configuration validation failed`, scripts fail with config errors

**Diagnosis**:

```bash
# Run validation
./scripts/test_config_validation.sh

# Check for default values
grep -r "example.com\|changeme\|password" etc/ config/ --exclude="*.example"

# Check file syntax
bash -n etc/properties.sh
bash -n config/*.conf
```

**Solutions**:

1. **Missing Configuration**:

   ```bash
   # Copy from examples
   cp etc/properties.sh.example etc/properties.sh
   cp config/monitoring.conf.example config/monitoring.conf
   ```

2. **Invalid Values**:

   ```bash
   # Review and fix configuration
   nano etc/properties.sh
   ```

3. **Syntax Errors**:
   ```bash
   # Check syntax
   bash -n etc/properties.sh
   ```

---

## Database Issues

### Issue: Database Full

**Symptoms**: `No space left on device`, database errors

**Diagnosis**:

```bash
# Check database size
psql -d notes_monitoring -c "SELECT pg_size_pretty(pg_database_size('notes_monitoring'));"

# Check disk space
df -h

# Check table sizes
psql -d notes_monitoring -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"

# Check metrics count
psql -d notes_monitoring -c "SELECT COUNT(*) FROM metrics;"
```

**Solutions**:

1. **Clean Old Metrics**:

   ```bash
   # Run cleanup
   psql -d notes_monitoring -c "SELECT cleanup_old_metrics();"
   psql -d notes_monitoring -c "SELECT cleanup_old_alerts();"
   ```

2. **Manual Cleanup**:

   ```bash
   # Delete old metrics (be careful!)
   psql -d notes_monitoring -c "DELETE FROM metrics WHERE timestamp < NOW() - INTERVAL '90 days';"
   ```

3. **Increase Disk Space**:
   ```bash
   # Add disk space or move database
   ```

### Issue: Slow Queries

**Symptoms**: Scripts take long time, database slow

**Diagnosis**:

```bash
# Check slow queries
psql -d notes_monitoring -c "SELECT query, calls, total_time, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# Check indexes
psql -d notes_monitoring -c "\di"

# Analyze tables
psql -d notes_monitoring -c "ANALYZE;"
```

**Solutions**:

1. **Add Indexes**:

   ```bash
   # Review sql/optimize_queries.sql
   psql -d notes_monitoring -f sql/optimize_queries.sql
   ```

2. **Vacuum Database**:

   ```bash
   psql -d notes_monitoring -c "VACUUM ANALYZE;"
   ```

3. **Review Queries**:
   ```bash
   ./scripts/analyze_query_performance.sh
   ```

---

## Monitoring Issues

### Issue: No Metrics Collected

**Symptoms**: Empty metrics table, dashboards show no data

**Diagnosis**:

```bash
# Check metrics count
psql -d notes_monitoring -c "SELECT COUNT(*) FROM metrics;"

# Check recent metrics
psql -d notes_monitoring -c "SELECT * FROM metrics ORDER BY timestamp DESC LIMIT 10;"

# Check script execution
./bin/monitor/monitorIngestion.sh

# Check logs
tail -50 /var/log/osm-notes-monitoring/ingestion.log
```

**Solutions**:

1. **Scripts Not Running**:

   ```bash
   # Check cron jobs
   crontab -l

   # Run manually
   ./bin/monitor/monitorIngestion.sh
   ```

2. **Database Write Issues**:

   ```bash
   # Test database write
   psql -d notes_monitoring -c "INSERT INTO metrics (component, name, value, unit) VALUES ('test', 'test', 1, 'count');"
   ```

3. **Script Errors**:
   ```bash
   # Check script output
   ./bin/monitor/monitorIngestion.sh 2>&1 | tee /tmp/test.log
   ```

### Issue: Incorrect Metrics

**Symptoms**: Metrics values seem wrong, alerts firing incorrectly

**Diagnosis**:

```bash
# Check recent metrics
psql -d notes_monitoring -c "SELECT * FROM metrics WHERE component = 'ingestion' ORDER BY timestamp DESC LIMIT 20;"

# Compare with source
# Check monitored system directly
```

**Solutions**:

1. **Review Script Logic**:

   ```bash
   # Review monitoring script
   nano bin/monitor/monitorIngestion.sh
   ```

2. **Check Source Data**:

   ```bash
   # Verify source data is correct
   # Check monitored database/API
   ```

3. **Adjust Thresholds**:
   ```bash
   # Review thresholds
   nano config/monitoring.conf
   ```

---

## Alert Issues

### Issue: Alerts Not Sending

**Symptoms**: No email/Slack notifications, alerts in database but not delivered

**Diagnosis**:

```bash
# Check alert configuration
cat config/alerts.conf

# Check alerts in database
psql -d notes_monitoring -c "SELECT * FROM alerts ORDER BY created_at DESC LIMIT 10;"

# Test alert manually
./bin/alerts/sendAlert.sh "TEST" "Test alert" "INFO"

# Check email configuration
echo "test" | mutt -s "test" admin@example.com
```

**Solutions**:

1. **Email Not Configured**:

   ```bash
   # Update config
   nano config/alerts.conf
   # Set: SEND_ALERT_EMAIL="true"
   # Set: ADMIN_EMAIL="your@email.com"
   ```

2. **Mutt Not Installed**:

   ```bash
   sudo apt-get install mutt
   # Or configure sendmail/postfix
   ```

3. **Slack Webhook Wrong**:
   ```bash
   # Update webhook URL
   nano config/alerts.conf
   # Set: SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
   ```

### Issue: Too Many Alerts

**Symptoms**: Alert storm, too many notifications

**Diagnosis**:

```bash
# Count alerts
psql -d notes_monitoring -c "SELECT COUNT(*) FROM alerts WHERE created_at > NOW() - INTERVAL '1 hour';"

# Check alert patterns
psql -d notes_monitoring -c "SELECT component, message, COUNT(*) FROM alerts WHERE created_at > NOW() - INTERVAL '1 hour' GROUP BY component, message ORDER BY COUNT(*) DESC;"
```

**Solutions**:

1. **Temporarily Disable Alerts**:

   ```bash
   nano config/alerts.conf
   # Set: SEND_ALERT_EMAIL="false"
   ```

2. **Adjust Thresholds**:

   ```bash
   # Review thresholds
   nano config/monitoring.conf
   # Increase thresholds to reduce false positives
   ```

3. **Fix Root Cause**:
   ```bash
   # Investigate why alerts are firing
   # Fix underlying issue
   ```

---

## Performance Issues

### Issue: Scripts Running Slow

**Symptoms**: Scripts take too long, system slow

**Diagnosis**:

```bash
# Time script execution
time ./bin/monitor/monitorIngestion.sh

# Check system resources
top
free -h
df -h

# Check database performance
psql -d notes_monitoring -c "SELECT * FROM pg_stat_activity WHERE state = 'active';"
```

**Solutions**:

1. **Optimize Database**:

   ```bash
   # Run optimizations
   psql -d notes_monitoring -f sql/optimize_queries.sql
   psql -d notes_monitoring -c "VACUUM ANALYZE;"
   ```

2. **Reduce Monitoring Frequency**:

   ```bash
   # Update cron jobs
   crontab -e
   # Increase intervals
   ```

3. **Add Resources**:
   ```bash
   # Increase database resources
   # Add more RAM/CPU
   ```

### Issue: High CPU/Memory Usage

**Symptoms**: System slow, high resource usage

**Diagnosis**:

```bash
# Check processes
ps aux | grep monitor

# Check system resources
top
htop

# Check database connections
psql -d notes_monitoring -c "SELECT COUNT(*) FROM pg_stat_activity;"
```

**Solutions**:

1. **Reduce Monitoring Frequency**:

   ```bash
   # Update cron intervals
   crontab -e
   ```

2. **Optimize Scripts**:

   ```bash
   # Review script performance
   # Optimize database queries
   ```

3. **Limit Database Connections**:
   ```bash
   # Review connection pooling
   # Limit concurrent connections
   ```

---

## Recovery Procedures

### Database Corruption

**Symptoms**: Database errors, data corruption

**Recovery**:

```bash
# 1. Stop monitoring
./scripts/setup_cron.sh --remove

# 2. Create current backup (if possible)
./sql/backups/backup_database.sh -c

# 3. Restore from known good backup
./sql/backups/restore_database.sh -f backup_file.sql.gz

# 4. Verify restore
psql -d notes_monitoring -c "SELECT COUNT(*) FROM metrics;"

# 5. Restart monitoring
./scripts/setup_cron.sh --install
```

### Complete System Failure

**Recovery**:

```bash
# 1. Restore from backup
./sql/backups/restore_database.sh -f latest_backup.sql.gz

# 2. Re-run deployment
./scripts/deploy_production.sh --skip-setup

# 3. Verify
./scripts/validate_production.sh

# 4. Restart monitoring
./scripts/setup_cron.sh --install
```

### Configuration Loss

**Recovery**:

```bash
# 1. Restore from git (if version controlled)
git checkout etc/properties.sh
git checkout config/*.conf

# 2. Or restore from backup
cp etc/properties.sh.backup etc/properties.sh

# 3. Update with production values
nano etc/properties.sh

# 4. Validate
./scripts/test_config_validation.sh
```

---

## Getting Help

If issues persist:

1. **Check Logs**: `/var/log/osm-notes-monitoring/`
2. **Run Diagnostics**: `./scripts/validate_production.sh`
3. **Review Documentation**: `docs/`
4. **Check GitHub Issues**: https://github.com/OSM-Notes/OSM-Notes-Monitoring/issues
5. **Contact Support**: See project README

---

**Last Updated:** 2026-01-01
