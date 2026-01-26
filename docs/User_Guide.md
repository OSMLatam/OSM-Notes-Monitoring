---
title: "OSM Notes Monitoring - User Guide"
description: "OSM Notes Monitoring is a centralized monitoring and alerting system for the entire OSM Notes"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "guide"
audience:
  - "users"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# OSM Notes Monitoring - User Guide

> **Purpose:** Comprehensive guide for end users of the OSM Notes Monitoring system  
> **Version:** 1.0.0  
> **Date:** 2025-12-31  
> **Status:** Active

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Understanding Dashboards](#understanding-dashboards)
4. [Working with Alerts](#working-with-alerts)
5. [Monitoring Components](#monitoring-components)
6. [Security Features](#security-features)
7. [Common Tasks](#common-tasks)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Reference Documentation](#reference-documentation)

---

## Introduction

### What is OSM Notes Monitoring?

OSM Notes Monitoring is a centralized monitoring and alerting system for the entire OSM Notes
ecosystem. It provides:

- **Unified Visibility**: Single dashboard to monitor all OSM Notes components
- **Automated Alerting**: Get notified when issues occur
- **Security Protection**: Rate limiting and DDoS protection for APIs
- **Performance Tracking**: Monitor response times and resource usage
- **Data Quality**: Track data freshness and integrity across components

### Who Should Use This Guide?

This guide is for:

- **System Administrators**: Setting up and maintaining the monitoring system
- **Operations Team**: Day-to-day monitoring and alert management
- **Developers**: Understanding how monitoring integrates with their components
- **On-Call Engineers**: Responding to alerts and incidents

---

## Getting Started

### Prerequisites

Before using OSM Notes Monitoring, ensure you have:

1. **Access to the Monitoring System**
   - Access to the monitoring server
   - Database credentials (if needed)
   - Grafana access (if using Grafana dashboards)

2. **Understanding of Monitored Components**
   - Familiarity with OSM Notes ecosystem
   - Knowledge of which components are being monitored
   - Understanding of alert thresholds

### Quick Setup

For a quick setup guide, see [Quick Start Guide](./Quick_Start_Guide.md).

For detailed setup instructions, see [Setup Guide](./Monitoring_SETUP_Guide.md).

---

## Understanding Dashboards

### Dashboard Types

OSM Notes Monitoring provides two types of dashboards:

#### 1. HTML Dashboards

Simple, lightweight dashboards that work without Grafana.

**Access:**

```bash
# Update dashboard data
./bin/dashboard/updateDashboard.sh html

# Open in browser
open dashboards/html/overview.html
```

**Available Dashboards:**

- **Overview**: High-level view of all components
- **Component Status**: Detailed view per component
- **Health Check**: Quick health status

For more details, see [Dashboard Guide](./Dashboard_Guide.md).

#### 2. Grafana Dashboards

Advanced dashboards with rich visualization capabilities.

**Access:**

- Navigate to Grafana URL (typically `http://localhost:3000`)
- Login with your credentials
- Select dashboard from the dashboard list

**Available Dashboards:**

- **Overview**: System-wide overview
- **Ingestion**: Ingestion component monitoring
- **Analytics**: Analytics/DWH monitoring
- **WMS**: WMS service monitoring
- **API**: API monitoring
- **Infrastructure**: Infrastructure monitoring

For Grafana setup, see [Grafana Setup Guide](./Grafana_Setup_Guide.md).

### Reading Dashboard Metrics

#### Component Health Status

- **Healthy** (Green): Component is operating normally
- **Degraded** (Yellow): Component has minor issues but is functional
- **Down** (Red): Component is not responding or has critical issues
- **Unknown** (Gray): Status cannot be determined

#### Key Metrics

Common metrics you'll see:

- **Error Rate**: Percentage of requests/operations that fail
- **Response Time**: Time taken to respond to requests
- **Data Freshness**: How recent the data is
- **Resource Usage**: CPU, memory, disk usage
- **Throughput**: Number of operations per unit time

---

## Working with Alerts

### Understanding Alerts

Alerts notify you when something requires attention. Alerts have:

- **Level**: `critical`, `warning`, or `info`
- **Component**: Which component generated the alert
- **Type**: Category of alert (e.g., `availability`, `performance`, `data_quality`)
- **Message**: Human-readable description
- **Status**: `active`, `acknowledged`, or `resolved`

### Viewing Alerts

#### Via Dashboard

Alerts appear in dashboard panels showing:

- Active alerts count
- Recent alerts list
- Alert details (component, level, message, timestamp)

#### Via Database

Query alerts directly:

```sql
-- View active alerts
SELECT * FROM alerts WHERE status = 'active' ORDER BY created_at DESC;

-- View alerts by component
SELECT * FROM alerts WHERE component = 'ingestion' ORDER BY created_at DESC;

-- View critical alerts
SELECT * FROM alerts WHERE alert_level = 'critical' AND status = 'active';
```

### Alert Channels

Alerts are delivered via:

1. **Email**: Sent to configured recipients
2. **Slack**: Posted to configured Slack channels
3. **Database**: Stored in PostgreSQL for querying

### Managing Alerts

#### Acknowledging Alerts

When you're working on an issue, acknowledge the alert:

```bash
# Acknowledge an alert (via script)
./bin/alerts/alertManager.sh acknowledge <alert_id>
```

Or via SQL:

```sql
UPDATE alerts SET status = 'acknowledged' WHERE id = <alert_id>;
```

#### Resolving Alerts

When the issue is fixed, resolve the alert:

```bash
# Resolve an alert
./bin/alerts/alertManager.sh resolve <alert_id>
```

Or via SQL:

```sql
UPDATE alerts SET status = 'resolved' WHERE id = <alert_id>;
```

### Alert Escalation

Alerts automatically escalate if not acknowledged:

- **Level 1**: After 15 minutes → Escalated to primary on-call
- **Level 2**: After 30 minutes → Escalated to secondary on-call
- **Level 3**: After 60 minutes → Escalated to management

For escalation configuration, see [Alerting Guide](./Alerting_Guide.md).

---

## Monitoring Components

### Ingestion Monitoring

Monitors the OSM-Notes-Ingestion component:

- Script execution status
- Error rates from logs
- Data freshness
- Database performance
- API download success rates

**Key Metrics:**

- `scripts_executable`: Number of executable scripts found
- `error_rate_percent`: Percentage of operations that fail
- `data_freshness_hours`: Hours since last data update
- `db_query_time_ms`: Database query response time

For details, see [Ingestion Monitoring Guide](./Ingestion_Monitoring_Guide.md).

### Analytics Monitoring

Monitors the OSM-Notes-Analytics component:

- ETL job status
- Data mart freshness
- Query performance
- Database size and growth
- Disk usage

**Key Metrics:**

- `etl_jobs_running`: Number of ETL jobs currently running
- `data_mart_freshness_hours`: Hours since last data mart update
- `avg_query_time_ms`: Average query execution time
- `db_size_bytes`: Total database size

For details, see [Analytics Monitoring Guide](./Analytics_Monitoring_Guide.md).

### WMS Monitoring

Monitors the OSM-Notes-WMS component:

- Service availability
- HTTP health checks
- Response times
- Error rates
- Tile generation performance

**Key Metrics:**

- `service_availability`: Service is available (1) or not (0)
- `service_response_time_ms`: HTTP response time
- `health_status`: Health check status
- `error_rate_percent`: Percentage of failed requests

For details, see [WMS Monitoring Guide](./WMS_Monitoring_Guide.md).

### API Monitoring

Monitors the OSM-Notes-API component:

- API availability
- Rate limiting status
- Security incidents
- Request rates
- Response times

**Key Metrics:**

- `api_availability`: API is available (1) or not (0)
- `request_rate_per_second`: Requests per second
- `security_incidents_count`: Number of security incidents
- `rate_limit_hits`: Number of rate limit violations

For details, see [API Security Guide](./API_Security_Guide.md).

### Infrastructure Monitoring

Monitors server infrastructure:

- CPU usage
- Memory usage
- Disk space
- Network connectivity
- Database health

**Key Metrics:**

- `cpu_usage_percent`: CPU utilization percentage
- `memory_usage_percent`: Memory utilization percentage
- `disk_usage_percent`: Disk space usage percentage
- `db_connections`: Number of database connections

For details, see [Infrastructure Monitoring Guide](./Infrastructure_Monitoring_Guide.md).

---

## Security Features

### Rate Limiting

Rate limiting protects APIs from abuse:

- **Per-IP Limits**: Limit requests per IP address
- **Per-API-Key Limits**: Limit requests per API key
- **Per-Endpoint Limits**: Different limits for different endpoints

**Viewing Rate Limits:**

```bash
# Check rate limit statistics
./bin/security/rateLimiter.sh stats

# Check if a specific IP/endpoint is allowed
./bin/security/rateLimiter.sh check 192.168.1.100 /api/notes
```

For details, see [Rate Limiting Guide](./Rate_Limiting_Guide.md).

### DDoS Protection

Automatic DDoS detection and mitigation:

- Detects unusual traffic patterns
- Automatically blocks suspicious IPs
- Alerts when DDoS is detected

**Viewing DDoS Status:**

```bash
# Check DDoS protection statistics
./bin/security/ddosProtection.sh stats

# Check for DDoS attacks
./bin/security/ddosProtection.sh check
```

### Abuse Detection

Detects and responds to abuse patterns:

- Unusual request patterns
- Suspicious behavior
- Automatic IP blocking

**Viewing Abuse Detection:**

```bash
# Check abuse detection statistics
./bin/security/abuseDetection.sh stats

# Analyze for abuse patterns
./bin/security/abuseDetection.sh analyze
```

For details, see [Security Best Practices](./Security_Best_Practices.md).

---

## Common Tasks

### Checking Component Health

```bash
# Check all components
./bin/monitor/monitorIngestion.sh
./bin/monitor/monitorAnalytics.sh
./bin/monitor/monitorWMS.sh

# Or use the unified monitor
./bin/monitor/monitorData.sh
```

### Viewing Recent Metrics

```bash
# Generate metrics report
./bin/dashboard/generateMetrics.sh

# View in dashboard
open dashboards/html/overview.html
```

### Updating Dashboard Data

```bash
# Update HTML dashboards
./bin/dashboard/updateDashboard.sh html

# Update Grafana dashboards
./bin/dashboard/updateDashboard.sh grafana
```

### Running Health Checks

```bash
# Check database connection (using psql directly)
psql -d osm_notes_monitoring -c "SELECT 1;" || echo "Database connection failed"

# Check component health
psql -d osm_notes_monitoring -c "SELECT * FROM component_health;"

# Or use a monitoring script which includes the check
./bin/monitor/monitorInfrastructure.sh
```

### Viewing Alert History

```sql
-- Last 24 hours of alerts
SELECT * FROM alerts
WHERE created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- Alerts by component
SELECT component, alert_level, COUNT(*)
FROM alerts
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY component, alert_level;
```

---

## Troubleshooting

### Dashboard Shows No Data

**Possible Causes:**

1. Metrics haven't been generated yet
2. Database connection issues
3. Monitoring scripts haven't run

**Solutions:**

```bash
# Generate metrics
./bin/dashboard/generateMetrics.sh

# Check database connection
psql -d osm_notes_monitoring -c "SELECT COUNT(*) FROM metrics;"

# Run monitoring scripts
./bin/monitor/monitorIngestion.sh
```

### Alerts Not Being Sent

**Possible Causes:**

1. Email/Slack not configured
2. Alert deduplication preventing duplicates
3. Alert level below threshold

**Solutions:**

```bash
# Check alert configuration
cat config/alerts.conf

# Check recent alerts
psql -d osm_notes_monitoring -c "SELECT * FROM alerts ORDER BY created_at DESC LIMIT 10;"

# Test alert sending (COMPONENT LEVEL TYPE MESSAGE)
./bin/alerts/sendAlert.sh TEST warning test "Test alert"
```

### Component Shows as Unknown

**Possible Causes:**

1. Monitoring script hasn't run
2. Component not accessible
3. Database connection issues

**Solutions:**

```bash
# Run monitoring for the component
./bin/monitor/monitorIngestion.sh  # or monitorAnalytics.sh, etc.

# Check component accessibility
curl -I http://wms-service-url/health  # for WMS

# Check database
psql -d osm_notes_monitoring -c "SELECT * FROM component_health WHERE component = 'ingestion';"
```

### High Error Rates

**Investigation Steps:**

1. Check component logs
2. Review recent alerts
3. Check component health status
4. Review metrics over time

**Commands:**

```bash
# View recent errors in metrics
psql -d osm_notes_monitoring -c "
  SELECT timestamp, metric_value
  FROM metrics
  WHERE component = 'ingestion'
    AND metric_name = 'error_rate_percent'
  ORDER BY timestamp DESC
  LIMIT 20;
"

# Check component logs
tail -f /path/to/component/logs/error.log
```

For more troubleshooting, see component-specific troubleshooting guides:

- [Ingestion Troubleshooting](./INGESTION_Troubleshooting_Guide.md)
- [WMS Service Availability Runbook](./WMS_SERVICE_AVAILABILITY_Runbook.md)
- [ETL Monitoring Runbook](./ETL_MONITORING_Runbook.md)

---

## Best Practices

### Daily Operations

1. **Check Dashboards Daily**: Review component health and metrics
2. **Monitor Alerts**: Respond to alerts promptly
3. **Review Metrics**: Look for trends and anomalies
4. **Update Dashboards**: Keep dashboard data fresh

### Alert Management

1. **Acknowledge Promptly**: Acknowledge alerts when you start working on them
2. **Resolve When Fixed**: Mark alerts as resolved when issues are fixed
3. **Document Actions**: Document what you did to resolve issues
4. **Review Escalations**: Learn from escalated alerts

### Performance Monitoring

1. **Track Trends**: Watch for gradual performance degradation
2. **Set Baselines**: Understand normal performance levels
3. **Investigate Spikes**: Investigate sudden performance changes
4. **Plan Capacity**: Use metrics to plan for growth

### Security

1. **Review Security Alerts**: Check security alerts regularly
2. **Monitor Rate Limits**: Watch for unusual rate limit hits
3. **Review Blocked IPs**: Check if legitimate IPs are blocked
4. **Update Thresholds**: Adjust thresholds based on actual usage

---

## Reference Documentation

### Setup and Configuration

- [Quick Start Guide](./Quick_Start_Guide.md): Get started quickly
- [Setup Guide](./Monitoring_SETUP_Guide.md): Detailed setup instructions
- [Configuration Reference](./Configuration_Reference.md): All configuration options
- [Grafana Setup Guide](./Grafana_Setup_Guide.md): Grafana dashboard setup

### Component Guides

- [Ingestion Monitoring Guide](./Ingestion_Monitoring_Guide.md): Ingestion monitoring
- [Analytics Monitoring Guide](./Analytics_Monitoring_Guide.md): Analytics/DWH monitoring
- [WMS Monitoring Guide](./WMS_Monitoring_Guide.md): WMS service monitoring
- [Infrastructure Monitoring Guide](./Infrastructure_Monitoring_Guide.md): Infrastructure monitoring

### Alerting and Security

- [Alerting Guide](./Alerting_Guide.md): Alert system usage
- [Alert Configuration Reference](./ALERT_Configuration_Reference.md): Alert configuration
- [API Security Guide](./API_Security_Guide.md): API security features
- [Rate Limiting Guide](./Rate_Limiting_Guide.md): Rate limiting configuration
- [Security Best Practices](./Security_Best_Practices.md): Security guidelines

### Dashboards

- [Dashboard Guide](./Dashboard_Guide.md): Using dashboards
- [Dashboard Customization Guide](./Dashboard_Customization_Guide.md): Customizing dashboards

### Troubleshooting

- [Ingestion Troubleshooting Guide](./INGESTION_Troubleshooting_Guide.md): Ingestion issues
- [WMS Service Availability Runbook](./WMS_SERVICE_AVAILABILITY_Runbook.md): WMS issues
- [ETL Monitoring Runbook](./ETL_MONITORING_Runbook.md): ETL issues
- [Security Incident Response Runbook](./SECURITY_INCIDENT_RESPONSE_Runbook.md): Security incidents

### Operations

- [On-Call Procedures](./Oncall_Procedures.md): On-call responsibilities
- [Capacity Planning Guide](./Capacity_Planning_Guide.md): Capacity planning
- [Query Performance Optimization](./Query_Performance_Optimization.md): Database optimization

### Architecture and Development

- [Architecture Proposal](./Monitoring_Architecture_Proposal.md): System architecture
- [Implementation Plan](./Implementation_Plan.md): Implementation details
- [Coding Standards](./Coding_Standards.md): Development standards
- [Database Schema](./Database_Schema.md): Database structure

---

## Getting Help

### Documentation

- See [Documentation Index](./Documentation_Index.md) for complete list
- Check component-specific guides for detailed information
- Review troubleshooting guides for common issues

### Support

- Check logs: `logs/` directory
- Review alert history in database
- Check component-specific documentation

---

**Last Updated:** 2025-12-31  
**Version:** 1.0.0
