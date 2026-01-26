---
title: "Alert Configuration Reference"
description: "This document provides a comprehensive reference for all alert configuration options in the OSM-Notes-Monitoring system."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "monitoring"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Alert Configuration Reference

> **Purpose:** Comprehensive reference for alert configuration options  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document provides a comprehensive reference for all alert configuration options in the
OSM-Notes-Monitoring system.

## Configuration Files

### Primary Configuration

- **`config/alerts.conf`**: Main alert configuration file
- **`config/monitoring.conf`**: Database and general monitoring configuration

## Configuration Options

### Email Configuration

#### `ADMIN_EMAIL`

- **Type:** String
- **Default:** `admin@example.com`
- **Description:** Default administrator email address
- **Example:** `ADMIN_EMAIL="admin@example.com"`

#### `SEND_ALERT_EMAIL`

- **Type:** Boolean
- **Default:** `false`
- **Description:** Enable/disable email alert delivery
- **Values:** `true`, `false`
- **Example:** `SEND_ALERT_EMAIL="true"`

### Slack Configuration

#### `SLACK_ENABLED`

- **Type:** Boolean
- **Default:** `false`
- **Description:** Enable/disable Slack notifications
- **Values:** `true`, `false`
- **Example:** `SLACK_ENABLED="true"`

#### `SLACK_WEBHOOK_URL`

- **Type:** String (URL)
- **Default:** `""`
- **Description:** Slack webhook URL for sending notifications
- **Example:** `SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"`

#### `SLACK_CHANNEL`

- **Type:** String
- **Default:** `#monitoring`
- **Description:** Slack channel for alerts
- **Example:** `SLACK_CHANNEL="#alerts"`

### Alert Recipients

#### `CRITICAL_ALERT_RECIPIENTS`

- **Type:** String (comma-separated emails)
- **Default:** `${ADMIN_EMAIL}`
- **Description:** Email recipients for critical alerts
- **Example:** `CRITICAL_ALERT_RECIPIENTS="admin@example.com,oncall@example.com"`

#### `WARNING_ALERT_RECIPIENTS`

- **Type:** String (comma-separated emails)
- **Default:** `${ADMIN_EMAIL}`
- **Description:** Email recipients for warning alerts
- **Example:** `WARNING_ALERT_RECIPIENTS="team@example.com"`

#### `INFO_ALERT_RECIPIENTS`

- **Type:** String (comma-separated emails)
- **Default:** `""`
- **Description:** Email recipients for info alerts (empty to disable)
- **Example:** `INFO_ALERT_RECIPIENTS="info@example.com"`

### Deduplication Configuration

#### `ALERT_DEDUPLICATION_ENABLED`

- **Type:** Boolean
- **Default:** `true`
- **Description:** Enable/disable alert deduplication
- **Values:** `true`, `false`
- **Example:** `ALERT_DEDUPLICATION_ENABLED="true"`

#### `ALERT_DEDUPLICATION_WINDOW_MINUTES`

- **Type:** Integer
- **Default:** `60`
- **Description:** Time window (in minutes) for deduplication
- **Example:** `ALERT_DEDUPLICATION_WINDOW_MINUTES=60`

### Aggregation Configuration

#### `ALERT_AGGREGATION_ENABLED`

- **Type:** Boolean
- **Default:** `true`
- **Description:** Enable/disable alert aggregation
- **Values:** `true`, `false`
- **Example:** `ALERT_AGGREGATION_ENABLED="true"`

#### `ALERT_AGGREGATION_WINDOW_MINUTES`

- **Type:** Integer
- **Default:** `15`
- **Description:** Time window (in minutes) for aggregation
- **Example:** `ALERT_AGGREGATION_WINDOW_MINUTES=15`

### Retention Configuration

#### `ALERT_RETENTION_DAYS`

- **Type:** Integer
- **Default:** `180`
- **Description:** Number of days to retain resolved alerts
- **Example:** `ALERT_RETENTION_DAYS=180`

### Escalation Configuration

#### `ESCALATION_ENABLED`

- **Type:** Boolean
- **Default:** `true`
- **Description:** Enable/disable alert escalation
- **Values:** `true`, `false`
- **Example:** `ESCALATION_ENABLED="true"`

#### `ESCALATION_LEVEL1_MINUTES`

- **Type:** Integer
- **Default:** `15`
- **Description:** Minutes before level 1 escalation
- **Example:** `ESCALATION_LEVEL1_MINUTES=15`

#### `ESCALATION_LEVEL2_MINUTES`

- **Type:** Integer
- **Default:** `30`
- **Description:** Minutes before level 2 escalation
- **Example:** `ESCALATION_LEVEL2_MINUTES=30`

#### `ESCALATION_LEVEL3_MINUTES`

- **Type:** Integer
- **Default:** `60`
- **Description:** Minutes before level 3 escalation
- **Example:** `ESCALATION_LEVEL3_MINUTES=60`

#### `ESCALATION_LEVEL1_RECIPIENTS`

- **Type:** String (comma-separated emails)
- **Default:** `${ADMIN_EMAIL}`
- **Description:** Recipients for level 1 escalation
- **Example:** `ESCALATION_LEVEL1_RECIPIENTS="oncall@example.com"`

#### `ESCALATION_LEVEL2_RECIPIENTS`

- **Type:** String (comma-separated emails)
- **Default:** `${ADMIN_EMAIL}`
- **Description:** Recipients for level 2 escalation
- **Example:** `ESCALATION_LEVEL2_RECIPIENTS="manager@example.com"`

#### `ESCALATION_LEVEL3_RECIPIENTS`

- **Type:** String (comma-separated emails)
- **Default:** `${ADMIN_EMAIL}`
- **Description:** Recipients for level 3 escalation
- **Example:** `ESCALATION_LEVEL3_RECIPIENTS="director@example.com"`

### On-Call Configuration

#### `ONCALL_ROTATION_ENABLED`

- **Type:** Boolean
- **Default:** `false`
- **Description:** Enable/disable on-call rotation
- **Values:** `true`, `false`
- **Example:** `ONCALL_ROTATION_ENABLED="true"`

#### `ONCALL_ROTATION_SCHEDULE`

- **Type:** String
- **Default:** `weekly`
- **Description:** On-call rotation schedule
- **Values:** `daily`, `weekly`, `monthly`
- **Example:** `ONCALL_ROTATION_SCHEDULE="weekly"`

#### `ONCALL_PRIMARY`

- **Type:** String (email)
- **Default:** `${ADMIN_EMAIL}`
- **Description:** Primary on-call contact
- **Example:** `ONCALL_PRIMARY="oncall-primary@example.com"`

#### `ONCALL_SECONDARY`

- **Type:** String (email)
- **Default:** `${ADMIN_EMAIL}`
- **Description:** Secondary on-call contact
- **Example:** `ONCALL_SECONDARY="oncall-secondary@example.com"`

## Alert Rules File

### Location

- **`config/alert_rules.conf`**: Alert routing rules file

### Format

```
component:alert_level:alert_type:route
```

### Examples

```
INGESTION:critical:data_quality:admin@example.com
INGESTION:warning:performance:team@example.com
ANALYTICS:critical:*:oncall@example.com
*:critical:*:admin@example.com
```

## Alert Templates Directory

### Location

- **`config/alert_templates/`**: Directory for alert templates

### Template Files

- **Format:** `{template_id}.template`
- **Example:** `default.template`, `critical.template`

## Configuration Examples

### Basic Configuration

```bash
# config/alerts.conf
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"
SLACK_ENABLED="false"

CRITICAL_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
WARNING_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
INFO_ALERT_RECIPIENTS=""

ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW_MINUTES=60
```

### Advanced Configuration with Escalation

```bash
# config/alerts.conf
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"
SLACK_ENABLED="true"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

CRITICAL_ALERT_RECIPIENTS="oncall@example.com"
WARNING_ALERT_RECIPIENTS="team@example.com"
INFO_ALERT_RECIPIENTS=""

ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW_MINUTES=60

ESCALATION_ENABLED="true"
ESCALATION_LEVEL1_MINUTES=15
ESCALATION_LEVEL2_MINUTES=30
ESCALATION_LEVEL3_MINUTES=60
ESCALATION_LEVEL1_RECIPIENTS="oncall@example.com"
ESCALATION_LEVEL2_RECIPIENTS="manager@example.com"
ESCALATION_LEVEL3_RECIPIENTS="director@example.com"

ONCALL_ROTATION_ENABLED="true"
ONCALL_ROTATION_SCHEDULE="weekly"
ONCALL_PRIMARY="oncall-primary@example.com"
ONCALL_SECONDARY="oncall-secondary@example.com"
```

## Environment Variables

All configuration options can be overridden via environment variables:

```bash
export ADMIN_EMAIL="admin@example.com"
export SEND_ALERT_EMAIL="true"
export SLACK_ENABLED="true"
```

## Validation

Configuration is validated on script startup. Invalid values will log warnings and use defaults.

## References

- **Alerting Guide**: `docs/ALERTING_GUIDE.md` - Comprehensive alerting guide
- **On-Call Procedures**: `docs/ONCALL_PROCEDURES.md` - On-call procedures
- **Configuration Example**: `config/alerts.conf.example` - Example configuration file
