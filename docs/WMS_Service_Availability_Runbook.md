---
title: "WMS Service Availability Runbook"
description: "This runbook provides detailed information about each WMS monitoring alert type, including:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "documentation"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# WMS Service Availability Runbook

> **Purpose:** Comprehensive guide for understanding and responding to WMS service availability
> alerts  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This runbook provides detailed information about each WMS monitoring alert type, including:

- What the alert means
- What causes it
- How to investigate
- How to resolve
- Prevention strategies

## Alert Severity Levels

### CRITICAL

- **Response Time:** Immediate (within 15 minutes)
- **Impact:** Service is non-functional
- **Action:** Escalate immediately, investigate root cause

### WARNING

- **Response Time:** Within 1 hour
- **Impact:** Performance degradation or potential issues
- **Action:** Investigate and resolve, monitor closely

## Alert Categories

### 1. Service Availability Alerts

#### Alert: Service Unavailable

**Alert Message:** `WMS service is unavailable (HTTP XXX, URL: http://...)`

**Severity:** CRITICAL

**Alert Type:** `service_unavailable`

**What it means:**

- WMS service is not responding to HTTP requests
- Service may be down, unreachable, or experiencing issues

**Common Causes:**

- Service process crashed or stopped
- Service not started
- Network connectivity issues
- Firewall blocking access
- Service overloaded
- Port conflict

**Investigation Steps:**

1. Check if service is running:
   ```bash
   systemctl status wms-service
   # Or check process
   ps aux | grep wms
   ```
2. Test service URL manually:
   ```bash
   curl -v http://localhost:8080
   ```
3. Check service logs:
   ```bash
   tail -f /var/log/wms/service.log
   journalctl -u wms-service -f
   ```
4. Check network connectivity:
   ```bash
   ping localhost
   telnet localhost 8080
   ```
5. Check firewall rules:
   ```bash
   sudo iptables -L -n | grep 8080
   sudo firewall-cmd --list-all
   ```
6. Check port availability:
   ```bash
   netstat -tlnp | grep 8080
   ss -tlnp | grep 8080
   ```

**Resolution:**

1. Start service if stopped:
   ```bash
   systemctl start wms-service
   ```
2. Restart service if needed:
   ```bash
   systemctl restart wms-service
   ```
3. Check service configuration for errors
4. Resolve network/firewall issues
5. Check for port conflicts and resolve
6. Review service logs for errors
7. Scale resources if overloaded

**Prevention:**

- Set up service auto-restart
- Monitor service health regularly
- Set up high availability
- Document service dependencies
- Regular health checks

---

### 2. Health Check Alerts

#### Alert: Health Check Failed

**Alert Message:** `WMS health check failed (HTTP XXX, status: unhealthy, URL: http://...)`

**Severity:** CRITICAL

**Alert Type:** `health_check_failed`

**What it means:**

- Health check endpoint returned unhealthy status or error
- Service may be partially functional but unhealthy

**Common Causes:**

- Service dependencies failing (database, cache, etc.)
- Service in degraded state
- Health endpoint misconfigured
- Service overloaded

**Investigation Steps:**

1. Test health endpoint manually:
   ```bash
   curl http://localhost:8080/health
   ```
2. Check health endpoint response:
   ```bash
   curl -v http://localhost:8080/health
   ```
3. Review service health status
4. Check service dependencies:
   - Database connectivity
   - Cache connectivity
   - External services
5. Review service logs for health-related errors

**Resolution:**

1. Fix dependency issues (database, cache, etc.)
2. Restart service if needed
3. Fix health endpoint configuration
4. Resolve service overload
5. Review and fix underlying issues

**Prevention:**

- Implement comprehensive health checks
- Monitor dependencies
- Set up dependency health checks
- Regular health endpoint testing

---

### 3. Performance Alerts

#### Alert: Response Time Exceeded

**Alert Message:** `WMS response time (XXXms) exceeds threshold (YYYms, URL: http://...)`

**Severity:** WARNING

**Alert Type:** `response_time_exceeded`

**What it means:**

- WMS response time exceeds configured threshold
- Service may be slow or overloaded

**Common Causes:**

- High server load
- Network latency
- Slow database queries
- Resource constraints (CPU, memory, disk)
- Service overloaded

**Investigation Steps:**

1. Check server load:
   ```bash
   top
   htop
   uptime
   ```
2. Check network latency:
   ```bash
   ping localhost
   traceroute localhost
   ```
3. Check resource usage:
   ```bash
   free -h
   df -h
   iostat -x 1
   ```
4. Review slow queries or operations
5. Check service logs for performance issues

**Resolution:**

1. Scale resources if constrained
2. Optimize slow operations
3. Reduce server load
4. Fix network issues
5. Optimize database queries
6. Consider load balancing

**Prevention:**

- Monitor resource usage
- Set up auto-scaling
- Optimize queries regularly
- Capacity planning
- Performance testing

---

#### Alert: Tile Generation Slow

**Alert Message:** `WMS tile generation time (XXXms) exceeds threshold (YYYms, URL: http://...)`

**Severity:** WARNING

**Alert Type:** `tile_generation_slow`

**What it means:**

- Tile generation is taking longer than expected
- May indicate performance issues

**Common Causes:**

- Large data volumes
- Complex rendering
- Resource constraints
- Slow data sources
- Cache issues

**Investigation Steps:**

1. Check tile generation logs
2. Review data source performance
3. Check cache effectiveness
4. Review resource usage
5. Test tile generation manually

**Resolution:**

1. Optimize tile generation
2. Improve cache strategy
3. Scale resources
4. Optimize data sources
5. Review rendering logic

**Prevention:**

- Monitor tile generation performance
- Optimize rendering
- Effective caching
- Regular performance reviews

---

### 4. Error Rate Alerts

#### Alert: Error Rate Exceeded

**Alert Message:** `WMS error rate (X%) exceeds threshold (Y%, errors: A, requests: B)`

**Severity:** WARNING

**Alert Type:** `error_rate_exceeded`

**What it means:**

- Error rate exceeds configured threshold
- Service may be experiencing issues

**Common Causes:**

- Service bugs
- Data quality issues
- Dependency failures
- Resource constraints
- Configuration errors

**Investigation Steps:**

1. Review error logs:
   ```bash
   grep -i error /var/log/wms/*.log | tail -50
   ```
2. Identify error patterns:
   ```bash
   grep -i error /var/log/wms/*.log | cut -d: -f4- | sort | uniq -c | sort -rn
   ```
3. Check for recent deployments
4. Review service stability
5. Check dependencies

**Resolution:**

1. Fix identified bugs
2. Resolve data quality issues
3. Fix dependency issues
4. Resolve resource constraints
5. Fix configuration errors
6. Rollback recent changes if needed

**Prevention:**

- Comprehensive testing
- Code reviews
- Gradual deployments
- Error monitoring
- Regular reviews

---

### 5. Cache Performance Alerts

#### Alert: Cache Hit Rate Low

**Alert Message:** `WMS cache hit rate (X%) is below threshold (Y%, hits: A, misses: B)`

**Severity:** WARNING

**Alert Type:** `cache_hit_rate_low`

**What it means:**

- Cache hit rate is below threshold
- Cache may not be effective
- **Note:** This alert only triggers when there is actual cache activity (hits + misses > 0). If you
  see 0% with 0 hits and 0 misses, there's no recent activity, which is normal and won't trigger an
  alert.

**Common Causes:**

- Cache size too small
- Cache eviction too aggressive
- Cache invalidation issues
- Poor cache key strategy
- Cache not configured properly
- GeoServer cache statistics not being collected (check `WMS_LOG_DIR` configuration)

**Investigation Steps:**

1. Check cache configuration
2. Review cache size and usage
3. Check eviction policies
4. Review cache key strategy
5. Monitor cache statistics

**Resolution:**

1. Increase cache size if needed
2. Adjust eviction policies
3. Fix cache invalidation
4. Optimize cache keys
5. Review cache configuration

**Prevention:**

- Monitor cache performance
- Regular cache tuning
- Effective cache strategy
- Capacity planning

---

## General Troubleshooting

### Service Won't Start

**Symptoms:**

- Service fails to start
- Start command returns error

**Investigation:**

1. Check service logs:
   ```bash
   journalctl -u wms-service -n 100
   ```
2. Check configuration files
3. Verify dependencies are available
4. Check file permissions

**Resolution:**

1. Fix configuration errors
2. Install missing dependencies
3. Fix file permissions
4. Review service logs

---

### High Resource Usage

**Symptoms:**

- High CPU or memory usage
- Service slow or unresponsive

**Investigation:**

1. Check resource usage:
   ```bash
   top -p $(pgrep -f wms)
   ```
2. Identify resource-intensive operations
3. Review service configuration

**Resolution:**

1. Optimize resource-intensive operations
2. Scale resources
3. Adjust service configuration
4. Consider load balancing

---

## Alert Response Checklist

### For CRITICAL Alerts:

- [ ] Acknowledge alert immediately
- [ ] Escalate to on-call engineer
- [ ] Check service status
- [ ] Review recent changes
- [ ] Investigate root cause
- [ ] Implement fix
- [ ] Verify resolution
- [ ] Document incident

### For WARNING Alerts:

- [ ] Acknowledge alert within 1 hour
- [ ] Review metrics and trends
- [ ] Investigate if needed
- [ ] Implement fix if necessary
- [ ] Monitor resolution
- [ ] Document if recurring

---

## Prevention Strategies

### 1. Proactive Monitoring

- Set up dashboards for key metrics
- Regular review of trends
- Capacity planning
- Performance monitoring

### 2. High Availability

- Set up service auto-restart
- Implement load balancing
- Set up failover mechanisms
- Regular failover testing

### 3. Regular Maintenance

- Regular service restarts
- Log rotation
- Configuration reviews
- Dependency updates

### 4. Testing

- Load testing
- Failure scenario testing
- Health check testing
- Performance testing

### 5. Documentation

- Document service dependencies
- Document alert procedures
- Document resolution steps
- Document thresholds

---

## Reference

### Related Documentation

- **[WMS_MONITORING_GUIDE.md](./WMS_Monitoring_Guide.md)**: Complete monitoring guide
- **[WMS_METRICS.md](./WMS_Metrics.md)**: Metric definitions
- **[WMS_ALERT_THRESHOLDS.md](./WMS_Alert_Thresholds.md)**: Alert thresholds

### Useful Commands

```bash
# Check service status
systemctl status wms-service

# Test service URL
curl -v http://localhost:8080

# Test health endpoint
curl http://localhost:8080/health

# Check service logs
tail -f /var/log/wms/service.log
journalctl -u wms-service -f

# Check service process
ps aux | grep wms

# Check port
netstat -tlnp | grep 8080

# Check resource usage
top -p $(pgrep -f wms)
free -h
df -h
```

---

**Last Updated**: 2025-12-27  
**Version**: 1.0.0
