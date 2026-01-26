---
title: "Operations Runbook"
description: "Operations runbook for OSM-Notes-Monitoring production system."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "documentation"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Operations Runbook

> **Last Updated:** 2026-01-07  
> **Version:** 1.0.0

Operations runbook for OSM-Notes-Monitoring production system.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Weekly Operations](#weekly-operations)
3. [Monthly Operations](#monthly-operations)
4. [Common Tasks](#common-tasks)
5. [Emergency Procedures](#emergency-procedures)
6. [On-Call Procedures](#on-call-procedures)
7. [Maintenance Windows](#maintenance-windows)
8. [Ongoing Maintenance Plan](#ongoing-maintenance-plan)

---

## Daily Operations

### Morning Checks

**Time**: 09:00 AM

1. **Check System Health**:

   ```bash
   ./scripts/validate_production.sh
   ```

2. **Review Overnight Alerts**:

   ```bash
   psql -d notes_monitoring -c "SELECT * FROM alerts WHERE created_at > NOW() - INTERVAL '12 hours' ORDER BY created_at DESC;"
   ```

3. **Check Logs for Errors**:

   ```bash
   grep -i error /var/log/osm-notes-monitoring/*.log | tail -20
   ```

4. **Verify Monitoring Running**:
   ```bash
   crontab -l | grep OSM-Notes-Monitoring
   ```

### Afternoon Checks

**Time**: 02:00 PM

1. **Review Metrics**:

   ```bash
   psql -d notes_monitoring -c "SELECT component, COUNT(*) FROM metrics WHERE timestamp > NOW() - INTERVAL '6 hours' GROUP BY component;"
   ```

2. **Check Dashboard Status**:
   ```bash
   # Open dashboards
   open dashboards/html/overview.html
   ```

### Evening Checks

**Time**: 06:00 PM

1. **Review Day's Activity**:

   ```bash
   psql -d notes_monitoring -c "SELECT component, COUNT(*) FROM metrics WHERE timestamp > NOW() - INTERVAL '12 hours' GROUP BY component;"
   ```

2. **Check for Pending Issues**:
   ```bash
   psql -d notes_monitoring -c "SELECT * FROM alerts WHERE status = 'OPEN' ORDER BY created_at DESC;"
   ```

---

## Weekly Operations

### Monday: System Review

1. **Review Weekly Metrics**:

   ```bash
   psql -d notes_monitoring -c "SELECT component, COUNT(*) FROM metrics WHERE timestamp > NOW() - INTERVAL '7 days' GROUP BY component;"
   ```

2. **Check Alert Trends**:

   ```bash
   psql -d notes_monitoring -c "SELECT severity, COUNT(*) FROM alerts WHERE created_at > NOW() - INTERVAL '7 days' GROUP BY severity;"
   ```

3. **Review Log Sizes**:
   ```bash
   du -sh /var/log/osm-notes-monitoring/
   ```

### Wednesday: Configuration Review

1. **Review Alert Thresholds**:

   ```bash
   cat config/monitoring.conf | grep THRESHOLD
   ```

2. **Check Configuration Changes**:
   ```bash
   git log --oneline --since="7 days ago" -- etc/ config/
   ```

### Friday: Backup Verification

1. **Verify Backups**:

   ```bash
   ./scripts/setup_backups.sh --list
   ls -lh sql/backups/
   ```

2. **Test Backup Restore** (on test database):

   ```bash
   # Create test database
   createdb notes_monitoring_test

   # Restore latest backup
   ./sql/backups/restore_database.sh -d notes_monitoring_test -f sql/backups/latest_backup.sql.gz
   ```

---

## Monthly Operations

### First Monday: Security Audit

1. **Run Security Audit**:

   ```bash
   ./scripts/security_audit.sh --report
   ```

2. **Review Security Report**:

   ```bash
   ls -lt reports/security_audit_*.txt | head -1 | xargs cat
   ```

3. **Apply Security Updates**:
   ```bash
   ./scripts/security_hardening.sh --apply
   ```

### Mid-Month: Performance Review

1. **Review Query Performance**:

   ```bash
   ./scripts/analyze_query_performance.sh
   ```

2. **Check Database Size**:

   ```bash
   psql -d notes_monitoring -c "SELECT pg_size_pretty(pg_database_size('notes_monitoring'));"
   ```

3. **Review Metrics Retention**:
   ```bash
   psql -d notes_monitoring -c "SELECT MIN(timestamp), MAX(timestamp) FROM metrics;"
   ```

### Last Friday: Documentation Update

1. **Review Documentation**:
   - Update runbooks with lessons learned
   - Document any custom configurations
   - Update troubleshooting guides

2. **Archive Old Reports**:
   ```bash
   # Archive reports older than 90 days
   find reports/ -type f -mtime +90 -exec mv {} archive/ \;
   ```

---

## Common Tasks

### Add New Monitoring Check

1. **Create Script**:

   ```bash
   # Create new monitoring script
   nano bin/monitor/monitorNewComponent.sh
   ```

2. **Add to Cron**:

   ```bash
   # Edit crontab
   crontab -e

   # Add new job
   */5 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorNewComponent.sh >> /var/log/osm-notes-monitoring/newcomponent.log 2>&1
   ```

3. **Test**:
   ```bash
   ./bin/monitor/monitorNewComponent.sh
   ```

### Update Alert Thresholds

1. **Edit Configuration**:

   ```bash
   nano config/monitoring.conf
   ```

2. **Reload Configuration**:
   ```bash
   # Configuration is loaded on each script execution
   # No reload needed, but test to verify
   ./bin/monitor/monitorIngestion.sh
   ```

### Add New Alert Recipient

1. **Edit Alert Configuration**:

   ```bash
   nano config/alerts.conf
   ```

2. **Add Email**:

   ```bash
   ADMIN_EMAIL="admin@example.com,newuser@example.com"
   ```

3. **Test Alert**:
   ```bash
   ./bin/alerts/sendAlert.sh "TEST" "Test alert" "INFO"
   ```

### Restore from Backup

1. **List Backups**:

   ```bash
   ./sql/backups/backup_database.sh -l
   ```

2. **Restore**:
   ```bash
   ./sql/backups/restore_database.sh -f sql/backups/backup_file.sql.gz
   ```

**WARNING**: This will overwrite the current database!

---

## Emergency Procedures

### System Down

**Symptoms**: No metrics, alerts not working, scripts failing

**Steps**:

1. **Check System Status**:

   ```bash
   ./scripts/validate_production.sh
   ```

2. **Check Database**:

   ```bash
   psql -d notes_monitoring -c "SELECT 1;"
   ```

3. **Check Logs**:

   ```bash
   tail -100 /var/log/osm-notes-monitoring/*.log
   ```

4. **Restart Services** (if needed):

   ```bash
   # Restart PostgreSQL if needed
   sudo systemctl restart postgresql
   ```

5. **Restore from Backup** (if database corrupted):
   ```bash
   ./sql/backups/restore_database.sh -f latest_backup.sql.gz
   ```

### Alert Storm

**Symptoms**: Too many alerts, system overwhelmed

**Steps**:

1. **Check Alert Count**:

   ```bash
   psql -d notes_monitoring -c "SELECT COUNT(*) FROM alerts WHERE created_at > NOW() - INTERVAL '1 hour';"
   ```

2. **Temporarily Disable Alerts**:

   ```bash
   # Edit config
   nano config/alerts.conf
   # Set: SEND_ALERT_EMAIL="false"
   ```

3. **Investigate Root Cause**:

   ```bash
   # Check what's causing alerts
   psql -d notes_monitoring -c "SELECT component, message, COUNT(*) FROM alerts WHERE created_at > NOW() - INTERVAL '1 hour' GROUP BY component, message ORDER BY COUNT(*) DESC;"
   ```

4. **Fix Root Cause**:
   - Adjust thresholds if false positives
   - Fix underlying issue if real problem

5. **Re-enable Alerts**:
   ```bash
   # Edit config
   nano config/alerts.conf
   # Set: SEND_ALERT_EMAIL="true"
   ```

### Database Full

**Symptoms**: Database errors, no space

**Steps**:

1. **Check Database Size**:

   ```bash
   psql -d notes_monitoring -c "SELECT pg_size_pretty(pg_database_size('notes_monitoring'));"
   ```

2. **Clean Old Metrics**:

   ```bash
   psql -d notes_monitoring -c "SELECT cleanup_old_metrics();"
   psql -d notes_monitoring -c "SELECT cleanup_old_alerts();"
   ```

3. **Check Disk Space**:

   ```bash
   df -h
   ```

4. **Archive Old Data** (if needed):

   ```bash
   # Export old metrics
   psql -d notes_monitoring -c "COPY (SELECT * FROM metrics WHERE timestamp < NOW() - INTERVAL '90 days') TO '/tmp/old_metrics.csv' CSV HEADER;"

   # Delete old metrics
   psql -d notes_monitoring -c "DELETE FROM metrics WHERE timestamp < NOW() - INTERVAL '90 days';"
   ```

---

## On-Call Procedures

### Receiving Alert

1. **Acknowledge Alert**:

   ```bash
   # Log into system
   # Review alert details
   ```

2. **Assess Severity**:
   - **CRITICAL**: System down, data loss risk
   - **HIGH**: Service degraded, user impact
   - **MEDIUM**: Issue detected, monitoring
   - **LOW**: Informational, no action needed

3. **Investigate**:

   ```bash
   # Check logs
   tail -100 /var/log/osm-notes-monitoring/*.log

   # Check metrics
   psql -d notes_monitoring -c "SELECT * FROM metrics WHERE component = 'COMPONENT_NAME' ORDER BY timestamp DESC LIMIT 20;"
   ```

4. **Take Action**:
   - Follow runbook procedures
   - Escalate if needed
   - Document actions taken

5. **Resolve**:
   - Fix root cause
   - Verify resolution
   - Update documentation

### Escalation

**When to Escalate**:

- Issue persists after 30 minutes
- System down
- Data loss risk
- Unclear how to proceed

**Escalation Path**:

1. On-call engineer
2. Team lead
3. Engineering manager
4. CTO (for critical issues)

---

## Maintenance Windows

### Scheduled Maintenance

**When**: First Sunday of month, 02:00-04:00 AM

**Tasks**:

1. Database maintenance
2. Security updates
3. Configuration review
4. Backup verification

**Procedure**:

1. **Notify Team**: Send maintenance notification
2. **Create Backup**: `./sql/backups/backup_database.sh -c`
3. **Perform Maintenance**: Run maintenance tasks
4. **Verify**: `./scripts/validate_production.sh`
5. **Notify Completion**: Send completion notification

### Emergency Maintenance

**When**: Critical issues require immediate attention

**Procedure**:

1. **Assess Impact**: Determine if maintenance can wait
2. **Notify Team**: Send emergency maintenance notification
3. **Create Backup**: Always backup before changes
4. **Perform Maintenance**: Fix issue
5. **Verify**: Validate system after changes
6. **Document**: Update runbook with lessons learned

---

## Ongoing Maintenance Plan

This section outlines continuous maintenance tasks that should be performed regularly to keep the
system healthy and up-to-date.

### Code Maintenance

- **Regular Code Reviews**: Review code changes, ensure standards compliance
- **Update Dependencies**: Keep system dependencies up-to-date (PostgreSQL, bash, tools)
- **Security Patches**: Apply security patches promptly
- **Performance Optimization**: Monitor and optimize slow queries, improve resource usage
- **Documentation Updates**: Keep documentation current with code changes

### Monitoring Improvements

- **Add New Monitoring Checks**: As new components or requirements emerge
- **Improve Alert Thresholds**: Adjust thresholds based on operational experience
- **Optimize Queries**: Review and optimize SQL queries based on usage patterns
- **Add New Dashboards**: Create dashboards for new metrics or components as needed

### Maintenance Schedule

**Weekly**:

- Review alert patterns and thresholds
- Check for dependency updates
- Review and optimize slow queries

**Monthly**:

- Code review session
- Security audit
- Performance review
- Documentation review

**Quarterly**:

- Comprehensive security review
- Architecture review
- Capacity planning review
- Dependency audit

### Maintenance Tracking

Track maintenance activities in:

- Git commits with appropriate tags (`maintenance`, `security`, `performance`)
- CHANGELOG.md for significant changes
- Documentation updates as needed

---

**Last Updated:** 2026-01-07
