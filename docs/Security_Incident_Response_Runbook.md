---
title: "Security Incident Response Runbook"
description: "This runbook provides detailed information about security incidents and how to respond to them, including:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "security"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Security Incident Response Runbook

> **Purpose:** Comprehensive guide for understanding and responding to security incidents  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This runbook provides detailed information about security incidents and how to respond to them,
including:

- What each incident type means
- What causes it
- How to investigate
- How to resolve
- Prevention strategies

## Alert Severity Levels

### CRITICAL

- **Response Time:** Immediate (within 5 minutes)
- **Impact:** Active attack, service availability at risk
- **Action:** Immediate response, block attacker, investigate source

### WARNING

- **Response Time:** Within 15 minutes
- **Impact:** Potential abuse or violation detected
- **Action:** Investigate and respond, monitor closely

### INFO

- **Response Time:** Within 1 hour
- **Impact:** Informational, no immediate threat
- **Action:** Review and document, may indicate trends

## Incident Categories

### 1. Rate Limit Violations

#### Incident: Rate limit exceeded

**Alert Message:** `Rate limit exceeded for IP: X (limit: Y requests/minute)`

**Severity:** WARNING

**Alert Type:** `rate_limit_violation`

**What it means:**

- An IP address has exceeded the configured rate limit
- Rate limit is enforced to prevent abuse and resource exhaustion

**Common Causes:**

- Legitimate high-volume user
- Automated scraping or abuse
- API integration making too many requests
- Burst traffic from legitimate source

**Investigation Steps:**

1. Check rate limit statistics:
   ```bash
   ./bin/security/rateLimiter.sh stats <IP>
   ```
2. Review request patterns:
   ```sql
   SELECT * FROM security_events
   WHERE ip_address = '<IP>'::inet
     AND event_type = 'rate_limit'
   ORDER BY timestamp DESC
   LIMIT 50;
   ```
3. Check if IP is whitelisted:
   ```bash
   ./bin/security/ipBlocking.sh status <IP>
   ```
4. Review request endpoints:
   ```sql
   SELECT endpoint, COUNT(*) as count
   FROM security_events
   WHERE ip_address = '<IP>'::inet
   GROUP BY endpoint
   ORDER BY count DESC;
   ```

**Resolution:**

1. **If Legitimate User:**
   - Add IP to whitelist: `./bin/security/ipBlocking.sh add <IP> whitelist "Legitimate user"`
   - Consider providing API key for higher limits
   - Contact user to optimize request patterns

2. **If Abuse:**
   - Block IP temporarily:
     `./bin/security/ipBlocking.sh add <IP> temp_block "Rate limit violation" 15`
   - Review abuse patterns
   - Consider permanent blacklist for repeat offenders

3. **If API Integration:**
   - Contact integration owner
   - Provide API key for higher limits
   - Optimize integration to reduce request frequency

**Prevention:**

- Monitor rate limit violations regularly
- Adjust thresholds based on usage patterns
- Provide API keys for authenticated users
- Whitelist trusted IPs

---

#### Incident: Multiple rate limit violations from same IP

**Alert Message:** `Multiple rate limit violations from IP: X`

**Severity:** WARNING (escalates to CRITICAL if persistent)

**Alert Type:** `rate_limit_repeated_violations`

**What it means:**

- Same IP has violated rate limits multiple times
- Indicates persistent abuse or misconfiguration

**Common Causes:**

- Persistent attacker
- Misconfigured API integration
- Bot or automated scraper
- Legitimate user unaware of limits

**Investigation Steps:**

1. Count violations:
   ```sql
   SELECT COUNT(*) as violation_count
   FROM security_events
   WHERE ip_address = '<IP>'::inet
     AND event_type = 'rate_limit'
     AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour';
   ```
2. Review violation timeline:
   ```sql
   SELECT timestamp, metadata
   FROM security_events
   WHERE ip_address = '<IP>'::inet
     AND event_type = 'rate_limit'
   ORDER BY timestamp DESC;
   ```
3. Check if already blocked:
   ```bash
   ./bin/security/ipBlocking.sh status <IP>
   ```

**Resolution:**

1. **First Violation:** Log and monitor
2. **Second Violation:** Block for 1 hour
3. **Third Violation:** Block for 24 hours
4. **Persistent:** Add to permanent blacklist

**Prevention:**

- Progressive blocking (15 min → 1 hour → 24 hours)
- Monitor violation patterns
- Automate blocking for repeat offenders

---

### 2. DDoS Attacks

#### Incident: DDoS attack detected

**Alert Message:** `DDoS attack detected from IP: X (requests/sec: Y, threshold: Z)`

**Severity:** CRITICAL

**Alert Type:** `ddos_attack`

**What it means:**

- An IP address is making requests at a rate that exceeds DDoS threshold
- Indicates potential distributed denial-of-service attack
- Service availability may be at risk

**Common Causes:**

- Coordinated attack from single IP
- Botnet attack
- Misconfigured client making excessive requests
- Legitimate traffic spike (false positive)

**Investigation Steps:**

1. Check attack statistics:
   ```bash
   ./bin/security/ddosProtection.sh stats
   ```
2. Review attack patterns:
   ```sql
   SELECT ip_address, COUNT(*) as request_count,
          MIN(timestamp) as first_request,
          MAX(timestamp) as last_request
   FROM security_events
   WHERE event_type = 'ddos'
     AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour'
   GROUP BY ip_address
   ORDER BY request_count DESC;
   ```
3. Check concurrent connections:
   ```sql
   SELECT COUNT(DISTINCT ip_address) as unique_ips
   FROM security_events
   WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '1 minute';
   ```
4. Review request endpoints:
   ```sql
   SELECT endpoint, COUNT(*) as count
   FROM security_events
   WHERE event_type = 'ddos'
   GROUP BY endpoint
   ORDER BY count DESC;
   ```

**Resolution:**

1. **Automatic Response (if enabled):**
   - IP is automatically blocked for `DDOS_AUTO_BLOCK_DURATION_MINUTES`
   - Monitor blocked IPs: `./bin/security/ipBlocking.sh list temp_block`

2. **Manual Response:**
   - Block IP immediately: `./bin/security/ddosProtection.sh block <IP> "DDoS attack"`
   - Review attack source (geographic location, ISP)
   - Consider enabling geographic filtering if attacks from specific regions

3. **If False Positive:**
   - Unblock IP: `./bin/security/ddosProtection.sh unblock <IP>`
   - Add to whitelist if legitimate high-volume user
   - Adjust DDoS thresholds if needed

4. **If Legitimate Traffic Spike:**
   - Review baseline traffic patterns
   - Adjust `DDOS_THRESHOLD_REQUESTS_PER_SECOND` if needed
   - Consider scaling infrastructure

**Prevention:**

- Monitor baseline traffic patterns
- Set thresholds 2-3x above normal peak traffic
- Enable automatic IP blocking
- Consider geographic filtering
- Regular review of blocked IPs

---

#### Incident: High concurrent connections

**Alert Message:** `High concurrent connections detected: X (threshold: Y)`

**Severity:** CRITICAL

**Alert Type:** `ddos_concurrent_connections`

**What it means:**

- Number of concurrent connections exceeds threshold
- May indicate DDoS attack or resource exhaustion
- Service availability may be at risk

**Common Causes:**

- DDoS attack (connection exhaustion)
- Legitimate traffic spike
- Misconfigured clients
- Resource exhaustion

**Investigation Steps:**

1. Check connection statistics:
   ```bash
   ./bin/security/ddosProtection.sh stats
   ```
2. Review unique IPs:
   ```sql
   SELECT COUNT(DISTINCT ip_address) as unique_ips
   FROM security_events
   WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '1 minute';
   ```
3. Check connection patterns:
   ```sql
   SELECT ip_address, COUNT(*) as connection_count
   FROM security_events
   WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '1 minute'
   GROUP BY ip_address
   ORDER BY connection_count DESC
   LIMIT 20;
   ```

**Resolution:**

1. **If Attack:**
   - Enable connection rate limiting
   - Block high-volume IPs
   - Review infrastructure capacity

2. **If Legitimate:**
   - Scale infrastructure
   - Adjust `MAX_TOTAL_CONNECTIONS` threshold
   - Optimize connection handling

**Prevention:**

- Monitor connection patterns
- Set appropriate connection limits
- Enable connection rate limiting
- Regular capacity planning

---

### 3. Abuse Detection

#### Incident: Abuse pattern detected

**Alert Message:** `Abuse pattern detected from IP: X (pattern: Y)`

**Severity:** WARNING

**Alert Type:** `abuse_pattern`

**What it means:**

- Known abuse pattern detected (SQL injection, XSS, etc.)
- Indicates potential attack attempt
- May indicate automated abuse

**Common Causes:**

- SQL injection attempt
- XSS attack attempt
- Path traversal attempt
- Automated vulnerability scanning

**Investigation Steps:**

1. Review abuse patterns:
   ```bash
   ./bin/security/abuseDetection.sh patterns
   ```
2. Check specific IP:
   ```bash
   ./bin/security/abuseDetection.sh check <IP>
   ```
3. Review security events:
   ```sql
   SELECT * FROM security_events
   WHERE ip_address = '<IP>'::inet
     AND event_type = 'abuse'
   ORDER BY timestamp DESC
   LIMIT 50;
   ```
4. Review request details:
   ```sql
   SELECT timestamp, endpoint, metadata
   FROM security_events
   WHERE ip_address = '<IP>'::inet
     AND event_type = 'abuse'
   ORDER BY timestamp DESC;
   ```

**Resolution:**

1. **If Attack Attempt:**
   - Block IP: `./bin/security/ipBlocking.sh add <IP> temp_block "Abuse pattern detected" 60`
   - Review attack patterns
   - Consider permanent blacklist for persistent attackers

2. **If False Positive:**
   - Review pattern matching logic
   - Adjust abuse detection thresholds
   - Whitelist IP if legitimate user

**Prevention:**

- Regular review of abuse patterns
- Update pattern matching rules
- Monitor false positive rate
- Adjust thresholds based on experience

---

#### Incident: Anomaly detected

**Alert Message:** `Anomaly detected from IP: X (score: Y, threshold: Z)`

**Severity:** WARNING

**Alert Type:** `abuse_anomaly`

**What it means:**

- Unusual activity pattern detected from an IP
- Activity significantly differs from baseline
- May indicate abuse or compromised account

**Common Causes:**

- Sudden spike in request volume
- Unusual endpoint access patterns
- Unusual time-of-day activity
- Compromised account or API key

**Investigation Steps:**

1. Review anomaly score:
   ```bash
   ./bin/security/abuseDetection.sh check <IP>
   ```
2. Compare to baseline:
   ```sql
   SELECT
     AVG(CASE WHEN timestamp < CURRENT_TIMESTAMP - INTERVAL '7 days' THEN 1 ELSE 0 END) as baseline,
     COUNT(*) FILTER (WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour') as current
   FROM security_events
   WHERE ip_address = '<IP>'::inet;
   ```
3. Review activity patterns:
   ```sql
   SELECT
     DATE_TRUNC('hour', timestamp) as hour,
     COUNT(*) as request_count
   FROM security_events
   WHERE ip_address = '<IP>'::inet
     AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
   GROUP BY hour
   ORDER BY hour;
   ```

**Resolution:**

1. **If Abuse:**
   - Block IP temporarily
   - Review activity patterns
   - Consider permanent block if persistent

2. **If Legitimate:**
   - Review baseline calculation
   - Adjust anomaly detection thresholds
   - Whitelist IP if trusted user

**Prevention:**

- Regular baseline updates
- Monitor anomaly detection accuracy
- Adjust thresholds based on false positive rate
- Review anomaly patterns regularly

---

#### Incident: Behavioral abuse detected

**Alert Message:** `Behavioral abuse detected from IP: X (score: Y)`

**Severity:** WARNING

**Alert Type:** `abuse_behavioral`

**What it means:**

- Suspicious behavioral patterns detected
- May indicate automated abuse or scraping
- May indicate compromised account

**Common Causes:**

- Automated scraping
- Bot activity
- Unusual endpoint diversity
- Unusual user agent patterns

**Investigation Steps:**

1. Review behavioral score:
   ```bash
   ./bin/security/abuseDetection.sh check <IP>
   ```
2. Review endpoint diversity:
   ```sql
   SELECT COUNT(DISTINCT endpoint) as endpoint_count
   FROM security_events
   WHERE ip_address = '<IP>'::inet
     AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour';
   ```
3. Review user agent diversity:
   ```sql
   SELECT metadata->>'user_agent' as user_agent, COUNT(*) as count
   FROM security_events
   WHERE ip_address = '<IP>'::inet
   GROUP BY user_agent
   ORDER BY count DESC;
   ```

**Resolution:**

1. **If Abuse:**
   - Block IP
   - Review scraping patterns
   - Consider rate limiting or blocking

2. **If Legitimate:**
   - Review behavioral analysis logic
   - Adjust behavioral thresholds
   - Whitelist IP if trusted user

**Prevention:**

- Monitor behavioral patterns
- Adjust behavioral analysis thresholds
- Regular review of false positives
- Update behavioral analysis rules

---

### 4. IP Management Incidents

#### Incident: IP automatically blocked

**Alert Message:** `IP automatically blocked: X (reason: Y, duration: Z)`

**Severity:** INFO (logged, not alerted)

**Alert Type:** `ip_auto_block`

**What it means:**

- An IP was automatically blocked due to security violation
- Block duration depends on violation count
- IP will be unblocked automatically after duration expires

**Common Causes:**

- Rate limit violation
- DDoS attack detection
- Abuse pattern detection
- Anomaly detection

**Investigation Steps:**

1. Check block status:
   ```bash
   ./bin/security/ipBlocking.sh status <IP>
   ```
2. Review block reason:
   ```sql
   SELECT * FROM ip_management
   WHERE ip_address = '<IP>'::inet
     AND list_type = 'temp_block'
   ORDER BY created_at DESC
   LIMIT 1;
   ```
3. Review violation history:
   ```sql
   SELECT event_type, COUNT(*) as count
   FROM security_events
   WHERE ip_address = '<IP>'::inet
   GROUP BY event_type
   ORDER BY count DESC;
   ```

**Resolution:**

1. **If Legitimate User:**
   - Unblock IP: `./bin/security/ipBlocking.sh remove <IP> temp_block`
   - Add to whitelist to prevent future blocks
   - Contact user to optimize request patterns

2. **If Abuse:**
   - Review violation history
   - Consider permanent blacklist if persistent
   - Monitor after unblock

**Prevention:**

- Regular review of blocked IPs
- Whitelist trusted IPs
- Provide API keys for authenticated users
- Monitor false positive rate

---

## Incident Response Checklist

### Immediate Response (CRITICAL)

- [ ] Acknowledge alert
- [ ] Check alert details (IP, type, severity)
- [ ] Review attack statistics
- [ ] Block attacker if confirmed attack
- [ ] Escalate if needed
- [ ] Document incident

### Investigation (WARNING)

- [ ] Review security events
- [ ] Check IP status (whitelisted/blacklisted)
- [ ] Review request patterns
- [ ] Check for false positives
- [ ] Document findings

### Resolution

- [ ] Take appropriate action (block/unblock)
- [ ] Update IP management lists
- [ ] Adjust thresholds if needed
- [ ] Document resolution
- [ ] Monitor after resolution

### Follow-up

- [ ] Review incident patterns
- [ ] Update runbook if needed
- [ ] Adjust thresholds based on experience
- [ ] Review prevention strategies

## Prevention Strategies

### Rate Limiting

- Monitor rate limit violations regularly
- Adjust thresholds based on usage patterns
- Provide API keys for authenticated users
- Whitelist trusted IPs

### DDoS Protection

- Monitor baseline traffic patterns
- Set thresholds 2-3x above normal peak
- Enable automatic IP blocking
- Consider geographic filtering

### Abuse Detection

- Regular review of abuse patterns
- Update pattern matching rules
- Monitor false positive rate
- Adjust thresholds based on experience

### IP Management

- Regular review of blocked IPs
- Whitelist trusted IPs
- Progressive blocking for repeat offenders
- Cleanup expired blocks regularly

## References

- **API Security Guide**: `docs/API_SECURITY_GUIDE.md` - Comprehensive security guide
- **Security Metrics**: `docs/API_SECURITY_METRICS.md` - Security metrics definition
- **Alert Thresholds**: `docs/API_SECURITY_ALERT_THRESHOLDS.md` - Alert threshold definitions
- **Rate Limiting Guide**: `docs/RATE_LIMITING_GUIDE.md` - Rate limiting guide
- **Security Best Practices**: `docs/SECURITY_BEST_PRACTICES.md` - Security best practices
