---
title: "Coding Standards - OSM-Notes-Monitoring"
description: "Every script must start with:"
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


# Coding Standards - OSM-Notes-Monitoring

> **Purpose:** Coding standards and best practices for the project  
> **Version:** 2025-12-24

## Table of Contents

1. [Bash Scripting Standards](#bash-scripting-standards)
2. [SQL Standards](#sql-standards)
3. [Configuration Standards](#configuration-standards)
4. [Documentation Standards](#documentation-standards)
5. [Error Handling](#error-handling)
6. [Logging Standards](#logging-standards)
7. [Testing Standards](#testing-standards)

## Bash Scripting Standards

### Script Header

Every script must start with:

```bash
#!/usr/bin/env bash
#
# Script Name: script_name.sh
# Description: Brief description of what the script does
# Author: Your Name
# Version: 1.0.0
# Date: YYYY-MM-DD
#
# Usage: ./script_name.sh [options] [arguments]
# Example: ./script_name.sh --verbose
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
```

### Error Handling

Always use strict error handling:

```bash
set -euo pipefail

# -e: Exit immediately if a command exits with a non-zero status
# -u: Treat unset variables as an error
# -o pipefail: Return value of a pipeline is the status of the last command to exit with a non-zero status
```

### Variable Naming

- Use `UPPER_CASE` for constants and environment variables
- Use `lower_case` for local variables
- Use descriptive names: `last_check_time` not `lct`
- Prefix internal variables with `_`: `_internal_var`

```bash
# Good
readonly MAX_RETRIES=3
local last_check_time
local _internal_counter

# Bad
maxRetries=3
lct=$(date)
```

### Function Standards

```bash
# Function naming: verb_noun format
# Use descriptive names
# Maximum 50 lines per function
# Document parameters and return values

##
# Check if a service is healthy
#
# Arguments:
#   $1 - Service URL to check
#   $2 - Timeout in seconds (default: 10)
#
# Returns:
#   0 if healthy, 1 if unhealthy
#
# Example:
#   check_service_health "http://localhost:8080/health" 5
##
check_service_health() {
    local service_url="${1:?Service URL required}"
    local timeout="${2:-10}"

    if curl -f -s --max-time "${timeout}" "${service_url}" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
```

### Code Organization

1. **Script structure:**

   ```bash
   #!/usr/bin/env bash
   # Header comments

   set -euo pipefail

   # Source configuration
   source "$(dirname "$0")/../etc/properties.sh"
   source "$(dirname "$0")/../bin/lib/monitoringFunctions.sh"

   # Constants
   readonly SCRIPT_NAME="$(basename "$0")"
   readonly MAX_RETRIES=3

   # Functions (in order of use)
   # - Helper functions first
   # - Main functions next
   # - Main execution last

   # Main execution
   main() {
       # Script logic here
   }

   # Run main if script is executed directly
   if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
       main "$@"
   fi
   ```

2. **Function order:**
   - Helper/utility functions first
   - Business logic functions next
   - Main function last

### Code Quality Rules

1. **Maximum line length:** 100 characters
2. **Maximum function length:** 50 lines
3. **Maximum file length:** 500 lines (split if exceeded)
4. **Indentation:** 4 spaces (no tabs)
5. **Quoting:** Always quote variables: `"${var}"` not `${var}`
6. **Arrays:** Use `"${array[@]}"` for iteration
7. **Command substitution:** Use `$(command)` not backticks

### ShellCheck Compliance

All scripts must pass `shellcheck` validation:

```bash
# Run shellcheck
shellcheck script_name.sh

# Or use in CI/CD
shellcheck --severity=error --format=gcc script_name.sh
```

Common issues to avoid:

- Unquoted variables
- Unused variables
- Missing shebang
- Using `$?` after `set -e`
- Using `[` instead of `[[`

## SQL Standards

### Query Formatting

```sql
-- Use consistent indentation
-- Comment complex queries
-- Use UPPER_CASE for SQL keywords
-- Use snake_case for identifiers

SELECT
    component,
    metric_name,
    AVG(metric_value) AS avg_value,
    COUNT(*) AS sample_count
FROM metrics
WHERE
    timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
    AND component = 'ingestion'
GROUP BY
    component,
    metric_name
ORDER BY avg_value DESC;
```

### Naming Conventions

- **Tables:** `snake_case`, plural: `security_events`, `component_health`
- **Columns:** `snake_case`: `ip_address`, `created_at`
- **Indexes:** `idx_<table>_<columns>`: `idx_metrics_component_timestamp`
- **Functions:** `snake_case`: `cleanup_old_metrics`
- **Constants:** `UPPER_CASE`: `MAX_RETENTION_DAYS`

### Best Practices

1. **Always use transactions** for multi-statement operations
2. **Use parameterized queries** when possible (via scripts)
3. **Add indexes** for frequently queried columns
4. **Document complex queries** with comments
5. **Use EXPLAIN ANALYZE** to optimize queries
6. **Avoid SELECT \*** in production queries

### Example

```sql
-- Get recent metrics for a component
-- This query retrieves the last 24 hours of metrics
-- grouped by metric name with average values
SELECT
    component,
    metric_name,
    AVG(metric_value) AS avg_value,
    MIN(metric_value) AS min_value,
    MAX(metric_value) AS max_value,
    COUNT(*) AS sample_count,
    MAX(timestamp) AS last_updated
FROM metrics
WHERE
    component = $1  -- Parameterized
    AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY
    component,
    metric_name
ORDER BY
    metric_name;
```

## Configuration Standards

### Configuration File Format

```bash
# Configuration file: config/component.conf
# Version: 1.0.0
# Last Updated: 2025-12-24

# Section: Component Settings
COMPONENT_ENABLED=true
COMPONENT_TIMEOUT=30

# Section: Thresholds
ERROR_RATE_THRESHOLD=5
RESPONSE_TIME_THRESHOLD=1000

# Section: Advanced (optional)
# ADVANCED_OPTION="value"
```

### Configuration Validation

Always validate configuration:

```bash
validate_config() {
    local config_file="${1:?Config file required}"

    # Check file exists
    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        return 1
    fi

    # Source and validate
    source "${config_file}"

    # Validate required variables
    if [[ -z "${COMPONENT_ENABLED:-}" ]]; then
        log_error "COMPONENT_ENABLED not set in ${config_file}"
        return 1
    fi

    return 0
}
```

## Documentation Standards

### Function Documentation

Every function must have:

```bash
##
# Brief description (one line)
#
# Longer description if needed (multiple lines)
#
# Arguments:
#   $1 - Description of first argument
#   $2 - Description of second argument (optional)
#
# Returns:
#   0 on success
#   1 on failure
#
# Example:
#   function_name "arg1" "arg2"
#
# Side effects:
#   - Logs to monitoring.log
#   - Updates database
##
```

### Script Documentation

Every script must have:

- Header with description, usage, examples
- Exit codes documented
- Dependencies listed
- Configuration requirements
- Examples

### README Files

Each major directory should have a README.md:

```markdown
# Directory Name

## Purpose

Brief description of what's in this directory.

## Structure

- `file1.sh` - Description
- `file2.sh` - Description

## Usage

Examples of how to use files in this directory.

## Dependencies

List of dependencies.

## Examples

Code examples.
```

## Error Handling

### Error Codes

Use consistent exit codes:

```bash
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_ARGUMENT=2
readonly EXIT_MISSING_DEPENDENCY=3
readonly EXIT_CONFIG_ERROR=4
readonly EXIT_DATABASE_ERROR=5
readonly EXIT_NETWORK_ERROR=6
```

### Error Handling Pattern

```bash
handle_error() {
    local exit_code="${1:-1}"
    local error_message="${2:-Unknown error}"

    log_error "${error_message}"
    cleanup_on_error
    exit "${exit_code}"
}

# Usage
if ! check_dependency; then
    handle_error "${EXIT_MISSING_DEPENDENCY}" "Required dependency not found"
fi
```

## Logging Standards

### Log Levels

```bash
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Log functions
log_debug() { log_message "DEBUG" "$@"; }
log_info() { log_message "INFO" "$@"; }
log_warning() { log_message "WARNING" "$@"; }
log_error() { log_message "ERROR" "$@"; }
```

### Log Format

```bash
# Format: TIMESTAMP [LEVEL] SCRIPT_NAME: MESSAGE
# Example: 2025-12-24 10:30:45 [INFO] monitorIngestion.sh: Check completed successfully

log_message() {
    local level="${1:?Log level required}"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "${timestamp} [${level}] ${SCRIPT_NAME}: ${message}" >> "${LOG_FILE}"
}
```

### Structured Logging

For complex systems, use structured logging:

```bash
log_structured() {
    local level="${1}"
    shift
    local json_data
    json_data=$(jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg level "${level}" \
        --arg script "${SCRIPT_NAME}" \
        --arg message "$*" \
        '{timestamp: $timestamp, level: $level, script: $script, message: $message}')

    echo "${json_data}" >> "${LOG_FILE}"
}
```

## Testing Standards

### Test File Structure

```bash
#!/usr/bin/env bash
#
# Test: test_script_name.sh
# Description: Tests for script_name.sh
#

load "$(dirname "$0")/../tests/test_helper.bash"

@test "test description" {
    # Arrange
    local expected="value"

    # Act
    local actual=$(function_to_test "input")

    # Assert
    assert_equal "${expected}" "${actual}"
}
```

### Test Naming

- Test files: `test_<script_name>.sh`
- Test functions: `@test "description"`
- Use descriptive test names
- One assertion per test (when possible)

### Test Coverage

- Aim for >80% code coverage
- Test all error paths
- Test edge cases
- Test with invalid inputs

---

**Last Updated:** 2025-12-24  
**Maintainer:** Andres Gomez (AngocA)
