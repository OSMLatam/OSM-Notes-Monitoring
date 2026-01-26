---
title: "Infrastructure Monitoring Guide"
description: "Infrastructure Monitoring"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "monitoring"
  - "guide"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Infrastructure Monitoring Guide

**Version:** 1.1.0  
**Last Updated:** 2026-01-09  
**Component:** Infrastructure Monitoring

## Overview

The Infrastructure Monitoring system provides comprehensive monitoring of server resources, network
connectivity, database health, and service dependencies. This guide covers setup, configuration,
usage, and troubleshooting for infrastructure monitoring.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Configuration](#configuration)
4. [Running Monitoring](#running-monitoring)
5. [Understanding Metrics](#understanding-metrics)
6. [Alerting](#alerting)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)
9. [Reference](#reference)

---

## Prerequisites

### System Requirements

- Linux/Unix system with bash 4.0+
- PostgreSQL database (for metrics and alerts storage)
- System commands: `top`, `free`, `df`, `ping`, `nc` (netcat), `systemctl` or `service`
- Git (optional, for repository sync checks)

### Database Setup

Ensure the monitoring database is set up with the required tables:

```bash
# Run database migrations
psql -U postgres -d osm_notes_monitoring -f sql/schema.sql
```

### Permissions

The monitoring script requires:

- Read access to system files (`/proc`, `/sys`)
- Execute permissions for system commands
- Database connection permissions
- Write access to log directory

---

## Quick Start

### 1. Configure Monitoring

Edit `config/monitoring.conf`:

```bash
# Infrastructure Monitoring
INFRASTRUCTURE_ENABLED=true
INFRASTRUCTURE_CPU_THRESHOLD=80
INFRASTRUCTURE_MEMORY_THRESHOLD=85
INFRASTRUCTURE_DISK_THRESHOLD=90
INFRASTRUCTURE_CHECK_TIMEOUT=30
INFRASTRUCTURE_NETWORK_HOSTS=localhost,127.0.0.1
INFRASTRUCTURE_SERVICE_DEPENDENCIES=postgresql,sshd
```

### 2. Run Monitoring

```bash
# Run all infrastructure checks
./bin/monitor/monitorInfrastructure.sh

# Run specific check
./bin/monitor/monitorInfrastructure.sh --check server_resources

# Verbose output
./bin/monitor/monitorInfrastructure.sh -v
```

### 3. View Results

```bash
# Check metrics in database
psql -U postgres -d osm_notes_monitoring -c "SELECT * FROM metrics WHERE component = 'INFRASTRUCTURE' ORDER BY timestamp DESC LIMIT 10;"

# Check alerts
psql -U postgres -d osm_notes_monitoring -c "SELECT * FROM alerts WHERE component = 'INFRASTRUCTURE' ORDER BY created_at DESC LIMIT 10;"
```

---

## Configuration

### Configuration Variables

| Variable                                   | Default      | Description                                                                |
| ------------------------------------------ | ------------ | -------------------------------------------------------------------------- |
| `INFRASTRUCTURE_ENABLED`                   | `true`       | Enable/disable infrastructure monitoring                                   |
| `INFRASTRUCTURE_CPU_THRESHOLD`             | `80`         | CPU usage warning threshold (%)                                            |
| `INFRASTRUCTURE_MEMORY_THRESHOLD`          | `85`         | Memory usage warning threshold (%)                                         |
| `INFRASTRUCTURE_DISK_THRESHOLD`            | `90`         | Disk usage warning threshold (%)                                           |
| `INFRASTRUCTURE_SWAP_THRESHOLD`            | `50`         | Swap usage warning threshold (%)                                           |
| `INFRASTRUCTURE_LOAD_THRESHOLD_MULTIPLIER` | `2`          | Load average threshold multiplier (alert if load > multiplier x CPU count) |
| `INFRASTRUCTURE_CHECK_TIMEOUT`             | `30`         | Timeout for network checks (seconds)                                       |
| `INFRASTRUCTURE_NETWORK_HOSTS`             | `localhost`  | Comma-separated list of hosts to check                                     |
| `INFRASTRUCTURE_SERVICE_DEPENDENCIES`      | `postgresql` | Comma-separated list of services to check                                  |

### Alert Thresholds

| Metric               | Warning      | Critical | Description                    |
| -------------------- | ------------ | -------- | ------------------------------ |
| CPU Usage            | 80%          | 95%      | CPU utilization percentage     |
| Memory Usage         | 85%          | 95%      | Memory utilization percentage  |
| Disk Usage           | 90%          | 95%      | Disk space usage percentage    |
| Swap Usage           | 50%          | N/A      | Swap space usage percentage    |
| Load Average         | 2x CPU count | N/A      | System load average (1 minute) |
| Network Connectivity | Any failure  | N/A      | Host reachability              |
| Database Connections | 80% of max   | N/A      | Active connection usage        |
| Service Dependencies | Any down     | N/A      | Service availability           |

---

## Running Monitoring

### Manual Execution

```bash
# Run all checks
./bin/monitor/monitorInfrastructure.sh

# Run specific check
./bin/monitor/monitorInfrastructure.sh --check server_resources
./bin/monitor/monitorInfrastructure.sh --check network_connectivity
./bin/monitor/monitorInfrastructure.sh --check database_health
./bin/monitor/monitorInfrastructure.sh --check service_dependencies

# Verbose mode
./bin/monitor/monitorInfrastructure.sh -v

# Quiet mode (errors only)
./bin/monitor/monitorInfrastructure.sh -q

# Custom config file
./bin/monitor/monitorInfrastructure.sh -c /path/to/config.conf
```

### Automated Execution

#### Cron Job

Add to crontab for regular monitoring:

```bash
# Run every 5 minutes
*/5 * * * * /path/to/bin/monitor/monitorInfrastructure.sh >> /var/log/infrastructure_monitoring.log 2>&1
```

#### Systemd Timer

Create `/etc/systemd/system/infrastructure-monitoring.service`:

```ini
[Unit]
Description=Infrastructure Monitoring
After=network.target postgresql.service

[Service]
Type=oneshot
ExecStart=/path/to/bin/monitor/monitorInfrastructure.sh
User=monitoring
Group=monitoring

[Install]
WantedBy=multi-user.target
```

Create `/etc/systemd/system/infrastructure-monitoring.timer`:

```ini
[Unit]
Description=Run Infrastructure Monitoring every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl enable infrastructure-monitoring.timer
sudo systemctl start infrastructure-monitoring.timer
```

---

## Understanding Metrics

### Server Resources Metrics

#### CPU Usage (`cpu_usage_percent`)

- **Type:** Gauge
- **Unit:** Percentage
- **Range:** 0-100
- **Description:** Current CPU utilization percentage
- **Collection:** `top` or `vmstat` command

#### Memory Usage (`memory_usage_percent`)

- **Type:** Gauge
- **Unit:** Percentage
- **Range:** 0-100
- **Description:** Current memory utilization percentage
- **Collection:** `free` command

#### Memory Total (`memory_total_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Total system memory
- **Collection:** `free` command

#### Memory Available (`memory_available_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Available system memory
- **Collection:** `free` command

#### Disk Usage (`disk_usage_percent`)

- **Type:** Gauge
- **Unit:** Percentage
- **Range:** 0-100
- **Description:** Disk space usage percentage for root filesystem
- **Collection:** `df` command

#### Disk Available (`disk_available_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Available disk space
- **Collection:** `df` command

#### Disk Total (`disk_total_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Total disk space
- **Collection:** `df` command

### Advanced System Metrics

#### Load Average - 1 minute (`system_load_average_1min`)

- **Type:** Gauge
- **Unit:** Load average
- **Description:** System load average for the last 1 minute
- **Collection:** `/proc/loadavg`
- **Alert Threshold:** > 2x CPU count (configurable via `INFRASTRUCTURE_LOAD_THRESHOLD_MULTIPLIER`)

#### Load Average - 5 minutes (`system_load_average_5min`)

- **Type:** Gauge
- **Unit:** Load average
- **Description:** System load average for the last 5 minutes
- **Collection:** `/proc/loadavg`

#### Load Average - 15 minutes (`system_load_average_15min`)

- **Type:** Gauge
- **Unit:** Load average
- **Description:** System load average for the last 15 minutes
- **Collection:** `/proc/loadavg`

#### PostgreSQL CPU Usage (`system_cpu_postgres_percent`)

- **Type:** Gauge
- **Unit:** Percentage
- **Description:** CPU usage by PostgreSQL processes (sum of all postgres processes)
- **Collection:** `ps` command
- **Range:** 0-100

#### PostgreSQL Memory Usage (`system_memory_postgres_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Memory usage by PostgreSQL processes (RSS, sum of all postgres processes)
- **Collection:** `ps` command

#### PostgreSQL Shared Memory (`system_memory_postgres_shared_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Shared memory used by PostgreSQL processes
- **Collection:** `/proc/[pid]/statm`

#### Swap Total (`system_swap_total_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Total swap space available
- **Collection:** `free` command

#### Swap Used (`system_swap_used_bytes`)

- **Type:** Gauge
- **Unit:** Bytes
- **Description:** Swap space currently in use
- **Collection:** `free` command

#### Swap Usage (`system_swap_usage_percent`)

- **Type:** Gauge
- **Unit:** Percentage
- **Description:** Swap usage percentage
- **Collection:** Calculated from `free` command
- **Alert Threshold:** > 50% (configurable via `INFRASTRUCTURE_SWAP_THRESHOLD`)

#### Disk Reads (`system_disk_reads_bytes`)

- **Type:** Counter
- **Unit:** Bytes
- **Description:** Total bytes read from disk (cumulative)
- **Collection:** `/proc/diskstats`

#### Disk Writes (`system_disk_writes_bytes`)

- **Type:** Counter
- **Unit:** Bytes
- **Description:** Total bytes written to disk (cumulative)
- **Collection:** `/proc/diskstats`

#### Network RX (`system_network_rx_bytes`)

- **Type:** Counter
- **Unit:** Bytes
- **Description:** Total bytes received over network (cumulative, all interfaces except loopback)
- **Collection:** `/proc/net/dev`

#### Network TX (`system_network_tx_bytes`)

- **Type:** Counter
- **Unit:** Bytes
- **Description:** Total bytes transmitted over network (cumulative, all interfaces except loopback)
- **Collection:** `/proc/net/dev`

#### Network Traffic (`system_network_traffic_bytes`)

- **Type:** Counter
- **Unit:** Bytes
- **Description:** Total network traffic (RX + TX)
- **Collection:** Calculated from `/proc/net/dev`

#### CPU Count (`system_cpu_count`)

- **Type:** Gauge
- **Unit:** Count
- **Description:** Number of CPU cores available
- **Collection:** `/proc/cpuinfo` or `nproc` command

### Network Connectivity Metrics

#### Network Connectivity (`network_connectivity`)

- **Type:** Gauge
- **Unit:** Boolean (0/1)
- **Description:** Overall network connectivity status (1 = all hosts reachable, 0 = failures)
- **Collection:** `ping` or `nc` command

#### Connectivity Failures (`network_connectivity_failures`)

- **Type:** Counter
- **Unit:** Count
- **Description:** Number of unreachable hosts
- **Collection:** `ping` or `nc` command

#### Connectivity Checks (`network_connectivity_checks`)

- **Type:** Counter
- **Unit:** Count
- **Description:** Total number of hosts checked
- **Collection:** `ping` or `nc` command

### Database Health Metrics

#### Database Uptime (`database_uptime_seconds`)

- **Type:** Gauge
- **Unit:** Seconds
- **Description:** Database server uptime
- **Collection:** PostgreSQL `pg_postmaster_start_time()`

#### Active Connections (`database_active_connections`)

- **Type:** Gauge
- **Unit:** Count
- **Description:** Current active database connections
- **Collection:** PostgreSQL `pg_stat_activity`

#### Max Connections (`database_max_connections`)

- **Type:** Gauge
- **Unit:** Count
- **Description:** Maximum allowed database connections
- **Collection:** PostgreSQL `max_connections` setting

### Service Dependencies Metrics

#### Service Availability (`service_dependencies_available`)

- **Type:** Gauge
- **Unit:** Boolean (0/1)
- **Description:** Overall service availability (1 = all services running, 0 = failures)
- **Collection:** `systemctl`, `service`, or `pgrep`

#### Service Failures (`service_dependencies_failures`)

- **Type:** Counter
- **Unit:** Count
- **Description:** Number of services not running
- **Collection:** `systemctl`, `service`, or `pgrep`

#### Service Total (`service_dependencies_total`)

- **Type:** Gauge
- **Unit:** Count
- **Description:** Total number of services checked
- **Collection:** Configuration

---

## Alerting

### Alert Types

#### Server Resource Alerts

**Alert Type:** `cpu_usage_high`

- **Severity:** WARNING (80-95%), CRITICAL (>95%)
- **Condition:** CPU usage exceeds threshold
- **Message:** "CPU usage (X%) exceeds threshold (Y%)"

**Alert Type:** `memory_usage_high`

- **Severity:** WARNING (85-95%), CRITICAL (>95%)
- **Condition:** Memory usage exceeds threshold
- **Message:** "Memory usage (X%) exceeds threshold (Y%)"

**Alert Type:** `disk_usage_high`

- **Severity:** WARNING (90-95%), CRITICAL (>95%)
- **Condition:** Disk usage exceeds threshold
- **Message:** "Disk usage (X%) exceeds threshold (Y%)"

#### Network Connectivity Alerts

**Alert Type:** `network_connectivity_failure`

- **Severity:** WARNING
- **Condition:** One or more hosts are unreachable
- **Message:** "Network connectivity check found X failure(s) out of Y hosts checked"

#### Database Health Alerts

**Alert Type:** `database_connection_failed`

- **Severity:** CRITICAL
- **Condition:** Database connection fails
- **Message:** "Database server connection failed"

**Alert Type:** `database_connections_high`

- **Severity:** WARNING
- **Condition:** Connection usage exceeds 80% of max
- **Message:** "Database connection usage (X%, Y/Z) is high"

#### Service Dependency Alerts

**Alert Type:** `service_dependency_failure`

- **Severity:** WARNING
- **Condition:** One or more services are not running
- **Message:** "Service dependencies check found X failure(s) out of Y services checked"

### Querying Alerts

```sql
-- Recent infrastructure alerts
SELECT * FROM alerts
WHERE component = 'INFRASTRUCTURE'
ORDER BY created_at DESC
LIMIT 20;

-- Critical alerts
SELECT * FROM alerts
WHERE component = 'INFRASTRUCTURE'
AND alert_level = 'CRITICAL'
ORDER BY created_at DESC;

-- Alerts by type
SELECT alert_type, COUNT(*) as count, MAX(created_at) as latest
FROM alerts
WHERE component = 'INFRASTRUCTURE'
GROUP BY alert_type
ORDER BY count DESC;
```

---

## Troubleshooting

### Common Issues

#### Issue: CPU/Memory metrics not recorded

**Symptoms:**

- Metrics table shows no CPU or memory data
- Script runs but no metrics appear

**Solutions:**

1. Check if `top` or `free` commands are available:
   ```bash
   which top free
   ```
2. Verify script has execute permissions:
   ```bash
   ls -l bin/monitor/monitorInfrastructure.sh
   ```
3. Check logs for errors:
   ```bash
   tail -f logs/infrastructure.log
   ```

#### Issue: Network connectivity checks fail

**Symptoms:**

- All hosts show as unreachable
- Network alerts triggered incorrectly

**Solutions:**

1. Verify `ping` or `nc` is available:
   ```bash
   which ping nc
   ```
2. Test connectivity manually:
   ```bash
   ping -c 1 localhost
   ```
3. Check firewall rules:
   ```bash
   sudo iptables -L
   ```
4. Verify timeout setting is appropriate:
   ```bash
   grep INFRASTRUCTURE_CHECK_TIMEOUT config/monitoring.conf
   ```

#### Issue: Database health check fails

**Symptoms:**

- Database connection errors
- Database metrics not recorded

**Solutions:**

1. Verify database connection:
   ```bash
   psql -U postgres -d osm_notes_monitoring -c "SELECT 1;"
   ```
2. Check database credentials in config:
   ```bash
   grep -E "DBNAME|DBHOST|DBPORT|DBUSER" config/monitoring.conf
   ```
3. Verify PostgreSQL is running:
   ```bash
   sudo systemctl status postgresql
   ```

#### Issue: Service dependency checks fail

**Symptoms:**

- Services show as down when they're running
- Incorrect service status

**Solutions:**

1. Verify service management tool:
   ```bash
   which systemctl service pgrep
   ```
2. Check service status manually:
   ```bash
   sudo systemctl status postgresql
   # or
   sudo service postgresql status
   ```
3. Verify service names match exactly:
   ```bash
   systemctl list-units --type=service | grep postgresql
   ```

### Debug Mode

Enable verbose logging:

```bash
export LOG_LEVEL=DEBUG
./bin/monitor/monitorInfrastructure.sh -v
```

Check log file:

```bash
tail -f logs/infrastructure.log
```

---

## Best Practices

### 1. Threshold Configuration

- **Start Conservative:** Begin with higher thresholds and adjust based on actual usage patterns
- **Monitor Trends:** Use historical data to set appropriate thresholds
- **Account for Peaks:** Set thresholds above normal peak usage
- **Review Regularly:** Adjust thresholds as infrastructure changes

### 2. Monitoring Frequency

- **Resource Checks:** Every 5 minutes for production systems
- **Network Checks:** Every 1-2 minutes for critical connectivity
- **Database Health:** Every 5 minutes
- **Service Dependencies:** Every 5 minutes

### 3. Alert Management

- **Avoid Alert Fatigue:** Set thresholds appropriately to avoid false positives
- **Use Alert Levels:** Use WARNING for recoverable issues, CRITICAL for immediate action
- **Review Alert History:** Regularly review alert patterns to identify trends
- **Document Responses:** Maintain runbooks for common alert scenarios

### 4. Resource Monitoring

- **Monitor Multiple Metrics:** Don't rely on a single metric (e.g., CPU alone)
- **Track Trends:** Use historical data to identify capacity issues
- **Set Baselines:** Establish normal operating ranges for your infrastructure
- **Plan for Growth:** Monitor trends to plan capacity upgrades

### 5. Network Monitoring

- **Monitor Critical Hosts:** Focus on hosts critical to operations
- **Use Multiple Methods:** Combine ping and port checks for reliability
- **Monitor Internal and External:** Check both internal and external connectivity
- **Document Network Topology:** Maintain documentation of network dependencies

### 6. Database Monitoring

- **Monitor Connection Pool:** Track connection usage to prevent exhaustion
- **Monitor Uptime:** Track database server uptime for availability metrics
- **Set Connection Limits:** Configure appropriate max_connections
- **Monitor Query Performance:** Use database-specific monitoring for query performance

### 7. Service Monitoring

- **Monitor Dependencies:** Track all services that infrastructure depends on
- **Use Service Manager:** Prefer systemd or service manager over process checks
- **Document Dependencies:** Maintain a list of service dependencies
- **Test Failover:** Regularly test service recovery procedures

---

## Reference

### Script Location

- **Main Script:** `bin/monitor/monitorInfrastructure.sh`
- **Configuration:** `config/monitoring.conf`
- **Logs:** `logs/infrastructure.log`

### SQL Queries

- **Resources Queries:** `sql/infrastructure/resources.sql`
- **Connectivity Queries:** `sql/infrastructure/connectivity.sql`

### Related Documentation

- [Configuration Reference](../docs/Configuration_Reference.md)
- [Alerting Guide](../docs/Alerting_Guide.md)
- [Metrics Guide](../docs/METRICS_GUIDE.md)

### Command Reference

```bash
# Run all checks
./bin/monitor/monitorInfrastructure.sh

# Run specific check
./bin/monitor/monitorInfrastructure.sh --check server_resources

# Verbose output
./bin/monitor/monitorInfrastructure.sh -v

# Quiet mode
./bin/monitor/monitorInfrastructure.sh -q

# Custom config
./bin/monitor/monitorInfrastructure.sh -c /path/to/config.conf
```

### Exit Codes

- **0:** All checks passed
- **1:** One or more checks failed
- **2:** Configuration error
- **3:** Database connection error

---

## Support

For issues or questions:

1. Check logs: `logs/infrastructure.log`
2. Review this guide
3. Check [Troubleshooting](#troubleshooting) section
4. Consult project documentation
