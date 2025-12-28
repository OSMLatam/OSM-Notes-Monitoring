# WMS Monitoring Guide

> **Purpose:** Comprehensive guide for monitoring the OSM-Notes-WMS component  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Running Monitoring](#running-monitoring)
6. [Understanding Metrics](#understanding-metrics)
7. [Alerting](#alerting)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Reference Documentation](#reference-documentation)

---

## Overview

The WMS Monitoring system provides comprehensive monitoring for the OSM-Notes-WMS component, tracking:

- **Service Availability**: Verifies that WMS service is responding to HTTP requests
- **Health Checks**: Monitors HTTP health endpoint status
- **Response Times**: Tracks response times for WMS requests
- **Error Rates**: Monitors error rates from logs or metrics
- **Tile Generation Performance**: Tracks tile generation times
- **Cache Performance**: Monitors cache hit rates

### Key Features

- **Automated Monitoring**: Run checks on a schedule (e.g., via cron)
- **Metrics Collection**: All metrics are stored in PostgreSQL for historical analysis
- **Alerting**: Configurable alerts for critical issues (WARNING, CRITICAL)
- **HTTP Health Checks**: Direct HTTP requests to WMS service
- **Low Overhead**: Designed to minimize impact on the monitored service
- **Log Analysis**: Optional log parsing for error and cache statistics

---

## Prerequisites

Before setting up WMS monitoring, ensure you have:

1. **PostgreSQL Database**: A PostgreSQL database for storing metrics and alerts
   - Version 12 or higher recommended
   - Database created and accessible
   - User with appropriate permissions

2. **WMS Service**: The WMS service must be accessible
   - Service running and accessible via HTTP
   - Health endpoint available (optional but recommended)
   - Network connectivity to WMS service

3. **Bash Environment**: Bash 4.0 or higher

4. **curl**: Command-line tool for HTTP requests
   ```bash
   # Install curl if not available
   sudo apt-get install curl  # Debian/Ubuntu
   sudo yum install curl       # RHEL/CentOS
   ```

5. **Network Access**: Ability to connect to WMS service URL

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

### 2. Configure WMS Service

```bash
# Enable WMS monitoring
WMS_ENABLED=true

# WMS service URL
WMS_BASE_URL=http://localhost:8080

# Health check URL (optional)
WMS_HEALTH_CHECK_URL=http://localhost:8080/health
```

### 3. Run Monitoring

```bash
# Run WMS monitoring manually
./bin/monitor/monitorWMS.sh

# Or run all monitoring
./bin/monitor/monitorAll.sh
```

### 4. Verify Metrics

```bash
# Check metrics in database
psql -d osm_notes_monitoring -c "SELECT * FROM metrics WHERE component = 'wms' ORDER BY timestamp DESC LIMIT 10;"
```

---

## Configuration

### Required Configuration

#### Database Configuration

```bash
# Monitoring database (stores metrics and alerts)
DBNAME=osm_notes_monitoring
DBHOST=localhost
DBPORT=5432
DBUSER=monitoring_user
```

#### WMS Service Configuration

```bash
# Enable WMS monitoring
WMS_ENABLED=true

# WMS service base URL
WMS_BASE_URL=http://localhost:8080

# Health check endpoint URL (optional)
WMS_HEALTH_CHECK_URL=http://localhost:8080/health
```

### Optional Configuration

#### Monitoring Thresholds

```bash
# Check timeout (seconds)
WMS_CHECK_TIMEOUT=30

# Response time threshold (milliseconds)
WMS_RESPONSE_TIME_THRESHOLD=2000

# Error rate threshold (percentage)
WMS_ERROR_RATE_THRESHOLD=5

# Tile generation threshold (milliseconds)
WMS_TILE_GENERATION_THRESHOLD=5000

# Cache hit rate threshold (percentage)
WMS_CACHE_HIT_RATE_THRESHOLD=80
```

#### Log Directory (Optional)

```bash
# WMS log directory for error and cache analysis
WMS_LOG_DIR=/var/log/wms
```

### Configuration File Example

See `config/monitoring.conf.example` for a complete configuration example.

---

## Running Monitoring

### Manual Execution

```bash
# Run WMS monitoring
./bin/monitor/monitorWMS.sh

# Run with debug logging
LOG_LEVEL=DEBUG ./bin/monitor/monitorWMS.sh

# Run specific check
./bin/monitor/monitorWMS.sh --check availability
```

### Scheduled Execution (Cron)

Add to crontab for regular monitoring:

```bash
# Run every 5 minutes
*/5 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorWMS.sh >> /var/log/monitoring/wms.log 2>&1

# Run every 15 minutes
*/15 * * * * /path/to/OSM-Notes-Monitoring/bin/monitor/monitorWMS.sh >> /var/log/monitoring/wms.log 2>&1
```

### Systemd Timer (Alternative)

Create `/etc/systemd/system/wms-monitoring.timer`:

```ini
[Unit]
Description=WMS Monitoring Timer
Requires=wms-monitoring.service

[Timer]
OnCalendar=*-*-* *:00,05,10,15,20,25,30,35,40,45,50,55:00
Persistent=true

[Install]
WantedBy=timers.target
```

Create `/etc/systemd/system/wms-monitoring.service`:

```ini
[Unit]
Description=WMS Monitoring Service

[Service]
Type=oneshot
ExecStart=/path/to/OSM-Notes-Monitoring/bin/monitor/monitorWMS.sh
User=monitoring
```

Enable and start:

```bash
sudo systemctl enable wms-monitoring.timer
sudo systemctl start wms-monitoring.timer
```

---

## Understanding Metrics

### Metric Categories

#### 1. Service Availability Metrics

- **`service_availability`**: Service availability status (1 = available, 0 = unavailable)
- **`service_response_time_ms`**: Response time for availability check

#### 2. Health Check Metrics

- **`health_status`**: Health endpoint status (1 = healthy, 0 = unhealthy)
- **`health_check_response_time_ms`**: Response time for health check

#### 3. Performance Metrics

- **`response_time_ms`**: General response time for WMS requests
- **`tile_generation_time_ms`**: Time taken to generate a map tile

#### 4. Error Metrics

- **`error_count`**: Number of errors detected
- **`request_count`**: Total number of requests
- **`error_rate_percent`**: Percentage of requests that resulted in errors

#### 5. Cache Performance Metrics

- **`cache_hits`**: Number of cache hits
- **`cache_misses`**: Number of cache misses
- **`cache_hit_rate_percent`**: Percentage of requests served from cache

### Querying Metrics

```bash
# View all WMS metrics
psql -d osm_notes_monitoring -c "
  SELECT metric_name, metric_value, timestamp 
  FROM metrics 
  WHERE component = 'wms' 
  ORDER BY timestamp DESC 
  LIMIT 20;
"

# View service availability trend
psql -d osm_notes_monitoring -c "
  SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(metric_value::numeric) as availability_percent
  FROM metrics 
  WHERE component = 'wms' 
    AND metric_name = 'service_availability'
  GROUP BY hour
  ORDER BY hour DESC
  LIMIT 24;
"

# View response time statistics
psql -d osm_notes_monitoring -c "
  SELECT 
    AVG(metric_value::numeric) as avg_response_time_ms,
    MIN(metric_value::numeric) as min_response_time_ms,
    MAX(metric_value::numeric) as max_response_time_ms
  FROM metrics 
  WHERE component = 'wms' 
    AND metric_name = 'response_time_ms'
    AND timestamp > NOW() - INTERVAL '24 hours';
"
```

For complete metric definitions, see **[WMS_METRICS.md](./WMS_METRICS.md)**.

---

## Alerting

### Alert Levels

- **CRITICAL**: Immediate action required (e.g., service unavailable, health check failed)
- **WARNING**: Warning condition detected (e.g., response time exceeded, error rate high, cache hit rate low)

### Alert Types

#### Service Availability Alerts

- **`service_unavailable`**: Service is not responding (CRITICAL)

#### Health Check Alerts

- **`health_check_failed`**: Health check endpoint failed (CRITICAL)

#### Performance Alerts

- **`response_time_exceeded`**: Response time exceeds threshold (WARNING)
- **`tile_generation_slow`**: Tile generation time exceeds threshold (WARNING)
- **`tile_generation_failed`**: Tile generation failed (WARNING)

#### Error Alerts

- **`error_rate_exceeded`**: Error rate exceeds threshold (WARNING)

#### Cache Alerts

- **`cache_hit_rate_low`**: Cache hit rate below threshold (WARNING)

### Viewing Alerts

```bash
# View active alerts
psql -d osm_notes_monitoring -c "
  SELECT component, alert_level, alert_type, message, created_at 
  FROM alerts 
  WHERE component = 'WMS' 
    AND status = 'active'
  ORDER BY created_at DESC;
"

# View alerts by level
psql -d osm_notes_monitoring -c "
  SELECT alert_level, COUNT(*) 
  FROM alerts 
  WHERE component = 'WMS' 
    AND created_at > NOW() - INTERVAL '24 hours'
  GROUP BY alert_level;
"
```

For complete alert threshold definitions, see **[WMS_ALERT_THRESHOLDS.md](./WMS_ALERT_THRESHOLDS.md)**.

---

## Troubleshooting

### Common Issues

#### Service Unavailable

**Symptoms**: Alerts about service being unavailable

**Solutions**:
1. Check if WMS service is running:
   ```bash
   systemctl status wms-service
   # Or check process
   ps aux | grep wms
   ```
2. Test service URL manually:
   ```bash
   curl -v http://localhost:8080
   ```
3. Check network connectivity:
   ```bash
   ping localhost
   telnet localhost 8080
   ```
4. Check firewall rules
5. Review WMS service logs

#### Health Check Failures

**Symptoms**: Health check alerts

**Solutions**:
1. Test health endpoint manually:
   ```bash
   curl http://localhost:8080/health
   ```
2. Verify health endpoint URL is correct
3. Check WMS service health status
4. Review service dependencies (database, cache, etc.)
5. Check service logs for errors

#### High Response Times

**Symptoms**: Response time alerts

**Solutions**:
1. Check server load:
   ```bash
   top
   htop
   ```
2. Check network latency:
   ```bash
   ping localhost
   traceroute localhost
   ```
3. Review WMS service performance
4. Check for slow queries or operations
5. Scale resources if needed

#### High Error Rates

**Symptoms**: Error rate alerts

**Solutions**:
1. Review WMS error logs:
   ```bash
   tail -f /var/log/wms/error.log
   grep -i error /var/log/wms/*.log
   ```
2. Identify error patterns
3. Check service stability
4. Review recent deployments
5. Check dependencies

#### Low Cache Hit Rate

**Symptoms**: Cache hit rate alerts

**Solutions**:
1. Check cache configuration
2. Review cache size and eviction policies
3. Check for cache invalidation issues
4. Optimize cache key strategy
5. Monitor cache memory usage

---

## Best Practices

### 1. Monitoring Frequency

- **Production Systems**: Run every 5-15 minutes
- **Development/Testing**: Run hourly or on-demand
- **Critical Systems**: Consider more frequent monitoring (every 1-5 minutes)

### 2. Threshold Tuning

- Start with default thresholds
- Monitor for 1-2 weeks to understand normal behavior
- Adjust thresholds based on your system's patterns
- Document threshold changes and reasons
- Review thresholds quarterly

### 3. Alert Management

- Use alert deduplication to avoid alert fatigue
- Set up alert escalation for critical issues
- Review and acknowledge alerts promptly
- Document alert responses for future reference
- Create runbooks for common alert scenarios

### 4. Health Endpoint

- Implement a comprehensive health endpoint
- Include dependency checks (database, cache, etc.)
- Return appropriate HTTP status codes
- Provide detailed health information in response body

### 5. Log Management

- Configure WMS log directory if available
- Rotate logs regularly
- Archive old logs for historical analysis
- Monitor log file sizes
- Use log aggregation tools if available

### 6. Performance Monitoring

- Monitor response time trends
- Track tile generation performance
- Monitor cache effectiveness
- Review performance regularly
- Optimize slow operations

### 7. Service Availability

- Monitor uptime percentage
- Track service outages
- Document outage causes and resolutions
- Plan for high availability

### 8. Error Analysis

- Regularly review error patterns
- Categorize errors by type
- Track error trends over time
- Address recurring errors proactively

---

## Reference Documentation

### Core Documentation

- **[WMS_METRICS.md](./WMS_METRICS.md)**: Complete metric definitions
- **[WMS_ALERT_THRESHOLDS.md](./WMS_ALERT_THRESHOLDS.md)**: All alert thresholds
- **[CONFIGURATION_REFERENCE.md](./CONFIGURATION_REFERENCE.md)**: Complete configuration reference

### Related Documentation

- **[Monitoring_SETUP_Guide.md](./Monitoring_SETUP_Guide.md)**: Initial setup guide
- **[DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)**: Database schema documentation
- **[Monitoring_Architecture_Proposal.md](./Monitoring_Architecture_Proposal.md)**: System architecture overview

### Scripts

- **`bin/monitor/monitorWMS.sh`**: Main WMS monitoring script
- **`bin/lib/monitoringFunctions.sh`**: Core monitoring functions
- **`bin/lib/metricsFunctions.sh`**: Metrics collection functions
- **`bin/lib/alertFunctions.sh`**: Alerting functions

### SQL Queries

- **`sql/wms/service_status.sql`**: Service status queries
- **`sql/wms/performance.sql`**: Performance analysis queries
- **`sql/wms/error_analysis.sql`**: Error analysis queries

### Testing

- **`tests/unit/monitor/test_monitorWMS.sh`**: Unit tests
- **`tests/integration/test_monitorWMS_integration.sh`**: Integration tests
- **`tests/integration/test_wms_alert_delivery.sh`**: Alert delivery tests
- **`tests/performance/test_wms_monitoring_overhead.sh`**: Performance tests

---

## Getting Help

If you encounter issues or have questions:

1. **Check Documentation**: Review this guide and related documentation
2. **Review Logs**: Check monitoring logs for error messages
3. **Run Tests**: Execute test suites to verify functionality
4. **Check Issues**: Review GitHub issues for known problems
5. **Create Issue**: Open a new issue with detailed information

---

**Last Updated**: 2025-12-27  
**Version**: 1.0.0

