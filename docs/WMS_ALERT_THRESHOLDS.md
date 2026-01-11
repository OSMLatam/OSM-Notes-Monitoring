# WMS Alert Thresholds

> **Purpose:** Comprehensive documentation of all alert thresholds for WMS monitoring  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document defines all alert thresholds for the OSM-Notes-WMS component. These thresholds are used to determine when alerts should be triggered based on metric values.

## Configuration

All thresholds are configurable via `config/monitoring.conf`. Default values are defined in `config/monitoring.conf.example`.

## Alert Thresholds by Category

### 1. Service Availability Thresholds

#### `WMS_CHECK_TIMEOUT`
- **Default:** `30`
- **Unit:** Seconds
- **Metric:** `service_response_time_ms`
- **Alert Condition:** Service does not respond within timeout
- **Description:** Maximum time to wait for service response before considering it unavailable
- **Severity:** CRITICAL (when service unavailable)
- **Action:** Check service status, network connectivity, server resources
- **Configuration:** `config/monitoring.conf`

#### Service Unavailable
- **Default:** `0` (service not responding)
- **Unit:** Binary (0 = unavailable, 1 = available)
- **Metric:** `service_availability`
- **Alert Condition:** `service_availability = 0`
- **Description:** Service is not responding to HTTP requests
- **Severity:** CRITICAL
- **Action:** 
  - Check if WMS service is running
  - Check network connectivity
  - Check server resources (CPU, memory, disk)
  - Review service logs for errors
- **Configuration:** Automatic (based on HTTP response)

### 2. Health Check Thresholds

#### Health Check Failed
- **Default:** `0` (health check failed)
- **Unit:** Binary (0 = unhealthy, 1 = healthy)
- **Metric:** `health_status`
- **Alert Condition:** `health_status = 0`
- **Description:** Health check endpoint returned unhealthy status or error
- **Severity:** CRITICAL
- **Action:**
  - Check health endpoint response
  - Review service health status
  - Check dependencies (database, cache, etc.)
  - Review service logs
- **Configuration:** Automatic (based on health endpoint response)

#### `WMS_HEALTH_CHECK_URL`
- **Default:** `http://localhost:8080/health`
- **Unit:** URL string
- **Metric:** N/A (configuration)
- **Alert Condition:** N/A
- **Description:** URL for health check endpoint
- **Severity:** N/A
- **Action:** Configure correct health check URL
- **Configuration:** `config/monitoring.conf`

### 3. Response Time Thresholds

#### `WMS_RESPONSE_TIME_THRESHOLD`
- **Default:** `2000`
- **Unit:** Milliseconds
- **Metric:** `response_time_ms`
- **Alert Condition:** `response_time_ms > threshold`
- **Description:** Maximum acceptable response time for WMS requests
- **Severity:** WARNING
- **Action:**
  - Check server load
  - Review slow queries
  - Check network latency
  - Optimize service performance
- **Configuration:** `config/monitoring.conf`

#### `WMS_TILE_GENERATION_THRESHOLD`
- **Default:** `5000`
- **Unit:** Milliseconds
- **Metric:** `tile_generation_time_ms`
- **Alert Condition:** `tile_generation_time_ms > threshold`
- **Description:** Maximum acceptable time for tile generation
- **Severity:** WARNING
- **Action:**
  - Check tile generation performance
  - Review data source performance
  - Check cache effectiveness
  - Optimize tile rendering
- **Configuration:** `config/monitoring.conf`

### 4. Error Rate Thresholds

#### `WMS_ERROR_RATE_THRESHOLD`
- **Default:** `5`
- **Unit:** Percent
- **Metric:** `error_rate_percent`
- **Alert Condition:** `error_rate_percent > threshold`
- **Description:** Maximum acceptable error rate percentage
- **Severity:** WARNING
- **Action:**
  - Review error logs
  - Identify error patterns
  - Check service stability
  - Review recent deployments
- **Configuration:** `config/monitoring.conf`

### 5. Cache Performance Thresholds

#### `WMS_CACHE_HIT_RATE_THRESHOLD`
- **Default:** `80`
- **Unit:** Percent
- **Metric:** `cache_hit_rate_percent`
- **Alert Condition:** `cache_hit_rate_percent < threshold AND total_requests > 0`
- **Description:** Minimum acceptable cache hit rate percentage. **Note:** Alerts are only generated when there is actual cache activity (hits + misses > 0). No alert is generated when there's no activity, as this is normal during periods of low or no traffic.
- **Severity:** WARNING
- **Action:**
  - Check cache configuration
  - Review cache size and eviction policies
  - Check for cache invalidation issues
  - Optimize cache key strategy
- **Configuration:** `config/monitoring.conf`

## Threshold Configuration Example

```bash
# WMS Monitoring Configuration
WMS_ENABLED=true
WMS_BASE_URL="http://localhost:8080"
WMS_HEALTH_CHECK_URL="http://localhost:8080/health"
WMS_CHECK_TIMEOUT=30
WMS_RESPONSE_TIME_THRESHOLD=2000
WMS_ERROR_RATE_THRESHOLD=5
WMS_TILE_GENERATION_THRESHOLD=5000
WMS_CACHE_HIT_RATE_THRESHOLD=80
WMS_LOG_DIR="/var/log/wms"
```

## Alert Severity Levels

### CRITICAL
- **Response Time:** Immediate (within 15 minutes)
- **Impact:** Service is non-functional
- **Examples:**
  - Service unavailable
  - Health check failed
  - Service not responding

### WARNING
- **Response Time:** Within 1 hour
- **Impact:** Performance degradation or potential issues
- **Examples:**
  - Response time exceeded
  - Error rate exceeded
  - Cache hit rate low
  - Tile generation slow

## Threshold Tuning Guidelines

### 1. Baseline Establishment
- Monitor metrics for 1-2 weeks to establish baseline
- Document normal operating ranges
- Identify peak usage patterns

### 2. Threshold Adjustment
- Start with default thresholds
- Adjust based on observed patterns
- Consider business requirements
- Document threshold changes and reasons

### 3. Regular Review
- Review thresholds quarterly
- Adjust based on system changes
- Consider seasonal patterns
- Update documentation

## Threshold Recommendations by Environment

### Development/Testing
- **Response Time:** 5000ms (more lenient)
- **Error Rate:** 10% (more lenient)
- **Cache Hit Rate:** 70% (more lenient)

### Staging
- **Response Time:** 3000ms
- **Error Rate:** 7%
- **Cache Hit Rate:** 75%

### Production
- **Response Time:** 2000ms (default)
- **Error Rate:** 5% (default)
- **Cache Hit Rate:** 80% (default)

## Related Documentation

- **[WMS_METRICS.md](./WMS_METRICS.md)**: Complete metric definitions
- **[WMS_MONITORING_GUIDE.md](./WMS_MONITORING_GUIDE.md)**: Monitoring setup guide
- **[ETL_MONITORING_RUNBOOK.md](./ETL_MONITORING_RUNBOOK.md)**: Alert response procedures (reference)
- **[CONFIGURATION_REFERENCE.md](./CONFIGURATION_REFERENCE.md)**: Configuration options

---

**Last Updated**: 2025-12-27  
**Version**: 1.0.0

