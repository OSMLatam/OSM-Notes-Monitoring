---
title: "Logging Best Practices"
description: "Comprehensive guide to logging best practices for OSM-Notes-Monitoring."
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


# Logging Best Practices

> **Last Updated:** 2025-12-24  
> **Version:** 1.0.0

Comprehensive guide to logging best practices for OSM-Notes-Monitoring.

## Table of Contents

1. [Log Level Guidelines](#log-level-guidelines)
2. [Message Format](#message-format)
3. [Context and Information](#context-and-information)
4. [Security Considerations](#security-considerations)
5. [Performance Best Practices](#performance-best-practices)
6. [Error Handling](#error-handling)
7. [Component-Specific Guidelines](#component-specific-guidelines)
8. [Common Patterns](#common-patterns)
9. [Anti-Patterns](#anti-patterns)
10. [Code Examples](#code-examples)

---

## Log Level Guidelines

### When to Use Each Level

#### DEBUG

Use DEBUG for detailed diagnostic information that is only useful during development or
troubleshooting.

**Use cases:**

- Function entry/exit points
- Variable values and state
- Detailed execution flow
- API request/response details (non-sensitive)
- Database query details

**Example:**

```bash
log_debug "Processing note ${note_id}"
log_debug "Database query: SELECT * FROM notes WHERE id=${note_id}"
log_debug "Response time: ${response_time}ms"
```

**Guidelines:**

- Never log sensitive information (passwords, tokens, API keys)
- Keep DEBUG logs concise
- Use DEBUG sparingly in production (enable only when needed)

#### INFO

Use INFO for general informational messages about normal operation.

**Use cases:**

- Component startup/shutdown
- Successful operations
- Status updates
- Configuration changes
- Health check results
- Scheduled task execution

**Example:**

```bash
log_info "Monitoring started for component: ${component}"
log_info "Health check passed: ${component} (response_time=${time}ms)"
log_info "Configuration loaded: ${config_file}"
```

**Guidelines:**

- Use INFO for events that are important but not errors
- Include relevant metrics (response times, counts, etc.)
- Keep messages clear and actionable

#### WARNING

Use WARNING for potentially problematic situations that don't prevent operation.

**Use cases:**

- Recoverable errors
- Degraded performance
- Configuration issues
- Resource usage approaching limits
- Deprecated feature usage
- Retry attempts

**Example:**

```bash
log_warning "High error rate detected: ${error_rate}% (threshold=${threshold}%)"
log_warning "Response time above threshold: ${response_time}ms (threshold=${threshold}ms)"
log_warning "Retrying operation (attempt ${attempt}/${max_attempts})"
```

**Guidelines:**

- Warnings should indicate something that needs attention
- Include context about why it's a warning
- Provide actionable information

#### ERROR

Use ERROR for failures that need immediate attention.

**Use cases:**

- Component failures
- Database connection errors
- Critical system errors
- Unrecoverable errors
- Security violations
- Data corruption

**Example:**

```bash
log_error "Failed to connect to database: ${error} (host=${DBHOST}, port=${DBPORT})"
log_error "Component ${component} is down: ${error_message}"
log_error "Data validation failed: ${validation_error}"
```

**Guidelines:**

- Always include error details
- Include context (what was being done, relevant parameters)
- Use ERROR sparingly (only for actual errors)

---

## Message Format

### Standard Format

All log messages should follow this format:

```
[LEVEL] Component: Action - Details
```

**Example:**

```bash
log_info "INGESTION: Processing batch - batch_id=${batch_id}, size=${size}, duration=${duration}ms"
log_error "DATABASE: Connection failed - host=${host}, error=${error}"
```

### Structured Logging

Include structured data in log messages:

```bash
# Good: Structured data
log_info "Health check: component=${component} status=${status} response_time=${time}ms errors=${errors}"

# Bad: Unstructured
log_info "Health check passed"
```

### Timestamp Format

Timestamps are automatically added by the logging system:

- Format: `YYYY-MM-DD HH:MM:SS`
- Timezone: System timezone (use UTC in production)

---

## Context and Information

### Always Include Context

**Good:**

```bash
log_error "Database query failed: query='${query}', error='${error}', host='${DBHOST}', database='${DBNAME}'"
```

**Bad:**

```bash
log_error "Query failed"
```

### Include Relevant Metrics

**Good:**

```bash
log_info "Batch processed: batch_id=${batch_id}, items=${count}, duration=${duration}ms, errors=${errors}"
```

**Bad:**

```bash
log_info "Batch processed"
```

### Use Meaningful Variable Names

**Good:**

```bash
log_info "Processing ingestion batch: batch_id=${batch_id}, source=${source_repo}"
```

**Bad:**

```bash
log_info "Processing: id=${id}, src=${src}"
```

---

## Security Considerations

### Never Log Sensitive Information

**Never log:**

- Passwords
- API keys
- Authentication tokens
- Credit card numbers
- Personal identifiable information (PII)
- Database credentials

**Example:**

```bash
# Good
log_info "Connecting to database: host=${DBHOST}, port=${DBPORT}, user=${DBUSER}"

# Bad
log_info "Connecting to database: password=${DBPASSWORD}"
```

### Sanitize User Input

Sanitize user input before logging to prevent log injection:

```bash
# Sanitize user input
local sanitized_input
sanitized_input=$(echo "${user_input}" | tr -d '\n\r')
log_info "User input: ${sanitized_input}"
```

### Log Security Events

Always log security-related events:

```bash
log_warning "SECURITY: Rate limit exceeded - ip=${ip}, endpoint=${endpoint}, count=${count}"
log_error "SECURITY: Authentication failed - user=${user}, ip=${ip}, reason=${reason}"
log_error "SECURITY: Unauthorized access attempt - ip=${ip}, endpoint=${endpoint}"
```

---

## Performance Best Practices

### Avoid Excessive Logging

**Guidelines:**

- Don't log in tight loops
- Use appropriate log levels (DEBUG for verbose, INFO for important)
- Consider performance impact of logging

**Example:**

```bash
# Bad: Logging in tight loop
for item in "${items[@]}"; do
    log_debug "Processing item: ${item}"  # Too verbose
done

# Good: Log summary
log_info "Processing ${#items[@]} items"
for item in "${items[@]}"; do
    # Process item
done
log_info "Processed ${#items[@]} items in ${duration}ms"
```

### Use Conditional Logging

Only log when necessary:

```bash
# Only log if level allows
if [[ ${LOG_LEVEL} -le ${LOG_LEVEL_DEBUG} ]]; then
    log_debug "Expensive operation: ${expensive_computation}"
fi
```

### Batch Log Operations

For high-volume operations, batch log messages:

```bash
# Bad: Individual log per item
for item in "${items[@]}"; do
    log_info "Processed: ${item}"
done

# Good: Batch summary
local processed=0
for item in "${items[@]}"; do
    # Process item
    processed=$((processed + 1))
done
log_info "Processed ${processed} items"
```

---

## Error Handling

### Always Log Errors

Never silently fail:

```bash
# Bad
if ! operation; then
    return 1  # No logging!
fi

# Good
if ! operation; then
    log_error "Operation failed: ${error}"
    return 1
fi
```

### Include Error Context

Always include context when logging errors:

```bash
log_error "Database connection failed: error='${error}', host='${DBHOST}', port='${DBPORT}', database='${DBNAME}'"
```

### Log Error Recovery

Log when errors are recovered:

```bash
if ! operation; then
    log_warning "Operation failed, retrying: attempt=${attempt}, error=${error}"
    if retry_operation; then
        log_info "Operation recovered after retry: attempt=${attempt}"
    else
        log_error "Operation failed after retries: attempts=${attempt}, error=${error}"
    fi
fi
```

### Use Appropriate Error Levels

```bash
# Recoverable error -> WARNING
log_warning "Temporary failure, will retry: ${error}"

# Unrecoverable error -> ERROR
log_error "Permanent failure: ${error}"
```

---

## Component-Specific Guidelines

### Monitoring Components

**Startup:**

```bash
log_info "MONITORING: Starting ${component} monitoring"
log_info "MONITORING: Configuration loaded - interval=${interval}s, timeout=${timeout}s"
```

**Health Checks:**

```bash
log_info "MONITORING: Health check - component=${component}, status=${status}, response_time=${time}ms"
log_warning "MONITORING: Health check degraded - component=${component}, response_time=${time}ms (threshold=${threshold}ms)"
log_error "MONITORING: Health check failed - component=${component}, error=${error}"
```

**Shutdown:**

```bash
log_info "MONITORING: Shutting down ${component} monitoring"
```

### Security Components

**Rate Limiting:**

```bash
log_warning "SECURITY: Rate limit exceeded - ip=${ip}, endpoint=${endpoint}, count=${count}/${limit}"
log_error "SECURITY: IP blocked - ip=${ip}, reason=${reason}, duration=${duration}"
```

**Authentication:**

```bash
log_info "SECURITY: Authentication successful - user=${user}, ip=${ip}"
log_warning "SECURITY: Authentication failed - user=${user}, ip=${ip}, reason=${reason}"
log_error "SECURITY: Multiple authentication failures - user=${user}, ip=${ip}, count=${count}"
```

### Database Operations

**Connections:**

```bash
log_info "DATABASE: Connected - host=${DBHOST}, database=${DBNAME}"
log_error "DATABASE: Connection failed - host=${DBHOST}, error=${error}"
```

**Queries:**

```bash
log_debug "DATABASE: Executing query - query='${query}'"
log_info "DATABASE: Query completed - rows=${rows}, duration=${duration}ms"
log_error "DATABASE: Query failed - query='${query}', error=${error}"
```

---

## Common Patterns

### Function Entry/Exit

```bash
function process_data() {
    log_debug "process_data: Entry - input_size=${#input[@]}"

    # Process data

    log_debug "process_data: Exit - output_size=${#output[@]}, duration=${duration}ms"
}
```

### Operation Start/End

```bash
log_info "OPERATION: Starting batch processing - batch_id=${batch_id}, size=${size}"
# Process batch
log_info "OPERATION: Batch processing completed - batch_id=${batch_id}, processed=${processed}, errors=${errors}, duration=${duration}ms"
```

### Retry Logic

```bash
local attempt=1
while [[ ${attempt} -le ${max_attempts} ]]; do
    if operation; then
        log_info "Operation succeeded on attempt ${attempt}"
        break
    else
        log_warning "Operation failed on attempt ${attempt}/${max_attempts}: ${error}"
        attempt=$((attempt + 1))
        sleep "${retry_delay}"
    fi
done

if [[ ${attempt} -gt ${max_attempts} ]]; then
    log_error "Operation failed after ${max_attempts} attempts: ${error}"
fi
```

### Configuration Loading

```bash
log_info "CONFIG: Loading configuration - file=${config_file}"
if load_config "${config_file}"; then
    log_info "CONFIG: Configuration loaded successfully - components=${#components[@]}"
else
    log_error "CONFIG: Failed to load configuration - file=${config_file}, error=${error}"
fi
```

---

## Anti-Patterns

### ❌ Don't Log Sensitive Information

```bash
# Bad
log_info "User password: ${password}"
log_debug "API key: ${api_key}"
```

### ❌ Don't Log Without Context

```bash
# Bad
log_error "Failed"
log_info "Done"
```

### ❌ Don't Log in Tight Loops

```bash
# Bad
for i in {1..10000}; do
    log_debug "Iteration ${i}"
done
```

### ❌ Don't Use Wrong Log Levels

```bash
# Bad: Using ERROR for non-errors
log_error "Processing started"  # Should be INFO

# Bad: Using INFO for errors
log_info "Operation failed"  # Should be ERROR
```

### ❌ Don't Log Empty Messages

```bash
# Bad
log_info ""
log_error "   "
```

### ❌ Don't Log Without Error Handling

```bash
# Bad: Logging might fail
echo "${message}" >> "${LOG_FILE}"

# Good: Use logging functions
log_info "${message}"
```

---

## Code Examples

### Complete Example: Monitoring Function

```bash
function monitor_component() {
    local component="${1}"
    local timeout="${2:-30}"

    log_info "MONITORING: Starting health check - component=${component}, timeout=${timeout}s"

    local start_time
    start_time=$(date +%s)

    if check_health "${component}" "${timeout}"; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_info "MONITORING: Health check passed - component=${component}, duration=${duration}s"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local error="${?}"

        log_error "MONITORING: Health check failed - component=${component}, duration=${duration}s, error=${error}"
        return 1
    fi
}
```

### Complete Example: Error Handling

```bash
function process_batch() {
    local batch_id="${1}"
    local items=("${@:2}")

    log_info "BATCH: Processing started - batch_id=${batch_id}, items=${#items[@]}"

    local processed=0
    local errors=0

    for item in "${items[@]}"; do
        if process_item "${item}"; then
            processed=$((processed + 1))
            log_debug "BATCH: Item processed - batch_id=${batch_id}, item=${item}"
        else
            errors=$((errors + 1))
            log_warning "BATCH: Item failed - batch_id=${batch_id}, item=${item}, error=${error}"
        fi
    done

    log_info "BATCH: Processing completed - batch_id=${batch_id}, processed=${processed}, errors=${errors}, total=${#items[@]}"

    if [[ ${errors} -gt 0 ]]; then
        log_warning "BATCH: Completed with errors - batch_id=${batch_id}, error_rate=$((errors * 100 / ${#items[@]}))%"
        return 1
    fi

    return 0
}
```

### Complete Example: Configuration Loading

```bash
function load_configuration() {
    local config_file="${1}"

    log_info "CONFIG: Loading configuration - file=${config_file}"

    if [[ ! -f "${config_file}" ]]; then
        log_error "CONFIG: Configuration file not found - file=${config_file}"
        return 1
    fi

    # Source configuration
    if source "${config_file}" 2>&1; then
        log_info "CONFIG: Configuration loaded - file=${config_file}"

        # Validate configuration
        if validate_config; then
            log_info "CONFIG: Configuration validated successfully"
            return 0
        else
            log_error "CONFIG: Configuration validation failed - file=${config_file}"
            return 1
        fi
    else
        log_error "CONFIG: Failed to load configuration - file=${config_file}, error=${error}"
        return 1
    fi
}
```

---

## Summary Checklist

When writing log statements, ensure:

- [ ] Appropriate log level is used
- [ ] Message includes relevant context
- [ ] No sensitive information is logged
- [ ] Message is clear and actionable
- [ ] Structured data is included when relevant
- [ ] Performance impact is considered
- [ ] Errors are always logged
- [ ] Component name is included
- [ ] Timestamps are accurate (handled automatically)
- [ ] Log messages follow standard format

---

**Last Updated:** 2025-12-24
