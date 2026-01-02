# Migration Guide

> **Last Updated:** 2026-01-01  
> **Version:** 1.0.0

Guide for migrating from OSM-Notes-Ingestion monitoring to OSM-Notes-Monitoring.

## Table of Contents

1. [Overview](#overview)
2. [Migration Strategy](#migration-strategy)
3. [Pre-Migration Checklist](#pre-migration-checklist)
4. [Migration Steps](#migration-steps)
5. [Post-Migration](#post-migration)
6. [Rollback Procedure](#rollback-procedure)

---

## Overview

This guide covers migrating monitoring functionality from OSM-Notes-Ingestion to OSM-Notes-Monitoring. The migration process is designed to be:

- **Non-disruptive**: Existing monitoring continues to work
- **Reversible**: Can rollback if needed
- **Gradual**: Can be done incrementally

### What Gets Migrated

- **Monitoring Scripts**: Scripts are called directly (no code migration needed)
- **Configuration**: Monitoring configuration moves to OSM-Notes-Monitoring
- **Metrics Storage**: Metrics stored in centralized monitoring database
- **Alerting**: Unified alerting system

### What Doesn't Change

- **OSM-Notes-Ingestion Scripts**: Scripts remain in their repository
- **Existing Functionality**: All existing monitoring continues to work
- **Data**: No data migration required

---

## Migration Strategy

### Approach

OSM-Notes-Monitoring calls OSM-Notes-Ingestion scripts directly. No code migration is required. The migration involves:

1. **Deploying OSM-Notes-Monitoring** alongside existing monitoring
2. **Configuring OSM-Notes-Monitoring** to call OSM-Notes-Ingestion scripts
3. **Gradually transitioning** from old monitoring to new system
4. **Decommissioning** old monitoring (optional)

### Phases

1. **Phase 1**: Deploy OSM-Notes-Monitoring (parallel operation)
2. **Phase 2**: Configure integration with OSM-Notes-Ingestion
3. **Phase 3**: Validate monitoring works correctly
4. **Phase 4**: Transition to new system (optional)
5. **Phase 5**: Decommission old monitoring (optional)

---

## Pre-Migration Checklist

Before starting migration:

- [ ] OSM-Notes-Monitoring deployed and validated
- [ ] OSM-Notes-Ingestion repository accessible
- [ ] Database backups created
- [ ] Configuration files reviewed
- [ ] Alert delivery tested
- [ ] Monitoring scripts tested manually
- [ ] Rollback plan prepared

### Prerequisites

1. **OSM-Notes-Monitoring** deployed (see [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md))
2. **OSM-Notes-Ingestion** repository path configured in `etc/properties.sh`
3. **Database backups** created
4. **Test environment** available (recommended)

---

## Migration Steps

### Step 1: Analyze Current Setup

Analyze what needs to be migrated:

```bash
./scripts/migrate_from_ingestion.sh --dry-run /path/to/OSM-Notes-Ingestion
```

This shows:
- Scripts found in OSM-Notes-Ingestion
- Integration status
- Recommended changes

### Step 2: Create Backup

Create backup before migration:

```bash
# Backup monitoring database
./sql/backups/backup_database.sh -c

# Backup OSM-Notes-Ingestion monitoring scripts (if modifying)
./scripts/migrate_from_ingestion.sh --backup /path/to/OSM-Notes-Ingestion
```

### Step 3: Configure Integration

Configure OSM-Notes-Monitoring to use OSM-Notes-Ingestion scripts:

1. **Update Properties** (`etc/properties.sh`):
   ```bash
   INGESTION_REPO_PATH="/path/to/OSM-Notes-Ingestion"
   ```

2. **Verify Script Paths**:
   ```bash
   # Check scripts exist
   ls -la /path/to/OSM-Notes-Ingestion/bin/monitor/
   ```

3. **Test Integration**:
   ```bash
   # Test ingestion monitoring
   ./bin/monitor/monitorIngestion.sh
   ```

### Step 4: Update References (Optional)

Update script references in OSM-Notes-Ingestion (optional, see [INTEGRATION_CHANGES.md](./INTEGRATION_CHANGES.md)):

```bash
./scripts/migrate_from_ingestion.sh --update-references /path/to/OSM-Notes-Ingestion
```

**Note**: This is optional. OSM-Notes-Monitoring can call scripts as-is.

### Step 5: Validate Migration

Validate that monitoring works:

```bash
# Run validation
./scripts/validate_production.sh

# Test monitoring scripts
./bin/monitor/monitorIngestion.sh
./bin/monitor/monitorAnalytics.sh

# Check metrics
psql -d notes_monitoring -c "SELECT * FROM metrics ORDER BY timestamp DESC LIMIT 10;"
```

### Step 6: Configure Cron Jobs

Set up automated monitoring:

```bash
./scripts/setup_cron.sh --install
```

### Step 7: Monitor and Verify

Monitor the system for a period:

```bash
# Watch logs
tail -f /var/log/osm-notes-monitoring/ingestion.log

# Check metrics
psql -d notes_monitoring -c "SELECT component, COUNT(*) FROM metrics GROUP BY component;"

# Verify alerts
psql -d notes_monitoring -c "SELECT * FROM alerts ORDER BY created_at DESC LIMIT 10;"
```

---

## Post-Migration

### Verification Checklist

- [ ] Monitoring scripts execute successfully
- [ ] Metrics are being collected
- [ ] Alerts are being sent
- [ ] Dashboards show data
- [ ] Cron jobs are running
- [ ] Logs are being written
- [ ] No errors in logs

### Monitoring

Monitor the system closely for the first few days:

1. **Check Logs Daily**:
   ```bash
   tail -f /var/log/osm-notes-monitoring/*.log
   ```

2. **Review Metrics**:
   ```bash
   psql -d notes_monitoring -c "SELECT component, COUNT(*) FROM metrics GROUP BY component;"
   ```

3. **Verify Alerts**:
   ```bash
   psql -d notes_monitoring -c "SELECT * FROM alerts WHERE created_at > NOW() - INTERVAL '24 hours';"
   ```

### Optimization

After migration is stable:

1. **Review Alert Thresholds**: Adjust based on actual data
2. **Optimize Monitoring Intervals**: Adjust based on needs
3. **Customize Dashboards**: Add custom dashboards as needed
4. **Tune Database**: Optimize queries and indexes

---

## Rollback Procedure

If migration needs to be rolled back:

### Step 1: Stop New Monitoring

```bash
# Remove cron jobs
./scripts/setup_cron.sh --remove

# Stop any running processes
pkill -f monitorIngestion
```

### Step 2: Restore Database

```bash
# Restore from backup
./sql/backups/restore_database.sh -f backup_file.sql.gz
```

### Step 3: Restore Configuration

```bash
# Restore configuration files if modified
cp etc/properties.sh.backup etc/properties.sh
```

### Step 4: Verify Rollback

```bash
# Verify old monitoring works
# (depends on your previous setup)
```

---

## Integration Changes

For recommended changes in OSM-Notes-Ingestion, see [INTEGRATION_CHANGES.md](./INTEGRATION_CHANGES.md).

### Optional Enhancements

1. **Add Exit Codes**: Scripts return proper exit codes
2. **Structured Output**: Scripts output metrics in parseable format
3. **Library Integration**: Optional use of shared libraries
4. **Monitoring Mode**: Support for monitoring mode

These are **optional** - OSM-Notes-Monitoring works without them.

---

## Troubleshooting

### Scripts Not Found

**Error**: `Script not found: /path/to/OSM-Notes-Ingestion/bin/monitor/...`

**Solution**:
1. Verify path in `etc/properties.sh`
2. Check script exists: `ls -la /path/to/OSM-Notes-Ingestion/bin/monitor/`
3. Verify permissions: Scripts should be executable

### Scripts Fail

**Error**: Monitoring scripts fail with errors

**Solution**:
1. Test scripts manually: `./path/to/OSM-Notes-Ingestion/bin/monitor/notesCheckVerifier.sh`
2. Check dependencies: Scripts may need environment variables
3. Review logs: Check for error messages
4. Check database access: Scripts may need database access

### Metrics Not Collected

**Error**: No metrics in database

**Solution**:
1. Check script execution: `./bin/monitor/monitorIngestion.sh`
2. Verify database connection: `psql -d notes_monitoring -c "SELECT 1;"`
3. Check logs: `tail -f /var/log/osm-notes-monitoring/ingestion.log`
4. Verify permissions: Scripts need write access to database

---

## Next Steps

After successful migration:

1. **Monitor System**: Watch for issues
2. **Optimize Configuration**: Adjust thresholds and intervals
3. **Customize Dashboards**: Add custom visualizations
4. **Document Changes**: Update documentation
5. **Train Team**: Share knowledge with team

---

**Last Updated:** 2026-01-01
