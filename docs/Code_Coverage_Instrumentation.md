---
title: "Code Coverage Instrumentation Guide"
description: "This guide explains how to use the `bashcov` code instrumentation tool to measure actual code"
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


# Code Coverage Instrumentation Guide

## Overview

This guide explains how to use the `bashcov` code instrumentation tool to measure **actual code
coverage** for Bash scripts, rather than relying on estimates based on test file presence.

## Why Instrumentation?

The current `generate_coverage_report.sh` script provides **estimated coverage** based on:

- Presence of test files
- Number of test files per script
- Heuristic calculations

**Instrumentation tools** provide **real coverage** by:

- Tracking which lines of code are actually executed during tests
- Identifying untested code paths
- Providing detailed HTML reports showing covered/uncovered lines
- Generating accurate coverage percentages

## Quick Start

### Installation

**Install bashcov:**

```bash
gem install bashcov
```

**Or use the installation script:**

```bash
./scripts/install_coverage_tools.sh bashcov
```

## bashcov

**bashcov** is a Ruby-based coverage tool specifically for Bash scripts.

**Advantages:**

- Works well with source-based tests (tests that use `source` to load libraries)
- Ruby-based (easy to install via gem)
- Good integration with test frameworks
- Detailed coverage reports

**Installation:**

```bash
# Requires Ruby and RubyGems
gem install bashcov
```

## Usage

### Automated Report Generation

**Generate coverage report (runs all tests):**

```bash
bash scripts/generate_coverage_instrumented_optimized.sh
```

**Run in background and monitor:**

```bash
# Start bashcov in background
bash scripts/run_bashcov_background.sh start

# Monitor progress
bash scripts/monitor_bashcov.sh

# Check status
bash scripts/run_bashcov_background.sh status

# Stop if needed
bash scripts/run_bashcov_background.sh stop
```

### Manual Usage

```bash
# Run single test file with bashcov
bashcov --root /path/to/project --skip-uncovered bats tests/unit/lib/test_monitoringFunctions.sh

# Run all tests
cd /path/to/project
find tests -name "*.sh" -type f | while read test_file; do
    bashcov --root . --skip-uncovered bats "${test_file}"
done
```

## Understanding Reports

### bashcov Report Format

bashcov generates a `.resultset.json` file in SimpleCov format:

- Location: `coverage/.resultset.json`
- Format: JSON with coverage data per file
- Coverage data: Array indicating which lines were executed

### Coverage Report

The script generates a text report at:

- `coverage/coverage_report_instrumented.txt`

This report shows:

- Coverage percentage per script
- Number of test files
- Overall average coverage
- Status indicators (✓/⚠/✗)

## Limitations

### Source-based Tests

This project uses source-based tests (tests that `source` library files directly). bashcov works
well with this architecture as it can track coverage when libraries are sourced.

### Mock Functions

Many tests use mock functions (e.g., `psql`, `curl`, `mutt`). This means:

- The actual external commands are not executed
- Coverage shows which code paths are tested, not necessarily which external commands are called
- This is expected behavior for unit tests

## Troubleshooting

### Issue: bashcov not found

**Solution:**

```bash
gem install bashcov
```

### Issue: bashcov is slow

**Solution:**

- This is expected - bashcov processes all tests sequentially
- Use the background script: `bash scripts/run_bashcov_background.sh start`
- Monitor progress: `bash scripts/monitor_bashcov.sh`

### Issue: Coverage shows 0%

**Possible causes:**

1. Tests use extensive mocks (expected)
2. Code only runs in production mode (not TEST_MODE)
3. Dependencies not available during tests

**Solution:**

- Review the estimated coverage report instead
- Check that tests are actually executing code paths
- Consider adding integration tests that run real code

## Best Practices

1. **Use estimated coverage for quick checks** - `generate_coverage_report.sh` is fast
2. **Use bashcov for detailed analysis** - Run periodically or before releases
3. **Run bashcov in background** - It takes time, use the background script
4. **Review coverage gaps** - Focus on critical paths and error handling
5. **Don't rely solely on coverage** - High coverage doesn't guarantee quality

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run coverage with bashcov
  run: |
    gem install bashcov
    bash scripts/generate_coverage_instrumented_optimized.sh
  continue-on-error: true # Don't fail build if coverage is low
```

## References

- [bashcov GitHub](https://github.com/infertux/bashcov)
- [SimpleCov Documentation](https://github.com/simplecov-ruby/simplecov)
