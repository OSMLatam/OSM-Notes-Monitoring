---
title: "API Security Guide"
description: "The API Security system provides comprehensive protection and monitoring for the OSM-Notes-API component, including:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "api"
  - "security"
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# API Security Guide

> **Purpose:** Comprehensive guide for API security monitoring and protection  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Running Security Monitoring](#running-security-monitoring)
6. [Understanding Security Metrics](#understanding-security-metrics)
7. [Alerting](#alerting)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Reference Documentation](#reference-documentation)

---

## Overview

The API Security system provides comprehensive protection and monitoring for the OSM-Notes-API
component, including:

- **Rate Limiting**: Per-IP, per-API-key, and per-endpoint rate limiting with sliding window
  algorithm
- **DDoS Protection**: Attack detection, automatic IP blocking, and connection rate limiting
- **Abuse Detection**: Pattern analysis, anomaly detection, and behavioral analysis
- **IP Management**: Whitelist, blacklist, and temporary blocking management

### Key Features

- **Automated Protection**: Real-time rate limiting and attack detection
- **Sliding Window Algorithm**: Fair rate limiting that prevents burst abuse
- **Automatic Response**: Automatic IP blocking for detected attacks
- **Metrics Collection**: All security events stored in PostgreSQL for analysis
- **Alerting**: Configurable alerts for security incidents (WARNING, CRITICAL)
- **Low Overhead**: Efficient algorithms designed to minimize performance impact
- **Geographic Filtering**: Optional geographic filtering for DDoS protection

---

## Prerequisites

Before setting up API security monitoring, ensure you have:

1. **PostgreSQL Database**: A PostgreSQL database for storing security events and metrics
   - Version 12 or higher recommended
   - Database created and accessible
   - User with appropriate permissions
   - `security_events` and `ip_management` tables created (via `sql/init.sql`)

2. **Bash Environment**: Bash 4.0 or higher

3. **Network Access**: Ability to connect to API service and database

4. **Security Configuration**: Security configuration file (`config/security.conf`)

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

### 2. Configure Security Settings

Copy and edit `config/security.conf.example`:

```bash
cp config/security.conf.example config/security.conf
```

Edit `config/security.conf`:

```bash
# Rate Limiting
RATE_LIMIT_PER_IP_PER_MINUTE=60
RATE_LIMIT_PER_IP_PER_HOUR=1000
RATE_LIMIT_PER_IP_PER_DAY=10000
RATE_LIMIT_BURST_SIZE=10

# DDoS Protection
DDOS_THRESHOLD_REQUESTS_PER_SECOND=100
DDOS_THRESHOLD_CONCURRENT_CONNECTIONS=500
DDOS_AUTO_BLOCK_DURATION_MINUTES=15

# Abuse Detection
ABUSE_DETECTION_ENABLED=true
ABUSE_RAPID_REQUEST_THRESHOLD=10
ABUSE_ERROR_RATE_THRESHOLD=50
ABUSE_EXCESSIVE_REQUESTS_THRESHOLD=1000
```

### 3. Initialize Security Functions

```bash
# Initialize security functions (loads configuration)
./bin/security/rateLimiter.sh check 192.168.1.100
```

### 4. Run Security Monitoring

```bash
# Check rate limit for an IP
./bin/security/rateLimiter.sh check 192.168.1.100 /api/notes

# Monitor for DDoS attacks
./bin/security/ddosProtection.sh monitor

# Analyze abuse patterns
./bin/security/abuseDetection.sh analyze

# Check IP status
./bin/security/ipBlocking.sh status 192.168.1.100
```

### 5. Verify Security Events

```bash
# Check security events in database
psql -d osm_notes_monitoring -c "SELECT * FROM security_events ORDER BY timestamp DESC LIMIT 10;"

# Check IP management
psql -d osm_notes_monitoring -c "SELECT * FROM ip_management ORDER BY created_at DESC LIMIT 10;"
```

---

## Configuration

### Required Configuration

#### Database Configuration

```bash
# Monitoring database (stores security events and metrics)
DBNAME=osm_notes_monitoring
DBHOST=localhost
DBPORT=5432
DBUSER=monitoring_user
```

#### Security Configuration

Create `config/security.conf` based on `config/security.conf.example`:

```bash
# Rate Limiting
RATE_LIMIT_PER_IP_PER_MINUTE=60
RATE_LIMIT_PER_IP_PER_HOUR=1000
RATE_LIMIT_PER_IP_PER_DAY=10000
RATE_LIMIT_BURST_SIZE=10
RATE_LIMIT_PER_API_KEY_PER_MINUTE=100

# Connection Limits
MAX_CONCURRENT_CONNECTIONS_PER_IP=10
MAX_TOTAL_CONNECTIONS=1000

# DDoS Protection
DDOS_THRESHOLD_REQUESTS_PER_SECOND=100
DDOS_THRESHOLD_CONCURRENT_CONNECTIONS=500
DDOS_AUTO_BLOCK_DURATION_MINUTES=15
DDOS_CHECK_WINDOW_SECONDS=60
DDOS_ENABLED=true
DDOS_GEO_FILTERING_ENABLED=false

# Abuse Detection
ABUSE_DETECTION_ENABLED=true
ABUSE_RAPID_REQUEST_THRESHOLD=10
ABUSE_ERROR_RATE_THRESHOLD=50
ABUSE_EXCESSIVE_REQUESTS_THRESHOLD=1000
ABUSE_PATTERN_ANALYSIS_WINDOW=3600

# IP Blocking
TEMP_BLOCK_FIRST_VIOLATION_MINUTES=15
TEMP_BLOCK_SECOND_VIOLATION_HOURS=1
TEMP_BLOCK_THIRD_VIOLATION_HOURS=24
```

### Optional Configuration

#### Geographic Filtering (DDoS Protection)

```bash
# Enable geographic filtering
DDOS_GEO_FILTERING_ENABLED=true

# Allowed countries (comma-separated ISO country codes)
DDOS_ALLOWED_COUNTRIES=US,CA,MX,GB,FR,DE

# Blocked countries (comma-separated ISO country codes)
DDOS_BLOCKED_COUNTRIES=CN,RU

# GeoLite2 database path (required if geographic filtering enabled)
GEOLITE_DB_PATH=/usr/share/GeoIP/GeoLite2-Country.mmdb
```

**Note:** Geographic filtering requires:

- GeoLite2 database installed (`mmdblookup` tool)
- MaxMind GeoLite2 Country database (free, requires registration)

#### API Key Rate Limiting

```bash
# Per-API-key rate limits (for authenticated users)
RATE_LIMIT_PER_API_KEY_PER_MINUTE=100
RATE_LIMIT_PER_API_KEY_PER_HOUR=10000
RATE_LIMIT_PER_API_KEY_PER_DAY=100000
```

#### Per-Endpoint Rate Limiting

Rate limiting can be configured per endpoint by modifying `rateLimiter.sh` or using
endpoint-specific thresholds in the configuration.

---

## Running Security Monitoring

### Rate Limiting

#### Check Rate Limit

```bash
# Check if request should be allowed
./bin/security/rateLimiter.sh check 192.168.1.100 /api/notes

# Check with API key
./bin/security/rateLimiter.sh check 192.168.1.100 /api/notes abc123

# Check with custom window and limit
./bin/security/rateLimiter.sh --window 30 --limit 30 check 192.168.1.100
```

**Exit Codes:**

- `0`: Request allowed
- `1`: Rate limit exceeded

#### Record Request

```bash
# Record a request for tracking
./bin/security/rateLimiter.sh record 192.168.1.100 /api/notes

# Record with API key
./bin/security/rateLimiter.sh record 192.168.1.100 /api/notes abc123
```

#### View Statistics

```bash
# View rate limit statistics
./bin/security/rateLimiter.sh stats

# View statistics for specific IP
./bin/security/rateLimiter.sh stats 192.168.1.100

# View statistics for specific endpoint
./bin/security/rateLimiter.sh stats 192.168.1.100 /api/notes
```

#### Reset Rate Limit

```bash
# Reset rate limit for IP
./bin/security/rateLimiter.sh reset 192.168.1.100

# Reset rate limit for IP and endpoint
./bin/security/rateLimiter.sh reset 192.168.1.100 /api/notes
```

### DDoS Protection

#### Monitor for Attacks

```bash
# Monitor continuously for DDoS attacks
./bin/security/ddosProtection.sh monitor

# Check for attacks (one-time)
./bin/security/ddosProtection.sh check

# Check specific IP
./bin/security/ddosProtection.sh check 192.168.1.100
```

#### Manual IP Blocking

```bash
# Block an IP manually
./bin/security/ddosProtection.sh block 192.168.1.100 "Manual block - suspicious activity"

# Unblock an IP
./bin/security/ddosProtection.sh unblock 192.168.1.100
```

#### View Statistics

```bash
# View DDoS protection statistics
./bin/security/ddosProtection.sh stats
```

### Abuse Detection

#### Analyze Patterns

```bash
# Analyze all IPs for abuse patterns
./bin/security/abuseDetection.sh analyze

# Analyze specific IP
./bin/security/abuseDetection.sh analyze 192.168.1.100

# Check specific IP for abuse
./bin/security/abuseDetection.sh check 192.168.1.100
```

#### View Statistics

```bash
# View abuse detection statistics
./bin/security/abuseDetection.sh stats

# View detected patterns
./bin/security/abuseDetection.sh patterns
```

### IP Management

#### Add IP to List

```bash
# Add IP to whitelist
./bin/security/ipBlocking.sh add 192.168.1.100 whitelist "Trusted user"

# Add IP to blacklist
./bin/security/ipBlocking.sh add 192.168.1.100 blacklist "Known attacker"

# Add temporary block
./bin/security/ipBlocking.sh add 192.168.1.100 temp_block "Rate limit violation" 15
```

#### Remove IP from List

```bash
# Remove IP from whitelist
./bin/security/ipBlocking.sh remove 192.168.1.100 whitelist

# Remove IP from blacklist
./bin/security/ipBlocking.sh remove 192.168.1.100 blacklist
```

#### List IPs

```bash
# List all whitelisted IPs
./bin/security/ipBlocking.sh list whitelist

# List all blacklisted IPs
./bin/security/ipBlocking.sh list blacklist

# List all temporarily blocked IPs
./bin/security/ipBlocking.sh list temp_block
```

#### Check IP Status

```bash
# Check IP status (whitelisted, blacklisted, or temporarily blocked)
./bin/security/ipBlocking.sh status 192.168.1.100
```

#### Cleanup Expired Blocks

```bash
# Cleanup expired temporary blocks
./bin/security/ipBlocking.sh cleanup
```

---

## Understanding Security Metrics

### Rate Limiting Metrics

- **`rate_limit_requests_per_minute`**: Requests per minute for an IP/API-key/endpoint
- **`rate_limit_requests_per_hour`**: Requests per hour
- **`rate_limit_requests_per_day`**: Requests per day
- **`rate_limit_violations`**: Number of rate limit violations
- **`rate_limit_burst_requests`**: Burst requests within burst window

### DDoS Protection Metrics

- **`ddos_requests_per_second`**: Requests per second from an IP
- **`ddos_request_count`**: Total requests in detection window
- **`ddos_concurrent_connections`**: Concurrent connections from unique IPs
- **`ddos_ips_blocked`**: Number of IPs automatically blocked
- **`ddos_geographic_blocked`**: Requests blocked by geographic filter

### Abuse Detection Metrics

- **`abuse_rapid_requests`**: Rapid requests detected (within 10 seconds)
- **`abuse_error_rate_percent`**: Percentage of requests resulting in errors
- **`abuse_excessive_requests`**: Excessive requests in analysis window
- **`abuse_pattern_matches`**: Known abuse patterns matched
- **`abuse_anomaly_score`**: Anomaly detection score (0-100)
- **`abuse_behavioral_score`**: Behavioral analysis score (0-100)

### IP Management Metrics

- **`ip_whitelist_count`**: Number of IPs in whitelist
- **`ip_blacklist_count`**: Number of IPs in blacklist
- **`ip_temp_block_count`**: Number of temporarily blocked IPs
- **`ip_blocks_expired`**: Number of expired blocks cleaned up

For detailed metric definitions, see `docs/API_SECURITY_METRICS.md`.

---

## Alerting

### Alert Types

#### Rate Limit Violations

- **Severity:** WARNING
- **Trigger:** When rate limit is exceeded
- **Action:**
  - Log violation
  - Optionally block IP temporarily
  - Review IP behavior

#### DDoS Attacks

- **Severity:** CRITICAL
- **Trigger:** When DDoS threshold is exceeded
- **Action:**
  - Automatically block IP
  - Send alert
  - Investigate attack source

#### Abuse Patterns

- **Severity:** WARNING
- **Trigger:** When abuse patterns are detected
- **Action:**
  - Analyze abuse type
  - Optionally block IP
  - Review request patterns

### Alert Configuration

Alerts are configured via thresholds in `config/security.conf`. See
`docs/API_SECURITY_ALERT_THRESHOLDS.md` for detailed threshold definitions.

### Alert Delivery

Alerts are stored in the `alerts` table and can be delivered via:

- Email (via `send_alert` function)
- Slack (if configured)
- Custom alert handlers

---

## Troubleshooting

### Rate Limiting Issues

#### Legitimate Users Being Blocked

**Symptoms:** Legitimate users report being rate limited

**Solutions:**

1. Check if IP is whitelisted: `./bin/security/ipBlocking.sh status <IP>`
2. Review rate limit thresholds in `config/security.conf`
3. Consider increasing limits for authenticated users (API keys)
4. Add IP to whitelist if legitimate high-volume user

#### Rate Limits Not Working

**Symptoms:** Rate limits not being enforced

**Solutions:**

1. Verify security configuration is loaded: `./bin/security/rateLimiter.sh stats`
2. Check database connection:
   `psql -d osm_notes_monitoring -c "SELECT COUNT(*) FROM security_events;"`
3. Verify `record_request()` is being called for each request
4. Check logs: `tail -f logs/rate_limiter.log`

### DDoS Protection Issues

#### False Positives

**Symptoms:** Legitimate traffic spikes triggering DDoS alerts

**Solutions:**

1. Review baseline traffic patterns
2. Increase `DDOS_THRESHOLD_REQUESTS_PER_SECOND` if needed
3. Adjust `DDOS_CHECK_WINDOW_SECONDS` for more stable detection
4. Whitelist legitimate high-volume IPs

#### Attacks Not Detected

**Symptoms:** Attacks occurring but not detected

**Solutions:**

1. Verify DDoS monitoring is running: `./bin/security/ddosProtection.sh monitor`
2. Check detection thresholds in `config/security.conf`
3. Review security events:
   `psql -d osm_notes_monitoring -c "SELECT * FROM security_events WHERE event_type = 'ddos';"`
4. Adjust thresholds if too high

### Abuse Detection Issues

#### Too Many Alerts

**Symptoms:** Excessive abuse detection alerts

**Solutions:**

1. Review abuse detection thresholds
2. Adjust `ABUSE_RAPID_REQUEST_THRESHOLD` if too low
3. Increase `ABUSE_PATTERN_ANALYSIS_WINDOW` for more stable detection
4. Review false positive patterns

#### Abuse Not Detected

**Symptoms:** Abuse occurring but not detected

**Solutions:**

1. Verify abuse detection is enabled: `ABUSE_DETECTION_ENABLED=true`
2. Review abuse detection thresholds
3. Check security events:
   `psql -d osm_notes_monitoring -c "SELECT * FROM security_events WHERE event_type = 'abuse';"`
4. Adjust thresholds if too high

### IP Management Issues

#### IP Not Blocked

**Symptoms:** IP should be blocked but isn't

**Solutions:**

1. Check IP status: `./bin/security/ipBlocking.sh status <IP>`
2. Verify IP is in blacklist: `./bin/security/ipBlocking.sh list blacklist`
3. Check if IP is whitelisted (whitelist takes precedence)
4. Review blocking logic in security scripts

#### IP Blocked But Shouldn't Be

**Symptoms:** Legitimate IP is blocked

**Solutions:**

1. Check IP status: `./bin/security/ipBlocking.sh status <IP>`
2. Remove from blacklist: `./bin/security/ipBlocking.sh remove <IP> blacklist`
3. Remove temporary block: Wait for expiration or manually remove
4. Add to whitelist to prevent future blocks:
   `./bin/security/ipBlocking.sh add <IP> whitelist "Legitimate user"`

---

## Best Practices

### Rate Limiting

1. **Start Conservative**: Begin with lower limits and increase based on usage patterns
2. **Use API Keys**: Provide higher limits for authenticated users via API keys
3. **Monitor Violations**: Regularly review rate limit violations to identify abuse
4. **Whitelist Legitimate Users**: Add high-volume legitimate users to whitelist
5. **Progressive Blocking**: Use progressive blocking (15 min → 1 hour → 24 hours) for repeat
   offenders

### DDoS Protection

1. **Baseline Monitoring**: Establish baseline traffic patterns before setting thresholds
2. **Automatic Response**: Enable automatic IP blocking for detected attacks
3. **Geographic Filtering**: Consider geographic filtering if attacks from specific regions
4. **Connection Limits**: Set appropriate connection limits to prevent resource exhaustion
5. **Regular Review**: Regularly review blocked IPs and adjust thresholds

### Abuse Detection

1. **Pattern Analysis**: Regularly review detected abuse patterns
2. **Anomaly Detection**: Use anomaly detection to identify unusual behavior
3. **Behavioral Analysis**: Monitor behavioral patterns over time
4. **False Positive Management**: Adjust thresholds to minimize false positives
5. **Automatic Response**: Enable automatic response for confirmed abuse

### IP Management

1. **Whitelist Management**: Maintain a curated whitelist of trusted IPs
2. **Blacklist Management**: Regularly review and update blacklist
3. **Temporary Blocks**: Use temporary blocks for first-time violations
4. **Progressive Escalation**: Escalate blocking duration for repeat offenders
5. **Cleanup**: Regularly cleanup expired temporary blocks

### General Security

1. **Regular Monitoring**: Run security monitoring on a schedule (e.g., via cron)
2. **Log Review**: Regularly review security logs for patterns
3. **Metrics Analysis**: Analyze security metrics for trends
4. **Incident Response**: Have an incident response plan for security incidents
5. **Documentation**: Document security policies and procedures

---

## Reference Documentation

- **Metrics Definition**: `docs/API_SECURITY_METRICS.md` - Detailed metric definitions
- **Alert Thresholds**: `docs/API_SECURITY_ALERT_THRESHOLDS.md` - Alert threshold definitions
- **Rate Limiting Guide**: `docs/RATE_LIMITING_GUIDE.md` - Detailed rate limiting guide
- **Incident Response**: `docs/SECURITY_INCIDENT_RESPONSE_RUNBOOK.md` - Incident response procedures
- **Best Practices**: `docs/SECURITY_BEST_PRACTICES.md` - Security best practices
- **Security Design**: `docs/API_Security_Design.md` - Security architecture design
- **Configuration Reference**: `docs/CONFIGURATION_REFERENCE.md` - Configuration options

### Scripts

- `bin/security/rateLimiter.sh` - Rate limiting implementation
- `bin/security/ddosProtection.sh` - DDoS protection implementation
- `bin/security/abuseDetection.sh` - Abuse detection implementation
- `bin/security/ipBlocking.sh` - IP management implementation
- `bin/lib/securityFunctions.sh` - Security utility functions

### Database Schema

- `sql/init.sql` - Database schema including `security_events` and `ip_management` tables

---

## Support

For issues or questions:

1. Check troubleshooting section above
2. Review logs: `logs/rate_limiter.log`, `logs/ddos_protection.log`, `logs/abuse_detection.log`
3. Review security events in database
4. Consult reference documentation
