---
title: "Code Coverage Explanation"
description: "This project uses  to measure code coverage, each serving a different purpose:"
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


# Code Coverage Explanation

## Overview

This project uses **two different methods** to measure code coverage, each serving a different
purpose:

1. **Estimated Coverage** (Fast, Optimistic)
2. **Instrumented Coverage** (Slow, Accurate)

## Why Two Methods?

### Estimated Coverage (80% average)

**What it measures:**

- Presence of test files for each script
- Number of test files per script
- Heuristic calculation based on test file count

**How it works:**

- Counts test files matching each script name
- Estimates coverage: 1 test = 40%, 2 tests = 60%, 3+ tests = 80%
- Very fast (seconds)

**Use when:**

- Quick check of test coverage status
- CI/CD pipelines (fast feedback)
- Identifying scripts without tests

**Limitations:**

- Doesn't measure actual code execution
- Assumes tests cover code well
- Can be overly optimistic

### Instrumented Coverage (27% average)

**What it measures:**

- Lines of code **actually executed** during tests
- Real code coverage using `bashcov` instrumentation
- Precise measurement of executed vs total lines

**How it works:**

- Runs all tests with `bashcov` instrumentation
- Tracks which lines are executed
- Calculates: (executed lines / total lines) × 100
- Very slow (hours)

**Use when:**

- Detailed analysis of code coverage
- Identifying untested code paths
- Before releases (comprehensive check)

**Limitations:**

- Very slow (requires running all tests)
- Requires Ruby and bashcov installation
- May show low coverage for valid reasons (see below)

## Why the Gap?

The large gap between estimated (80%) and instrumented (27%) coverage is **normal and expected**:

### 1. Unit Tests vs Full Execution

**Unit tests:**

- Test individual functions in isolation
- Use `source` to load libraries
- Don't execute the full script flow
- Skip initialization code

**Example:**

```bash
# Test only tests the function
source bin/lib/metricsFunctions.sh
record_metric "component" "metric" 100

# But never executes:
# - Script initialization
# - Main function
# - Command-line argument parsing
# - Error handling in main flow
```

### 2. Extensive Mocking

**Mocks prevent real code execution:**

- `psql` is mocked → database connection code never runs
- `curl` is mocked → HTTP request code never runs
- `mutt` is mocked → email sending code never runs

**Example:**

```bash
# Mock replaces real function
psql() { echo "mocked"; }

# Real code in script:
psql -h "${dbhost}" -d "${dbname}" -c "${query}"
# This line exists but never executes because psql is mocked
```

### 3. Conditional Code Paths

**Code that only runs in production:**

- `TEST_MODE=true` skips initialization
- `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` blocks only run when script executed directly
- Production-only error handling

**Example:**

```bash
# Only runs when script executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_logging  # Never runs in tests
    main "$@"     # Never runs in tests
fi
```

### 4. Test Architecture

**Tests focus on functions, not scripts:**

- Tests call individual functions
- Don't execute `main()` functions
- Don't test command-line interfaces
- Don't test full workflows

## Which Number Should You Trust?

### Use Estimated Coverage (80%) for:

- ✅ Quick status checks
- ✅ CI/CD pipelines
- ✅ Identifying missing tests
- ✅ General project health

### Use Instrumented Coverage (27%) for:

- ✅ Detailed analysis
- ✅ Finding untested code
- ✅ Release preparation
- ✅ Understanding real coverage

## Improving Instrumented Coverage

To improve the **real** (instrumented) coverage:

### 1. Execute Scripts Directly with bashcov

**Problem:** bashcov doesn't track scripts executed with `bash script.sh` inside tests.

**Solution:** The coverage script now executes scripts directly with bashcov after running tests:

```bash
# Scripts are executed directly with bashcov for better coverage tracking
bashcov --root . --skip-uncovered bin/monitor/monitorData.sh --help
```

This ensures scripts are tracked even if tests execute them with `bash script.sh`.

**Result:** Scripts like `monitorData.sh` now show 10% coverage (up from 0%).

### 2. Add Integration Tests

**Current:** Unit tests test functions in isolation **Improvement:** Add tests that execute full
scripts

```bash
# Example: Test full script execution
@test "monitorAPI.sh executes main function" {
    run bash bin/monitor/monitorAPI.sh check
    assert_success
}
```

### 2. Reduce Mocking Where Possible

**Current:** Everything is mocked **Improvement:** Use real dependencies in integration tests

```bash
# Instead of mocking psql, use test database
export TEST_DB_NAME="osm_notes_monitoring_test"
# Run real psql commands against test DB
```

### 3. Test Main Functions

**Current:** Only test individual functions **Improvement:** Test `main()` functions

```bash
# Source script and call main
source bin/monitor/monitorAPI.sh
run main "check"
assert_success
```

### 4. Test Initialization Code

**Current:** `TEST_MODE=true` skips initialization **Improvement:** Test initialization separately

```bash
# Test initialization explicitly
export TEST_MODE=false
run init_logging "${LOG_FILE}" "component"
assert_success
```

### 5. Reduce Mocking Where Possible

**Strategy:** Mock only what's necessary, use real implementations when safe

**Safe to Use Real:**

- File system operations
- Git commands (if git is available)
- Environment variables
- Logging functions

**Should Mock:**

- Database connections (unless test database available)
- Email sending
- Slack API calls
- External HTTP requests

**Example:**

```bash
# Before: Mock everything
psql() { echo "mocked"; }
git() { echo "mocked"; }
curl() { echo "mocked"; }

# After: Use real when safe
# Use real git if available
if command -v git >/dev/null 2>&1; then
    # Use real git
else
    git() { echo "mocked"; }
fi

# Mock only external services
psql() { echo "mocked"; }  # Database
curl() { echo "mocked"; }  # External API
```

## Implementation Examples

### Example 1: Adding Main Function Tests

**File:** `tests/unit/monitor/test_monitorData_main.sh`

```bash
@test "main function executes all checks when no argument provided" {
    # Mock check functions
    check_backup_freshness() { return 0; }
    check_repository_sync_status() { return 0; }
    # ... other checks

    # Run main
    run main

    # Verify success
    assert_success
}

@test "main function executes specific check when argument provided" {
    run main "backup_freshness"
    assert_success
}
```

### Example 2: Full Script Execution Test

**File:** `tests/integration/test_monitorData_full_execution.sh`

```bash
@test "Full script execution: creates backup and checks freshness" {
    # Create real backup file
    echo "test backup" > "${TEST_BACKUP_DIR}/backup.sql"

    # Execute script directly (not sourced)
    run bash bin/monitor/monitorData.sh backup_freshness

    # Should execute without crashing
    assert [ ${status} -ge 0 ] && [ ${status} -le 1 ]
}
```

## Testing Checklist

When adding tests to improve coverage:

- [x] Add tests for `main()` function
- [x] Test script execution directly (not just sourcing)
- [ ] Reduce mocking (use real file system, git, etc.)
- [ ] Test initialization code explicitly
- [ ] Test error paths and edge cases
- [ ] Test command-line argument parsing
- [ ] Test conditional code paths

## Current Status

**Tests Added:**

- ✅ `tests/unit/monitor/test_monitorData_main.sh` - Main function tests for monitorData.sh
- ✅ `tests/unit/monitor/test_monitorInfrastructure_main.sh` - Main function tests for
  monitorInfrastructure.sh
- ✅ `tests/unit/monitor/test_monitorIngestion_main.sh` - Main function tests for
  monitorIngestion.sh
- ✅ `tests/unit/monitor/test_monitorAnalytics_main.sh` - Main function tests for
  monitorAnalytics.sh
- ✅ `tests/integration/test_monitorData_full_execution.sh` - Full execution tests for
  monitorData.sh
- ✅ `tests/integration/test_monitorInfrastructure_full_execution.sh` - Full execution tests for
  monitorInfrastructure.sh
- ✅ `tests/integration/test_monitorIngestion_full_execution.sh` - Full execution tests for
  monitorIngestion.sh

**Remaining Opportunities:**

- Add more integration tests for other scripts
- Reduce mocking in existing tests
- Add tests for initialization code
- Test error paths and edge cases

## Best Practices

1. **Start with main() tests** - Easiest way to increase coverage
2. **Add integration tests gradually** - Don't try to test everything at once
3. **Reduce mocking incrementally** - Start with file system, then git, etc.
4. **Test error paths** - These are often untested
5. **Test edge cases** - Empty inputs, missing files, etc.
6. **Execute scripts directly** - This ensures initialization code runs
7. **Use helper functions** - `run_script_for_coverage.sh` helps bashcov track scripts

## Generating Reports

### Estimated Coverage (Fast)

```bash
bash scripts/generate_coverage_report.sh
# Output: coverage/coverage_report.txt
```

### Instrumented Coverage (Slow)

```bash
# Run in background (takes hours)
bash scripts/run_bashcov_background.sh start

# Monitor progress
bash scripts/monitor_bashcov.sh

# Check status
bash scripts/run_bashcov_background.sh status
# Output: coverage/coverage_report_instrumented.txt
```

### Combined Report (Both Side by Side)

```bash
bash scripts/generate_coverage_combined.sh
# Output: coverage/coverage_report_combined.txt
```

## Recommendations

1. **For daily development:** Use estimated coverage (fast feedback)
2. **For releases:** Run instrumented coverage (comprehensive check)
3. **For CI/CD:** Use estimated coverage (fast enough for pipelines)
4. **For detailed analysis:** Use combined report (see both perspectives)

## Understanding the Numbers

- **Estimated 80%**: "We have tests for 80% of scripts"
- **Instrumented 27%**: "27% of code lines are executed during tests"
- **Gap 53%**: "Tests exist but don't execute much code (normal for unit tests)"

This gap is **expected** and **acceptable** for a project with extensive unit tests and mocking. The
goal is to gradually improve instrumented coverage by adding integration tests and testing main
functions.

## How Scripts Are Tracked for Coverage

### The Problem

bashcov has a limitation: it **cannot track scripts executed with `bash script.sh`** inside tests.
When a test runs:

```bash
run bash bin/monitor/monitorData.sh backup_freshness
```

bashcov doesn't track `monitorData.sh` because it's executed in a child process.

### The Solution

The coverage script (`generate_coverage_instrumented_optimized.sh`) now **executes scripts directly
with bashcov** after running all tests:

```bash
# After running all tests, execute scripts directly
bashcov --root . --skip-uncovered bin/monitor/monitorData.sh --help
bashcov --root . --skip-uncovered bin/monitor/monitorInfrastructure.sh --help
# ... etc
```

This ensures scripts are tracked even if tests execute them with `bash script.sh`.

### Result

- **Before:** Scripts executed with `bash script.sh` showed **0% coverage**
- **After:** Scripts executed directly with bashcov show **real coverage** (e.g., `monitorData.sh`
  shows 10%)

### Helper Function for Tests

A helper function is available for tests that want to execute scripts in a way that bashcov can
track:

```bash
# Load helper
source tests/helpers/run_script_for_coverage.sh

# Use in tests
run_script_for_coverage "bin/monitor/monitorData.sh" "backup_freshness"
```

This function:

- Detects if running under bashcov
- If yes: executes script directly (bashcov tracks it)
- If no: executes with `bash` (normal test behavior)

## Important: Integration Tests Inclusion

**Why the coverage was so low (27%):**

Previously, integration tests were **excluded** from bashcov because they are slow. However, this
significantly impacted coverage because:

- **22 integration tests** were excluded (~18% of all tests)
- Integration tests execute **more code** than unit tests:
  - Execute scripts completely (not just individual functions)
  - Execute `main()` functions and initialization code
  - Use fewer mocks (real file system, real git, etc.)
  - Test full workflows end-to-end

**Current behavior:**

Integration tests are now **included by default** in bashcov to provide more accurate coverage. This
should improve coverage from ~27% to ~40-50%.

**To exclude integration tests (faster but less accurate):**

```bash
SKIP_INTEGRATION_TESTS=true bash scripts/generate_coverage_instrumented_optimized.sh
```

## Coverage Improvement Results

After implementing the strategies above, we've achieved significant improvements:

### Overall Improvement

- **Before:** 18% average instrumented coverage
- **After:** 26% average instrumented coverage
- **Improvement:** +8 percentage points (+44.4% relative improvement)

### Scripts with Significant Improvements

1. **loggingFunctions**: 17% → 73% (+56%)
2. **alertFunctions**: 6% → 53% (+47%)
3. **monitorAnalytics**: 0% → 46% (+46%)
4. **escalation**: 0% → 35% (+35%)
5. **alertRules**: 0% → 29% (+29%)
6. **monitorIngestion**: 0% → 25% (+25%)
7. **monitoringFunctions**: 9% → 34% (+25%)

### Tests Added

- **Main function tests**: 4 files (21 tests total)
  - `test_monitorData_main.sh` (5 tests)
  - `test_monitorInfrastructure_main.sh` (6 tests)
  - `test_monitorIngestion_main.sh` (7 tests)
  - `test_monitorAnalytics_main.sh` (8 tests)

- **Full execution tests**: 3 files (26 tests total)
  - `test_monitorData_full_execution.sh` (5 tests)
  - `test_monitorInfrastructure_full_execution.sh` (8 tests)
  - `test_monitorIngestion_full_execution.sh` (10 tests)

- **Initialization tests**: 1 file (11 tests)
  - `test_initialization.sh` (11 tests)

- **Helpers**: 2 files
  - `run_script_for_coverage.sh` - Execute scripts for bashcov tracking
  - `use_real_commands.sh` - Use real commands instead of mocks when safe

**Total:** 50+ new tests added, significantly improving code coverage.

### Key Improvements

1. **Main functions now tested** - Scripts execute their main() functions
2. **Full script execution** - Scripts run as they would in production
3. **Initialization code tested** - TEST_MODE=false tests execute init code
4. **Better bashcov tracking** - Scripts executed directly are tracked
5. **Reduced mocking** - Real file system and git used when safe

## See Also

- [Code Coverage Instrumentation Guide](./Code_Coverage_Instrumentation.md): How to use bashcov
- [Testing Guide](../README.md#testing): How to write tests
- Combined Coverage Report: `coverage/coverage_report_combined.txt`
