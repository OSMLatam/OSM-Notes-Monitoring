---
title: "Dashboard Guide"
description: "OSM Notes Monitoring provides two types of dashboards:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "monitoring"
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Dashboard Guide

> **Purpose:** Comprehensive guide for using OSM Notes Monitoring dashboards  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

OSM Notes Monitoring provides two types of dashboards:

1. **HTML Dashboards**: Simple, lightweight dashboards that work without Grafana
2. **Grafana Dashboards**: Advanced dashboards with rich visualization capabilities

Both dashboard types provide visibility into the health and performance of all OSM Notes components.

---

## HTML Dashboards

### Overview Dashboard (`dashboards/html/overview.html`)

The overview dashboard provides a high-level view of all components.

**Features:**

- Component health status at a glance
- Key metrics for each component
- Recent alerts summary
- Auto-refresh every 5 minutes

**Access:**

```bash
# Generate metrics data
./bin/dashboard/updateDashboard.sh html

# Open in browser
open dashboards/html/overview.html
```

**Data Files Required:**

- `overview_data.json` - Aggregated metrics for all components
- `component_health.json` - Health status for each component
- `recent_alerts.json` - Recent alerts across all components

### Component Status Dashboard (`dashboards/html/component_status.html`)

Detailed view of each component's status and metrics.

**Features:**

- Individual component cards
- Detailed metrics tables
- Health status indicators
- Last check timestamps

**Access:**

```bash
# Ensure component data files exist
./bin/dashboard/updateDashboard.sh html

# Open in browser
open dashboards/html/component_status.html
```

**Data Files Required:**

- `{component}_data.json` - Metrics for each component (ingestion, analytics, wms, api,
  infrastructure, data)
- `component_health.json` - Health status

### Health Check Dashboard (`dashboards/html/health_check.html`)

Quick health check page for rapid status assessment.

**Features:**

- Overall system health indicator
- Component status grid
- Quick statistics
- Auto-refresh every minute

**Access:**

```bash
# Update health data
./bin/dashboard/updateDashboard.sh html

# Open in browser
open dashboards/html/health_check.html
```

**Data Files Required:**

- `component_health.json` - Health status for all components

---

## Grafana Dashboards

### Overview Dashboard (`dashboards/grafana/overview.json`)

High-level view of the entire OSM Notes ecosystem.

**Panels:**

- Component Health Status
- Error Rate Trends (Last 24h)
- Active Alerts Table

**Data Source:** PostgreSQL (`osm_notes_monitoring` database)

**Import:**

1. Open Grafana
2. Go to Dashboards → Import
3. Upload `dashboards/grafana/overview.json`
4. Select PostgreSQL data source
5. Click Import

### Component-Specific Dashboards

#### Ingestion Dashboard (`dashboards/grafana/ingestion.json`)

Monitors the ingestion component:

- Script execution status
- Error rates
- Database query performance

#### Analytics Dashboard (`dashboards/grafana/analytics.json`)

Monitors the analytics component:

- ETL job status
- Data warehouse freshness
- Query performance
- Storage growth

#### WMS Dashboard (`dashboards/grafana/wms.json`)

Monitors the WMS component:

- Service availability
- Response times
- Cache hit rates
- Error rates

#### API/Security Dashboard (`dashboards/grafana/api.json`)

Monitors the API and security:

- Security events
- Rate limiting statistics
- DDoS protection status
- Abuse detection alerts

#### Infrastructure Dashboard (`dashboards/grafana/infrastructure.json`)

Monitors infrastructure:

- Server resources (CPU, memory, disk)
- Network connectivity
- Database health
- Service dependencies

---

## Dashboard Scripts

### generateMetrics.sh

Generates metrics data in various formats.

**Usage:**

```bash
# Generate JSON metrics for a component
./bin/dashboard/generateMetrics.sh ingestion json

# Generate CSV metrics
./bin/dashboard/generateMetrics.sh ingestion csv

# Generate dashboard-formatted metrics
./bin/dashboard/generateMetrics.sh ingestion dashboard

# Generate for all components
./bin/dashboard/generateMetrics.sh all json

# Save to file
./bin/dashboard/generateMetrics.sh -o metrics.json ingestion json

# Specify time range (hours)
./bin/dashboard/generateMetrics.sh --time-range 168 ingestion json
```

**Output Formats:**

- **JSON**: Raw metrics data as JSON array
- **CSV**: Metrics as comma-separated values
- **Dashboard**: Aggregated metrics optimized for dashboard display

### updateDashboard.sh

Updates dashboard data files from the database.

**Usage:**

```bash
# Update HTML dashboards
./bin/dashboard/updateDashboard.sh html

# Update Grafana dashboards
./bin/dashboard/updateDashboard.sh grafana

# Update all dashboards
./bin/dashboard/updateDashboard.sh all

# Force update (ignore time checks)
./bin/dashboard/updateDashboard.sh --force html

# Update specific component
./bin/dashboard/updateDashboard.sh --component ingestion all
```

**Update Logic:**

- Checks file modification time
- Updates if data is older than `DASHBOARD_UPDATE_INTERVAL` (default: 5 minutes)
- Use `--force` to update regardless of age

### exportDashboard.sh

Exports dashboard configurations and data.

**Usage:**

```bash
# Export HTML dashboards to directory
./bin/dashboard/exportDashboard.sh html /path/to/backup

# Export Grafana dashboards as tar archive
./bin/dashboard/exportDashboard.sh grafana backup.tar.gz

# Export all dashboards
./bin/dashboard/exportDashboard.sh all /path/to/backup

# Export as zip
./bin/dashboard/exportDashboard.sh --format zip html backup.zip

# Include metrics data
./bin/dashboard/exportDashboard.sh --include-data all /path/to/backup
```

**Export Formats:**

- **Directory**: Copy files to specified directory
- **Tar**: Create `.tar.gz` archive
- **Zip**: Create `.zip` archive (requires `zip` command)

### importDashboard.sh

Imports dashboard configurations and data.

**Usage:**

```bash
# Import from directory
./bin/dashboard/importDashboard.sh /path/to/backup grafana

# Import from tar archive
./bin/dashboard/importDashboard.sh backup.tar.gz grafana

# Import from zip archive
./bin/dashboard/importDashboard.sh backup.zip html

# Import all dashboards
./bin/dashboard/importDashboard.sh backup.tar.gz all

# Create backup before importing
./bin/dashboard/importDashboard.sh --backup backup.tar.gz grafana

# Overwrite existing files
./bin/dashboard/importDashboard.sh --overwrite backup.tar.gz all
```

**Import Sources:**

- Directory with dashboard files
- Tar archive (`.tar.gz`, `.tgz`)
- Zip archive (`.zip`)

---

## Configuration

### Environment Variables

```bash
# Dashboard update interval (seconds)
export DASHBOARD_UPDATE_INTERVAL=300

# Dashboard output directory
export DASHBOARD_OUTPUT_DIR="${PROJECT_ROOT}/dashboards"

# Metrics time range (hours)
export METRICS_TIME_RANGE_HOURS=24
```

### Configuration File

Add to `config/monitoring.conf`:

```bash
# Dashboard Configuration
DASHBOARD_UPDATE_INTERVAL=300
DASHBOARD_OUTPUT_DIR="${PROJECT_ROOT}/dashboards"
METRICS_TIME_RANGE_HOURS=24
```

---

## Data Files

### HTML Dashboard Data Files

Located in `dashboards/html/`:

- `overview_data.json` - Aggregated metrics for all components
- `component_health.json` - Health status for all components
- `recent_alerts.json` - Recent alerts
- `{component}_data.json` - Component-specific metrics (e.g., `ingestion_data.json`)

### Grafana Dashboard Files

Located in `dashboards/grafana/`:

- `overview.json` - Overview dashboard definition
- `ingestion.json` - Ingestion dashboard definition
- `analytics.json` - Analytics dashboard definition
- `wms.json` - WMS dashboard definition
- `api.json` - API/Security dashboard definition
- `infrastructure.json` - Infrastructure dashboard definition

---

## Automated Updates

### Cron Job Setup

Update dashboards automatically:

```bash
# Add to crontab (runs every 5 minutes)
*/5 * * * * /path/to/OSM-Notes-Monitoring/bin/dashboard/updateDashboard.sh all > /dev/null 2>&1
```

### Systemd Timer (Alternative)

Create `/etc/systemd/system/dashboard-update.timer`:

```ini
[Unit]
Description=Update OSM Notes Monitoring Dashboards

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
```

Create `/etc/systemd/system/dashboard-update.service`:

```ini
[Unit]
Description=Update OSM Notes Monitoring Dashboards

[Service]
Type=oneshot
ExecStart=/path/to/OSM-Notes-Monitoring/bin/dashboard/updateDashboard.sh all
Environment="DASHBOARD_OUTPUT_DIR=/path/to/dashboards"
```

Enable timer:

```bash
sudo systemctl enable dashboard-update.timer
sudo systemctl start dashboard-update.timer
```

---

## Accessing Dashboards

### HTML Dashboards

**Local Access:**

```bash
# Start simple HTTP server
cd dashboards/html
python3 -m http.server 8080

# Access in browser
open http://localhost:8080/overview.html
```

**Production Access:**

- Serve via web server (nginx, Apache)
- Configure reverse proxy if needed
- Set up HTTPS for secure access

### Grafana Dashboards

**Access Grafana:**

- URL: `http://localhost:3000` (or configured port)
- Default credentials: `admin` / `admin`
- Change password on first login

**Import Dashboards:**

1. Login to Grafana
2. Go to Dashboards → Import
3. Upload JSON files from `dashboards/grafana/`
4. Select PostgreSQL data source
5. Configure as needed

---

## Troubleshooting

### HTML Dashboards Show "Loading..."

**Problem:** Dashboard can't load data files.

**Solutions:**

1. Check data files exist: `ls -la dashboards/html/*.json`
2. Update dashboards: `./bin/dashboard/updateDashboard.sh html`
3. Check file permissions
4. Verify JSON syntax: `jq . dashboards/html/overview_data.json`

### Grafana Shows No Data

**Problem:** Grafana dashboards show "No data".

**Solutions:**

1. Verify PostgreSQL data source is configured
2. Check database connection: `psql -d osm_notes_monitoring -c "SELECT COUNT(*) FROM metrics;"`
3. Verify metrics exist: `SELECT * FROM metrics LIMIT 10;`
4. Check dashboard SQL queries
5. Verify time range in dashboard

### Dashboard Update Fails

**Problem:** `updateDashboard.sh` fails or shows errors.

**Solutions:**

1. Check database connection
2. Verify `generateMetrics.sh` works: `./bin/dashboard/generateMetrics.sh ingestion json`
3. Check log files: `tail -f logs/update_dashboard.log`
4. Verify permissions on dashboard directories
5. Check disk space

### Metrics Not Updating

**Problem:** Dashboard shows stale data.

**Solutions:**

1. Force update: `./bin/dashboard/updateDashboard.sh --force all`
2. Check monitoring scripts are running
3. Verify metrics are being collected: `SELECT MAX(timestamp) FROM metrics;`
4. Check cron jobs or systemd timers

---

## Best Practices

### 1. Regular Updates

- Set up automated updates via cron or systemd
- Update interval: 5 minutes for HTML, 30 seconds for Grafana
- Monitor update script logs

### 2. Data Retention

- Keep HTML dashboard data files for quick access
- Archive old dashboard exports regularly
- Clean up old metrics data per retention policy

### 3. Dashboard Maintenance

- Review dashboard performance regularly
- Optimize slow queries
- Update dashboards as metrics evolve
- Version control dashboard JSON files

### 4. Access Control

- Restrict Grafana access appropriately
- Use HTTPS for production dashboards
- Implement authentication for HTML dashboards if exposed
- Monitor dashboard access logs

### 5. Backup

- Export dashboards regularly
- Backup dashboard data files
- Version control dashboard definitions
- Test restore procedures

---

## Examples

### Example 1: Quick Health Check

```bash
# Update dashboards
./bin/dashboard/updateDashboard.sh html

# Open health check page
open dashboards/html/health_check.html
```

### Example 2: Generate Metrics Report

```bash
# Generate metrics for last 7 days
./bin/dashboard/generateMetrics.sh --time-range 168 all json > metrics_report.json

# Generate CSV for ingestion
./bin/dashboard/generateMetrics.sh ingestion csv > ingestion_metrics.csv
```

### Example 3: Backup Dashboards

```bash
# Export all dashboards with data
./bin/dashboard/exportDashboard.sh --include-data all /backup/dashboards_$(date +%Y%m%d)
```

### Example 4: Restore Dashboards

```bash
# Import from backup
./bin/dashboard/importDashboard.sh --backup /backup/dashboards_20251227.tar.gz all
```

---

## Reference

### Related Documentation

- [Grafana Architecture](./GRAFANA_Architecture.md) - Dual Grafana deployment
- [Grafana Setup Guide](./Grafana_Setup_Guide.md) - Grafana installation and configuration
- [Dashboard Customization Guide](./Dashboard_Customization_Guide.md) - Customizing dashboards

### Scripts

- `bin/dashboard/generateMetrics.sh` - Generate metrics data
- `bin/dashboard/updateDashboard.sh` - Update dashboard data
- `bin/dashboard/exportDashboard.sh` - Export dashboards
- `bin/dashboard/importDashboard.sh` - Import dashboards

### Data Files

- `dashboards/html/` - HTML dashboard files and data
- `dashboards/grafana/` - Grafana dashboard JSON definitions

---

## Summary

OSM Notes Monitoring dashboards provide comprehensive visibility into the health and performance of
all components. Use HTML dashboards for quick checks and Grafana dashboards for detailed analysis.
Keep dashboards updated automatically and maintain backups for disaster recovery.
