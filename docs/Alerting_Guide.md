---
title: "Alerting System Guide"
description: "The OSM-Notes-Monitoring alerting system provides comprehensive alert management including:"
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


# Alerting System Guide

> **Purpose:** Comprehensive guide for the OSM-Notes-Monitoring alerting system  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Using the Alert System](#using-the-alert-system)
6. [Alert Management](#alert-management)
7. [Escalation](#escalation)
8. [Alert Rules and Routing](#alert-rules-and-routing)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)
11. [Reference Documentation](#reference-documentation)

---

## Overview

The OSM-Notes-Monitoring alerting system provides comprehensive alert management including:

- **Alert Storage**: All alerts stored in PostgreSQL database
- **Deduplication**: Prevents duplicate alerts within a time window
- **Aggregation**: Groups similar alerts for better visibility
- **History**: Complete alert history tracking
- **Acknowledgment**: Alert acknowledgment workflow
- **Escalation**: Automatic escalation based on time and severity
- **Multi-Channel Delivery**: Email and Slack notifications
- **Routing**: Configurable alert routing based on rules
- **Templates**: Customizable alert message templates

### Key Features

- **Automated Alerting**: Alerts generated automatically by monitoring scripts
- **Deduplication**: Prevents alert spam from repeated issues
- **Aggregation**: Groups related alerts for easier management
- **Escalation**: Automatic escalation for unacknowledged alerts
- **Multi-Channel**: Email and Slack support
- **History Tracking**: Complete audit trail of all alerts
- **Flexible Routing**: Route alerts based on component, level, or type

---

## Prerequisites

Before setting up the alerting system, ensure you have:

1. **PostgreSQL Database**: A PostgreSQL database for storing alerts
   - Version 12 or higher recommended
   - Database created and accessible
   - User with appropriate permissions
   - `alerts` table created (via `sql/init.sql`)

2. **Email Configuration** (optional):
   - `mutt` installed for email alerts
   - SMTP server configured (if using external SMTP)

3. **Slack Configuration** (optional):
   - Slack webhook URL
   - Slack workspace access

4. **Bash Environment**: Bash 4.0 or higher

---

## Quick Start

### 1. Configure Database Connection

Edit `config/monitoring.conf`:

```bash
# Monitoring database
DBNAME=osm_notes_monitoring
DBHOST=localhost
DBPORT=5432
DBUSER=monitoring_user
```

### 2. Configure Alert Settings

Copy and edit `config/alerts.conf.example`:

```bash
cp config/alerts.conf.example config/alerts.conf
```

Edit `config/alerts.conf`:

```bash
# Email
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"

# Slack (optional)
SLACK_ENABLED="false"
SLACK_WEBHOOK_URL=""

# Alert Levels
CRITICAL_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
WARNING_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
INFO_ALERT_RECIPIENTS=""

# Deduplication
ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW_MINUTES=60
```

### 3. Send a Test Alert

```bash
# Send test alert
./bin/alerts/sendAlert.sh INGESTION warning test "Test alert message"
```

### 4. View Alerts

```bash
# List active alerts
./bin/alerts/alertManager.sh list

# List alerts for specific component
./bin/alerts/alertManager.sh list INGESTION active
```

---

## Configuration

### Required Configuration

#### Database Configuration

```bash
# Monitoring database (stores alerts)
DBNAME=osm_notes_monitoring
DBHOST=localhost
DBPORT=5432
DBUSER=monitoring_user
```

#### Alert Configuration

Create `config/alerts.conf`:

```bash
# Email Configuration
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"

# Slack Configuration (optional)
SLACK_ENABLED="false"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
SLACK_CHANNEL="#monitoring"

# Alert Recipients
CRITICAL_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
WARNING_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
INFO_ALERT_RECIPIENTS=""  # Optional, leave empty to disable

# Deduplication
ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW_MINUTES=60

# Aggregation
ALERT_AGGREGATION_ENABLED="true"
ALERT_AGGREGATION_WINDOW_MINUTES=15

# Retention
ALERT_RETENTION_DAYS=180
```

### Optional Configuration

#### Escalation Configuration

```bash
# Escalation
ESCALATION_ENABLED="true"
ESCALATION_LEVEL1_MINUTES=15
ESCALATION_LEVEL2_MINUTES=30
ESCALATION_LEVEL3_MINUTES=60

# Escalation Recipients
ESCALATION_LEVEL1_RECIPIENTS="${ADMIN_EMAIL}"
ESCALATION_LEVEL2_RECIPIENTS="${ADMIN_EMAIL}"
ESCALATION_LEVEL3_RECIPIENTS="${ADMIN_EMAIL}"
```

#### On-Call Rotation (optional)

```bash
# On-Call Rotation
ONCALL_ROTATION_ENABLED="false"
ONCALL_ROTATION_SCHEDULE="weekly"
ONCALL_PRIMARY="${ADMIN_EMAIL}"
ONCALL_SECONDARY="${ADMIN_EMAIL}"
```

---

## Using the Alert System

### Sending Alerts

#### From Monitoring Scripts

Monitoring scripts automatically send alerts:

```bash
# Example: From monitorIngestion.sh
send_alert "INGESTION" "critical" "data_quality" "Data quality check failed"
```

#### Manually

```bash
# Using sendAlert.sh
./bin/alerts/sendAlert.sh INGESTION critical data_quality "Data quality check failed"

# With metadata
./bin/alerts/sendAlert.sh INGESTION warning performance "Query slow" '{"query_time": 5000}'

# HTML format
./bin/alerts/sendAlert.sh --format html INGESTION critical availability "Service down"
```

### Alert Levels

- **critical**: Immediate attention required, service at risk
- **warning**: Attention required, potential issues
- **info**: Informational, no immediate action needed

---

## Alert Management

### List Alerts

```bash
# List all active alerts
./bin/alerts/alertManager.sh list

# List alerts for specific component
./bin/alerts/alertManager.sh list INGESTION active

# List resolved alerts
./bin/alerts/alertManager.sh list "" resolved
```

### View Alert Details

```bash
# Show alert details
./bin/alerts/alertManager.sh show <alert-id>
```

### Acknowledge Alerts

```bash
# Acknowledge an alert
./bin/alerts/alertManager.sh acknowledge <alert-id> admin

# Short form
./bin/alerts/alertManager.sh ack <alert-id> admin
```

### Resolve Alerts

```bash
# Resolve an alert
./bin/alerts/alertManager.sh resolve <alert-id> admin
```

### Aggregate Alerts

```bash
# Aggregate alerts for component
./bin/alerts/alertManager.sh aggregate INGESTION 60

# Aggregate all alerts
./bin/alerts/alertManager.sh aggregate "" 60
```

### View Alert History

```bash
# View 7-day history for component
./bin/alerts/alertManager.sh history INGESTION 7

# View 30-day history
./bin/alerts/alertManager.sh history INGESTION 30
```

### View Statistics

```bash
# View alert statistics
./bin/alerts/alertManager.sh stats

# View statistics for component
./bin/alerts/alertManager.sh stats INGESTION
```

### Cleanup Old Alerts

```bash
# Cleanup alerts older than 180 days
./bin/alerts/alertManager.sh cleanup 180
```

---

## Escalation

### Check Escalation

```bash
# Check all alerts for escalation
./bin/alerts/escalation.sh check

# Check alerts for specific component
./bin/alerts/escalation.sh check INGESTION
```

### Manual Escalation

```bash
# Escalate alert to level 1
./bin/alerts/escalation.sh escalate <alert-id> 1

# Escalate alert to level 2
./bin/alerts/escalation.sh escalate <alert-id> 2
```

### View Escalation Rules

```bash
# Show escalation rules
./bin/alerts/escalation.sh rules

# Show rules for component
./bin/alerts/escalation.sh rules INGESTION
```

### On-Call Schedule

```bash
# Show today's on-call
./bin/alerts/escalation.sh oncall

# Show on-call for specific date
./bin/alerts/escalation.sh oncall 2025-12-28
```

---

## Alert Rules and Routing

### List Rules

```bash
# List all alert rules
./bin/alerts/alertRules.sh list

# List rules for component
./bin/alerts/alertRules.sh list INGESTION
```

### Add Rule

```bash
# Add alert rule: component:level:type:route
./bin/alerts/alertRules.sh add INGESTION critical data_quality "admin@example.com"

# Route to Slack channel
./bin/alerts/alertRules.sh add INGESTION warning performance "#monitoring"
```

### Remove Rule

```bash
# Remove rule by line number
./bin/alerts/alertRules.sh remove 1

# Remove rule by pattern
./bin/alerts/alertRules.sh remove "INGESTION:critical"
```

### Get Routing

```bash
# Get routing for alert
./bin/alerts/alertRules.sh route INGESTION critical data_quality
```

### Alert Templates

```bash
# List templates
./bin/alerts/alertRules.sh template list

# Show template
./bin/alerts/alertRules.sh template show default

# Add/update template
./bin/alerts/alertRules.sh template add custom "Custom template content"
```

---

## Troubleshooting

### Alerts Not Being Sent

**Symptoms:** Alerts not appearing in database or email

**Solutions:**

1. Check database connection: `psql -d osm_notes_monitoring -c "SELECT COUNT(*) FROM alerts;"`
2. Verify configuration: `cat config/alerts.conf`
3. Check logs: `tail -f logs/send_alert.log`
4. Verify `SEND_ALERT_EMAIL` is set to `true`
5. Test email: `echo "test" | mutt -s "test" admin@example.com`

### Duplicate Alerts

**Symptoms:** Same alert appearing multiple times

**Solutions:**

1. Verify deduplication is enabled: `ALERT_DEDUPLICATION_ENABLED="true"`
2. Check deduplication window: `ALERT_DEDUPLICATION_WINDOW_MINUTES`
3. Review alert messages (must be identical for deduplication)

### Email Not Working

**Symptoms:** Alerts stored but emails not sent

**Solutions:**

1. Check `mutt` installation: `which mutt`
2. Test email manually: `echo "test" | mutt -s "test" admin@example.com`
3. Verify `SEND_ALERT_EMAIL="true"`
4. Check SMTP configuration (if using external SMTP)

### Slack Not Working

**Symptoms:** Slack notifications not received

**Solutions:**

1. Verify `SLACK_ENABLED="true"`
2. Check `SLACK_WEBHOOK_URL` is set correctly
3. Test webhook:
   `curl -X POST -H 'Content-type: application/json' --data '{"text":"test"}' ${SLACK_WEBHOOK_URL}`
4. Check Slack channel permissions

### Escalation Not Working

**Symptoms:** Alerts not escalating automatically

**Solutions:**

1. Verify escalation is enabled: `ESCALATION_ENABLED="true"`
2. Check escalation thresholds: `ESCALATION_LEVEL1_MINUTES`, etc.
3. Run escalation check manually: `./bin/alerts/escalation.sh check`
4. Verify alert age exceeds thresholds

---

## Best Practices

### Alert Configuration

1. **Set Appropriate Recipients**: Configure different recipients for different alert levels
2. **Enable Deduplication**: Prevent alert spam from repeated issues
3. **Configure Escalation**: Set up escalation for critical alerts
4. **Regular Cleanup**: Cleanup old resolved alerts regularly

### Alert Management

1. **Acknowledge Promptly**: Acknowledge alerts when investigating
2. **Resolve When Fixed**: Resolve alerts when issues are fixed
3. **Review Regularly**: Review alert statistics regularly
4. **Document Resolutions**: Add notes to alert metadata when resolving

### Escalation

1. **Set Realistic Thresholds**: Set escalation thresholds based on response times
2. **Configure Recipients**: Set different recipients for each escalation level
3. **Monitor Escalations**: Review escalated alerts regularly
4. **Adjust Thresholds**: Adjust thresholds based on experience

### Routing

1. **Route by Severity**: Route critical alerts to on-call, warnings to team
2. **Use Rules**: Define rules for common alert patterns
3. **Test Routing**: Test routing rules before deploying
4. **Document Rules**: Document routing rules for team reference

---

## Reference Documentation

- **Alert Configuration Reference**: `docs/ALERT_CONFIGURATION_REFERENCE.md` - Detailed
  configuration options
- **On-Call Procedures**: `docs/ONCALL_PROCEDURES.md` - On-call procedures and guidelines
- **Alert Functions**: `bin/lib/alertFunctions.sh` - Alert function library
- **Alert Manager**: `bin/alerts/alertManager.sh` - Alert management script
- **Escalation**: `bin/alerts/escalation.sh` - Escalation script
- **Alert Rules**: `bin/alerts/alertRules.sh` - Alert rules management
- **Send Alert**: `bin/alerts/sendAlert.sh` - Enhanced alert sender

---

## Support

For issues or questions:

1. Check troubleshooting section above
2. Review logs: `logs/send_alert.log`, `logs/alert_manager.log`, `logs/escalation.log`
3. Review alerts in database
4. Consult reference documentation
