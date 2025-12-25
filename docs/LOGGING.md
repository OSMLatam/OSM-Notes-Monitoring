# Logging Guide

> **Last Updated:** 2025-12-24  
> **Version:** 1.0.0

Complete guide to logging in OSM-Notes-Monitoring.

## Table of Contents

1. [Logging Overview](#logging-overview)
2. [Log Levels](#log-levels)
3. [Log Files](#log-files)
4. [Log Rotation](#log-rotation)
5. [Using Logging Functions](#using-logging-functions)
6. [Best Practices](#best-practices)
7. [Troubleshooting](#troubleshooting)

---

## Logging Overview

OSM-Notes-Monitoring uses a centralized logging system with:
- **Structured logging** with consistent format
- **Multiple log levels** (DEBUG, INFO, WARNING, ERROR)
- **Automatic log rotation** to manage disk space
- **Component-specific log files** for easier debugging

### Log Directory Structure

```
/var/log/osm-notes-monitoring/
├── monitoring.log          # General monitoring logs
├── ingestion.log          # Ingestion monitoring logs
├── analytics.log          # Analytics monitoring logs
├── wms.log                # WMS monitoring logs
├── api.log                # API monitoring logs
├── security.log            # Security event logs
├── error.log              # Error logs (all components)
└── debug.log              # Debug logs (when enabled)
```

---

## Log Levels

### DEBUG
Detailed debugging information. Only enabled when `LOG_LEVEL=DEBUG`.

**When to use:**
- Function entry/exit
- Variable values
- Detailed execution flow

**Example:**
```bash
log_debug "Processing note ${note_id}"
log_debug "Database query: ${query}"
```

### INFO
General informational messages about normal operation.

**When to use:**
- Component startup/shutdown
- Successful operations
- Status updates

**Example:**
```bash
log_info "Monitoring started for component: ${component}"
log_info "Health check passed: ${component}"
```

### WARNING
Warning messages for potentially problematic situations.

**When to use:**
- Recoverable errors
- Degraded performance
- Configuration issues

**Example:**
```bash
log_warning "High error rate detected: ${error_rate}%"
log_warning "Response time above threshold: ${response_time}ms"
```

### ERROR
Error messages for failures that need attention.

**When to use:**
- Component failures
- Database connection errors
- Critical system errors

**Example:**
```bash
log_error "Failed to connect to database: ${error}"
log_error "Component ${component} is down"
```

---

## Log Files

### Component Logs

Each monitoring component writes to its own log file:

- **`monitoring.log`**: General monitoring operations
- **`ingestion.log`**: Ingestion monitoring checks
- **`analytics.log`**: Analytics monitoring checks
- **`wms.log`**: WMS service monitoring
- **`api.log`**: API monitoring
- **`security.log`**: Security events (rate limiting, DDoS, abuse)

### Special Log Files

- **`error.log`**: Aggregated error logs from all components
- **`debug.log`**: Debug logs (only when `LOG_LEVEL=DEBUG`)

### Log File Format

All log entries follow this format:

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [COMPONENT] Message
```

**Example:**
```
[2025-12-24 10:30:45] [INFO] [MONITORING] Health check started
[2025-12-24 10:30:46] [WARNING] [INGESTION] High error rate: 6%
[2025-12-24 10:30:47] [ERROR] [DATABASE] Connection failed: timeout
```

---

## Log Rotation

### Automatic Rotation

Logs are automatically rotated daily using `logrotate`:

- **Regular logs**: Kept for 30 days
- **Error logs**: Kept for 90 days
- **Debug logs**: Kept for 7 days

### Setup Log Rotation

1. **Install logrotate configuration:**
```bash
sudo ./scripts/setup_logrotate.sh
```

2. **Test configuration:**
```bash
sudo ./scripts/setup_logrotate.sh --test
```

3. **Manual rotation (dry-run):**
```bash
logrotate -d /etc/logrotate.d/osm-notes-monitoring
```

4. **Force rotation:**
```bash
logrotate -f /etc/logrotate.d/osm-notes-monitoring
```

### Log Rotation Configuration

The configuration file is located at:
- **Source**: `config/logrotate.conf`
- **Installed**: `/etc/logrotate.d/osm-notes-monitoring`

**Features:**
- Daily rotation
- Compression of old logs
- Date-based naming (`*.log-YYYYMMDD.gz`)
- Automatic cleanup of old logs

---

## Using Logging Functions

### Basic Usage

```bash
# Source logging functions
source bin/lib/loggingFunctions.sh

# Initialize logging
init_logging "component_name"

# Log messages
log_info "Component started"
log_warning "High load detected"
log_error "Operation failed"
log_debug "Variable value: ${value}"
```

### Component-Specific Logging

```bash
# Set component name
set_log_component "INGESTION"

# Log with component context
log_info "Monitoring ingestion pipeline"
log_error "Ingestion failed: ${error}"
```

### Logging to Specific Files

```bash
# Log to component-specific file
log_to_file "ingestion.log" "INFO" "Ingestion check started"

# Log errors to error log
log_error_to_file "error.log" "Database connection failed"
```

### Logging with Context

```bash
# Log with additional context
log_info_with_context "Operation completed" "duration=${duration}s" "items=${count}"

# Log errors with stack trace
log_error_with_trace "Function failed" "${BASH_SOURCE[0]}" "${LINENO}"
```

---

## Best Practices

> **Note:** For comprehensive logging best practices, see **[Logging Best Practices](./LOGGING_BEST_PRACTICES.md)**

### 1. Use Appropriate Log Levels

- **DEBUG**: Only for detailed debugging
- **INFO**: Normal operation events
- **WARNING**: Recoverable issues
- **ERROR**: Failures requiring attention

### 2. Include Context

Always include relevant context in log messages:

```bash
# Good
log_error "Database connection failed: ${error} (host=${DBHOST}, port=${DBPORT})"

# Bad
log_error "Connection failed"
```

### 3. Avoid Sensitive Information

Never log passwords, API keys, or sensitive data:

```bash
# Good
log_info "Connecting to database: ${DBHOST}:${DBPORT}"

# Bad
log_info "Database password: ${DBPASSWORD}"
```

### 4. Use Structured Format

Include structured data when possible:

```bash
log_info "Health check: component=${component} status=${status} response_time=${time}ms"
```

### 5. Log at Appropriate Times

- **Startup**: Log component initialization
- **Operations**: Log significant operations
- **Errors**: Always log errors with context
- **Shutdown**: Log graceful shutdown

### 6. Performance Considerations

- Avoid excessive DEBUG logging in production
- Use log rotation to manage disk space
- Monitor log file sizes
- Consider log aggregation for large deployments

---

## Troubleshooting

### Logs Not Being Created

**Problem**: Log files are not being created.

**Solutions:**
1. Check log directory permissions:
```bash
ls -ld /var/log/osm-notes-monitoring
```

2. Ensure directory exists:
```bash
mkdir -p /var/log/osm-notes-monitoring
chmod 755 /var/log/osm-notes-monitoring
```

3. Check `LOG_DIR` configuration:
```bash
grep LOG_DIR etc/properties.sh
```

### Log Rotation Not Working

**Problem**: Logs are not rotating.

**Solutions:**
1. Check logrotate configuration:
```bash
logrotate -d /etc/logrotate.d/osm-notes-monitoring
```

2. Verify logrotate is running:
```bash
systemctl status logrotate
```

3. Check cron for logrotate:
```bash
grep logrotate /etc/cron.daily/logrotate
```

### Too Many Log Files

**Problem**: Disk space filling up with logs.

**Solutions:**
1. Reduce retention period in `config/logrotate.conf`:
```bash
rotate 7  # Keep only 7 days instead of 30
```

2. Force immediate rotation:
```bash
logrotate -f /etc/logrotate.d/osm-notes-monitoring
```

3. Clean up old logs manually:
```bash
find /var/log/osm-notes-monitoring -name "*.log-*.gz" -mtime +30 -delete
```

### Debug Logs Too Verbose

**Problem**: Debug logs are too verbose in production.

**Solutions:**
1. Change log level in `etc/properties.sh`:
```bash
LOG_LEVEL="INFO"  # Instead of DEBUG
```

2. Disable debug logging:
```bash
export LOG_LEVEL="INFO"
```

### Logs Not Showing Component Name

**Problem**: Log entries don't show component name.

**Solutions:**
1. Initialize logging with component name:
```bash
init_logging "COMPONENT_NAME"
```

2. Set component explicitly:
```bash
set_log_component "COMPONENT_NAME"
```

---

## Log Aggregation Utilities

OSM-Notes-Monitoring includes built-in log aggregation and analysis utilities:

### Log Aggregator (`scripts/log_aggregator.sh`)

Aggregates logs from multiple components with filtering options.

**Usage:**
```bash
# Show last 100 lines from all logs
./scripts/log_aggregator.sh

# Show only ERROR logs
./scripts/log_aggregator.sh --level ERROR

# Show logs from ingestion component
./scripts/log_aggregator.sh --component ingestion

# Show logs from last hour
./scripts/log_aggregator.sh --since "1 hour ago"

# Search for pattern
./scripts/log_aggregator.sh --grep "database"

# Follow logs in real-time
./scripts/log_aggregator.sh --follow

# Combine filters
./scripts/log_aggregator.sh --component ingestion --level ERROR --since "1 hour ago"
```

**Options:**
- `-d, --dir DIR`: Log directory
- `-c, --component NAME`: Filter by component
- `-l, --level LEVEL`: Filter by log level
- `-s, --since TIME`: Show logs since time
- `-u, --until TIME`: Show logs until time
- `-g, --grep PATTERN`: Search for pattern
- `-f, --follow`: Follow logs (like tail -f)
- `-n, --lines N`: Show last N lines

### Log Analyzer (`scripts/log_analyzer.sh`)

Analyzes logs and generates statistics and reports.

**Usage:**
```bash
# Show statistics
./scripts/log_analyzer.sh stats

# Show error summary
./scripts/log_analyzer.sh errors

# Show top error messages
./scripts/log_analyzer.sh top-errors

# Show component statistics
./scripts/log_analyzer.sh components

# Show summary report
./scripts/log_analyzer.sh summary

# Analyze last hour
./scripts/log_analyzer.sh --since "1 hour ago" stats

# Component-specific analysis
./scripts/log_analyzer.sh --component ingestion errors
```

**Commands:**
- `stats`: Show log statistics
- `errors`: Show error summary
- `top-errors`: Show top error messages
- `components`: Show component statistics
- `summary`: Show summary report

**Options:**
- `-d, --dir DIR`: Log directory
- `-s, --since TIME`: Analyze logs since time
- `-u, --until TIME`: Analyze logs until time
- `-c, --component NAME`: Filter by component
- `-o, --output FILE`: Output to file

## External Log Aggregation

For large deployments, consider using external log aggregation tools:

### Options

1. **rsyslog**: Forward logs to central server
2. **ELK Stack**: Elasticsearch, Logstash, Kibana
3. **Loki**: Log aggregation system from Grafana
4. **Fluentd**: Log collector and processor

### Example: Forwarding to rsyslog

Add to `/etc/rsyslog.d/osm-notes-monitoring.conf`:

```
$ModLoad imfile
$InputFilePollInterval 10
$InputFileName /var/log/osm-notes-monitoring/*.log
$InputFileTag osm-notes-monitoring:
$InputFileStateFile osm-notes-monitoring-state
$InputFileSeverity info
$InputFileFacility local0
$InputRunFileMonitor
local0.* @@log-server:514
```

---

## Performance Testing

### Running Performance Tests

Test logging performance with the performance test suite:

```bash
# Run all performance tests
./scripts/test_logging_performance.sh
```

**Test Coverage:**
- Single log write performance
- Batch log write performance
- Log level filtering performance
- Concurrent logging performance
- Log file size impact
- Different log levels performance
- Memory usage

**Example Output:**
```
=== Testing Single Log Write Performance ===
  Total time: 26630ms
  Iterations: 10000
  Average time per log: 2ms
  Logs per second: 375
  Log file size: 738894 bytes
```

**Performance Guidelines:**
- Single log writes: ~2-3ms per message
- Log level filtering adds minimal overhead
- Concurrent logging scales well
- File size impact decreases with larger files
- Memory usage is minimal

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Log level (DEBUG, INFO, WARNING, ERROR) |
| `LOG_DIR` | `/var/log/osm-notes-monitoring` | Log directory |
| `LOG_COMPONENT` | `MONITORING` | Default component name |

### Log Rotation Settings

| Setting | Value | Description |
|---------|-------|-------------|
| Rotation frequency | Daily | Logs rotated once per day |
| Regular retention | 30 days | Standard logs kept for 30 days |
| Error retention | 90 days | Error logs kept for 90 days |
| Debug retention | 7 days | Debug logs kept for 7 days |
| Compression | Yes | Old logs are compressed |

---

**Last Updated:** 2025-12-24

