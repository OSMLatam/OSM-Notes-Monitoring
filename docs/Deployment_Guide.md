---
title: "Deployment Guide"
description: "Complete guide for deploying OSM-Notes-Monitoring to production."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "installation"
  - "guide"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Deployment Guide

> **Last Updated:** 2026-01-01  
> **Version:** 1.0.0

Complete guide for deploying OSM-Notes-Monitoring to production.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Deployment](#quick-deployment)
3. [Step-by-Step Deployment](#step-by-step-deployment)
4. [Post-Deployment](#post-deployment)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

- **Operating System**: Linux (Debian/Ubuntu/RHEL/CentOS)
- **PostgreSQL**: Version 12 or higher
- **Bash**: Version 4.0 or higher
- **Disk Space**: At least 1GB free
- **Memory**: At least 512MB RAM

### Required Software

- PostgreSQL client (`psql`)
- `curl` (for HTTP health checks)
- `mutt` (for email alerts, optional)
- `logrotate` (for log rotation)
- `gzip` (for backup compression)

### Access Requirements

- Database access (read/write to monitoring database)
- Read access to monitored databases (ingestion, analytics)
- Write access to log directories
- Root access (for logrotate setup)

---

## Quick Deployment

For a quick deployment with defaults:

```bash
# 1. Clone repository
git clone https://github.com/OSM-Notes/OSM-Notes-Monitoring.git
cd OSM-Notes-Monitoring

# 2. Run complete deployment
sudo ./scripts/deploy_production.sh

# 3. Configure alerts
nano etc/properties.sh
nano config/alerts.conf

# 4. Validate deployment
./scripts/validate_production.sh
```

---

## Step-by-Step Deployment

### Step 1: Production Environment Setup

Set up the production environment:

```bash
./scripts/production_setup.sh
```

This script:

- Validates the environment
- Creates necessary directories
- Sets up configuration files
- Initializes the database
- Applies security hardening

**Important:** After database initialization, grant permissions to the monitoring user:

```sql
-- Grant permissions on all existing tables
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO osm_notes_monitoring_user;

-- Grant permissions on all sequences (for auto-increment columns)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO osm_notes_monitoring_user;

-- Grant execute permissions on all functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO osm_notes_monitoring_user;

-- Grant permissions on default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO osm_notes_monitoring_user;

-- Grant permissions on default privileges for future sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO osm_notes_monitoring_user;

-- Grant permissions on default privileges for future functions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO osm_notes_monitoring_user;

-- Grant usage on schema (required to access objects in schema)
GRANT USAGE ON SCHEMA public TO osm_notes_monitoring_user;
```

Execute these commands:

```bash
# Replace 'osm_notes_monitoring_user' with your actual monitoring database user
psql -d notes_monitoring -c "GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "GRANT USAGE ON SCHEMA public TO osm_notes_monitoring_user;"

```

**Note:** Replace `osm_notes_monitoring_user` with your actual monitoring database user if
different.

**Options:**

- `--skip-checks`: Skip environment validation
- `--skip-database`: Skip database setup
- `--skip-config`: Skip configuration setup
- `--skip-security`: Skip security hardening
- `--force`: Force re-setup

### Step 2: Database Migration

Run database migrations:

```bash
./scripts/production_migration.sh -b
```

The `-b` flag creates a backup before migration.

**Options:**

- `-b, --backup`: Create backup before migration
- `-r, --rollback FILE`: Rollback from backup file
- `-l, --list`: List pending migrations
- `-v, --verbose`: Verbose output

### Step 3: Security Hardening

Apply security hardening:

```bash
./scripts/security_hardening.sh --apply
```

This script:

- Sets secure file permissions
- Checks for hardcoded credentials
- Validates security configuration
- Runs security audit

**Options:**

- `--check`: Run security checks only
- `--apply`: Apply security hardening
- `--report`: Generate security report

### Step 4: Configure Cron Jobs

Set up automated monitoring:

```bash
./scripts/setup_cron.sh --install
```

This installs cron jobs for:

- Ingestion monitoring (every 5 minutes)
- Analytics monitoring (every 15 minutes)
- WMS monitoring (every 5 minutes)
- API monitoring (every minute)
- Data freshness monitoring (every hour)
- Infrastructure monitoring (every 5 minutes)
- Dashboard updates (every 15 minutes)
- Database cleanup (daily at 2 AM)
- Database backup (daily at 3 AM)

**Options:**

- `--install`: Install cron jobs
- `--remove`: Remove cron jobs
- `--list`: List current cron jobs
- `--user USER`: User to install for (default: current user)

### Step 5: Configure Backups

Set up automated backups:

```bash
./scripts/setup_backups.sh --install
```

**Options:**

- `--install`: Install backup cron job
- `--remove`: Remove backup cron job
- `--test`: Test backup creation
- `--list`: List backup configuration
- `--retention DAYS`: Set retention period (default: 30)
- `--schedule SCHEDULE`: Set cron schedule (default: "0 3 \* \* \*")

### Step 6: Set Up Log Rotation

Configure log rotation:

```bash
sudo ./scripts/setup_logrotate.sh
```

This installs logrotate configuration to `/etc/logrotate.d/osm-notes-monitoring`.

**Options:**

- `-t, --test`: Test configuration without installing
- `-d, --dry-run`: Dry run test

### Step 7: Validation

Validate the deployment:

```bash
./scripts/validate_production.sh
```

This checks:

- Database connection
- Configuration files
- Monitoring scripts
- Alert delivery
- Dashboards
- System health
- Cron jobs

---

## Post-Deployment

### Configuration Review

Review and update configuration files:

1. **Main Configuration** (`etc/properties.sh`):

   ```bash
   nano etc/properties.sh
   ```

   - Update database connection details
   - Set admin email
   - Configure repository paths

2. **Alert Configuration** (`config/alerts.conf`):

   ```bash
   nano config/alerts.conf
   ```

   - Configure email alerts
   - Set up Slack webhook (optional)
   - Configure alert routing

3. **Monitoring Configuration** (`config/monitoring.conf`):

   ```bash
   nano config/monitoring.conf
   ```

   - Adjust alert thresholds
   - Configure monitoring intervals

4. **Security Configuration** (`config/security.conf`):

   ```bash
   nano config/security.conf
   ```

   - Configure rate limiting
   - Set up DDoS protection
   - Configure IP blocking

### Test Monitoring

Test monitoring scripts manually:

```bash
# Test ingestion monitoring
./bin/monitor/monitorIngestion.sh

# Test analytics monitoring
./bin/monitor/monitorAnalytics.sh

# Test infrastructure monitoring
./bin/monitor/monitorInfrastructure.sh
```

### Test Alert Delivery

Test alert delivery:

```bash
# Send test alert
./bin/alerts/sendAlert.sh "TEST" "Test alert from deployment" "INFO"

# Check email delivery (if configured)
# Check Slack (if configured)
```

### Monitor Logs

Monitor logs for issues:

```bash
# Watch ingestion logs
tail -f /var/log/osm-notes-monitoring/ingestion.log

# Watch all monitoring logs
tail -f /var/log/osm-notes-monitoring/*.log
```

---

## Verification

### Quick Verification

Run the validation script:

```bash
./scripts/validate_production.sh
```

### Manual Verification

1. **Check Database**:

   ```bash
   psql -d notes_monitoring -c "SELECT COUNT(*) FROM metrics;"
   psql -d notes_monitoring -c "SELECT * FROM component_health;"
   ```

2. **Check Cron Jobs**:

   ```bash
   crontab -l | grep OSM-Notes-Monitoring
   ```

3. **Check Logs**:

   ```bash
   ls -lh /var/log/osm-notes-monitoring/
   ```

4. **Check Dashboards**:

   ```bash
   # HTML dashboards
   ls -lh dashboards/html/

   # Open in browser
   open dashboards/html/overview.html
   ```

---

## Troubleshooting

### Common Issues

#### Database Connection Failed

**Error**: `Cannot connect to database`

**Solution**:

1. Check PostgreSQL is running: `systemctl status postgresql`
2. Verify database exists: `psql -l | grep notes_monitoring`
3. Check credentials in `etc/properties.sh`
4. Test connection: `psql -d notes_monitoring -c "SELECT 1;"`

#### Configuration Validation Failed

**Error**: `Configuration validation found issues`

**Solution**:

1. Run validation with verbose output: `./scripts/test_config_validation.sh`
2. Check for default values: `grep -r "example.com\|changeme" etc/ config/`
3. Review configuration files manually

#### Cron Jobs Not Running

**Error**: Monitoring scripts not executing

**Solution**:

1. Check cron service: `systemctl status cron`
2. Verify cron jobs: `crontab -l`
3. Check cron logs: `grep CRON /var/log/syslog`
4. Test script manually: `./bin/monitor/monitorIngestion.sh`

#### Log Rotation Not Working

**Error**: Logs not rotating

**Solution**:

1. Check logrotate config: `cat /etc/logrotate.d/osm-notes-monitoring`
2. Test manually: `sudo logrotate -d /etc/logrotate.d/osm-notes-monitoring`
3. Force rotation: `sudo logrotate -f /etc/logrotate.d/osm-notes-monitoring`

#### Alert Delivery Failed

**Error**: Alerts not being sent

**Solution**:

1. Check alert configuration: `cat config/alerts.conf`
2. Test email: `echo "test" | mutt -s "test" admin@example.com`
3. Check Slack webhook:
   `curl -X POST -H 'Content-type: application/json' --data '{"text":"test"}' SLACK_WEBHOOK_URL`
4. Review alert logs: `tail -f /var/log/osm-notes-monitoring/*.log`

### Getting Help

If you encounter issues:

1. Check logs: `/var/log/osm-notes-monitoring/`
2. Run validation: `./scripts/validate_production.sh`
3. Review documentation: `docs/`
4. Check GitHub issues: https://github.com/OSM-Notes/OSM-Notes-Monitoring/issues

---

## Next Steps

After successful deployment:

1. **Configure Grafana** (optional):

   ```bash
   ./scripts/setup_grafana_all.sh
   ```

2. **Set Up Monitoring Alerts**:
   - Configure email/Slack notifications
   - Set up alert escalation
   - Configure on-call rotation

3. **Review Dashboards**:
   - Customize dashboards as needed
   - Set up additional dashboards
   - Configure dashboard refresh intervals

4. **Monitor System Health**:
   - Review metrics regularly
   - Check alert delivery
   - Monitor system resources

5. **Documentation**:
   - Document custom configurations
   - Update runbooks
   - Share knowledge with team

---

**Last Updated:** 2026-01-01
