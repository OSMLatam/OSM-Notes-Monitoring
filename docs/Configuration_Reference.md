---
title: "Configuration Reference"
description: "Complete reference for all configuration options in OSM-Notes-Monitoring."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "documentation"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Configuration Reference

> **Last Updated:** 2025-12-24  
> **Version:** 1.0.0

Complete reference for all configuration options in OSM-Notes-Monitoring.

## Table of Contents

1. [Main Configuration (`etc/properties.sh`)](#main-configuration)
2. [Monitoring Configuration (`config/monitoring.conf`)](#monitoring-configuration)
3. [Alert Configuration (`config/alerts.conf`)](#alert-configuration)
4. [Security Configuration (`config/security.conf`)](#security-configuration)
5. [Configuration Generation](#configuration-generation)

---

## Main Configuration

**File:** `etc/properties.sh`  
**Template:** `etc/properties.sh.example`  
**Required:** Yes

### Database Settings

| Variable | Type    | Default                | Description                     |
| -------- | ------- | ---------------------- | ------------------------------- |
| `DBNAME` | String  | `osm_notes_monitoring` | Name of the monitoring database |
| `DBHOST` | String  | `localhost`            | Database server hostname or IP  |
| `DBPORT` | Integer | `5432`                 | Database server port            |
| `DBUSER` | String  | `postgres`             | Database username               |

**Example:**

```bash
DBNAME="osm_notes_monitoring"
DBHOST="localhost"
DBPORT="5432"
DBUSER="postgres"
```

**Notes:**

- `DBPORT` must be a numeric value
- Database password should be set via `PGPASSWORD` environment variable or `.pgpass` file
- Ensure the database user has appropriate permissions

### Alerting Settings

| Variable            | Type    | Default             | Description                  |
| ------------------- | ------- | ------------------- | ---------------------------- |
| `ADMIN_EMAIL`       | String  | `admin@example.com` | Primary email for alerts     |
| `SEND_ALERT_EMAIL`  | Boolean | `true`              | Enable/disable email alerts  |
| `SLACK_WEBHOOK_URL` | String  | `""`                | Slack webhook URL (optional) |

**Example:**

```bash
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"
SLACK_WEBHOOK_URL=""  # Optional
```

### Monitoring Intervals

All intervals are specified in **seconds**.

| Variable                        | Type    | Default | Description                                      |
| ------------------------------- | ------- | ------- | ------------------------------------------------ |
| `INGESTION_CHECK_INTERVAL`      | Integer | `300`   | Ingestion monitoring check interval (5 minutes)  |
| `ANALYTICS_CHECK_INTERVAL`      | Integer | `900`   | Analytics monitoring check interval (15 minutes) |
| `WMS_CHECK_INTERVAL`            | Integer | `300`   | WMS monitoring check interval (5 minutes)        |
| `API_CHECK_INTERVAL`            | Integer | `60`    | API monitoring check interval (1 minute)         |
| `DATA_CHECK_INTERVAL`           | Integer | `3600`  | Data freshness check interval (1 hour)           |
| `INFRASTRUCTURE_CHECK_INTERVAL` | Integer | `300`   | Infrastructure check interval (5 minutes)        |

**Example:**

```bash
INGESTION_CHECK_INTERVAL=300      # 5 minutes
ANALYTICS_CHECK_INTERVAL=900       # 15 minutes
WMS_CHECK_INTERVAL=300             # 5 minutes
API_CHECK_INTERVAL=60              # 1 minute
DATA_CHECK_INTERVAL=3600           # 1 hour
INFRASTRUCTURE_CHECK_INTERVAL=300  # 5 minutes
```

### Logging Settings

| Variable    | Type   | Default                         | Description                            |
| ----------- | ------ | ------------------------------- | -------------------------------------- |
| `LOG_LEVEL` | String | `INFO`                          | Log level: DEBUG, INFO, WARNING, ERROR |
| `LOG_DIR`   | String | `/var/log/osm-notes-monitoring` | Directory for log files                |
| `TMP_DIR`   | String | `/var/tmp/osm-notes-monitoring` | Directory for temporary files          |
| `LOCK_DIR`  | String | `/var/run/osm-notes-monitoring` | Directory for lock files               |

**Example:**

```bash
LOG_LEVEL="INFO"
LOG_DIR="/var/log/osm-notes-monitoring"
TMP_DIR="/var/tmp/osm-notes-monitoring"
LOCK_DIR="/var/run/osm-notes-monitoring"
```

**Log Levels:**

- `DEBUG`: Detailed debugging information
- `INFO`: General informational messages
- `WARNING`: Warning messages
- `ERROR`: Error messages only

### Repository Paths

Paths to other OSM-Notes repositories (for integration).

| Variable              | Type   | Default                        | Description                            |
| --------------------- | ------ | ------------------------------ | -------------------------------------- |
| `INGESTION_REPO_PATH` | String | `/path/to/OSM-Notes-Ingestion` | Path to OSM-Notes-Ingestion repository |
| `ANALYTICS_REPO_PATH` | String | `/path/to/OSM-Notes-Analytics` | Path to OSM-Notes-Analytics repository |
| `WMS_REPO_PATH`       | String | `/path/to/OSM-Notes-WMS`       | Path to OSM-Notes-WMS repository       |
| `DATA_REPO_PATH`      | String | `/path/to/OSM-Notes-Data`      | Path to OSM-Notes-Data repository      |

**Example:**

```bash
INGESTION_REPO_PATH="/opt/osm-notes/OSM-Notes-Ingestion"
ANALYTICS_REPO_PATH="/opt/osm-notes/OSM-Notes-Analytics"
WMS_REPO_PATH="/opt/osm-notes/OSM-Notes-WMS"
DATA_REPO_PATH="/opt/osm-notes/OSM-Notes-Data"
```

---

## Monitoring Configuration

**File:** `config/monitoring.conf`  
**Template:** `config/monitoring.conf.example`  
**Required:** No (uses defaults if not present)

### Component-Specific Settings

Each component can be enabled/disabled and has its own timeout settings.

#### Ingestion Monitoring

| Variable                           | Type    | Default | Description                     |
| ---------------------------------- | ------- | ------- | ------------------------------- |
| `INGESTION_ENABLED`                | Boolean | `true`  | Enable ingestion monitoring     |
| `INGESTION_CHECK_TIMEOUT`          | Integer | `300`   | Check timeout in seconds        |
| `INGESTION_MAX_ERROR_RATE`         | Integer | `5`     | Maximum error rate percentage   |
| `INGESTION_DATA_QUALITY_THRESHOLD` | Integer | `95`    | Minimum data quality percentage |

#### Analytics Monitoring

| Variable                             | Type    | Default | Description                                  |
| ------------------------------------ | ------- | ------- | -------------------------------------------- |
| `ANALYTICS_ENABLED`                  | Boolean | `true`  | Enable analytics monitoring                  |
| `ANALYTICS_CHECK_TIMEOUT`            | Integer | `600`   | Check timeout in seconds                     |
| `ANALYTICS_ETL_TIMEOUT`              | Integer | `3600`  | ETL timeout in seconds (1 hour)              |
| `ANALYTICS_DATA_FRESHNESS_THRESHOLD` | Integer | `3600`  | Data freshness threshold in seconds (1 hour) |

#### WMS Monitoring

| Variable                      | Type    | Default                        | Description                             |
| ----------------------------- | ------- | ------------------------------ | --------------------------------------- |
| `WMS_ENABLED`                 | Boolean | `true`                         | Enable WMS monitoring                   |
| `WMS_CHECK_TIMEOUT`           | Integer | `30`                           | Check timeout in seconds                |
| `WMS_RESPONSE_TIME_THRESHOLD` | Integer | `2000`                         | Response time threshold in milliseconds |
| `WMS_ERROR_RATE_THRESHOLD`    | Integer | `5`                            | Error rate threshold percentage         |
| `WMS_HEALTH_CHECK_URL`        | String  | `http://localhost:8080/health` | WMS health check URL                    |

#### API Monitoring

| Variable                      | Type    | Default                        | Description                             |
| ----------------------------- | ------- | ------------------------------ | --------------------------------------- |
| `API_ENABLED`                 | Boolean | `true`                         | Enable API monitoring                   |
| `API_CHECK_TIMEOUT`           | Integer | `10`                           | Check timeout in seconds                |
| `API_RESPONSE_TIME_THRESHOLD` | Integer | `500`                          | Response time threshold in milliseconds |
| `API_ERROR_RATE_THRESHOLD`    | Integer | `1`                            | Error rate threshold percentage         |
| `API_HEALTH_CHECK_URL`        | String  | `http://localhost:8081/health` | API health check URL                    |

#### Data Freshness Monitoring

| Variable                          | Type    | Default | Description                                      |
| --------------------------------- | ------- | ------- | ------------------------------------------------ |
| `DATA_ENABLED`                    | Boolean | `true`  | Enable data freshness monitoring                 |
| `DATA_CHECK_TIMEOUT`              | Integer | `60`    | Check timeout in seconds                         |
| `DATA_BACKUP_FRESHNESS_THRESHOLD` | Integer | `86400` | Backup freshness threshold in seconds (24 hours) |
| `DATA_REPO_SYNC_CHECK_ENABLED`    | Boolean | `true`  | Enable repository sync checks                    |

#### Infrastructure Monitoring

| Variable                          | Type    | Default | Description                       |
| --------------------------------- | ------- | ------- | --------------------------------- |
| `INFRASTRUCTURE_ENABLED`          | Boolean | `true`  | Enable infrastructure monitoring  |
| `INFRASTRUCTURE_CHECK_TIMEOUT`    | Integer | `30`    | Check timeout in seconds          |
| `INFRASTRUCTURE_CPU_THRESHOLD`    | Integer | `80`    | CPU usage threshold percentage    |
| `INFRASTRUCTURE_MEMORY_THRESHOLD` | Integer | `85`    | Memory usage threshold percentage |
| `INFRASTRUCTURE_DISK_THRESHOLD`   | Integer | `90`    | Disk usage threshold percentage   |

### Metrics Collection

| Variable                   | Type    | Default     | Description                               |
| -------------------------- | ------- | ----------- | ----------------------------------------- |
| `METRICS_RETENTION_DAYS`   | Integer | `90`        | Number of days to retain metrics          |
| `METRICS_CLEANUP_ENABLED`  | Boolean | `true`      | Enable automatic metrics cleanup          |
| `METRICS_CLEANUP_SCHEDULE` | String  | `0 2 * * *` | Cron schedule for cleanup (daily at 2 AM) |

### Health Check Settings

| Variable                   | Type    | Default | Description                                |
| -------------------------- | ------- | ------- | ------------------------------------------ |
| `HEALTH_CHECK_ENABLED`     | Boolean | `true`  | Enable health checks                       |
| `HEALTH_CHECK_INTERVAL`    | Integer | `60`    | Health check interval in seconds           |
| `HEALTH_CHECK_RETRY_COUNT` | Integer | `3`     | Number of retries before marking as failed |
| `HEALTH_CHECK_RETRY_DELAY` | Integer | `10`    | Delay between retries in seconds           |

### Performance Monitoring

| Variable                           | Type    | Default | Description                          |
| ---------------------------------- | ------- | ------- | ------------------------------------ |
| `PERFORMANCE_MONITORING_ENABLED`   | Boolean | `true`  | Enable performance monitoring        |
| `PERFORMANCE_SLOW_QUERY_THRESHOLD` | Integer | `1000`  | Slow query threshold in milliseconds |
| `PERFORMANCE_TRACK_DB_QUERIES`     | Boolean | `true`  | Track database query performance     |

### Dependency Monitoring

| Variable                    | Type    | Default | Description                                      |
| --------------------------- | ------- | ------- | ------------------------------------------------ |
| `DEPENDENCY_CHECK_ENABLED`  | Boolean | `true`  | Enable dependency checks                         |
| `DEPENDENCY_CHECK_INTERVAL` | Integer | `300`   | Dependency check interval in seconds (5 minutes) |

### Notification Settings

| Variable                | Type    | Default | Description                                   |
| ----------------------- | ------- | ------- | --------------------------------------------- |
| `NOTIFY_ON_DEGRADED`    | Boolean | `true`  | Send notifications when component is degraded |
| `NOTIFY_ON_RECOVERY`    | Boolean | `true`  | Send notifications when component recovers    |
| `NOTIFY_ON_MAINTENANCE` | Boolean | `false` | Send notifications during maintenance         |

---

## Alert Configuration

**File:** `config/alerts.conf`  
**Template:** `config/alerts.conf.example`  
**Required:** No (uses defaults if not present)

### Email Settings

| Variable           | Type    | Default             | Description                 |
| ------------------ | ------- | ------------------- | --------------------------- |
| `ADMIN_EMAIL`      | String  | `admin@example.com` | Primary admin email address |
| `SEND_ALERT_EMAIL` | Boolean | `true`              | Enable/disable email alerts |

**Example:**

```bash
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"
```

### Slack Settings

| Variable            | Type    | Default       | Description                             |
| ------------------- | ------- | ------------- | --------------------------------------- |
| `SLACK_ENABLED`     | Boolean | `false`       | Enable/disable Slack notifications      |
| `SLACK_WEBHOOK_URL` | String  | `""`          | Slack webhook URL (required if enabled) |
| `SLACK_CHANNEL`     | String  | `#monitoring` | Slack channel for notifications         |

**Example:**

```bash
SLACK_ENABLED="true"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
SLACK_CHANNEL="#monitoring"
```

**Notes:**

- Slack webhook URL format:
  `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX`
- Channel name should include `#` prefix (e.g., `#monitoring`)

### Alert Recipients

Different alert levels can have different recipients.

| Variable                    | Type   | Default          | Description                                   |
| --------------------------- | ------ | ---------------- | --------------------------------------------- |
| `CRITICAL_ALERT_RECIPIENTS` | String | `${ADMIN_EMAIL}` | Recipients for critical alerts                |
| `WARNING_ALERT_RECIPIENTS`  | String | `${ADMIN_EMAIL}` | Recipients for warning alerts                 |
| `INFO_ALERT_RECIPIENTS`     | String | `""`             | Recipients for info alerts (empty = disabled) |

**Example:**

```bash
CRITICAL_ALERT_RECIPIENTS="admin@example.com,oncall@example.com"
WARNING_ALERT_RECIPIENTS="admin@example.com"
INFO_ALERT_RECIPIENTS=""  # Disabled
```

**Notes:**

- Multiple recipients: comma-separated list
- Can use `${ADMIN_EMAIL}` variable
- Empty `INFO_ALERT_RECIPIENTS` disables info alerts

### Alert Deduplication

| Variable                             | Type    | Default | Description                     |
| ------------------------------------ | ------- | ------- | ------------------------------- |
| `ALERT_DEDUPLICATION_ENABLED`        | Boolean | `true`  | Enable alert deduplication      |
| `ALERT_DEDUPLICATION_WINDOW_MINUTES` | Integer | `60`    | Deduplication window in minutes |

**Example:**

```bash
ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW_MINUTES=60
```

**How it works:**

- Prevents duplicate alerts within the time window
- Same component + alert type + message = duplicate
- Only one alert sent per window period

---

## Security Configuration

**File:** `config/security.conf`  
**Template:** `config/security.conf.example`  
**Required:** No (uses defaults if not present)

### Rate Limiting

| Variable                       | Type    | Default | Description                        |
| ------------------------------ | ------- | ------- | ---------------------------------- |
| `RATE_LIMIT_PER_IP_PER_MINUTE` | Integer | `60`    | Maximum requests per IP per minute |
| `RATE_LIMIT_PER_IP_PER_HOUR`   | Integer | `1000`  | Maximum requests per IP per hour   |
| `RATE_LIMIT_PER_IP_PER_DAY`    | Integer | `10000` | Maximum requests per IP per day    |
| `RATE_LIMIT_BURST_SIZE`        | Integer | `10`    | Burst size (concurrent requests)   |

**Example:**

```bash
RATE_LIMIT_PER_IP_PER_MINUTE=60
RATE_LIMIT_PER_IP_PER_HOUR=1000
RATE_LIMIT_PER_IP_PER_DAY=10000
RATE_LIMIT_BURST_SIZE=10
```

**Notes:**

- All values must be >= 1
- Burst size allows temporary spikes above per-minute limit
- Whitelisted IPs bypass rate limiting

### Connection Limits

| Variable                            | Type    | Default | Description                           |
| ----------------------------------- | ------- | ------- | ------------------------------------- |
| `MAX_CONCURRENT_CONNECTIONS_PER_IP` | Integer | `10`    | Maximum concurrent connections per IP |
| `MAX_TOTAL_CONNECTIONS`             | Integer | `1000`  | Maximum total concurrent connections  |

**Example:**

```bash
MAX_CONCURRENT_CONNECTIONS_PER_IP=10
MAX_TOTAL_CONNECTIONS=1000
```

### DDoS Protection

| Variable                                | Type    | Default | Description                                       |
| --------------------------------------- | ------- | ------- | ------------------------------------------------- |
| `DDOS_THRESHOLD_REQUESTS_PER_SECOND`    | Integer | `100`   | DDoS detection threshold (requests/second)        |
| `DDOS_THRESHOLD_CONCURRENT_CONNECTIONS` | Integer | `500`   | DDoS detection threshold (concurrent connections) |
| `DDOS_AUTO_BLOCK_DURATION_MINUTES`      | Integer | `15`    | Auto-block duration for DDoS (minutes)            |

**Example:**

```bash
DDOS_THRESHOLD_REQUESTS_PER_SECOND=100
DDOS_THRESHOLD_CONCURRENT_CONNECTIONS=500
DDOS_AUTO_BLOCK_DURATION_MINUTES=15
```

**How it works:**

- Monitors request rate per IP
- Automatically blocks IPs exceeding thresholds
- Temporary block (expires automatically)

### Abuse Detection

| Variable                             | Type    | Default | Description                                      |
| ------------------------------------ | ------- | ------- | ------------------------------------------------ |
| `ABUSE_DETECTION_ENABLED`            | Boolean | `true`  | Enable abuse detection                           |
| `ABUSE_RAPID_REQUEST_THRESHOLD`      | Integer | `10`    | Rapid request threshold (requests in short time) |
| `ABUSE_ERROR_RATE_THRESHOLD`         | Integer | `50`    | Error rate threshold percentage                  |
| `ABUSE_EXCESSIVE_REQUESTS_THRESHOLD` | Integer | `1000`  | Excessive requests threshold                     |

**Example:**

```bash
ABUSE_DETECTION_ENABLED=true
ABUSE_RAPID_REQUEST_THRESHOLD=10
ABUSE_ERROR_RATE_THRESHOLD=50
ABUSE_EXCESSIVE_REQUESTS_THRESHOLD=1000
```

### Blocking Policy

| Variable                             | Type    | Default | Description                              |
| ------------------------------------ | ------- | ------- | ---------------------------------------- |
| `TEMP_BLOCK_FIRST_VIOLATION_MINUTES` | Integer | `15`    | First violation block duration (minutes) |
| `TEMP_BLOCK_SECOND_VIOLATION_HOURS`  | Integer | `1`     | Second violation block duration (hours)  |
| `TEMP_BLOCK_THIRD_VIOLATION_HOURS`   | Integer | `24`    | Third violation block duration (hours)   |

**Example:**

```bash
TEMP_BLOCK_FIRST_VIOLATION_MINUTES=15
TEMP_BLOCK_SECOND_VIOLATION_HOURS=1
TEMP_BLOCK_THIRD_VIOLATION_HOURS=24
```

**Escalation Policy:**

- **First violation**: 15 minutes temporary block
- **Second violation**: 1 hour temporary block
- **Third violation**: 24 hours temporary block
- **Fourth violation**: Consider permanent blacklist (manual)

---

## Configuration Generation

### Using the Generator Script

Generate configuration files from templates:

```bash
# Generate all configs interactively
./scripts/generate_config.sh -i

# Generate all configs with defaults
./scripts/generate_config.sh -a

# Generate specific config
./scripts/generate_config.sh main

# Force overwrite existing
./scripts/generate_config.sh -f main
```

### Manual Setup

1. Copy template files:

```bash
cp etc/properties.sh.example etc/properties.sh
cp config/monitoring.conf.example config/monitoring.conf
cp config/alerts.conf.example config/alerts.conf
cp config/security.conf.example config/security.conf
```

2. Edit configuration files with your values

3. Validate configuration:

```bash
# Source config functions and validate
source bin/lib/configFunctions.sh
load_all_configs
validate_all_configs
```

---

## Environment Variables

Some settings can be overridden via environment variables:

| Variable     | Description                                  |
| ------------ | -------------------------------------------- |
| `PGPASSWORD` | PostgreSQL password (alternative to .pgpass) |
| `DBNAME`     | Override database name                       |
| `DBHOST`     | Override database host                       |
| `LOG_LEVEL`  | Override log level                           |

**Example:**

```bash
export PGPASSWORD="your_password"
export LOG_LEVEL="DEBUG"
./bin/monitor/monitorIngestion.sh
```

---

## Configuration Validation

All configurations are validated when loaded:

- **Required variables**: Must be set
- **Data types**: Numbers must be numeric, booleans must be true/false
- **Ranges**: Values must be within acceptable ranges
- **Formats**: Email addresses, URLs must be valid format

Run validation:

```bash
./scripts/test_config_validation.sh
```

---

## Best Practices

1. **Security**
   - Never commit actual config files (only `.example` files)
   - Use environment variables for sensitive data (passwords)
   - Restrict file permissions: `chmod 600 etc/properties.sh`

2. **Organization**
   - Keep production configs separate from development
   - Use version control for config templates
   - Document any custom settings

3. **Testing**
   - Test configurations in development first
   - Validate before deploying to production
   - Keep backups of working configurations

4. **Maintenance**
   - Review configurations periodically
   - Update thresholds based on actual usage
   - Adjust intervals based on monitoring needs

---

## Troubleshooting

### Configuration Not Loading

- Check file exists and is readable
- Verify syntax with `bash -n config_file`
- Check file permissions

### Validation Errors

- Run `./scripts/test_config_validation.sh` to see specific errors
- Check variable names match exactly (case-sensitive)
- Verify data types (numbers, booleans, strings)

### Database Connection Issues

- Verify `DBHOST`, `DBPORT`, `DBUSER` are correct
- Check `PGPASSWORD` or `.pgpass` file
- Test connection: `psql -h $DBHOST -p $DBPORT -U $DBUSER -d $DBNAME`

---

**Last Updated:** 2025-12-24
