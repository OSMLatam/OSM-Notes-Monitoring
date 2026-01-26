---
title: "On-Call Procedures"
description: "This document provides procedures and guidelines for on-call operations in the OSM-Notes-Monitoring system."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "documentation"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# On-Call Procedures

> **Purpose:** Procedures and guidelines for on-call operations  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document provides procedures and guidelines for on-call operations in the OSM-Notes-Monitoring
system.

## On-Call Responsibilities

### Primary Responsibilities

1. **Monitor Alerts**: Monitor active alerts and respond promptly
2. **Acknowledge Alerts**: Acknowledge alerts when investigating
3. **Resolve Issues**: Resolve issues or escalate as needed
4. **Document Actions**: Document actions taken in alert metadata
5. **Escalate When Needed**: Escalate to next level if unable to resolve

### Response Times

- **CRITICAL Alerts**: Respond within 15 minutes
- **WARNING Alerts**: Respond within 1 hour
- **INFO Alerts**: Review within 24 hours

## On-Call Schedule

### Viewing Schedule

```bash
# Show today's on-call
./bin/alerts/escalation.sh oncall

# Show on-call for specific date
./bin/alerts/escalation.sh oncall 2025-12-28
```

### Rotation

On-call rotation can be configured in `config/alerts.conf`:

```bash
ONCALL_ROTATION_ENABLED="true"
ONCALL_ROTATION_SCHEDULE="weekly"  # daily, weekly, monthly
ONCALL_PRIMARY="oncall-primary@example.com"
ONCALL_SECONDARY="oncall-secondary@example.com"
```

## Alert Response Workflow

### 1. Receive Alert

- Alert received via email/Slack
- Alert stored in database
- Alert appears in active alerts list

### 2. Acknowledge Alert

```bash
# Acknowledge alert
./bin/alerts/alertManager.sh acknowledge <alert-id> <your-name>
```

**When to Acknowledge:**

- When you start investigating
- When you take ownership
- When you begin working on resolution

### 3. Investigate Issue

- Review alert details: `./bin/alerts/alertManager.sh show <alert-id>`
- Check component logs
- Review related metrics
- Check system status

### 4. Resolve or Escalate

**If Resolved:**

```bash
# Resolve alert
./bin/alerts/alertManager.sh resolve <alert-id> <your-name>
```

**If Escalation Needed:**

- Alert will auto-escalate based on time thresholds
- Or manually escalate: `./bin/alerts/escalation.sh escalate <alert-id> <level>`

### 5. Document Resolution

Add notes to alert metadata when resolving:

```bash
# Resolve with notes (via database)
psql -d osm_notes_monitoring -c "UPDATE alerts SET metadata = metadata || '{\"resolution_notes\": \"Issue resolved by restarting service\"}' WHERE id = '<alert-id>';"
```

## Escalation Procedures

### Escalation Levels

1. **Level 1** (15 minutes): Primary on-call
2. **Level 2** (30 minutes): Secondary on-call or manager
3. **Level 3** (60 minutes): Director or senior management

### When to Escalate

- Unable to resolve within response time
- Issue requires additional expertise
- Issue affects multiple systems
- Issue requires management decision

### Escalation Process

1. Document what has been tried
2. Escalate alert: `./bin/alerts/escalation.sh escalate <alert-id> <level>`
3. Notify escalation recipient
4. Continue monitoring until resolved

## Common Scenarios

### Scenario 1: Critical Alert - Service Down

1. **Acknowledge** alert immediately
2. **Check** service status: `systemctl status <service>`
3. **Review** logs: `tail -f logs/<service>.log`
4. **Restart** service if needed: `systemctl restart <service>`
5. **Verify** service is up
6. **Resolve** alert

### Scenario 2: Warning Alert - Performance Degradation

1. **Acknowledge** alert
2. **Review** metrics: Check database for performance metrics
3. **Identify** root cause
4. **Apply** fix or optimization
5. **Monitor** for improvement
6. **Resolve** alert when fixed

### Scenario 3: Multiple Related Alerts

1. **Aggregate** alerts: `./bin/alerts/alertManager.sh aggregate <component> 60`
2. **Identify** common root cause
3. **Resolve** root cause
4. **Resolve** all related alerts

## Best Practices

### Alert Management

1. **Acknowledge Promptly**: Acknowledge alerts within response time
2. **Update Status**: Keep alert status updated (acknowledged/resolved)
3. **Document Actions**: Document actions in alert metadata
4. **Resolve When Fixed**: Resolve alerts when issues are fixed

### Communication

1. **Notify Team**: Notify team of critical issues
2. **Update Status**: Provide status updates during resolution
3. **Document Resolution**: Document resolution steps for future reference

### Escalation

1. **Escalate Early**: Escalate if unable to resolve quickly
2. **Provide Context**: Include context when escalating
3. **Follow Up**: Follow up on escalated alerts

## Tools and Commands

### Alert Management

```bash
# List active alerts
./bin/alerts/alertManager.sh list

# Show alert details
./bin/alerts/alertManager.sh show <alert-id>

# Acknowledge alert
./bin/alerts/alertManager.sh acknowledge <alert-id> <user>

# Resolve alert
./bin/alerts/alertManager.sh resolve <alert-id> <user>
```

### Escalation

```bash
# Check for escalation
./bin/alerts/escalation.sh check

# Escalate alert
./bin/alerts/escalation.sh escalate <alert-id> <level>

# View escalation rules
./bin/alerts/escalation.sh rules
```

### Statistics

```bash
# View alert statistics
./bin/alerts/alertManager.sh stats

# View alert history
./bin/alerts/alertManager.sh history <component> <days>
```

## References

- **Alerting Guide**: `docs/ALERTING_GUIDE.md` - Comprehensive alerting guide
- **Alert Configuration**: `docs/ALERT_CONFIGURATION_REFERENCE.md` - Configuration reference
- **Alert Manager**: `bin/alerts/alertManager.sh` - Alert management script
- **Escalation**: `bin/alerts/escalation.sh` - Escalation script
