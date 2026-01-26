---
title: "Quick Start Guide"
description: "This guide will help you get OSM Notes Monitoring running in 15 minutes. For detailed setup, see the ."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Quick Start Guide

> **Purpose:** Get OSM Notes Monitoring up and running quickly  
> **Version:** 1.0.0  
> **Date:** 2025-12-31  
> **Status:** Active

## Overview

This guide will help you get OSM Notes Monitoring running in 15 minutes. For detailed setup, see the
[Setup Guide](./Monitoring_SETUP_Guide.md).

---

## Prerequisites

Before starting, ensure you have:

- ✅ PostgreSQL installed and running
- ✅ Bash 4.0 or higher
- ✅ `curl` installed
- ✅ Access to monitored components (databases, services, etc.)

---

## Step 1: Clone and Configure (2 minutes)

```bash
# Clone the repository
git clone https://github.com/OSM-Notes/OSM-Notes-Monitoring.git
cd OSM-Notes-Monitoring

# Copy configuration template
cp etc/properties.sh.example etc/properties.sh

# Edit configuration (minimal required settings)
nano etc/properties.sh
```

**Minimum Configuration:**

```bash
# Monitoring Database (this project's own database)
# Development: osm_notes_monitoring
# Production: notes_monitoring
export DBNAME="osm_notes_monitoring"
export DBHOST="localhost"
export DBPORT="5432"
export DBUSER="${USER}"  # Use your system user

# Monitored Databases (databases from other projects)
# These are separate from the monitoring database above
# Ingestion database (OSM-Notes-Ingestion)
export INGESTION_DBNAME="${INGESTION_DBNAME:-notes}"
# Analytics database (OSM-Notes-Analytics)
export ANALYTICS_DBNAME="${ANALYTICS_DBNAME:-notes_dwh}"

# Logging
export LOG_DIR="${HOME}/logs/osm-notes-monitoring"
mkdir -p "${LOG_DIR}"
```

---

## Step 2: Set Up Database (3 minutes)

```bash
# Create database
createdb osm_notes_monitoring

# Initialize schema
psql -d osm_notes_monitoring -f sql/init.sql

# Grant permissions to monitoring user (required!)
# Replace 'osm_notes_monitoring_user' with your actual database user
psql -d osm_notes_monitoring -c "GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d osm_notes_monitoring -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d osm_notes_monitoring -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO osm_notes_monitoring_user;"
psql -d osm_notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO osm_notes_monitoring_user;"
psql -d osm_notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO osm_notes_monitoring_user;"
psql -d osm_notes_monitoring -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO osm_notes_monitoring_user;"
psql -d osm_notes_monitoring -c "GRANT USAGE ON SCHEMA public TO osm_notes_monitoring_user;"

# Apply optimizations (recommended)
psql -d osm_notes_monitoring -f sql/optimize_queries.sql
```

---

## Step 3: Configure Alerts (2 minutes)

```bash
# Copy alert configuration
cp config/alerts.conf.example config/alerts.conf

# Edit alert configuration
nano config/alerts.conf
```

**Minimum Configuration:**

```bash
# Email (optional - can be configured later)
export ADMIN_EMAIL="your-email@example.com"
export SEND_ALERT_EMAIL="false"  # Set to "true" when email is configured

# Slack (optional - can be configured later)
export SEND_ALERT_SLACK="false"
```

---

## Step 4: Run First Monitoring Check (2 minutes)

```bash
# Test database connection
psql -d osm_notes_monitoring -c "SELECT 1;" || echo "Database connection failed"

# Run ingestion monitoring (if you have OSM-Notes-Ingestion)
./bin/monitor/monitorIngestion.sh

# Or run infrastructure monitoring (always works)
./bin/monitor/monitorInfrastructure.sh
```

---

## Step 5: Generate Dashboard Data (2 minutes)

```bash
# Generate metrics
./bin/dashboard/generateMetrics.sh

# Update HTML dashboards
./bin/dashboard/updateDashboard.sh html
```

---

## Step 6: View Dashboards (1 minute)

### HTML Dashboards

```bash
# Open overview dashboard
open dashboards/html/overview.html
# Or use your browser to open the file
```

### Or Use Grafana (Optional - 5 minutes)

```bash
# Run Grafana setup script
./scripts/setup_grafana_all.sh

# Access Grafana at http://localhost:3000
# Default login: admin/admin (change immediately)
```

---

## Step 7: Set Up Automated Monitoring (2 minutes)

Add monitoring to cron:

```bash
# Edit crontab
crontab -e

# Add monitoring checks (example: every 5 minutes)
*/5 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorIngestion.sh >> /path/to/logs/cron.log 2>&1
*/5 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorInfrastructure.sh >> /path/to/logs/cron.log 2>&1

# Update dashboards every 15 minutes
*/15 * * * * /path/to/OSM-Notes-Monitoring/bin/dashboard/updateDashboard.sh html >> /path/to/logs/cron.log 2>&1
```

---

## Verification

### Check Database

```bash
# Verify metrics are being stored
psql -d osm_notes_monitoring -c "SELECT COUNT(*) FROM metrics;"

# Check component health
psql -d osm_notes_monitoring -c "SELECT * FROM component_health;"
```

### Check Dashboards

- Open `dashboards/html/overview.html` in your browser
- Verify components show up
- Check that metrics are displayed

### Check Logs

```bash
# View monitoring logs
tail -f logs/monitoring.log

# Check for errors
grep -i error logs/*.log
```

---

## Next Steps

### Basic Usage

1. **Monitor Components**: Run monitoring scripts regularly (via cron)
2. **View Dashboards**: Check dashboards for component health
3. **Review Alerts**: Check for active alerts in database or dashboards

### Advanced Setup

1. **Configure Email Alerts**: Set up email sending in `config/alerts.conf`
2. **Set Up Grafana**: Use `./scripts/setup_grafana_all.sh` for advanced dashboards
3. **Configure Security**: Set up rate limiting and DDoS protection
4. **Customize Dashboards**: Modify dashboard templates for your needs

### Documentation

- [User Guide](./User_Guide.md): Comprehensive user documentation
- [Setup Guide](./Monitoring_SETUP_Guide.md): Detailed setup instructions
- [Configuration Reference](./Configuration_Reference.md): All configuration options
- [Dashboard Guide](./Dashboard_Guide.md): Using dashboards
- [Alerting Guide](./Alerting_Guide.md): Alert system configuration

---

## Troubleshooting

### Database Connection Issues

```bash
# Test connection
psql -d osm_notes_monitoring -c "SELECT 1;"

# Check PostgreSQL is running
sudo systemctl status postgresql

# Verify user permissions
psql -d osm_notes_monitoring -c "\du"
```

### No Metrics Showing

```bash
# Run monitoring manually
./bin/monitor/monitorInfrastructure.sh

# Check logs
tail -f logs/monitoring.log

# Verify database has data
psql -d osm_notes_monitoring -c "SELECT COUNT(*) FROM metrics;"
```

### Dashboard Not Updating

```bash
# Regenerate dashboard data
./bin/dashboard/generateMetrics.sh
./bin/dashboard/updateDashboard.sh html

# Check file permissions
ls -la dashboards/html/
```

### Permission Errors

```bash
# Ensure scripts are executable
chmod +x bin/**/*.sh

# Check log directory permissions
mkdir -p logs
chmod 755 logs
```

---

## Common Issues

### "Command not found" Errors

**Solution:** Ensure scripts are executable:

```bash
chmod +x bin/**/*.sh
```

### "Permission denied" for Log Directory

**Solution:** Create log directory with proper permissions:

```bash
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"
```

### PostgreSQL Authentication Errors

**Solution:** Use peer authentication or configure `.pgpass`:

```bash
# For peer authentication (default on many systems)
export DBUSER="${USER}"

# Or create .pgpass file
echo "localhost:5432:osm_notes_monitoring:${USER}:password" > ~/.pgpass
chmod 600 ~/.pgpass
```

---

## Support

- **Documentation**: See [Documentation Index](./Documentation_Index.md)
- **User Guide**: [USER_GUIDE.md](./User_Guide.md) for detailed usage
- **Troubleshooting**: Component-specific troubleshooting guides

---

**Last Updated:** 2025-12-31  
**Version:** 1.0.0
