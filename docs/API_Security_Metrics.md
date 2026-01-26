---
title: "API Security Metrics Definition"
description: "This document defines all metrics collected for the OSM-Notes-API security component. These metrics"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "performance"
  - "api"
  - "security"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# API Security Metrics Definition

> **Purpose:** Comprehensive definition of all API security-specific metrics  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document defines all metrics collected for the OSM-Notes-API security component. These metrics
are stored in the `metrics` table and `security_events` table of the monitoring database and are
used for:

- Security monitoring
- Attack detection
- Rate limiting enforcement
- Abuse pattern analysis
- Incident response
- Security reporting

## Metric Naming Convention

All security metrics follow this naming pattern:

- **Format:** `{category}_{metric_name}_{unit_suffix}`
- **Category:** Groups related metrics (e.g., `rate_limit`, `ddos`, `abuse`, `ip_block`)
- **Unit Suffix:** Indicates unit type (`_count`, `_percent`, `_per_second`, `_per_minute`)

## Metric Categories

### 1. Rate Limiting Metrics

Metrics related to rate limiting enforcement and violations.

#### `rate_limit_requests_per_minute`

- **Description:** Number of requests per minute for a specific IP/API-key/endpoint
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_rate_limit_sliding_window()` in `rateLimiter.sh`
- **Frequency:** On every request check
- **Expected Range:** 0 to configured limit (default: 60 per IP per minute)
- **Alert Threshold:** Exceeds configured limit
- **Metadata:** `component=security,identifier={ip|api_key|endpoint}`

#### `rate_limit_requests_per_hour`

- **Description:** Number of requests per hour for a specific IP/API-key/endpoint
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_rate_limit_sliding_window()` in `rateLimiter.sh`
- **Frequency:** On every request check
- **Expected Range:** 0 to configured limit (default: 1000 per IP per hour)
- **Alert Threshold:** Exceeds configured limit
- **Metadata:** `component=security,identifier={ip|api_key|endpoint}`

#### `rate_limit_requests_per_day`

- **Description:** Number of requests per day for a specific IP/API-key/endpoint
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_rate_limit_sliding_window()` in `rateLimiter.sh`
- **Frequency:** On every request check
- **Expected Range:** 0 to configured limit (default: 10000 per IP per day)
- **Alert Threshold:** Exceeds configured limit
- **Metadata:** `component=security,identifier={ip|api_key|endpoint}`

#### `rate_limit_violations`

- **Description:** Number of rate limit violations detected
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Recorded when `check_rate_limit_sliding_window()` returns violation
- **Frequency:** On every violation
- **Expected Range:** 0 (no violations expected)
- **Alert Threshold:** > 0 violations
- **Metadata:** `component=security,ip={ip},endpoint={endpoint}`

#### `rate_limit_burst_requests`

- **Description:** Number of burst requests allowed within burst window
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during burst handling in `check_rate_limit_sliding_window()`
- **Frequency:** On every request check
- **Expected Range:** 0 to burst size (default: 10)
- **Alert Threshold:** Exceeds burst size
- **Metadata:** `component=security,identifier={ip|api_key|endpoint}`

### 2. DDoS Protection Metrics

Metrics related to DDoS attack detection and mitigation.

#### `ddos_requests_per_second`

- **Description:** Number of requests per second from a specific IP address
- **Type:** Gauge
- **Unit:** `per_second`
- **Collection:** Collected during `check_attack_detection()` in `ddosProtection.sh`
- **Frequency:** Every monitoring cycle (default: 60 seconds)
- **Expected Range:** 0 to threshold (default: 100 req/sec)
- **Alert Threshold:** Exceeds `DDOS_THRESHOLD_REQUESTS_PER_SECOND` (default: 100)
- **Metadata:** `component=security,ip={ip}`

#### `ddos_request_count`

- **Description:** Total number of requests from an IP in the detection window
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_attack_detection()` in `ddosProtection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to threshold × window (default: 100 × 60 = 6000)
- **Alert Threshold:** Exceeds threshold × window
- **Metadata:** `component=security,ip={ip},window={seconds}`

#### `ddos_concurrent_connections`

- **Description:** Number of concurrent connections from unique IPs
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_connection_rate_limiting()` in `ddosProtection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to threshold (default: 500)
- **Alert Threshold:** Exceeds `DDOS_THRESHOLD_CONCURRENT_CONNECTIONS` (default: 500)
- **Metadata:** `component=security`

#### `ddos_ips_blocked`

- **Description:** Number of IPs automatically blocked due to DDoS detection
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Recorded during `auto_block_ip()` in `ddosProtection.sh`
- **Frequency:** On every automatic block
- **Expected Range:** 0 (no attacks expected)
- **Alert Threshold:** > 0 blocks
- **Metadata:** `component=security,ip={ip},reason={reason}`

#### `ddos_geographic_blocked`

- **Description:** Number of requests blocked due to geographic filtering
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Recorded during `check_geographic_filtering()` in `ddosProtection.sh`
- **Frequency:** On every geographic filter violation
- **Expected Range:** 0 (if geographic filtering enabled)
- **Alert Threshold:** > 0 blocks
- **Metadata:** `component=security,ip={ip},country={country}`

### 3. Abuse Detection Metrics

Metrics related to abuse pattern detection and behavioral analysis.

#### `abuse_rapid_requests`

- **Description:** Number of rapid requests detected from an IP (within 10 seconds)
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_pattern_analysis()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to threshold (default: 10)
- **Alert Threshold:** Exceeds `ABUSE_RAPID_REQUEST_THRESHOLD` (default: 10)
- **Metadata:** `component=security,ip={ip}`

#### `abuse_error_rate_percent`

- **Description:** Percentage of requests that result in errors (4xx/5xx) from an IP
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Collected during `check_pattern_analysis()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-100%
- **Alert Threshold:** Exceeds `ABUSE_ERROR_RATE_THRESHOLD` (default: 50%)
- **Metadata:** `component=security,ip={ip}`

#### `abuse_excessive_requests`

- **Description:** Number of excessive requests from an IP in a time window
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_pattern_analysis()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 to threshold (default: 1000)
- **Alert Threshold:** Exceeds `ABUSE_EXCESSIVE_REQUESTS_THRESHOLD` (default: 1000)
- **Metadata:** `component=security,ip={ip}`

#### `abuse_pattern_matches`

- **Description:** Number of known abuse patterns matched (SQL injection, XSS, etc.)
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_pattern_analysis()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no patterns expected)
- **Alert Threshold:** > 0 matches
- **Metadata:** `component=security,ip={ip},pattern={pattern_type}`

#### `abuse_anomaly_score`

- **Description:** Anomaly detection score indicating unusual activity (0-100)
- **Type:** Gauge
- **Unit:** `score`
- **Collection:** Collected during `check_anomaly_detection()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-100 (higher = more anomalous)
- **Alert Threshold:** > 70 (high anomaly)
- **Metadata:** `component=security,ip={ip}`

#### `abuse_baseline_requests`

- **Description:** Baseline request count for an IP (used for anomaly detection)
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_anomaly_detection()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by IP
- **Alert Threshold:** N/A (used for comparison)
- **Metadata:** `component=security,ip={ip}`

#### `abuse_current_requests`

- **Description:** Current request count for an IP (compared to baseline)
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_anomaly_detection()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies by IP
- **Alert Threshold:** Significantly exceeds baseline
- **Metadata:** `component=security,ip={ip}`

#### `abuse_behavioral_score`

- **Description:** Behavioral analysis score indicating suspicious behavior (0-100)
- **Type:** Gauge
- **Unit:** `score`
- **Collection:** Collected during `check_behavioral_analysis()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-100 (higher = more suspicious)
- **Alert Threshold:** > 70 (high suspicion)
- **Metadata:** `component=security,ip={ip}`

#### `abuse_endpoint_diversity`

- **Description:** Number of unique endpoints accessed by an IP
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_behavioral_analysis()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Varies (low diversity may indicate scraping)
- **Alert Threshold:** Very low diversity (< 3 endpoints) with high request volume
- **Metadata:** `component=security,ip={ip}`

#### `abuse_user_agent_diversity`

- **Description:** Number of unique user agents used by an IP
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during `check_behavioral_analysis()` in `abuseDetection.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** Typically 1-3 per IP
- **Alert Threshold:** Very high diversity (> 10) may indicate botnet
- **Metadata:** `component=security,ip={ip}`

#### `abuse_auto_blocks`

- **Description:** Number of automatic IP blocks triggered by abuse detection
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Recorded during `automatic_response()` in `abuseDetection.sh`
- **Frequency:** On every automatic block
- **Expected Range:** 0 (no abuse expected)
- **Alert Threshold:** > 0 blocks
- **Metadata:** `component=security,ip={ip},type={abuse_type}`

### 4. IP Management Metrics

Metrics related to IP whitelist, blacklist, and temporary blocking.

#### `ip_whitelist_count`

- **Description:** Number of IPs in the whitelist
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during IP management operations in `ipBlocking.sh`
- **Frequency:** On demand or periodic audit
- **Expected Range:** Varies by deployment
- **Alert Threshold:** N/A
- **Metadata:** `component=security,list=whitelist`

#### `ip_blacklist_count`

- **Description:** Number of IPs in the blacklist
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during IP management operations in `ipBlocking.sh`
- **Frequency:** On demand or periodic audit
- **Expected Range:** Varies by deployment
- **Alert Threshold:** N/A
- **Metadata:** `component=security,list=blacklist`

#### `ip_temp_block_count`

- **Description:** Number of IPs currently temporarily blocked
- **Type:** Gauge
- **Unit:** `count`
- **Collection:** Collected during IP management operations in `ipBlocking.sh`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0 (no blocks expected)
- **Alert Threshold:** > 0 blocks (indicates active threats)
- **Metadata:** `component=security,list=temp_block`

#### `ip_blocks_expired`

- **Description:** Number of temporary IP blocks that expired and were cleaned up
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Recorded during `cleanup_expired_blocks()` in `ipBlocking.sh`
- **Frequency:** On cleanup execution
- **Expected Range:** Varies
- **Alert Threshold:** N/A
- **Metadata:** `component=security`

### 5. Security Event Metrics

Metrics related to security events recorded in the `security_events` table.

#### `security_events_total`

- **Description:** Total number of security events recorded
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Recorded whenever `record_security_event()` is called
- **Frequency:** On every security event
- **Expected Range:** Continuously increasing
- **Alert Threshold:** N/A (used for trending)
- **Metadata:** `component=security,event_type={type}`

#### `security_events_by_type`

- **Description:** Number of security events grouped by event type
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Aggregated from `security_events` table
- **Frequency:** On demand or periodic reporting
- **Expected Range:** Varies by event type
- **Alert Threshold:** N/A (used for analysis)
- **Metadata:** `component=security,event_type={rate_limit|ddos|abuse|ip_block}`

#### `security_events_by_ip`

- **Description:** Number of security events grouped by IP address
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Aggregated from `security_events` table
- **Frequency:** On demand or periodic reporting
- **Expected Range:** Varies by IP
- **Alert Threshold:** High count from single IP indicates abuse
- **Metadata:** `component=security,ip={ip}`

## Metric Collection Methods

### Database Queries

Most security metrics are collected by querying the `security_events` table:

```sql
-- Example: Count rate limit violations
SELECT COUNT(*)
FROM security_events
WHERE event_type = 'rate_limit'
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour';
```

### Real-time Monitoring

Some metrics are collected in real-time during request processing:

- Rate limit checks
- Request counting
- Burst handling

### Periodic Analysis

Some metrics require periodic analysis:

- Anomaly detection (compares current vs baseline)
- Behavioral analysis (tracks patterns over time)
- Pattern matching (scans logs for known patterns)

## Metric Storage

### Metrics Table

Standard metrics are stored in the `metrics` table with:

- `component`: Always `"SECURITY"`
- `metric_name`: One of the metric names defined above
- `value`: Numeric value
- `metadata`: JSON with additional context (IP, endpoint, etc.)
- `timestamp`: When the metric was recorded

### Security Events Table

Security events are stored in the `security_events` table with:

- `event_type`: Type of event (`rate_limit`, `ddos`, `abuse`, `ip_block`)
- `ip_address`: IP address involved
- `endpoint`: API endpoint (if applicable)
- `metadata`: JSON with event details
- `timestamp`: When the event occurred

## Metric Retention

- **Metrics Table:** Retained according to `METRICS_RETENTION_DAYS` (default: 90 days)
- **Security Events Table:** Retained according to `SECURITY_EVENTS_RETENTION_DAYS` (default: 365
  days)

## Metric Aggregation

Metrics can be aggregated for reporting:

- **By IP:** Track metrics per IP address
- **By Endpoint:** Track metrics per API endpoint
- **By Time Period:** Aggregate metrics by hour/day/week
- **By Event Type:** Group metrics by security event type

## References

- `bin/security/rateLimiter.sh` - Rate limiting implementation
- `bin/security/ddosProtection.sh` - DDoS protection implementation
- `bin/security/abuseDetection.sh` - Abuse detection implementation
- `bin/security/ipBlocking.sh` - IP management implementation
- `sql/init.sql` - Database schema for `security_events` and `ip_management` tables
- `config/security.conf.example` - Security configuration with thresholds
