---
title: "Integration Changes for OSM-Notes-Ingestion"
description: "Documentation of recommended changes in OSM-Notes-Ingestion for better integration with"
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


# Integration Changes for OSM-Notes-Ingestion

> **Last Updated:** 2025-12-24  
> **Version:** 1.0.0

Documentation of recommended changes in OSM-Notes-Ingestion for better integration with
OSM-Notes-Monitoring.

## Table of Contents

1. [Overview](#overview)
2. [Recommended Changes](#recommended-changes)
3. [Script Modifications](#script-modifications)
4. [Configuration Updates](#configuration-updates)
5. [Testing](#testing)
6. [Migration Plan](#migration-plan)

---

## Overview

This document outlines recommended changes in OSM-Notes-Ingestion to improve integration with
OSM-Notes-Monitoring. These changes are **optional** but recommended for:

- Better monitoring integration
- Consistent logging
- Unified alerting
- Centralized metrics collection

### Current State

OSM-Notes-Monitoring currently calls OSM-Notes-Ingestion scripts without requiring modifications.
Scripts are executed as-is and their output is parsed.

### Future State (Recommended)

With recommended changes, scripts can:

- Use shared logging libraries
- Send alerts through unified system
- Record metrics automatically
- Share configuration

---

## Recommended Changes

### Priority 1: High Impact, Low Risk

#### 1. Add Monitoring Integration Points

Add exit codes and structured output to monitoring scripts:

**File:** `bin/monitor/notesCheckVerifier.sh`

```bash
# Add at the end of script
# Exit codes:
# 0 = Success, no issues
# 1 = Errors found
# 2 = Warnings found
# 3 = Script error

if [[ ${errors_found} -gt 0 ]]; then
    exit 1
elif [[ ${warnings_found} -gt 0 ]]; then
    exit 2
else
    exit 0
fi
```

**File:** `bin/monitor/analyzeDatabasePerformance.sh`

```bash
# Add structured output
echo "METRICS:passes=${pass_count}"
echo "METRICS:failures=${fail_count}"
echo "METRICS:warnings=${warning_count}"
```

#### 2. Standardize Log Output

Ensure log messages follow consistent format:

```bash
# Current (varies)
echo "Error: Something went wrong"
logger "Warning: High rate"

# Recommended (consistent)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Component: Message"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] Component: Message"
```

#### 3. Add Configuration Support

Support environment variables for configuration:

```bash
# Add at top of scripts
INGESTION_REPO_PATH="${INGESTION_REPO_PATH:-/path/to/OSM-Notes-Ingestion}"
LOG_DIR="${LOG_DIR:-/var/log/osm-notes-ingestion}"
```

### Priority 2: Medium Impact, Medium Risk

#### 4. Optional Library Integration

Make library integration optional:

**File:** `bin/monitor/notesCheckVerifier.sh`

```bash
# Add optional library support
if [[ -n "${OSM_NOTES_MONITORING_ROOT}" ]]; then
    MONITORING_ROOT="${OSM_NOTES_MONITORING_ROOT}"
    if [[ -f "${MONITORING_ROOT}/bin/lib/loggingFunctions.sh" ]]; then
        source "${MONITORING_ROOT}/bin/lib/loggingFunctions.sh"
        USE_SHARED_LIBS=true
    fi
fi

# Use shared libraries if available
if [[ "${USE_SHARED_LIBS}" == "true" ]]; then
    log_info "Using shared logging libraries"
else
    echo "INFO: Using standard logging"
fi
```

#### 5. Add Metrics Output

Output metrics in parseable format:

```bash
# Add metrics output
echo "METRIC:component=ingestion,name=processing_duration,value=${duration},unit=seconds"
echo "METRIC:component=ingestion,name=records_processed,value=${count},unit=count"
```

### Priority 3: Low Priority, Optional

#### 6. Full Library Migration

Migrate scripts to use shared libraries (see `docs/ADAPTING_SCRIPTS.md`):

- Replace logging with shared logging functions
- Replace alerting with unified alert system
- Use shared configuration management
- Use shared metrics collection

---

## Script Modifications

### notesCheckVerifier.sh

**Recommended Changes:**

1. **Add exit codes:**

```bash
# At end of script
if [[ ${discrepancies_found} -gt 0 ]]; then
    echo "ERROR: Found ${discrepancies_found} discrepancies"
    exit 1
else
    echo "SUCCESS: No discrepancies found"
    exit 0
fi
```

2. **Add structured output:**

```bash
# Output summary
echo "SUMMARY:discrepancies=${discrepancies_found}"
echo "SUMMARY:notes_checked=${notes_checked}"
echo "SUMMARY:duration=${duration}"
```

3. **Support monitoring integration:**

```bash
# Check if called from monitoring
if [[ -n "${MONITORING_MODE}" ]]; then
    # Output in monitoring format
    echo "MONITORING:status=${status}"
    echo "MONITORING:errors=${errors}"
fi
```

### processCheckPlanetNotes.sh

**Recommended Changes:**

1. **Add progress output:**

```bash
# Add progress indicators
echo "PROGRESS:step=download,status=running"
echo "PROGRESS:step=download,status=complete"
echo "PROGRESS:step=import,status=running"
```

2. **Add timing information:**

```bash
# Add timing
start_time=$(date +%s)
# ... processing ...
end_time=$(date +%s)
duration=$((end_time - start_time))
echo "TIMING:total_duration=${duration}"
```

### analyzeDatabasePerformance.sh

**Recommended Changes:**

1. **Structured output:**

```bash
# Current output (colored, human-readable)
# Add machine-readable output
echo "METRICS:passes=${pass_count},failures=${fail_count},warnings=${warning_count}"
```

2. **Exit codes:**

```bash
# Add exit codes
if [[ ${fail_count} -gt 0 ]]; then
    exit 1
elif [[ ${warning_count} -gt 0 ]]; then
    exit 2
else
    exit 0
fi
```

---

## Configuration Updates

### Add Monitoring Configuration

**File:** `etc/properties.sh` (or similar)

Add optional monitoring configuration:

```bash
# OSM-Notes-Monitoring Integration (optional)
OSM_NOTES_MONITORING_ROOT="${OSM_NOTES_MONITORING_ROOT:-}"
MONITORING_ENABLED="${MONITORING_ENABLED:-false}"

# If monitoring is enabled, use shared libraries
if [[ "${MONITORING_ENABLED}" == "true" ]] && [[ -n "${OSM_NOTES_MONITORING_ROOT}" ]]; then
    export USE_SHARED_LIBS=true
fi
```

### Environment Variables

Support these environment variables:

- `OSM_NOTES_MONITORING_ROOT` - Path to OSM-Notes-Monitoring
- `MONITORING_MODE` - Enable monitoring mode
- `LOG_DIR` - Log directory (can be shared)
- `INGESTION_REPO_PATH` - Self-reference path

---

## Testing

### Test Integration Points

1. **Test exit codes:**

```bash
./bin/monitor/notesCheckVerifier.sh
echo "Exit code: $?"
```

2. **Test structured output:**

```bash
./bin/monitor/analyzeDatabasePerformance.sh | grep "METRICS:"
```

3. **Test monitoring mode:**

```bash
MONITORING_MODE=true ./bin/monitor/notesCheckVerifier.sh
```

### Test Library Integration

1. **Test optional library loading:**

```bash
OSM_NOTES_MONITORING_ROOT="/path/to/OSM-Notes-Monitoring" ./bin/monitor/notesCheckVerifier.sh
```

2. **Verify backward compatibility:**

```bash
# Should work without monitoring
./bin/monitor/notesCheckVerifier.sh
```

---

## Migration Plan

### Phase 1: Non-Breaking Changes (Week 1)

1. Add exit codes to scripts
2. Add structured output
3. Add environment variable support
4. Test with OSM-Notes-Monitoring

### Phase 2: Optional Integration (Week 2)

1. Add optional library loading
2. Add monitoring mode support
3. Test library integration
4. Document usage

### Phase 3: Full Integration (Future)

1. Migrate to shared libraries (optional)
2. Use unified configuration
3. Use unified alerting
4. Use unified metrics

---

## Implementation Checklist

For each script in `bin/monitor/`:

- [ ] Add exit codes (0=success, 1=error, 2=warning)
- [ ] Add structured output (METRICS:, SUMMARY:, PROGRESS:)
- [ ] Add environment variable support
- [ ] Add optional library loading
- [ ] Test backward compatibility
- [ ] Test monitoring integration
- [ ] Update documentation

---

## Backward Compatibility

**Important:** All changes must maintain backward compatibility:

1. Scripts must work without monitoring
2. Scripts must work with existing configurations
3. Scripts must produce same results
4. Only add new features, don't remove existing ones

### Example: Optional Feature

```bash
# Feature is optional
if [[ -n "${MONITORING_MODE}" ]]; then
    # New monitoring features
    echo "MONITORING:status=..."
else
    # Existing behavior
    echo "Status: ..."
fi
```

---

## Benefits Summary

### For OSM-Notes-Ingestion

- Better monitoring visibility
- Consistent logging format
- Unified alerting
- Centralized metrics

### For OSM-Notes-Monitoring

- Better integration
- More reliable monitoring
- Richer metrics
- Better alerting

### For Operations

- Single monitoring dashboard
- Unified alerting
- Consistent logging
- Better troubleshooting

---

## Next Steps

1. **Review this document** with OSM-Notes-Ingestion maintainers
2. **Prioritize changes** based on needs
3. **Implement Phase 1** (non-breaking changes)
4. **Test integration** with OSM-Notes-Monitoring
5. **Iterate** based on feedback

---

## Questions?

For questions about integration changes:

- See `docs/ADAPTING_SCRIPTS.md` for library migration guide
- See `docs/Existing_Monitoring_Components.md` for current integration
- Contact OSM-Notes-Monitoring maintainers

---

**Last Updated:** 2025-12-24
