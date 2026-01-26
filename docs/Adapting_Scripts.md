---
title: "Adapting Scripts to Use Shared Libraries"
description: "OSM-Notes-Monitoring provides shared libraries that can be used by scripts in OSM-Notes-Ingestion and other repositories. These libraries provide:"
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


# Adapting Scripts to Use Shared Libraries

> **Last Updated:** 2025-12-24  
> **Version:** 1.0.0

Guide for adapting existing OSM-Notes-Ingestion scripts to use OSM-Notes-Monitoring shared
libraries.

## Table of Contents

1. [Overview](#overview)
2. [Benefits of Using Shared Libraries](#benefits)
3. [Migration Steps](#migration-steps)
4. [Library Reference](#library-reference)
5. [Examples](#examples)
6. [Best Practices](#best-practices)

---

## Overview

OSM-Notes-Monitoring provides shared libraries that can be used by scripts in OSM-Notes-Ingestion
and other repositories. These libraries provide:

- **Centralized logging** with consistent format
- **Unified alerting** (email, Slack)
- **Metrics collection** and storage
- **Configuration management**
- **Database utilities**
- **Security functions**

### Current Integration Approach

Currently, OSM-Notes-Monitoring calls existing scripts from OSM-Notes-Ingestion without
modification. For deeper integration, scripts can be adapted to use shared libraries.

---

## Benefits

### 1. Consistent Logging

All scripts use the same logging format and levels:

```bash
# Before (inconsistent)
echo "Error: Something went wrong"
logger -t ingestion "Warning: High error rate"

# After (consistent)
log_error "Something went wrong"
log_warning "High error rate: ${rate}%"
```

### 2. Unified Alerting

Centralized alerting system:

```bash
# Before (script-specific)
sendmail -t <<EOF
To: admin@example.com
Subject: Alert
...
EOF

# After (unified)
send_alert "WARNING" "INGESTION" "High error rate: ${rate}%"
```

### 3. Metrics Collection

Automatic metrics storage:

```bash
# Before (manual)
psql -c "INSERT INTO metrics ..."

# After (automatic)
record_metric "INGESTION" "error_rate" "${rate}" "component=ingestion"
```

### 4. Configuration Management

Centralized configuration:

```bash
# Before (hardcoded or scattered)
DBHOST="localhost"
DBNAME="osm_notes"

# After (centralized)
load_all_configs
# Uses etc/properties.sh and config/*.conf
```

---

## Migration Steps

### Step 1: Add Library Source

Add at the top of your script:

```bash
#!/usr/bin/env bash

# Determine project root (adjust path as needed)
PROJECT_ROOT="/path/to/OSM-Notes-Monitoring"

# Source shared libraries
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"
```

### Step 2: Initialize Logging

Replace existing logging setup:

```bash
# Before
LOG_FILE="/var/log/ingestion.log"
exec 1>> "${LOG_FILE}" 2>&1

# After
init_logging "${LOG_DIR}/ingestion.log" "script_name"
```

### Step 3: Replace Logging Calls

Replace echo/logger calls:

```bash
# Before
echo "INFO: Processing started"
echo "ERROR: Processing failed" >&2

# After
log_info "Processing started"
log_error "Processing failed"
```

### Step 4: Replace Alerting

Replace email/alert calls:

```bash
# Before
sendmail -t <<EOF
To: ${ADMIN_EMAIL}
Subject: Alert
Body: Error occurred
EOF

# After
send_alert "ERROR" "INGESTION" "Error occurred"
```

### Step 5: Add Metrics Collection

Add metrics recording:

```bash
# Before
# No metrics collection

# After
record_metric "INGESTION" "processing_duration" "${duration}" "component=ingestion"
record_metric "INGESTION" "records_processed" "${count}" "component=ingestion"
```

### Step 6: Use Configuration Functions

Replace hardcoded configuration:

```bash
# Before
DBHOST="localhost"
DBNAME="osm_notes"

# After
load_all_configs
validate_all_configs
# Uses centralized configuration
```

---

## Library Reference

### Logging Functions

**File:** `bin/lib/loggingFunctions.sh`

**Functions:**

- `init_logging(log_file, script_name)` - Initialize logging
- `log_debug(message)` - Log debug message
- `log_info(message)` - Log info message
- `log_warning(message)` - Log warning message
- `log_error(message)` - Log error message

**Example:**

```bash
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
init_logging "${LOG_DIR}/script.log" "my_script"
log_info "Script started"
log_error "Script failed: ${error}"
```

### Monitoring Functions

**File:** `bin/lib/monitoringFunctions.sh`

**Functions:**

- `check_database_connection()` - Check DB connectivity
- `execute_sql_query(query)` - Execute SQL query
- `store_metric(component, name, value, unit, metadata)` - Store metric

**Example:**

```bash
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
if check_database_connection; then
    result=$(execute_sql_query "SELECT COUNT(*) FROM notes")
    store_metric "INGESTION" "note_count" "${result}" "count"
fi
```

### Alert Functions

**File:** `bin/lib/alertFunctions.sh`

**Functions:**

- `send_alert(level, component, message)` - Send alert

**Example:**

```bash
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
send_alert "WARNING" "INGESTION" "High error rate: ${rate}%"
send_alert "ERROR" "INGESTION" "Processing failed: ${error}"
```

### Config Functions

**File:** `bin/lib/configFunctions.sh`

**Functions:**

- `load_all_configs()` - Load all configurations
- `validate_all_configs()` - Validate configurations

**Example:**

```bash
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
load_all_configs
if validate_all_configs; then
    echo "Configuration valid"
fi
```

### Metrics Functions

**File:** `bin/lib/metricsFunctions.sh`

**Functions:**

- `record_metric(component, name, value, metadata)` - Record metric

**Example:**

```bash
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"
record_metric "INGESTION" "processing_time" "${duration}" "component=ingestion"
```

---

## Examples

### Example 1: Simple Script Migration

**Before:**

```bash
#!/usr/bin/env bash

LOG_FILE="/var/log/ingestion.log"
exec 1>> "${LOG_FILE}" 2>&1

echo "INFO: Starting processing"
# ... processing ...
if [[ $? -ne 0 ]]; then
    echo "ERROR: Processing failed"
    sendmail -t <<EOF
To: admin@example.com
Subject: Error
Processing failed
EOF
    exit 1
fi
echo "INFO: Processing completed"
```

**After:**

```bash
#!/usr/bin/env bash

PROJECT_ROOT="/path/to/OSM-Notes-Monitoring"
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"

load_all_configs
init_logging "${LOG_DIR}/ingestion.log" "process_notes"

log_info "Starting processing"
# ... processing ...
if [[ $? -ne 0 ]]; then
    log_error "Processing failed"
    send_alert "ERROR" "INGESTION" "Processing failed"
    exit 1
fi
log_info "Processing completed"
```

### Example 2: Script with Metrics

**Before:**

```bash
#!/usr/bin/env bash

# Process notes
start_time=$(date +%s)
process_notes
end_time=$(date +%s)
duration=$((end_time - start_time))

echo "Processed in ${duration} seconds"
```

**After:**

```bash
#!/usr/bin/env bash

PROJECT_ROOT="/path/to/OSM-Notes-Monitoring"
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/metricsFunctions.sh"

init_logging "${LOG_DIR}/ingestion.log" "process_notes"

# Process notes
start_time=$(date +%s)
process_notes
end_time=$(date +%s)
duration=$((end_time - start_time))

log_info "Processed in ${duration} seconds"
record_metric "INGESTION" "processing_duration" "${duration}" "component=ingestion"
```

### Example 3: Script with Database Operations

**Before:**

```bash
#!/usr/bin/env bash

DBHOST="localhost"
DBNAME="osm_notes"
DBUSER="postgres"

psql -h "${DBHOST}" -U "${DBUSER}" -d "${DBNAME}" -c "SELECT COUNT(*) FROM notes"
```

**After:**

```bash
#!/usr/bin/env bash

PROJECT_ROOT="/path/to/OSM-Notes-Monitoring"
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"

load_all_configs

if check_database_connection; then
    count=$(execute_sql_query "SELECT COUNT(*) FROM notes")
    log_info "Note count: ${count}"
    record_metric "INGESTION" "note_count" "${count}" "component=ingestion"
fi
```

---

## Best Practices

### 1. Gradual Migration

Migrate scripts gradually, starting with new scripts:

- New scripts: Use shared libraries from the start
- Existing scripts: Migrate when making significant changes
- Critical scripts: Test thoroughly before migration

### 2. Maintain Backward Compatibility

Keep existing functionality while adding new features:

```bash
# Support both old and new logging
if command -v log_info > /dev/null; then
    log_info "Using new logging"
else
    echo "INFO: Using old logging"
fi
```

### 3. Error Handling

Always handle library loading errors:

```bash
if ! source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"; then
    echo "ERROR: Failed to load logging library" >&2
    exit 1
fi
```

### 4. Configuration Path

Make PROJECT_ROOT configurable:

```bash
PROJECT_ROOT="${OSM_NOTES_MONITORING_ROOT:-/opt/osm-notes/OSM-Notes-Monitoring}"
```

### 5. Testing

Test migrated scripts thoroughly:

- Test with existing data
- Verify logging output
- Check alert delivery
- Validate metrics collection

---

## Migration Checklist

When migrating a script:

- [ ] Add library source statements
- [ ] Initialize logging with `init_logging`
- [ ] Replace `echo`/`logger` with logging functions
- [ ] Replace email alerts with `send_alert`
- [ ] Add metrics collection with `record_metric`
- [ ] Replace hardcoded config with `load_all_configs`
- [ ] Test script execution
- [ ] Verify log output format
- [ ] Test alert delivery
- [ ] Verify metrics in database
- [ ] Update documentation

---

## Integration Points

### Current Integration (No Modification Required)

OSM-Notes-Monitoring currently calls existing scripts without modification:

```bash
# In monitorIngestion.sh
cd "${INGESTION_REPO_PATH}"
bash "${verifier_script}"
```

### Future Integration (With Shared Libraries)

Scripts can be adapted to use shared libraries for deeper integration:

```bash
# In adapted script
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
log_info "Using shared libraries"
```

---

## Troubleshooting

### Library Not Found

**Problem:** Script can't find shared libraries

**Solution:**

```bash
# Check PROJECT_ROOT path
echo "PROJECT_ROOT: ${PROJECT_ROOT}"

# Verify library exists
ls -la "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
```

### Configuration Not Loading

**Problem:** Configuration variables not available

**Solution:**

```bash
# Load configuration explicitly
load_all_configs

# Verify configuration
validate_all_configs
```

### Logging Not Working

**Problem:** Log messages not appearing

**Solution:**

```bash
# Initialize logging first
init_logging "${LOG_DIR}/script.log" "script_name"

# Check log level
echo "LOG_LEVEL: ${LOG_LEVEL}"

# Check log file permissions
ls -la "${LOG_DIR}/script.log"
```

---

**Last Updated:** 2025-12-24
