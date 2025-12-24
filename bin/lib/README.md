# Shared Libraries

This directory contains shared library functions used across OSM-Notes-Monitoring scripts.

## Libraries

### `monitoringFunctions.sh`
Core monitoring utilities:
- Database connection and query execution
- Component health status management
- HTTP health checks
- Metrics storage

**Usage:**
```bash
source "$(dirname "$0")/../lib/monitoringFunctions.sh"
store_metric "ingestion" "processing_time" 123.45 "ms"
```

### `loggingFunctions.sh`
Centralized logging utilities:
- Log levels (DEBUG, INFO, WARNING, ERROR)
- Timestamp formatting
- Log file management

**Usage:**
```bash
source "$(dirname "$0")/../lib/loggingFunctions.sh"
log_info "Processing started"
log_error "Failed to connect"
```

### `alertFunctions.sh`
Alerting system:
- Alert storage in database
- Alert deduplication
- Email alerts (via mutt)
- Slack notifications

**Usage:**
```bash
source "$(dirname "$0")/../lib/alertFunctions.sh"
send_alert "ingestion" "critical" "data_quality" "Data quality check failed"
```

### `securityFunctions.sh`
Security utilities:
- IP validation and management
- Rate limiting checks
- IP whitelist/blacklist
- Security event recording

**Usage:**
```bash
source "$(dirname "$0")/../lib/securityFunctions.sh"
if check_rate_limit "192.168.1.100" 60 100; then
    echo "Within rate limit"
fi
```

### `metricsFunctions.sh`
Metrics collection and aggregation:
- Metrics summary retrieval
- Metrics cleanup
- Metric aggregation by time period

**Usage:**
```bash
source "$(dirname "$0")/../lib/metricsFunctions.sh"
get_metrics_summary "ingestion" 24
cleanup_old_metrics 90
```

### `configFunctions.sh`
Configuration management:
- Configuration loading
- Configuration validation
- Multi-config support

**Usage:**
```bash
source "$(dirname "$0")/../lib/configFunctions.sh"
load_all_configs
```

## Loading Libraries

All libraries can be sourced individually or together:

```bash
# Load all libraries
for lib in monitoringFunctions loggingFunctions alertFunctions securityFunctions metricsFunctions configFunctions; do
    source "$(dirname "$0")/../lib/${lib}.sh"
done

# Or load individually
source "$(dirname "$0")/../lib/monitoringFunctions.sh"
```

## Dependencies

- **PostgreSQL**: Required for database operations
- **curl**: Required for HTTP health checks
- **mutt**: Required for email alerts (optional)
- **jq**: Required for JSON parsing in some functions (optional)

## Initialization

Most libraries initialize automatically when sourced. Some require explicit initialization:

```bash
# Monitoring functions auto-initialize
source "$(dirname "$0")/../lib/monitoringFunctions.sh"

# Alerting requires config loading
source "$(dirname "$0")/../lib/configFunctions.sh"
load_all_configs
source "$(dirname "$0")/../lib/alertFunctions.sh"
```

## Error Handling

All functions return:
- `0` on success
- `1` on failure

Functions that output data use stdout for results and stderr for errors.

## Testing

See `tests/unit/lib/` for unit tests of these libraries.

