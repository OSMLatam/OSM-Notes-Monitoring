# API Security & Protection Design

> **Purpose:** Detailed design for API security and protection mechanisms  
> **Author:** Andres Gomez (AngocA)  
> **Version:** 2025-01-23  
> **Status:** Design Document

## Overview

This document details the security and protection mechanisms for the OSM-Notes-API service to prevent abuse, DDoS attacks, and ensure service availability.

## Threat Model

### Potential Threats

1. **DDoS Attacks**
   - Volume-based: Overwhelming the server with requests
   - Protocol-based: Exploiting protocol weaknesses
   - Application-based: Targeting specific endpoints

2. **Abuse & Scraping**
   - Automated data scraping
   - Unauthorized bulk data access
   - Resource exhaustion

3. **Authentication Attacks**
   - Brute force attacks
   - Credential stuffing
   - Session hijacking

4. **Geographic Attacks**
   - Attacks from specific regions
   - Unusual geographic patterns

5. **Resource Exhaustion**
   - Database connection exhaustion
   - Memory exhaustion
   - Disk space exhaustion

## Protection Mechanisms

### 1. Rate Limiting

#### Implementation Strategy

**Per-IP Rate Limiting:**
```bash
# Configuration
RATE_LIMIT_PER_IP_PER_MINUTE=60
RATE_LIMIT_PER_IP_PER_HOUR=1000
RATE_LIMIT_PER_IP_PER_DAY=10000
BURST_ALLOWANCE=10  # Allow short bursts
```

**Per-API-Key Rate Limiting:**
```bash
# For authenticated users
RATE_LIMIT_PER_KEY_PER_MINUTE=300
RATE_LIMIT_PER_KEY_PER_HOUR=10000
RATE_LIMIT_PER_KEY_PER_DAY=100000
```

**Per-Endpoint Rate Limiting:**
```bash
# Different limits for different endpoints
RATE_LIMIT_SEARCH_PER_MINUTE=30
RATE_LIMIT_DETAIL_PER_MINUTE=100
RATE_LIMIT_EXPORT_PER_MINUTE=5
```

#### Algorithm: Sliding Window

**Implementation:**
- Use Redis or PostgreSQL to track request counts
- Maintain counters per IP/Key/Endpoint
- Use sliding window (not fixed window) for fairness
- Reset counters after time window expires

**Example:**
```sql
-- PostgreSQL table for rate limiting
CREATE TABLE api_rate_limits (
    identifier VARCHAR(255) NOT NULL,  -- IP or API key
    endpoint VARCHAR(255) NOT NULL,
    window_start TIMESTAMP NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (identifier, endpoint, window_start)
);

-- Index for fast lookups
CREATE INDEX idx_rate_limits_lookup 
    ON api_rate_limits (identifier, endpoint, window_start);
```

#### Rate Limit Headers

**Response Headers:**
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1640995200
X-RateLimit-Window: 60
```

**429 Too Many Requests Response:**
```json
{
  "error": "rate_limit_exceeded",
  "message": "Rate limit exceeded. Maximum 60 requests per minute.",
  "retry_after": 15,
  "limit": 60,
  "window": "1 minute"
}
```

### 2. IP Management

#### Whitelist

**Purpose:** Bypass rate limiting for trusted IPs

**Use Cases:**
- Your own servers
- Trusted partners
- Internal services

**Implementation:**
```sql
CREATE TABLE api_ip_whitelist (
    ip_address INET NOT NULL PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    created_by VARCHAR(255)
);
```

**Management Script:**
```bash
# bin/security/manageWhitelist.sh
# Usage:
#   ./manageWhitelist.sh add 192.168.1.100 "Internal server"
#   ./manageWhitelist.sh remove 192.168.1.100
#   ./manageWhitelist.sh list
```

#### Blacklist

**Purpose:** Permanently block known bad actors

**Implementation:**
```sql
CREATE TABLE api_ip_blacklist (
    ip_address INET NOT NULL PRIMARY KEY,
    reason TEXT,
    blocked_at TIMESTAMP DEFAULT NOW(),
    blocked_by VARCHAR(255),
    expires_at TIMESTAMP,  -- NULL = permanent
    is_active BOOLEAN DEFAULT TRUE
);
```

**Automatic Blocking:**
- Block IPs that exceed rate limits repeatedly
- Block IPs with suspicious patterns
- Block IPs from known attack sources

**Manual Blocking:**
```bash
# bin/security/manageBlacklist.sh
# Usage:
#   ./manageBlacklist.sh add 192.168.1.200 "Abuse detected"
#   ./manageBlacklist.sh remove 192.168.1.200
#   ./manageBlacklist.sh list
```

#### Temporary Blocks

**Purpose:** Short-term blocks for suspicious activity

**Implementation:**
```sql
CREATE TABLE api_ip_temp_blocks (
    ip_address INET NOT NULL PRIMARY KEY,
    reason TEXT,
    blocked_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,
    violation_count INTEGER DEFAULT 1
);
```

**Block Duration:**
- First violation: 15 minutes
- Second violation: 1 hour
- Third violation: 24 hours
- Fourth violation: Permanent block

### 3. DDoS Protection

#### Detection Mechanisms

**Volume-Based Detection:**
```bash
# Thresholds
DDOS_THRESHOLD_REQUESTS_PER_SECOND=100
DDOS_THRESHOLD_CONCURRENT_CONNECTIONS=500
DDOS_THRESHOLD_BANDWIDTH_MBPS=100
```

**Pattern Detection:**
- Rapid sequential requests from same IP
- Requests to non-existent endpoints
- Missing or invalid headers
- Unusual request sizes

**Implementation:**
```sql
-- Track request patterns
CREATE TABLE api_request_patterns (
    ip_address INET NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    endpoint VARCHAR(255),
    response_code INTEGER,
    response_time_ms INTEGER,
    user_agent TEXT,
    PRIMARY KEY (ip_address, timestamp)
);

-- Analyze patterns for DDoS
CREATE OR REPLACE FUNCTION detect_ddos_pattern(
    check_window INTERVAL DEFAULT '1 minute'
) RETURNS TABLE (
    ip_address INET,
    request_count BIGINT,
    avg_response_time_ms NUMERIC,
    error_rate NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        arp.ip_address,
        COUNT(*) as request_count,
        AVG(arp.response_time_ms) as avg_response_time_ms,
        (COUNT(*) FILTER (WHERE arp.response_code >= 400)::NUMERIC / COUNT(*)::NUMERIC * 100) as error_rate
    FROM api_request_patterns arp
    WHERE arp.timestamp > NOW() - check_window
    GROUP BY arp.ip_address
    HAVING COUNT(*) > 100  -- Threshold
    ORDER BY request_count DESC;
END;
$$ LANGUAGE plpgsql;
```

#### Mitigation Strategies

**Automatic Responses:**
1. **Immediate**: Block IP temporarily (15 minutes)
2. **Escalation**: Extend block duration if pattern continues
3. **Alert**: Notify administrator immediately
4. **Logging**: Log all suspicious activity

**Rate Limiting Escalation:**
- Reduce rate limits for suspicious IPs
- Implement stricter limits during attacks
- Prioritize legitimate traffic

**Connection Limits:**
```bash
# Maximum concurrent connections per IP
MAX_CONCURRENT_CONNECTIONS_PER_IP=10
MAX_TOTAL_CONNECTIONS=1000
```

### 4. Abuse Detection

#### Pattern Analysis

**Suspicious Patterns:**
1. **Rapid Sequential Requests**
   - Multiple requests in < 1 second
   - Pattern: Request → Response → Immediate Request

2. **Unusual Query Patterns**
   - Repeated identical queries
   - Queries with unusual parameters
   - Queries to non-existent resources

3. **Missing Headers**
   - Missing User-Agent
   - Invalid User-Agent
   - Missing Referer (if required)

4. **Geographic Anomalies**
   - Requests from unusual locations
   - Rapid geographic changes
   - Requests from known bad regions

5. **Resource Exhaustion Attempts**
   - Very large query parameters
   - Deep pagination requests
   - Complex queries that timeout

#### Detection Algorithm

```sql
-- Abuse detection function
CREATE OR REPLACE FUNCTION detect_abuse_patterns(
    ip_address INET,
    check_window INTERVAL DEFAULT '5 minutes'
) RETURNS TABLE (
    pattern_type VARCHAR(255),
    severity VARCHAR(50),
    evidence TEXT
) AS $$
DECLARE
    request_count BIGINT;
    avg_time_between_requests NUMERIC;
    unique_endpoints BIGINT;
    error_rate NUMERIC;
BEGIN
    -- Get request statistics
    SELECT 
        COUNT(*),
        AVG(EXTRACT(EPOCH FROM (timestamp - LAG(timestamp) OVER (ORDER BY timestamp)))),
        COUNT(DISTINCT endpoint),
        (COUNT(*) FILTER (WHERE response_code >= 400)::NUMERIC / COUNT(*)::NUMERIC * 100)
    INTO request_count, avg_time_between_requests, unique_endpoints, error_rate
    FROM api_request_patterns
    WHERE api_request_patterns.ip_address = detect_abuse_patterns.ip_address
      AND timestamp > NOW() - check_window;
    
    -- Pattern 1: Rapid sequential requests
    IF avg_time_between_requests < 0.1 THEN
        RETURN QUERY SELECT 
            'rapid_sequential_requests'::VARCHAR(255),
            'high'::VARCHAR(50),
            format('Average time between requests: %s seconds', avg_time_between_requests)::TEXT;
    END IF;
    
    -- Pattern 2: High error rate
    IF error_rate > 50 THEN
        RETURN QUERY SELECT 
            'high_error_rate'::VARCHAR(255),
            'medium'::VARCHAR(50),
            format('Error rate: %s%%', error_rate)::TEXT;
    END IF;
    
    -- Pattern 3: Too many requests
    IF request_count > 1000 THEN
        RETURN QUERY SELECT 
            'excessive_requests'::VARCHAR(255),
            'high'::VARCHAR(50),
            format('Request count: %s', request_count)::TEXT;
    END IF;
    
    -- Pattern 4: Single endpoint abuse
    IF unique_endpoints = 1 AND request_count > 500 THEN
        RETURN QUERY SELECT 
            'single_endpoint_abuse'::VARCHAR(255),
            'medium'::VARCHAR(50),
            format('Repeated requests to single endpoint: %s requests', request_count)::TEXT;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;
```

#### Response Actions

**Automatic Actions:**
1. **Log**: Record all abuse patterns
2. **Alert**: Notify administrator
3. **Block**: Temporarily block IP
4. **Throttle**: Reduce rate limits for IP

**Manual Review:**
- Review flagged IPs daily
- Investigate patterns
- Decide on permanent blocks
- Adjust detection thresholds

### 5. Connection Management

#### Connection Limits

**Per-IP Limits:**
```bash
MAX_CONCURRENT_CONNECTIONS_PER_IP=10
MAX_CONCURRENT_CONNECTIONS_PER_KEY=20
```

**Global Limits:**
```bash
MAX_TOTAL_CONNECTIONS=1000
MAX_CONNECTIONS_PER_ENDPOINT=100
```

**Implementation:**
```sql
-- Track active connections
CREATE TABLE api_active_connections (
    connection_id VARCHAR(255) PRIMARY KEY,
    ip_address INET NOT NULL,
    api_key VARCHAR(255),
    endpoint VARCHAR(255),
    connected_at TIMESTAMP DEFAULT NOW(),
    last_activity TIMESTAMP DEFAULT NOW()
);

-- Cleanup stale connections
CREATE OR REPLACE FUNCTION cleanup_stale_connections(
    timeout_seconds INTEGER DEFAULT 300
) RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM api_active_connections
    WHERE last_activity < NOW() - (timeout_seconds || ' seconds')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;
```

### 6. Request Validation

#### Input Validation

**Validate:**
- Request size limits
- Parameter types and ranges
- Required headers
- Query parameter formats
- Geographic bounds (if applicable)

**Example:**
```bash
# Request size limits
MAX_REQUEST_SIZE_KB=100
MAX_QUERY_STRING_LENGTH=2048
MAX_POST_BODY_SIZE_KB=1000
```

#### Header Validation

**Required Headers:**
- User-Agent (required, validated)
- Accept (optional, but validated if present)
- Content-Type (for POST requests)

**Validation:**
```bash
# Validate User-Agent
if [[ -z "${USER_AGENT}" ]] || [[ "${USER_AGENT}" == *"bot"* ]] && [[ "${USER_AGENT}" != *"OSM-Notes"* ]]; then
    # Flag as suspicious
fi
```

### 7. Monitoring & Alerting

#### Security Metrics

**Track:**
- Blocked IPs count
- Rate limit violations
- DDoS attack attempts
- Abuse pattern detections
- Authentication failures
- Suspicious activity

**Metrics Storage:**
```sql
CREATE TABLE api_security_metrics (
    metric_date DATE NOT NULL,
    metric_hour INTEGER NOT NULL,
    blocked_ips_count INTEGER DEFAULT 0,
    rate_limit_violations INTEGER DEFAULT 0,
    ddos_attempts INTEGER DEFAULT 0,
    abuse_detections INTEGER DEFAULT 0,
    auth_failures INTEGER DEFAULT 0,
    suspicious_activity INTEGER DEFAULT 0,
    PRIMARY KEY (metric_date, metric_hour)
);
```

#### Alerting

**Alert Triggers:**
- DDoS attack detected
- High rate of blocked IPs
- Multiple abuse patterns detected
- Authentication failure spike
- Unusual traffic patterns

**Alert Channels:**
- Email (immediate)
- Slack (team notification)
- PagerDuty (critical escalation)

## Implementation Scripts

### Rate Limiter Script

```bash
#!/bin/bash
# bin/security/rateLimiter.sh
# Checks if request should be allowed based on rate limits

# Configuration
RATE_LIMIT_PER_MINUTE=60
RATE_LIMIT_WINDOW_SECONDS=60

# Check rate limit
function check_rate_limit {
    local IP_ADDRESS=$1
    local ENDPOINT=$2
    
    # Query database for request count in window
    local REQUEST_COUNT=$(psql -d "${MONITORING_DB}" -Atq -c "
        SELECT COUNT(*) 
        FROM api_rate_limits 
        WHERE identifier = '${IP_ADDRESS}' 
          AND endpoint = '${ENDPOINT}'
          AND window_start > NOW() - INTERVAL '${RATE_LIMIT_WINDOW_SECONDS} seconds';
    ")
    
    if [[ "${REQUEST_COUNT}" -ge "${RATE_LIMIT_PER_MINUTE}" ]]; then
        return 1  # Rate limit exceeded
    fi
    
    return 0  # Within limits
}
```

### IP Blocking Script

```bash
#!/bin/bash
# bin/security/ipBlocking.sh
# Manages IP blocking (whitelist, blacklist, temporary blocks)

function check_ip_blocked {
    local IP_ADDRESS=$1
    
    # Check blacklist
    local IS_BLACKLISTED=$(psql -d "${MONITORING_DB}" -Atq -c "
        SELECT COUNT(*) 
        FROM api_ip_blacklist 
        WHERE ip_address = '${IP_ADDRESS}'::INET 
          AND is_active = TRUE
          AND (expires_at IS NULL OR expires_at > NOW());
    ")
    
    if [[ "${IS_BLACKLISTED}" -gt 0 ]]; then
        return 1  # Blocked
    fi
    
    # Check temporary blocks
    local IS_TEMP_BLOCKED=$(psql -d "${MONITORING_DB}" -Atq -c "
        SELECT COUNT(*) 
        FROM api_ip_temp_blocks 
        WHERE ip_address = '${IP_ADDRESS}'::INET 
          AND expires_at > NOW();
    ")
    
    if [[ "${IS_TEMP_BLOCKED}" -gt 0 ]]; then
        return 1  # Temporarily blocked
    fi
    
    return 0  # Not blocked
}
```

### Abuse Detection Script

```bash
#!/bin/bash
# bin/security/abuseDetection.sh
# Detects abuse patterns and takes action

function detect_and_respond_abuse {
    local IP_ADDRESS=$1
    
    # Run abuse detection
    local ABUSE_PATTERNS=$(psql -d "${MONITORING_DB}" -Atq -c "
        SELECT pattern_type, severity 
        FROM detect_abuse_patterns('${IP_ADDRESS}'::INET);
    ")
    
    if [[ -n "${ABUSE_PATTERNS}" ]]; then
        # Log abuse
        __log_abuse "${IP_ADDRESS}" "${ABUSE_PATTERNS}"
        
        # Block IP temporarily
        block_ip_temporary "${IP_ADDRESS}" "Abuse detected: ${ABUSE_PATTERNS}"
        
        # Send alert
        send_security_alert "Abuse detected from ${IP_ADDRESS}: ${ABUSE_PATTERNS}"
        
        return 1  # Abuse detected
    fi
    
    return 0  # No abuse
}
```

## Configuration

### Security Configuration File

```bash
# etc/security.conf

# Rate Limiting
RATE_LIMIT_PER_IP_PER_MINUTE=60
RATE_LIMIT_PER_IP_PER_HOUR=1000
RATE_LIMIT_PER_IP_PER_DAY=10000
RATE_LIMIT_BURST_SIZE=10

# Connection Limits
MAX_CONCURRENT_CONNECTIONS_PER_IP=10
MAX_TOTAL_CONNECTIONS=1000

# DDoS Protection
DDOS_THRESHOLD_REQUESTS_PER_SECOND=100
DDOS_THRESHOLD_CONCURRENT_CONNECTIONS=500
DDOS_AUTO_BLOCK_DURATION_MINUTES=15

# Abuse Detection
ABUSE_DETECTION_ENABLED=true
ABUSE_RAPID_REQUEST_THRESHOLD=10
ABUSE_ERROR_RATE_THRESHOLD=50
ABUSE_EXCESSIVE_REQUESTS_THRESHOLD=1000

# Blocking
TEMP_BLOCK_FIRST_VIOLATION_MINUTES=15
TEMP_BLOCK_SECOND_VIOLATION_HOURS=1
TEMP_BLOCK_THIRD_VIOLATION_HOURS=24
```

## Testing

### Test Scenarios

1. **Rate Limiting Tests**
   - Send requests at limit
   - Exceed rate limit
   - Verify 429 response
   - Verify rate limit headers

2. **IP Blocking Tests**
   - Test whitelist bypass
   - Test blacklist blocking
   - Test temporary blocks
   - Test block expiration

3. **DDoS Detection Tests**
   - Simulate high-volume attack
   - Verify detection
   - Verify automatic blocking
   - Verify alerting

4. **Abuse Detection Tests**
   - Test rapid sequential requests
   - Test high error rate
   - Test unusual patterns
   - Verify response actions

## Maintenance

### Daily Tasks

1. Review blocked IPs
2. Review abuse patterns
3. Check security metrics
4. Review alerts

### Weekly Tasks

1. Analyze security trends
2. Adjust thresholds if needed
3. Review and update blacklist
4. Test security mechanisms

### Monthly Tasks

1. Security audit
2. Review and update documentation
3. Performance optimization
4. Update security rules

## Conclusion

This security design provides comprehensive protection for the OSM-Notes-API:

- **Rate Limiting**: Prevents abuse and resource exhaustion
- **IP Management**: Controls access from known good/bad actors
- **DDoS Protection**: Detects and mitigates attacks
- **Abuse Detection**: Identifies suspicious patterns
- **Connection Management**: Prevents connection exhaustion
- **Monitoring**: Tracks security metrics and alerts

The system is designed to be:
- **Automatic**: Responds to threats automatically
- **Configurable**: Easy to adjust thresholds
- **Maintainable**: Clear structure and documentation
- **Scalable**: Handles growth in traffic and threats

