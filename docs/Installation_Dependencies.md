---
title: "Installation and Dependencies Guide"
description: "Complete guide to install dependencies and set up OSM-Notes-Monitoring for development"
version: "1.0.0"
last_updated: "2026-01-26"
author: "AngocA"
tags:
  - "installation"
  - "dependencies"
  - "setup"
audience:
  - "developers"
  - "system-admins"
  - "devops"
project: "OSM-Notes-Monitoring"
status: "active"
---

# Installation and Dependencies Guide

Complete guide to install all dependencies and set up OSM-Notes-Monitoring for development and production.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [System Dependencies](#system-dependencies)
3. [Internal Dependencies](#internal-dependencies)
4. [Database Setup](#database-setup)
5. [Project Installation](#project-installation)
6. [Configuration](#configuration)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Operating System

- **Linux** (Ubuntu 20.04+ / Debian 11+ recommended)
- **Bash** 4.0 or higher
- **Git** for cloning repositories

### Hardware Requirements

- **CPU**: 1+ core (minimal requirements)
- **RAM**: 2GB minimum, 4GB+ recommended
- **Disk**: 5GB+ free space (for metrics storage)
- **Network**: Access to all monitored components

---

## System Dependencies

### Required Software

Install all required dependencies on Ubuntu/Debian:

```bash
# Update package list
sudo apt-get update

# PostgreSQL (for metrics storage)
sudo apt-get install -y postgresql postgresql-contrib

# Standard UNIX utilities
sudo apt-get install -y grep awk sed curl jq

# Email client (for email alerts)
sudo apt-get install -y mutt

# Git (if not already installed)
sudo apt-get install -y git
```

### Verify Installation

```bash
# Check PostgreSQL version
psql --version  # Should be 12+

# Check Bash version
bash --version  # Should be 4.0+

# Check other tools
curl --version
jq --version
mutt --version
```

---

## Internal Dependencies

### ⚠️ Required: Other OSM-Notes Projects

**OSM-Notes-Monitoring monitors other OSM-Notes projects. Access to these projects is required:**

#### Required Projects

1. **OSM-Notes-Ingestion** ⚠️ **REQUIRED**
   - Access to Ingestion database (`notes`)
   - Monitors: Data quality, sync status, processing times

2. **OSM-Notes-Analytics** ⚠️ **REQUIRED**
   - Access to Analytics database (`osm_notes_dwh` or `notes_dwh`)
   - Monitors: ETL status, data freshness, processing times

#### Optional Projects (Recommended)

3. **OSM-Notes-API** (optional but recommended)
   - HTTP access to API service
   - Monitors: API availability, response times, error rates

4. **OSM-Notes-WMS** (optional but recommended)
   - HTTP access to GeoServer/WMS service
   - Monitors: WMS availability, layer status

5. **OSM-Notes-Data** (optional but recommended)
   - HTTP access to GitHub repository
   - Monitors: Data freshness, commit frequency

6. **OSM-Notes-Viewer** (optional but recommended)
   - HTTP access to Viewer service
   - Monitors: Viewer availability, page load times

### Installation Order

1. **First**: Install and configure all monitored projects
2. **Second**: Ensure all monitored services are running
3. **Third**: Install OSM-Notes-Monitoring (this project)
4. **Verify**: Ensure Monitoring can access all monitored components

**Note**: Monitoring can be installed with access to only some projects, but full monitoring requires access to all monitored components.

---

## Database Setup

### 1. Create Monitoring Database

```bash
# Switch to postgres user
sudo su - postgres

# Create database
psql << EOF
CREATE DATABASE osm_notes_monitoring WITH OWNER notes;
\q
EOF

exit
```

### 2. Create Monitoring Schema

```bash
# Create schema for monitoring tables
psql -h localhost -U notes -d osm_notes_monitoring << EOF
CREATE SCHEMA IF NOT EXISTS monitoring;
GRANT USAGE ON SCHEMA monitoring TO notes;
GRANT CREATE ON SCHEMA monitoring TO notes;
\q
EOF
```

### 3. Run Monitoring SQL Scripts

```bash
# Run database setup scripts (if available)
psql -h localhost -U notes -d osm_notes_monitoring -f sql/monitoring/setupDatabase.sql

# Verify schema was created
psql -h localhost -U notes -d osm_notes_monitoring -c "\dn monitoring"
```

---

## Project Installation

### 1. Clone Repository with Submodules

```bash
# Clone with submodules (recommended)
git clone --recurse-submodules https://github.com/OSM-Notes/OSM-Notes-Monitoring.git
cd OSM-Notes-Monitoring

# Or if already cloned, initialize submodules
git submodule update --init --recursive
```

### 2. Verify Submodule Installation

```bash
# Check submodule status
git submodule status

# Verify common functions exist
ls -la lib/osm-common/commonFunctions.sh
ls -la lib/osm-common/validationFunctions.sh
ls -la lib/osm-common/errorHandlingFunctions.sh
ls -la lib/osm-common/bash_logger.sh
```

### 3. Verify Access to Monitored Components

```bash
# Test Ingestion database access
psql -h localhost -U notes -d notes -c "SELECT COUNT(*) FROM public.notes;"

# Test Analytics database access
psql -h localhost -U notes -d osm_notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartUsers;"

# Test API access (if available)
curl -H "User-Agent: Monitoring/1.0" http://localhost:3000/health

# Test WMS access (if available)
curl -I http://localhost:8080/geoserver

# Test Data access (if available)
curl -I https://notes.osm.lat/data/api/metadata.json
```

---

## Configuration

### 1. Environment Variables

Set required environment variables:

```bash
# Monitoring database configuration
export DB_HOST="localhost"
export DB_PORT="5432"
export DB_NAME="osm_notes_monitoring"
export DB_USER="notes"
export DB_PASSWORD="your_secure_password_here"

# Ingestion database configuration
export INGESTION_DB_HOST="localhost"
export INGESTION_DB_PORT="5432"
export INGESTION_DB_NAME="notes"
export INGESTION_DB_USER="notes"
export INGESTION_DB_PASSWORD="your_password"

# Analytics database configuration
export ANALYTICS_DB_HOST="localhost"
export ANALYTICS_DB_PORT="5432"
export ANALYTICS_DB_NAME="osm_notes_dwh"
export ANALYTICS_DB_USER="notes"
export ANALYTICS_DB_PASSWORD="your_password"

# API configuration (if monitoring API)
export API_URL="http://localhost:3000"
export API_USER_AGENT="Monitoring/1.0"

# WMS configuration (if monitoring WMS)
export WMS_URL="http://localhost:8080/geoserver"

# Email configuration (for alerts)
export ALERT_EMAIL="monitoring@example.com"
export SMTP_SERVER="smtp.example.com"
export SMTP_PORT="587"

# Logging
export LOG_LEVEL="INFO"  # TRACE, DEBUG, INFO, WARN, ERROR, FATAL
```

### 2. Configuration File

Create or edit `etc/monitoring.properties.sh`:

```bash
# Copy example if exists
cp etc/monitoring.properties.sh.example etc/monitoring.properties.sh

# Edit configuration
nano etc/monitoring.properties.sh
```

### 3. Source Configuration

```bash
# Source the configuration
source etc/monitoring.properties.sh

# Or export variables in your shell
export DB_NAME="osm_notes_monitoring"
export DB_USER="notes"
# ... etc
```

---

## Verification

### 1. Verify Prerequisites

```bash
# Check all tools are installed
which psql curl jq mutt

# Check PostgreSQL connection
psql -h localhost -U notes -d osm_notes_monitoring -c "SELECT version();"
```

### 2. Verify Database Setup

```bash
# Check monitoring schema exists
psql -h localhost -U notes -d osm_notes_monitoring -c "\dn monitoring"

# Check monitoring tables exist (if setup scripts were run)
psql -h localhost -U notes -d osm_notes_monitoring -c "\dt monitoring.*"
```

### 3. Verify Access to Monitored Components

```bash
# Test Ingestion database
psql -h localhost -U notes -d notes -c "SELECT COUNT(*) FROM public.notes;"

# Test Analytics database
psql -h localhost -U notes -d osm_notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartUsers;"

# Test API (if available)
curl -H "User-Agent: Monitoring/1.0" http://localhost:3000/health

# Test WMS (if available)
curl -I http://localhost:8080/geoserver
```

### 4. Run Monitoring Scripts

```bash
# Monitor Ingestion
./bin/monitor/monitorIngestion.sh

# Monitor Analytics
./bin/monitor/monitorAnalytics.sh

# Monitor API (if configured)
./bin/monitor/monitorAPI.sh

# Monitor WMS (if configured)
./bin/monitor/monitorWMS.sh
```

### 5. Run Tests

```bash
# Run all tests
./tests/run_all_tests.sh

# Run specific test suites
./tests/unit/bash/run_unit_tests.sh
```

---

## Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test connection
psql -h localhost -U notes -d osm_notes_monitoring

# Check user permissions
psql -U postgres -c "\du notes"
```

### Monitored Component Access Issues

**Error**: `Could not connect to Ingestion database`

**Solution**:
1. Verify Ingestion database is running and accessible
2. Check database connection settings
3. Verify user has SELECT permissions on Ingestion tables
4. Test connection manually: `psql -h localhost -U notes -d notes`

### Email Alert Issues

```bash
# Test email configuration
echo "Test email" | mutt -s "Test" monitoring@example.com

# Check mutt configuration
mutt -v

# Check SMTP server access
telnet smtp.example.com 587
```

### Submodule Issues

```bash
# Initialize submodules
git submodule update --init --recursive

# Verify submodule exists
ls -la lib/osm-common/commonFunctions.sh
```

### Permission Issues

```bash
# Ensure scripts are executable
chmod +x bin/monitor/*.sh
chmod +x bin/scripts/*.sh

# Check directory permissions
ls -la /var/log/osm-notes-monitoring/  # If using installed mode
ls -la /tmp/osm-notes-monitoring/      # If using fallback mode
```

---

## Next Steps

After installation:

1. **Read Quick Start**: `docs/Quick_Start_Guide.md` - Quick setup guide
2. **Review Configuration**: `docs/Configuration_Reference.md` - All configuration options
3. **Check User Guide**: `docs/User_Guide.md` - User documentation
4. **Explore Alerting**: `docs/Alerting_Guide.md` - Alert system usage

---

## Related Documentation

- [Quick Start Guide](Quick_Start_Guide.md) - Quick setup guide
- [Configuration Reference](Configuration_Reference.md) - All configuration options
- [User Guide](User_Guide.md) - User documentation
- [Alerting Guide](Alerting_Guide.md) - Alert system usage
- [Ingestion Monitoring Guide](Ingestion_Monitoring_Guide.md) - Monitor ingestion
- [Analytics Monitoring Guide](Analytics_Monitoring_Guide.md) - Monitor analytics
- [API Security Guide](API_Security_Guide.md) - API security features
