---
title: "WMS Metrics Definition"
description: "This document defines all metrics collected for the OSM-Notes-WMS component. These metrics are"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "performance"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# WMS Metrics Definition

> **Purpose:** Comprehensive definition of all WMS-specific metrics  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This document defines all metrics collected for the OSM-Notes-WMS component. These metrics are
stored in the `metrics` table of the monitoring database and are used for:

- Health monitoring
- Performance analysis
- Alerting
- Capacity planning
- Troubleshooting

## Metric Naming Convention

All WMS metrics follow this naming pattern:

- **Format:** `{category}_{metric_name}_{unit_suffix}`
- **Category:** Groups related metrics (e.g., `service`, `health`, `performance`, `cache`, `error`)
- **Unit Suffix:** Indicates unit type (`_count`, `_percent`, `_ms`, `_seconds`)

## Metric Categories

### 1. Service Availability Metrics

Metrics related to WMS service availability and basic connectivity.

#### `service_availability`

- **Description:** Service availability status (1 = available, 0 = unavailable)
- **Type:** Gauge
- **Unit:** `count` (binary: 0 or 1)
- **Collection:** Collected during `check_wms_service_availability()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-1 (1 = available, 0 = unavailable)
- **Alert Threshold:** 0 (service unavailable)
- **Metadata:** `component=wms,url={service_url}`

#### `service_response_time_ms`

- **Description:** Response time for basic service availability check
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_wms_service_availability()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 50-5000ms (varies by network and server load)
- **Alert Threshold:** > 2000ms (configurable via `WMS_RESPONSE_TIME_THRESHOLD`)
- **Metadata:** `component=wms,url={service_url}`

### 2. Health Check Metrics

Metrics related to HTTP health endpoint checks.

#### `health_status`

- **Description:** Health endpoint status (1 = healthy, 0 = unhealthy)
- **Type:** Gauge
- **Unit:** `count` (binary: 0 or 1)
- **Collection:** Collected during `check_http_health()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-1 (1 = healthy, 0 = unhealthy)
- **Alert Threshold:** 0 (health check failed)
- **Metadata:** `component=wms,url={health_url}`

#### `health_check_response_time_ms`

- **Description:** Response time for health check endpoint
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_http_health()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 50-2000ms
- **Alert Threshold:** > 2000ms
- **Metadata:** `component=wms,url={health_url}`

### 3. Performance Metrics

Metrics related to WMS performance and response times.

#### `response_time_ms`

- **Description:** General response time for WMS requests
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_response_time()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 100-2000ms (varies by request type and load)
- **Alert Threshold:** > 2000ms (configurable via `WMS_RESPONSE_TIME_THRESHOLD`)
- **Metadata:** `component=wms,url={test_url}`

#### `tile_generation_time_ms`

- **Description:** Time taken to generate a map tile
- **Type:** Gauge
- **Unit:** `milliseconds`
- **Collection:** Collected during `check_tile_generation_performance()`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 200-5000ms (varies by zoom level and data complexity)
- **Alert Threshold:** > 5000ms (configurable via `WMS_TILE_GENERATION_THRESHOLD`)
- **Metadata:** `component=wms,zoom={zoom_level}`

### 4. Error Metrics

Metrics related to errors and failures.

#### `error_count`

- **Description:** Number of errors detected in a time period
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_error_rate()` from logs or metrics
- **Frequency:** Every monitoring cycle (aggregated over last hour)
- **Expected Range:** 0-100 (varies by traffic volume)
- **Alert Threshold:** Depends on error rate percentage
- **Metadata:** `component=wms,period=1h`

#### `request_count`

- **Description:** Total number of requests in a time period
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_error_rate()` from logs or metrics
- **Frequency:** Every monitoring cycle (aggregated over last hour)
- **Expected Range:** Varies significantly by traffic volume
- **Alert Threshold:** N/A (used for calculating error rate)
- **Metadata:** `component=wms,period=1h`

#### `error_rate_percent`

- **Description:** Percentage of requests that resulted in errors
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Calculated during `check_error_rate()` as `(error_count / request_count) * 100`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 0-5% (normal), > 5% (concerning)
- **Alert Threshold:** > 5% (configurable via `WMS_ERROR_RATE_THRESHOLD`)
- **Metadata:** `component=wms,period=1h`

### 5. Cache Performance Metrics

Metrics related to cache hit rates and performance.

#### `cache_hits`

- **Description:** Number of cache hits in a time period
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_cache_hit_rate()` from logs or metrics
- **Frequency:** Every monitoring cycle (aggregated over last hour)
- **Expected Range:** Varies by traffic volume
- **Alert Threshold:** N/A (used for calculating hit rate)
- **Metadata:** `component=wms,period=1h`

#### `cache_misses`

- **Description:** Number of cache misses in a time period
- **Type:** Counter
- **Unit:** `count`
- **Collection:** Collected during `check_cache_hit_rate()` from logs or metrics
- **Frequency:** Every monitoring cycle (aggregated over last hour)
- **Expected Range:** Varies by traffic volume
- **Alert Threshold:** N/A (used for calculating hit rate)
- **Metadata:** `component=wms,period=1h`

#### `cache_hit_rate_percent`

- **Description:** Percentage of requests served from cache
- **Type:** Gauge
- **Unit:** `percent`
- **Collection:** Calculated during `check_cache_hit_rate()` as
  `(cache_hits / (cache_hits + cache_misses)) * 100`
- **Frequency:** Every monitoring cycle
- **Expected Range:** 70-95% (good), < 70% (concerning)
- **Alert Threshold:** < 80% (configurable via `WMS_CACHE_HIT_RATE_THRESHOLD`)
- **Metadata:** `component=wms,period=1h`

## Metric Collection Methods

### 1. HTTP Checks

- **Service Availability:** Basic HTTP GET request to service URL
- **Health Check:** HTTP GET request to health endpoint
- **Response Time:** Measure time for HTTP request/response cycle

### 2. Log Analysis

- **Error Rate:** Parse WMS logs for error patterns
- **Cache Statistics:** Parse logs for cache hit/miss patterns
- **Request Count:** Count HTTP requests in logs

### 3. Database Queries

- **Historical Metrics:** Query metrics table for trends
- **Aggregated Statistics:** Calculate averages, percentiles, etc.

## Metric Retention

- **Default Retention:** 90 days (configurable via `METRICS_RETENTION_DAYS`)
- **Aggregation:** Daily aggregates can be created for long-term storage
- **Cleanup:** Old metrics are automatically cleaned up based on retention policy

## Querying Metrics

### Get Latest Service Availability

```sql
SELECT metric_value, timestamp
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'service_availability'
ORDER BY timestamp DESC
LIMIT 1;
```

### Get Average Response Time (Last Hour)

```sql
SELECT AVG(metric_value::numeric) as avg_response_time_ms
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'response_time_ms'
  AND timestamp > NOW() - INTERVAL '1 hour';
```

### Get Error Rate Trend (Last 24 Hours)

```sql
SELECT
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(metric_value::numeric) as error_rate_percent
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'error_rate_percent'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;
```

### Get Cache Performance (Last Hour)

```sql
SELECT
    AVG(CASE WHEN metric_name = 'cache_hit_rate_percent' THEN metric_value::numeric END) as hit_rate,
    SUM(CASE WHEN metric_name = 'cache_hits' THEN metric_value::numeric ELSE 0 END) as hits,
    SUM(CASE WHEN metric_name = 'cache_misses' THEN metric_value::numeric ELSE 0 END) as misses
FROM metrics
WHERE component = 'wms'
  AND metric_name IN ('cache_hit_rate_percent', 'cache_hits', 'cache_misses')
  AND timestamp > NOW() - INTERVAL '1 hour';
```

## Alert Conditions

Metrics trigger alerts under the following conditions:

1. **Service Unavailable:** `service_availability = 0` → CRITICAL alert
2. **Health Check Failed:** `health_status = 0` → CRITICAL alert
3. **Response Time Exceeded:** `response_time_ms > WMS_RESPONSE_TIME_THRESHOLD` → WARNING alert
4. **Error Rate Exceeded:** `error_rate_percent > WMS_ERROR_RATE_THRESHOLD` → WARNING alert
5. **Tile Generation Slow:** `tile_generation_time_ms > WMS_TILE_GENERATION_THRESHOLD` → WARNING
   alert
6. **Cache Hit Rate Low:** `cache_hit_rate_percent < WMS_CACHE_HIT_RATE_THRESHOLD` → WARNING alert

## Related Documentation

- **[WMS Alert Thresholds](./WMS_Alert_Thresholds.md)**: Complete alert threshold definitions
- **[WMS Monitoring Guide](./WMS_Monitoring_Guide.md)**: Monitoring setup and usage guide
- **[CONFIGURATION_REFERENCE.md](./Configuration_Reference.md)**: Configuration options

---

**Last Updated**: 2025-12-27  
**Version**: 1.0.0
