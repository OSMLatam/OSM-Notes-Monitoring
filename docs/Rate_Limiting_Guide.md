---
title: "Rate Limiting Guide"
description: "Rate limiting protects the API from abuse by limiting the number of requests that can be made within"
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


# Rate Limiting Guide

> **Purpose:** Detailed guide for rate limiting implementation and usage  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Table of Contents

1. [Overview](#overview)
2. [How Rate Limiting Works](#how-rate-limiting-works)
3. [Configuration](#configuration)
4. [Usage Examples](#usage-examples)
5. [Algorithm Details](#algorithm-details)
6. [Best Practices](#best-practices)
7. [Troubleshooting](#troubleshooting)

---

## Overview

Rate limiting protects the API from abuse by limiting the number of requests that can be made within
a specific time window. The OSM-Notes-Monitoring rate limiting system supports:

- **Per-IP Rate Limiting**: Limit requests per IP address
- **Per-API-Key Rate Limiting**: Limit requests per API key (for authenticated users)
- **Per-Endpoint Rate Limiting**: Limit requests per API endpoint
- **Sliding Window Algorithm**: Fair rate limiting that prevents burst abuse
- **Burst Handling**: Allow short bursts while maintaining overall limits

### Key Features

- **Sliding Window**: More fair than fixed windows, prevents edge cases
- **Burst Allowance**: Allows legitimate burst traffic while preventing abuse
- **Multiple Identifiers**: Support for IP, API key, and endpoint-based limiting
- **Database-Backed**: Uses PostgreSQL for persistent rate limit tracking
- **Low Overhead**: Efficient queries minimize performance impact

---

## How Rate Limiting Works

### Basic Flow

1. **Request Arrives**: API receives a request from an IP address
2. **Check Rate Limit**: System checks if request should be allowed
3. **Decision**:
   - **Allowed**: Request proceeds, event recorded
   - **Denied**: Request rejected, violation recorded
4. **Record Event**: All requests (allowed or denied) are recorded for tracking

### Rate Limit Types

#### Per-IP Rate Limiting

Limits requests based on the client's IP address. This is the most common form of rate limiting.

**Example:**

- Limit: 60 requests per minute per IP
- IP `192.168.1.100` makes 70 requests in 1 minute
- First 60 requests: **Allowed**
- Remaining 10 requests: **Denied**

#### Per-API-Key Rate Limiting

Limits requests based on the API key used for authentication. Provides higher limits for
authenticated users.

**Example:**

- Limit: 100 requests per minute per API key
- API key `abc123` makes 120 requests in 1 minute
- First 100 requests: **Allowed**
- Remaining 20 requests: **Denied**

#### Per-Endpoint Rate Limiting

Limits requests to specific API endpoints. Useful for protecting expensive endpoints.

**Example:**

- Limit: 30 requests per minute for `/api/search`
- IP `192.168.1.100` makes 40 requests to `/api/search` in 1 minute
- First 30 requests: **Allowed**
- Remaining 10 requests: **Denied**

### Sliding Window Algorithm

The sliding window algorithm is more fair than fixed windows because it:

1. **Prevents Edge Cases**: Fixed windows allow bursts at window boundaries
2. **Smooth Limits**: Provides smoother rate limiting
3. **Fair Distribution**: Distributes requests more evenly over time

**How It Works:**

```
Time:  |----|----|----|----|----|----|
Window: [    ]  [    ]  [    ]  [    ]
        ^                    ^
        |                    |
    Request 1            Request 2
```

The window "slides" forward in time, always looking at the last N seconds of requests.

**Example:**

- Limit: 60 requests per minute
- Current time: 10:00:30
- Window: Last 60 seconds (9:59:30 to 10:00:30)
- Count requests in this window
- If count < 60: **Allow**
- If count >= 60: **Deny**

### Burst Handling

Burst handling allows short bursts of requests while maintaining overall rate limits.

**Example:**

- Limit: 60 requests per minute
- Burst size: 10 requests
- IP makes 15 requests in 5 seconds
- First 10 requests: **Allowed** (burst allowance)
- Remaining 5 requests: **Checked against per-minute limit**

---

## Configuration

### Basic Configuration

Edit `config/security.conf`:

```bash
# Per-IP Rate Limits
RATE_LIMIT_PER_IP_PER_MINUTE=60
RATE_LIMIT_PER_IP_PER_HOUR=1000
RATE_LIMIT_PER_IP_PER_DAY=10000

# Burst Handling
RATE_LIMIT_BURST_SIZE=10

# Per-API-Key Rate Limits (for authenticated users)
RATE_LIMIT_PER_API_KEY_PER_MINUTE=100
RATE_LIMIT_PER_API_KEY_PER_HOUR=10000
RATE_LIMIT_PER_API_KEY_PER_DAY=100000
```

### Configuration Options

#### `RATE_LIMIT_PER_IP_PER_MINUTE`

- **Default:** `60`
- **Description:** Maximum requests per IP per minute
- **Recommendation:** Start with 60, adjust based on usage

#### `RATE_LIMIT_PER_IP_PER_HOUR`

- **Default:** `1000`
- **Description:** Maximum requests per IP per hour
- **Recommendation:** Set to ~16x per-minute limit

#### `RATE_LIMIT_PER_IP_PER_DAY`

- **Default:** `10000`
- **Description:** Maximum requests per IP per day
- **Recommendation:** Set to ~10x per-hour limit

#### `RATE_LIMIT_BURST_SIZE`

- **Default:** `10`
- **Description:** Maximum burst requests allowed
- **Recommendation:** Set to ~15-20% of per-minute limit

#### `RATE_LIMIT_PER_API_KEY_PER_MINUTE`

- **Default:** `100`
- **Description:** Maximum requests per API key per minute
- **Recommendation:** Set higher than per-IP limit (authenticated users)

---

## Usage Examples

### Check Rate Limit

```bash
# Check if request should be allowed
./bin/security/rateLimiter.sh check 192.168.1.100 /api/notes

# Exit code: 0 = allowed, 1 = denied
if ./bin/security/rateLimiter.sh check 192.168.1.100; then
    echo "Request allowed"
else
    echo "Rate limit exceeded"
fi
```

### Record Request

```bash
# Record a request (call after request is processed)
./bin/security/rateLimiter.sh record 192.168.1.100 /api/notes

# Record with API key
./bin/security/rateLimiter.sh record 192.168.1.100 /api/notes abc123
```

### View Statistics

```bash
# View all rate limit statistics
./bin/security/rateLimiter.sh stats

# View statistics for specific IP
./bin/security/rateLimiter.sh stats 192.168.1.100

# View statistics for specific endpoint
./bin/security/rateLimiter.sh stats 192.168.1.100 /api/notes
```

### Reset Rate Limit

```bash
# Reset rate limit for IP (use with caution)
./bin/security/rateLimiter.sh reset 192.168.1.100

# Reset rate limit for IP and endpoint
./bin/security/rateLimiter.sh reset 192.168.1.100 /api/notes
```

### Integration Example

```bash
#!/bin/bash
# Example: Rate limiting in API request handler

IP_ADDRESS="192.168.1.100"
ENDPOINT="/api/notes"
API_KEY="abc123"

# Check rate limit
if ./bin/security/rateLimiter.sh check "${IP_ADDRESS}" "${ENDPOINT}" "${API_KEY}"; then
    # Process request
    process_api_request "${ENDPOINT}"

    # Record successful request
    ./bin/security/rateLimiter.sh record "${IP_ADDRESS}" "${ENDPOINT}" "${API_KEY}"

    echo "Request processed successfully"
else
    # Rate limit exceeded
    echo "Rate limit exceeded"
    exit 429  # HTTP 429 Too Many Requests
fi
```

---

## Algorithm Details

### Sliding Window Implementation

The sliding window algorithm works by:

1. **Query Recent Events**: Query `security_events` table for events in the last N seconds
2. **Count Requests**: Count requests matching the identifier (IP/API-key/endpoint)
3. **Compare to Limit**: Compare count to configured limit
4. **Decision**: Allow if count < limit, deny otherwise

**SQL Query Example:**

```sql
SELECT COUNT(*)
FROM security_events
WHERE event_type = 'rate_limit'
  AND ip_address = '192.168.1.100'::inet
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 minute';
```

### Burst Handling Implementation

Burst handling works by:

1. **Check Burst Window**: Check requests in last few seconds (burst window)
2. **Allow Burst**: If burst count < burst size, allow request
3. **Check Overall Limit**: If burst count >= burst size, check per-minute limit
4. **Decision**: Allow if either burst or per-minute limit allows

**Example:**

- Burst size: 10
- Burst window: 5 seconds
- Per-minute limit: 60

```
Time: 10:00:00 - 10 requests in 5 seconds
- Burst count: 10
- Per-minute count: 10
- Decision: ALLOW (within burst allowance)

Time: 10:00:05 - 5 more requests
- Burst count: 15 (in last 5 seconds)
- Per-minute count: 15
- Decision: DENY (exceeds burst size, and per-minute count is still OK but burst exceeded)
```

### Identifier Resolution

The system determines which identifier to use based on:

1. **API Key Present**: Use API key identifier if provided
2. **Endpoint Present**: Use endpoint identifier if provided
3. **IP Address**: Use IP address as fallback

**Priority:**

1. API key (highest priority)
2. Endpoint
3. IP address (lowest priority)

---

## Best Practices

### Setting Limits

1. **Start Conservative**: Begin with lower limits and increase based on usage
2. **Monitor Violations**: Track rate limit violations to identify abuse
3. **Adjust Based on Usage**: Increase limits for legitimate high-volume users
4. **Use API Keys**: Provide higher limits for authenticated users

### Handling Violations

1. **Log Violations**: Always log rate limit violations for analysis
2. **Progressive Blocking**: Use progressive blocking for repeat offenders
3. **Whitelist Legitimate Users**: Add trusted IPs to whitelist
4. **Provide Feedback**: Return clear error messages (HTTP 429)

### Performance

1. **Database Indexing**: Ensure `security_events` table has indexes on `timestamp` and `ip_address`
2. **Query Optimization**: Use efficient queries for rate limit checks
3. **Cleanup Old Events**: Regularly cleanup old security events
4. **Connection Pooling**: Use connection pooling for database queries

### Monitoring

1. **Track Metrics**: Monitor rate limit metrics regularly
2. **Review Violations**: Review violation patterns weekly
3. **Adjust Thresholds**: Adjust thresholds based on usage patterns
4. **Alert on Abuse**: Set up alerts for excessive violations

---

## Troubleshooting

### Legitimate Users Being Blocked

**Symptoms:** Legitimate users report being rate limited

**Solutions:**

1. Check if IP is whitelisted: `./bin/security/ipBlocking.sh status <IP>`
2. Review rate limit thresholds
3. Consider increasing limits for authenticated users
4. Add IP to whitelist if legitimate high-volume user

### Rate Limits Not Working

**Symptoms:** Rate limits not being enforced

**Solutions:**

1. Verify configuration is loaded
2. Check database connection
3. Verify `record_request()` is being called
4. Check logs: `tail -f logs/rate_limiter.log`

### High Database Load

**Symptoms:** Rate limiting causing high database load

**Solutions:**

1. Add indexes to `security_events` table
2. Optimize queries (use EXPLAIN ANALYZE)
3. Consider caching rate limit results
4. Cleanup old events regularly

### Burst Handling Issues

**Symptoms:** Burst handling not working as expected

**Solutions:**

1. Review burst size configuration
2. Check burst window implementation
3. Verify burst logic in `check_rate_limit_sliding_window()`
4. Adjust burst size based on usage patterns

---

## References

- **API Security Guide**: `docs/API_SECURITY_GUIDE.md` - Comprehensive security guide
- **Security Metrics**: `docs/API_SECURITY_METRICS.md` - Rate limiting metrics
- **Alert Thresholds**: `docs/API_SECURITY_ALERT_THRESHOLDS.md` - Rate limit thresholds
- **Script**: `bin/security/rateLimiter.sh` - Rate limiting implementation
- **Security Functions**: `bin/lib/securityFunctions.sh` - Security utilities
