---
title: "API Security Alert Thresholds"
description: "This document defines all alert thresholds for the OSM-Notes-API security component. These"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "api"
  - "security"
  - "monitoring"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# API Security Alert Thresholds

> **Purpose:** Comprehensive definition of all alert thresholds for API security monitoring  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document defines all alert thresholds for the OSM-Notes-API security component. These
thresholds are used to trigger alerts when security metrics exceed acceptable levels.

## Threshold Categories

### 1. Rate Limiting Thresholds

Thresholds for rate limiting enforcement and violations.

#### `RATE_LIMIT_PER_IP_PER_MINUTE`

- **Default Value:** `60`
- **Unit:** Requests per minute
- **Description:** Maximum number of requests allowed per IP address per minute
- **Associated Metrics:** `rate_limit_requests_per_minute`
- **Alert Condition:** When requests exceed this limit
- **Severity:** `WARNING`
- **Recommended Action:**
  - Block IP temporarily if repeated violations
  - Review IP behavior for legitimate use cases
  - Consider whitelisting if legitimate high-volume user

#### `RATE_LIMIT_PER_IP_PER_HOUR`

- **Default Value:** `1000`
- **Unit:** Requests per hour
- **Description:** Maximum number of requests allowed per IP address per hour
- **Associated Metrics:** `rate_limit_requests_per_hour`
- **Alert Condition:** When requests exceed this limit
- **Severity:** `WARNING`
- **Recommended Action:**
  - Review IP behavior patterns
  - Consider temporary blocking if abuse suspected
  - Contact user if legitimate high-volume use case

#### `RATE_LIMIT_PER_IP_PER_DAY`

- **Default Value:** `10000`
- **Unit:** Requests per day
- **Description:** Maximum number of requests allowed per IP address per day
- **Associated Metrics:** `rate_limit_requests_per_day`
- **Alert Condition:** When requests exceed this limit
- **Severity:** `WARNING`
- **Recommended Action:**
  - Investigate usage patterns
  - Consider API key for authenticated users
  - Block IP if abuse confirmed

#### `RATE_LIMIT_BURST_SIZE`

- **Default Value:** `10`
- **Unit:** Requests
- **Description:** Maximum number of burst requests allowed within burst window
- **Associated Metrics:** `rate_limit_burst_requests`
- **Alert Condition:** When burst requests exceed this limit
- **Severity:** `INFO` (logged, not alerted)
- **Recommended Action:**
  - Normal behavior for legitimate users
  - Monitor for patterns if repeated frequently

#### `RATE_LIMIT_PER_API_KEY_PER_MINUTE`

- **Default Value:** `100`
- **Unit:** Requests per minute
- **Description:** Maximum number of requests allowed per API key per minute
- **Associated Metrics:** `rate_limit_requests_per_minute` (with API key identifier)
- **Alert Condition:** When requests exceed this limit
- **Severity:** `WARNING`
- **Recommended Action:**
  - Review API key usage
  - Consider rate limit increase for legitimate use cases
  - Revoke API key if abuse confirmed

### 2. DDoS Protection Thresholds

Thresholds for DDoS attack detection and mitigation.

#### `DDOS_THRESHOLD_REQUESTS_PER_SECOND`

- **Default Value:** `100`
- **Unit:** Requests per second
- **Description:** Maximum number of requests per second from a single IP before triggering DDoS
  detection
- **Associated Metrics:** `ddos_requests_per_second`, `ddos_request_count`
- **Alert Condition:** When requests per second exceed this threshold
- **Severity:** `CRITICAL`
- **Recommended Action:**
  - Automatically block IP for `DDOS_AUTO_BLOCK_DURATION_MINUTES`
  - Investigate attack source
  - Review logs for attack patterns
  - Consider enabling geographic filtering if attacks from specific regions

#### `DDOS_THRESHOLD_CONCURRENT_CONNECTIONS`

- **Default Value:** `500`
- **Unit:** Connections
- **Description:** Maximum number of concurrent connections from unique IPs before triggering DDoS
  detection
- **Associated Metrics:** `ddos_concurrent_connections`
- **Alert Condition:** When concurrent connections exceed this threshold
- **Severity:** `CRITICAL`
- **Recommended Action:**
  - Enable connection rate limiting
  - Investigate source of connections
  - Consider enabling geographic filtering
  - Review infrastructure capacity

#### `DDOS_AUTO_BLOCK_DURATION_MINUTES`

- **Default Value:** `15`
- **Unit:** Minutes
- **Description:** Duration for automatic IP blocking when DDoS attack is detected
- **Associated Metrics:** `ddos_ips_blocked`
- **Alert Condition:** N/A (configuration value)
- **Severity:** N/A
- **Recommended Action:**
  - Adjust based on attack patterns
  - Increase for persistent attackers
  - Decrease for false positives

#### `DDOS_CHECK_WINDOW_SECONDS`

- **Default Value:** `60`
- **Unit:** Seconds
- **Description:** Time window for DDoS attack detection analysis
- **Associated Metrics:** `ddos_request_count`
- **Alert Condition:** N/A (configuration value)
- **Severity:** N/A
- **Recommended Action:**
  - Adjust based on attack characteristics
  - Shorter window for faster detection
  - Longer window for more stable detection

### 3. Abuse Detection Thresholds

Thresholds for abuse pattern detection and behavioral analysis.

#### `ABUSE_RAPID_REQUEST_THRESHOLD`

- **Default Value:** `10`
- **Unit:** Requests
- **Description:** Maximum number of requests within 10 seconds before triggering abuse detection
- **Associated Metrics:** `abuse_rapid_requests`
- **Alert Condition:** When rapid requests exceed this threshold
- **Severity:** `WARNING`
- **Recommended Action:**
  - Investigate IP behavior
  - Check for automated scraping
  - Consider temporary blocking if abuse confirmed

#### `ABUSE_ERROR_RATE_THRESHOLD`

- **Default Value:** `50`
- **Unit:** Percent
- **Description:** Maximum percentage of requests that result in errors (4xx/5xx) before triggering
  abuse detection
- **Associated Metrics:** `abuse_error_rate_percent`
- **Alert Condition:** When error rate exceeds this threshold
- **Severity:** `WARNING`
- **Recommended Action:**
  - Investigate error patterns
  - Check for brute force attempts
  - Review endpoint access patterns
  - Block IP if attack confirmed

#### `ABUSE_EXCESSIVE_REQUESTS_THRESHOLD`

- **Default Value:** `1000`
- **Unit:** Requests
- **Description:** Maximum number of requests in analysis window before triggering abuse detection
- **Associated Metrics:** `abuse_excessive_requests`
- **Alert Condition:** When excessive requests exceed this threshold
- **Severity:** `WARNING`
- **Recommended Action:**
  - Review request patterns
  - Check for data scraping
  - Consider rate limiting or blocking
  - Contact user if legitimate use case

#### `ABUSE_ANOMALY_SCORE_THRESHOLD`

- **Default Value:** `70`
- **Unit:** Score (0-100)
- **Description:** Minimum anomaly score before triggering abuse alert
- **Associated Metrics:** `abuse_anomaly_score`
- **Alert Condition:** When anomaly score exceeds this threshold
- **Severity:** `WARNING`
- **Recommended Action:**
  - Investigate unusual activity patterns
  - Compare to baseline behavior
  - Review request characteristics
  - Block IP if abuse confirmed

#### `ABUSE_BEHAVIORAL_SCORE_THRESHOLD`

- **Default Value:** `70`
- **Unit:** Score (0-100)
- **Description:** Minimum behavioral analysis score before triggering abuse alert
- **Associated Metrics:** `abuse_behavioral_score`
- **Alert Condition:** When behavioral score exceeds this threshold
- **Severity:** `WARNING`
- **Recommended Action:**
  - Review behavioral patterns
  - Check for suspicious activity
  - Investigate endpoint diversity
  - Block IP if abuse confirmed

#### `ABUSE_PATTERN_ANALYSIS_WINDOW`

- **Default Value:** `3600`
- **Unit:** Seconds
- **Description:** Time window for abuse pattern analysis
- **Associated Metrics:** `abuse_pattern_matches`
- **Alert Condition:** N/A (configuration value)
- **Severity:** N/A
- **Recommended Action:**
  - Adjust based on analysis needs
  - Shorter window for faster detection
  - Longer window for more comprehensive analysis

### 4. IP Management Thresholds

Thresholds for IP whitelist, blacklist, and temporary blocking.

#### `TEMP_BLOCK_FIRST_VIOLATION_MINUTES`

- **Default Value:** `15`
- **Unit:** Minutes
- **Description:** Duration for temporary IP blocking on first violation
- **Associated Metrics:** `ip_temp_block_count`
- **Alert Condition:** N/A (configuration value)
- **Severity:** N/A
- **Recommended Action:**
  - Adjust based on violation severity
  - Increase for more serious violations
  - Decrease for minor violations

#### `TEMP_BLOCK_SECOND_VIOLATION_HOURS`

- **Default Value:** `1`
- **Unit:** Hours
- **Description:** Duration for temporary IP blocking on second violation
- **Associated Metrics:** `ip_temp_block_count`
- **Alert Condition:** N/A (configuration value)
- **Severity:** N/A
- **Recommended Action:**
  - Escalated blocking for repeat offenders
  - Review violation history
  - Consider permanent blacklist for persistent abuse

#### `TEMP_BLOCK_THIRD_VIOLATION_HOURS`

- **Default Value:** `24`
- **Unit:** Hours
- **Description:** Duration for temporary IP blocking on third violation
- **Associated Metrics:** `ip_temp_block_count`
- **Alert Condition:** N/A (configuration value)
- **Severity:** N/A
- **Recommended Action:**
  - Extended blocking for persistent offenders
  - Consider permanent blacklist
  - Review attack patterns

### 5. Connection Limits

Thresholds for connection rate limiting.

#### `MAX_CONCURRENT_CONNECTIONS_PER_IP`

- **Default Value:** `10`
- **Unit:** Connections
- **Description:** Maximum number of concurrent connections allowed per IP address
- **Associated Metrics:** Connection tracking (not explicitly recorded as metric)
- **Alert Condition:** When concurrent connections exceed this limit
- **Severity:** `WARNING`
- **Recommended Action:**
  - Review connection patterns
  - Check for connection pooling abuse
  - Consider blocking IP if abuse confirmed

#### `MAX_TOTAL_CONNECTIONS`

- **Default Value:** `1000`
- **Unit:** Connections
- **Description:** Maximum total concurrent connections across all IPs
- **Associated Metrics:** Connection tracking (not explicitly recorded as metric)
- **Alert Condition:** When total connections exceed this limit
- **Severity:** `CRITICAL`
- **Recommended Action:**
  - Review infrastructure capacity
  - Check for DDoS attack
  - Enable connection rate limiting
  - Scale infrastructure if needed

## Threshold Configuration

All thresholds are configured in `config/security.conf`:

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
ABUSE_RAPID_REQUEST_THRESHOLD=10
ABUSE_ERROR_RATE_THRESHOLD=50
ABUSE_EXCESSIVE_REQUESTS_THRESHOLD=1000

# IP Management
TEMP_BLOCK_FIRST_VIOLATION_MINUTES=15
TEMP_BLOCK_SECOND_VIOLATION_HOURS=1
TEMP_BLOCK_THIRD_VIOLATION_HOURS=24

# Connection Limits
MAX_CONCURRENT_CONNECTIONS_PER_IP=10
MAX_TOTAL_CONNECTIONS=1000
```

## Threshold Tuning Guidelines

### Rate Limiting

- **Too Low:** May block legitimate users, especially during peak usage
- **Too High:** May allow abuse and resource exhaustion
- **Recommendation:** Start with defaults and adjust based on:
  - Normal usage patterns
  - Peak traffic times
  - Legitimate high-volume use cases

### DDoS Protection

- **Too Low:** May trigger false positives during legitimate traffic spikes
- **Too High:** May allow attacks to succeed before detection
- **Recommendation:**
  - Monitor baseline traffic patterns
  - Set thresholds 2-3x above normal peak traffic
  - Adjust based on attack patterns

### Abuse Detection

- **Too Low:** May generate excessive alerts for normal behavior
- **Too High:** May miss subtle abuse patterns
- **Recommendation:**
  - Start with conservative thresholds
  - Adjust based on false positive rate
  - Review alerts regularly to tune thresholds

### IP Blocking Duration

- **Too Short:** May allow attackers to resume quickly
- **Too Long:** May block legitimate users who made mistakes
- **Recommendation:**
  - Use progressive blocking (15 min → 1 hour → 24 hours)
  - Review blocked IPs regularly
  - Provide appeal mechanism for legitimate users

## Alert Severity Levels

### CRITICAL

- Immediate action required
- Service availability at risk
- Examples: DDoS attacks, connection exhaustion

### WARNING

- Attention required
- Potential abuse or violation
- Examples: Rate limit violations, abuse patterns detected

### INFO

- Informational only
- No immediate action required
- Examples: Burst requests, normal threshold monitoring

## References

- `config/security.conf.example` - Security configuration file
- `docs/API_SECURITY_METRICS.md` - Security metrics definition
- `bin/security/rateLimiter.sh` - Rate limiting implementation
- `bin/security/ddosProtection.sh` - DDoS protection implementation
- `bin/security/abuseDetection.sh` - Abuse detection implementation
- `bin/security/ipBlocking.sh` - IP management implementation
