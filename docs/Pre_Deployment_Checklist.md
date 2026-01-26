---
title: "Pre-Deployment Checklist"
description: "Complete checklist to verify readiness for production deployment."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "installation"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Pre-Deployment Checklist

> **Last Updated:** 2026-01-01  
> **Version:** 1.0.0

Complete checklist to verify readiness for production deployment.

## Quick Start

Run the automated checklist:

```bash
./scripts/pre_deployment_checklist.sh
```

This will check all prerequisites and show what's ready and what needs attention.

---

## Step-by-Step Deployment Process

Follow these steps in order:

### Step 1: Run Automated Checklist

```bash
cd /home/notes/OSM-Notes-Monitoring
./scripts/pre_deployment_checklist.sh
```

**What it checks:**

- Prerequisites (PostgreSQL, bash, curl, etc.)
- Configuration files exist and are configured
- All scripts exist and are executable
- Database connection works
- Security settings
- System resources

**Expected result:** All checks should pass (or have only minor warnings)

**If checks fail:** Fix the issues shown before proceeding.

---

### Step 2: Configure System

```bash
./scripts/configure_production.sh --review
```

Review your current configuration. If needed, update:

```bash
# Configure all sections interactively
./scripts/configure_production.sh

# Or configure specific sections
./scripts/configure_production.sh --main        # Database, paths, etc.
./scripts/configure_production.sh --monitoring  # Thresholds
./scripts/configure_production.sh --alerts      # Email/Slack
./scripts/configure_production.sh --security    # Rate limiting, etc.
```

**Key things to configure:**

- Database name and user in `etc/properties.sh`
- Admin email in `etc/properties.sh`
- Repository paths (INGESTION_REPO_PATH, etc.)
- Alert thresholds in `config/monitoring.conf`
- Email/Slack configuration in `config/alerts.conf`

**Important:** Database password goes in `~/.pgpass` file, NOT in properties.sh (see below).

---

### Step 3: Set Up Database Password

**DO NOT put password in `etc/properties.sh`**

Create `.pgpass` file instead:

```bash
cat > ~/.pgpass << EOF
localhost:5432:notes_monitoring:angoca:YOUR_PASSWORD
localhost:5432:notes:osm_notes_ingestion_user:YOUR_PASSWORD
localhost:5432:notes_dwh:osm_notes_analytics_user:YOUR_PASSWORD
EOF

chmod 600 ~/.pgpass
```

**Test connection:**

```bash
psql -d notes_monitoring -c "SELECT 1;"
```

---

### Step 4: Validate Configuration

```bash
# Validate configuration syntax and values
./scripts/test_config_validation.sh

# Run production validation
./scripts/validate_production.sh
```

**Expected:** All validations should pass.

---

### Step 5: Test Deployment (Optional but Recommended)

```bash
# Quick test (no database changes)
./scripts/test_deployment.sh --quick

# Full test (creates test database)
./scripts/test_deployment.sh --full
```

---

### Step 6: Deploy to Production

Once all checks pass, run the complete deployment:

```bash
./scripts/deploy_production.sh
```

**What it does:**

1. Sets up production environment
2. Runs database migrations (with backup)
3. Applies security hardening
4. Configures cron jobs
5. Sets up backups
6. Configures log rotation
7. Validates deployment

**After deployment:**

```bash
# Verify everything works
./scripts/validate_production.sh

# Check monitoring is running
crontab -l | grep OSM-Notes-Monitoring

# Check logs
tail -f /var/log/osm-notes-monitoring/*.log
```

---

## Detailed Checklist Items

### Prerequisites ✓

- [x] PostgreSQL 12+ installed and running
- [x] Bash 4.0+ available
- [x] curl installed
- [x] mutt installed (for email alerts)
- [x] logrotate installed
- [x] gzip installed
- [x] Disk space: At least 1GB free
- [x] Memory: At least 512MB available

**Verify:**

```bash
./scripts/pre_deployment_checklist.sh
```

---

### Configuration Files ✓

- [ ] `etc/properties.sh` exists and configured
  - [ ] Database name set (not default)
  - [ ] Database user set
  - [ ] Admin email configured
  - [ ] Repository paths set (not `/path/to/...`)
- [ ] `config/monitoring.conf` exists and configured
  - [ ] Thresholds reviewed
- [ ] `config/alerts.conf` exists and configured
  - [ ] Email or Slack configured
- [ ] `config/security.conf` exists and configured

**Verify:**

```bash
./scripts/configure_production.sh --review
```

---

### Database Setup ✓

- [x] Database connection works
- [x] Database schema initialized
- [x] Database permissions granted to monitoring user
- [x] `.pgpass` file created with correct permissions (600)
- [x] `sql/init.sql` exists
- [x] `sql/migrations/run_migrations.sh` exists
- [x] `sql/backups/backup_database.sh` exists

**Verify:**

```bash
# Test database connection
psql -d notes_monitoring -c "SELECT 1;"

# Grant permissions (if not done during init)
# Replace 'osm_notes_monitoring_user' with your actual monitoring database user
psql -d notes_monitoring -c "GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO osm_notes_monitoring_user;"
psql -d notes_monitoring -c "GRANT USAGE ON SCHEMA public TO osm_notes_monitoring_user;"

# Verify permissions
psql -d notes_monitoring -c "SELECT COUNT(*) FROM metrics;"

# Check PostgreSQL logs if connection fails: sudo journalctl -u postgresql
```

---

### Scripts ✓

- [x] All deployment scripts exist and executable
- [x] All monitoring scripts exist and executable
- [x] Scripts have valid syntax

**Verify:**

```bash
./scripts/pre_deployment_checklist.sh
```

---

### Security ✓

- [x] No world-writable files
- [x] No hardcoded credentials
- [x] Config files have restricted permissions

**Verify:**

```bash
./scripts/security_hardening.sh --check
```

---

### System Resources ✓

- [x] Disk space sufficient
- [x] Memory sufficient
- [x] Log directories created and writable

**Verify:**

```bash
df -h
free -h
ls -ld /var/log/osm-notes-monitoring
```

---

## Troubleshooting

### Checklist Shows Failures

1. **Read the error message** - it tells you what's wrong
2. **Fix the issue** - follow the suggestions in the error
3. **Re-run checklist** - `./scripts/pre_deployment_checklist.sh`
4. **Repeat until all pass**

### Common Issues

**Database connection fails:**

```bash
# Check .pgpass
ls -la ~/.pgpass
cat ~/.pgpass

# Test manually
psql -d notes_monitoring -c "SELECT 1;"

# Check PostgreSQL logs
sudo journalctl -u postgresql -n 50
```

**Configuration has defaults:**

```bash
# Review configuration
./scripts/configure_production.sh --review

# Edit files
nano etc/properties.sh
nano config/monitoring.conf
```

**Scripts missing:**

```bash
# Check what's missing
./scripts/pre_deployment_checklist.sh | grep "✗"

# Upload missing files (from your local repo)
rsync -avz scripts/ angoca@192.168.0.7:/home/notes/OSM-Notes-Monitoring/scripts/
```

---

## Ready for Deployment?

When the checklist shows:

✅ **All checks passed** (or only minor warnings)  
✅ **Configuration reviewed and updated**  
✅ **Database connection works**  
✅ **All scripts present**

Then you're ready to deploy:

```bash
./scripts/deploy_production.sh
```

---

## Emergency Rollback

If something goes wrong during deployment:

```bash
# Stop monitoring
./scripts/setup_cron.sh --remove

# Restore database from backup
./sql/backups/restore_database.sh -f backup_file.sql.gz

# Restore configuration (if needed)
cp etc/properties.sh.backup etc/properties.sh
```

---

**Last Updated:** 2026-01-01
