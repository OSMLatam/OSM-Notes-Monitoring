---
title: "Configuration Customization Guide"
description: "Guide for customizing OSM-Notes-Monitoring configuration for your specific needs."
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


# Configuration Customization Guide

> **Last Updated:** 2026-01-01  
> **Version:** 1.0.0

Guide for customizing OSM-Notes-Monitoring configuration for your specific needs.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Main Configuration](#main-configuration)
3. [Monitoring Thresholds](#monitoring-thresholds)
4. [Alert Configuration](#alert-configuration)
5. [Security Configuration](#security-configuration)
6. [Best Practices](#best-practices)

---

## Quick Start

Use the interactive configuration script:

```bash
./scripts/configure_production.sh
```

Or configure specific sections:

```bash
./scripts/configure_production.sh --main        # Main properties only
./scripts/configure_production.sh --monitoring  # Monitoring thresholds
./scripts/configure_production.sh --alerts      # Alert configuration
./scripts/configure_production.sh --security   # Security settings
./scripts/configure_production.sh --review     # Review current config
```

---

## Main Configuration

**File**: `etc/properties.sh`

### Database Settings

```bash
# Monitoring database (this project's database)
DBNAME="notes_monitoring"           # Production database name
DBHOST="localhost"                  # Database host
DBPORT="5432"                       # Database port
DBUSER="postgres"                   # Database user
# Password via PGPASSWORD env var or .pgpass file
```

### Monitored Databases

```bash
# Ingestion database (OSM-Notes-Ingestion)
INGESTION_DBNAME="notes"            # Ingestion database name
INGESTION_DBHOST="${DBHOST}"        # Same host by default
INGESTION_DBPORT="${DBPORT}"        # Same port by default
INGESTION_DBUSER="${DBUSER}"        # Same user by default

# Analytics database (OSM-Notes-Analytics)
ANALYTICS_DBNAME="notes_dwh"        # Analytics database name
ANALYTICS_DBHOST="${DBHOST}"
ANALYTICS_DBPORT="${DBPORT}"
ANALYTICS_DBUSER="${DBUSER}"
```

### Alerting

```bash
ADMIN_EMAIL="admin@example.com"     # Primary admin email
SEND_ALERT_EMAIL="true"             # Enable email alerts
SLACK_WEBHOOK_URL=""                # Slack webhook (optional)
```

### Monitoring Intervals

```bash
INGESTION_CHECK_INTERVAL=300        # 5 minutes
ANALYTICS_CHECK_INTERVAL=900        # 15 minutes
WMS_CHECK_INTERVAL=300              # 5 minutes
API_CHECK_INTERVAL=60               # 1 minute
DATA_CHECK_INTERVAL=3600            # 1 hour
INFRASTRUCTURE_CHECK_INTERVAL=300   # 5 minutes
```

### Repository Paths

```bash
INGESTION_REPO_PATH="/path/to/OSM-Notes-Ingestion"
ANALYTICS_REPO_PATH="/path/to/OSM-Notes-Analytics"
WMS_REPO_PATH="/path/to/OSM-Notes-WMS"
DATA_REPO_PATH="/path/to/OSM-Notes-Data"
```

### Logging

```bash
LOG_LEVEL="INFO"                    # DEBUG, INFO, WARN, ERROR
LOG_DIR="/var/log/osm-notes-monitoring"
TMP_DIR="/var/tmp/osm-notes-monitoring"
LOCK_DIR="/var/run/osm-notes-monitoring"
```

---

## Monitoring Thresholds

**File**: `config/monitoring.conf`

### Ingestion Thresholds

```bash
# Data freshness (seconds)
INGESTION_DATA_FRESHNESS_THRESHOLD=3600      # 1 hour

# Processing latency (seconds)
INGESTION_LATENCY_THRESHOLD=300              # 5 minutes

# Error rates (percentage)
INGESTION_MAX_ERROR_RATE=5                  # 5% max error rate
INGESTION_ERROR_COUNT_THRESHOLD=1000        # Max errors per period

# Data quality (percentage)
INGESTION_DATA_QUALITY_THRESHOLD=95          # 95% quality minimum

# API download success rate (percentage)
INGESTION_API_DOWNLOAD_SUCCESS_RATE_THRESHOLD=95
```

### Analytics Thresholds

```bash
# ETL execution age (hours)
ANALYTICS_ETL_EXECUTION_AGE_THRESHOLD=24    # 24 hours max

# ETL processing duration (seconds)
ANALYTICS_ETL_DURATION_THRESHOLD=3600        # 1 hour max

# Query performance (milliseconds)
ANALYTICS_SLOW_QUERY_THRESHOLD=5000         # 5 seconds

# Storage growth (percentage)
ANALYTICS_STORAGE_GROWTH_THRESHOLD=10       # 10% per period
```

### WMS Thresholds

```bash
# Response time (milliseconds)
WMS_RESPONSE_TIME_THRESHOLD=2000            # 2 seconds

# Error rate (percentage)
WMS_ERROR_RATE_THRESHOLD=5                 # 5% max

# Tile generation (milliseconds)
WMS_TILE_GENERATION_THRESHOLD=5000         # 5 seconds

# Cache hit rate (percentage)
WMS_CACHE_HIT_RATE_THRESHOLD=80           # 80% minimum
```

### Infrastructure Thresholds

```bash
# CPU usage (percentage)
INFRASTRUCTURE_CPU_THRESHOLD=80            # 80% warning, 90% critical

# Memory usage (percentage)
INFRASTRUCTURE_MEMORY_THRESHOLD=80         # 80% warning, 90% critical

# Disk usage (percentage)
INFRASTRUCTURE_DISK_THRESHOLD=85          # 85% warning, 90% critical
```

---

## Alert Configuration

**File**: `config/alerts.conf`

### Email Configuration

```bash
ADMIN_EMAIL="admin@example.com,team@example.com"  # Multiple emails (comma-separated)
SEND_ALERT_EMAIL="true"                           # Enable email alerts

# Email settings
EMAIL_FROM="monitoring@example.com"
EMAIL_SUBJECT_PREFIX="[OSM-Notes-Monitoring]"
```

### Slack Configuration

```bash
SLACK_ENABLED="true"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
SEND_ALERT_SLACK="true"

# Slack settings
SLACK_CHANNEL="#monitoring"
SLACK_USERNAME="OSM-Notes-Monitoring"
SLACK_ICON_EMOJI=":warning:"
```

### Alert Routing

```bash
# Route alerts by severity
ROUTE_CRITICAL_TO="email,slack"           # Critical: email + Slack
ROUTE_HIGH_TO="email"                      # High: email only
ROUTE_MEDIUM_TO="slack"                   # Medium: Slack only
ROUTE_LOW_TO=""                           # Low: no alerts
```

### Alert Deduplication

```bash
ALERT_DEDUPLICATION_ENABLED="true"        # Enable deduplication
ALERT_DEDUPLICATION_WINDOW=3600            # 1 hour window
```

### Escalation

```bash
# Escalation rules
ESCALATION_ENABLED="true"
ESCALATION_LEVEL1_DELAY=300                # 5 minutes
ESCALATION_LEVEL2_DELAY=900                # 15 minutes
ESCALATION_LEVEL3_DELAY=3600              # 1 hour
```

---

## Security Configuration

**File**: `config/security.conf`

### Rate Limiting

```bash
# Per-IP rate limiting
RATE_LIMIT_PER_IP_PER_MINUTE=60           # 60 requests/minute
RATE_LIMIT_PER_IP_PER_HOUR=1000           # 1000 requests/hour
RATE_LIMIT_BURST_SIZE=10                  # Burst allowance

# Per-API-key rate limiting
RATE_LIMIT_PER_API_KEY_PER_MINUTE=120
RATE_LIMIT_PER_API_KEY_PER_HOUR=5000

# Per-endpoint rate limiting
RATE_LIMIT_PER_ENDPOINT_PER_MINUTE=30
```

### DDoS Protection

```bash
# Attack detection thresholds
DDOS_CONNECTION_RATE_THRESHOLD=100        # Connections per second
DDOS_REQUEST_RATE_THRESHOLD=200           # Requests per second
DDOS_AUTO_BLOCK_ENABLED="true"           # Auto-block attacks
DDOS_BLOCK_DURATION=3600                 # Block for 1 hour
```

### IP Management

```bash
# Whitelist/Blacklist
IP_WHITELIST_ENABLED="true"
IP_BLACKLIST_ENABLED="true"

# Temporary blocks
TEMP_BLOCK_DURATION=3600                  # 1 hour default
AUTO_CLEANUP_EXPIRED_BLOCKS="true"       # Auto-cleanup
```

---

## Best Practices

### 1. Start Conservative

Begin with default thresholds and adjust based on actual behavior:

```bash
# Start with defaults, then adjust
# Monitor for 1-2 weeks
# Adjust thresholds based on actual patterns
```

### 2. Use Environment-Specific Configs

Keep separate configs for dev/staging/production:

```bash
# Development
cp etc/properties.sh.example etc/properties.dev.sh

# Production
cp etc/properties.sh.example etc/properties.prod.sh
```

### 3. Document Custom Settings

Add comments explaining why thresholds were changed:

```bash
# Custom threshold for our high-traffic system
INGESTION_DATA_FRESHNESS_THRESHOLD=7200  # 2 hours (increased due to batch processing)
```

### 4. Regular Review

Review and adjust thresholds quarterly:

```bash
# Review alert frequency
psql -d notes_monitoring -c "SELECT severity, COUNT(*) FROM alerts WHERE created_at > NOW() - INTERVAL '30 days' GROUP BY severity;"

# Adjust thresholds if too many false positives
```

### 5. Test Changes

Test configuration changes before production:

```bash
# Test in development first
DBNAME=osm_notes_monitoring_test ./scripts/test_config_validation.sh

# Validate before deploying
./scripts/configure_production.sh --review
```

### 6. Backup Configurations

Keep backups of working configurations:

```bash
# Backup before changes
cp etc/properties.sh etc/properties.sh.backup.$(date +%Y%m%d)

# Version control (if appropriate)
git add etc/properties.sh
git commit -m "Update production configuration"
```

---

## Common Customizations

### High-Traffic System

```bash
# Increase intervals to reduce load
INGESTION_CHECK_INTERVAL=600              # 10 minutes
ANALYTICS_CHECK_INTERVAL=1800            # 30 minutes

# Adjust thresholds for higher volume
INGESTION_ERROR_COUNT_THRESHOLD=5000     # Higher threshold
```

### Low-Traffic System

```bash
# More frequent checks
INGESTION_CHECK_INTERVAL=180             # 3 minutes
ANALYTICS_CHECK_INTERVAL=600             # 10 minutes

# Stricter thresholds
INGESTION_MAX_ERROR_RATE=2               # Lower tolerance
```

### Development Environment

```bash
# More verbose logging
LOG_LEVEL="DEBUG"

# Less frequent checks
INGESTION_CHECK_INTERVAL=1800            # 30 minutes

# Disable alerts
SEND_ALERT_EMAIL="false"
```

---

## Validation

After making changes, validate:

```bash
# Validate configuration
./scripts/test_config_validation.sh

# Review configuration
./scripts/configure_production.sh --review

# Test deployment
./scripts/test_deployment.sh --quick
```

---

**Last Updated:** 2026-01-01
