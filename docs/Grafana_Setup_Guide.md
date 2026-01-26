---
title: "Grafana Setup Guide"
description: "This guide covers installing and configuring Grafana for the OSM Notes Monitoring system. Grafana"
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


# Grafana Setup Guide

> **Purpose:** Step-by-step guide for installing and configuring Grafana for OSM Notes Monitoring  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This guide covers installing and configuring Grafana for the OSM Notes Monitoring system. Grafana
provides advanced visualization capabilities for monitoring all OSM Notes components.

**Note:** This guide is for the **OSM-Notes-Monitoring Grafana** deployment. For API-specific
Grafana setup, see [OSM-Notes-API Monitoring Documentation](../OSM-Notes-API/docs/Monitoring.md).

---

## Prerequisites

- PostgreSQL database (`osm_notes_monitoring`) with metrics data
- Access to the monitoring database
- Root or sudo access for installation
- Port 3000 available (or configure different port)

---

## Installation

### Option 1: Docker (Recommended)

**Quick Start:**

```bash
# Create Grafana data directory
mkdir -p /var/lib/grafana

# Run Grafana container
docker run -d \
  --name osm-notes-grafana \
  -p 3000:3000 \
  -v /var/lib/grafana:/var/lib/grafana \
  -v $(pwd)/dashboards/grafana:/etc/grafana/provisioning/dashboards:ro \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD='your_secure_password' \
  grafana/grafana:latest
```

**With Docker Compose:**

Create `docker-compose.yml`:

```yaml
version: "3.8"

services:
  grafana:
    image: grafana/grafana:latest
    container_name: osm-notes-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
      - ./dashboards/grafana:/etc/grafana/provisioning/dashboards:ro
    restart: unless-stopped

volumes:
  grafana_data:
    driver: local
```

Start:

```bash
docker-compose up -d grafana
```

### Option 2: Package Installation

**Ubuntu/Debian:**

```bash
# Add Grafana repository
sudo apt-get install -y software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -

# Install Grafana
sudo apt-get update
sudo apt-get install grafana

# Start and enable Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

**CentOS/RHEL:**

```bash
# Add Grafana repository
cat <<EOF | sudo tee /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

# Install Grafana
sudo yum install grafana

# Start and enable Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

### Option 3: Binary Installation

```bash
# Download Grafana
wget https://dl.grafana.com/oss/release/grafana-10.0.0.linux-amd64.tar.gz

# Extract
tar -zxvf grafana-10.0.0.linux-amd64.tar.gz
cd grafana-10.0.0

# Copy files
sudo cp -r bin/* /usr/local/bin/
sudo cp -r conf /etc/grafana
sudo cp -r public /usr/share/grafana

# Create systemd service
sudo cp packaging/systemd/grafana-server.service /etc/systemd/system/

# Start Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

---

## Initial Configuration

### First Login

1. **Access Grafana:**
   - URL: `http://localhost:3000` (or your server IP)
   - Default credentials: `admin` / `admin`

2. **Change Password:**
   - Grafana will prompt to change password on first login
   - Use a strong password

3. **Verify Installation:**
   - Check Grafana version in bottom-left corner
   - Verify no errors in logs: `docker logs osm-notes-grafana` or `journalctl -u grafana-server`

---

## PostgreSQL Data Source Configuration

### Step 1: Add Data Source

1. Go to **Configuration** → **Data Sources**
2. Click **Add data source**
3. Select **PostgreSQL**

### Step 2: Configure Connection

**Basic Settings:**

- **Name**: `PostgreSQL` (or descriptive name)
- **Host**: `localhost:5432` (or your DB host:port)
- **Database**: `osm_notes_monitoring`
- **User**: `postgres` (or your DB user)
- **Password**: Your database password
- **SSL Mode**: `disable` (or `require` for production)

**Advanced Settings:**

- **Max open connections**: `100`
- **Max idle connections**: `100`
- **Connection max lifetime**: `14400` (4 hours)

### Step 3: Test Connection

1. Click **Save & Test**
2. Verify "Data source is working" message appears
3. If error, check:
   - Database is running
   - Credentials are correct
   - Network connectivity
   - Firewall rules

### Step 4: Configure Time Series

**PostgreSQL Options:**

- **TimescaleDB**: Enable if using TimescaleDB extension
- **Version**: Select PostgreSQL version (12+)

---

## Dashboard Provisioning

### Automatic Provisioning

**Create provisioning directory:**

```bash
mkdir -p /etc/grafana/provisioning/dashboards
```

**Create dashboard provider:** `/etc/grafana/provisioning/dashboards/dashboard.yml`:

```yaml
apiVersion: 1

providers:
  - name: "OSM Notes Monitoring"
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
```

**Copy dashboards:**

```bash
# Copy dashboard JSON files
cp dashboards/grafana/*.json /etc/grafana/provisioning/dashboards/

# Restart Grafana
sudo systemctl restart grafana-server
# Or for Docker:
docker restart osm-notes-grafana
```

### Manual Import

1. Go to **Dashboards** → **Import**
2. Click **Upload JSON file**
3. Select dashboard JSON file from `dashboards/grafana/`
4. Select PostgreSQL data source
5. Click **Import**

---

## Authentication Configuration

### Basic Authentication

**Default:** Username/password authentication

**Change default password:**

1. Go to **Administration** → **Users**
2. Click on `admin` user
3. Change password

### LDAP Authentication (Optional)

**Configure LDAP:** `/etc/grafana/ldap.toml`:

```toml
[[servers]]
host = "ldap.example.com"
port = 389
bind_dn = "cn=admin,dc=example,dc=com"
bind_password = "password"
search_filter = "(sAMAccountName=%s)"
search_base_dns = ["dc=example,dc=com"]

[servers.attributes]
name = "givenName"
surname = "sn"
username = "sAMAccountName"
member_of = "memberOf"
email = "mail"
```

**Enable in Grafana:**

1. Go to **Configuration** → **Authentication** → **LDAP**
2. Enable LDAP
3. Configure LDAP settings

### OAuth Authentication (Optional)

**Configure OAuth provider:**

1. Go to **Configuration** → **Authentication**
2. Select OAuth provider (Google, GitHub, etc.)
3. Configure client ID and secret
4. Set callback URL

---

## Dashboard Configuration

### Import Dashboards

**Available Dashboards:**

- `overview.json` - System overview
- `ingestion.json` - Ingestion monitoring
- `analytics.json` - Analytics monitoring
- `wms.json` - WMS monitoring
- `api.json` - API/Security monitoring
- `infrastructure.json` - Infrastructure monitoring

**Import Steps:**

1. Go to **Dashboards** → **Import**
2. Upload JSON file
3. Select PostgreSQL data source
4. Configure variables if needed
5. Click **Import**

### Configure Dashboard Variables

**Add time range variable:**

1. Open dashboard
2. Click **Dashboard settings** (gear icon)
3. Go to **Variables** tab
4. Click **Add variable**
5. Configure:
   - **Name**: `time_range`
   - **Type**: `Query`
   - **Query**: `SELECT DISTINCT '24h' as value UNION SELECT '7d' UNION SELECT '30d'`

### Set Default Time Range

**Dashboard settings:**

1. Open dashboard
2. Click **Dashboard settings**
3. Go to **General** tab
4. Set **Time range**: `Last 24 hours`
5. Save dashboard

---

## Alerting Configuration

### Configure Alert Channels

**Email Channel:**

1. Go to **Alerting** → **Notification channels**
2. Click **Add channel**
3. Select **Email**
4. Configure:
   - **Name**: `Email Alerts`
   - **Email addresses**: `admin@example.com`
   - **Send on all alerts**: Enable

**Slack Channel:**

1. Click **Add channel**
2. Select **Slack**
3. Configure:
   - **Name**: `Slack Alerts`
   - **Webhook URL**: Your Slack webhook URL
   - **Channel**: `#monitoring`

### Create Alert Rules

**In Dashboard Panel:**

1. Edit panel
2. Go to **Alert** tab
3. Click **Create Alert**
4. Configure:
   - **Name**: Alert name
   - **Conditions**: When metric exceeds threshold
   - **Notifications**: Select notification channels
   - **Frequency**: How often to check

---

## Performance Tuning

### Database Query Optimization

**Enable query caching:**

```ini
[database]
query_cache_enabled = true
query_cache_max_size = 1000
```

**Optimize PostgreSQL:**

```sql
-- Create indexes for common queries
CREATE INDEX idx_metrics_component_timestamp ON metrics(component, timestamp DESC);
CREATE INDEX idx_metrics_metric_name ON metrics(metric_name);
```

### Grafana Performance

**Increase query timeout:**

```ini
[datasources]
query_timeout = 60s
```

**Limit data points:**

- Use appropriate time ranges
- Aggregate data when possible
- Limit number of series in queries

### Resource Limits

**Docker:**

```yaml
services:
  grafana:
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 2G
        reservations:
          cpus: "1"
          memory: 1G
```

---

## Security Hardening

### Change Default Credentials

**First login:**

- Change `admin` password immediately
- Use strong password (12+ characters, mixed case, numbers, symbols)

### Enable HTTPS

**Using Reverse Proxy (Nginx):**

```nginx
server {
    listen 443 ssl;
    server_name grafana.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Grafana Configuration:**

```ini
[server]
protocol = https
cert_file = /path/to/cert.pem
cert_key = /path/to/key.pem
```

### Restrict Access

**Firewall Rules:**

```bash
# Allow only specific IPs
sudo ufw allow from 192.168.1.0/24 to any port 3000
```

**Grafana IP Whitelist:**

```ini
[server]
ip_whitelist = 192.168.1.0/24,10.0.0.0/8
```

### Disable Sign-Up

**Configuration:**

```ini
[users]
allow_sign_up = false
```

---

## Backup and Restore

### Backup Dashboards

**Export dashboards:**

```bash
# Use export script
./bin/dashboard/exportDashboard.sh grafana /backup/grafana_dashboards

# Or export via API
curl -u admin:password http://localhost:3000/api/dashboards/db/overview > overview_backup.json
```

### Backup Grafana Data

**Docker:**

```bash
# Backup Grafana data directory
docker exec osm-notes-grafana tar -czf /tmp/grafana_backup.tar.gz /var/lib/grafana
docker cp osm-notes-grafana:/tmp/grafana_backup.tar.gz ./grafana_backup.tar.gz
```

**Package Installation:**

```bash
# Backup Grafana data
sudo tar -czf grafana_backup.tar.gz /var/lib/grafana
```

### Restore

**Restore dashboards:**

```bash
# Use import script
./bin/dashboard/importDashboard.sh /backup/grafana_dashboards.tar.gz grafana

# Or import via UI
# Dashboards → Import → Upload JSON file
```

**Restore Grafana data:**

```bash
# Extract backup
tar -xzf grafana_backup.tar.gz

# Copy to Grafana directory
sudo cp -r var/lib/grafana/* /var/lib/grafana/

# Restart Grafana
sudo systemctl restart grafana-server
```

---

## Troubleshooting

### Grafana Won't Start

**Check logs:**

```bash
# Docker
docker logs osm-notes-grafana

# Systemd
sudo journalctl -u grafana-server -f
```

**Common issues:**

- Port 3000 already in use
- Permission issues on data directory
- Configuration file errors

### Can't Connect to PostgreSQL

**Verify connection:**

```bash
# Test database connection
psql -h localhost -U postgres -d osm_notes_monitoring -c "SELECT 1;"
```

**Check:**

- Database is running
- Credentials are correct
- Network connectivity
- Firewall rules

### Dashboards Show No Data

**Verify:**

1. Data source is configured correctly
2. Metrics exist in database: `SELECT COUNT(*) FROM metrics;`
3. Time range includes data
4. SQL queries are correct

**Test query:**

```sql
SELECT timestamp, metric_value
FROM metrics
WHERE component = 'ingestion'
  AND timestamp > NOW() - INTERVAL '24 hours'
LIMIT 10;
```

### Performance Issues

**Optimize:**

1. Add database indexes
2. Reduce time range
3. Aggregate data
4. Limit number of panels
5. Increase query timeout

---

## Maintenance

### Regular Tasks

**Weekly:**

- Review dashboard performance
- Check for slow queries
- Verify alerts are working
- Review user access

**Monthly:**

- Update Grafana version
- Review and optimize queries
- Clean up old dashboards
- Audit user permissions

**Quarterly:**

- Review dashboard effectiveness
- Update dashboards as needed
- Performance tuning
- Security audit

### Updates

**Docker:**

```bash
# Pull latest image
docker pull grafana/grafana:latest

# Stop container
docker stop osm-notes-grafana

# Remove container (data persists in volume)
docker rm osm-notes-grafana

# Start new container
docker run -d \
  --name osm-notes-grafana \
  -p 3000:3000 \
  -v grafana_data:/var/lib/grafana \
  grafana/grafana:latest
```

**Package:**

```bash
# Update package
sudo apt-get update
sudo apt-get upgrade grafana

# Restart service
sudo systemctl restart grafana-server
```

---

## Reference

### Related Documentation

- [Grafana Architecture](./GRAFANA_Architecture.md) - Dual Grafana deployment
- [Dashboard Guide](./Dashboard_Guide.md) - Using dashboards
- [Dashboard Customization Guide](./Dashboard_Customization_Guide.md) - Customizing dashboards

### External Resources

- [Grafana Official Documentation](https://grafana.com/docs/)
- [PostgreSQL Data Source](https://grafana.com/docs/grafana/latest/datasources/postgres/)
- [Grafana Docker Hub](https://hub.docker.com/r/grafana/grafana)

---

## Summary

Grafana provides powerful visualization capabilities for OSM Notes Monitoring. Install using Docker
for easiest setup, configure PostgreSQL data source, import dashboards, and set up authentication.
Regular maintenance ensures optimal performance and security.
