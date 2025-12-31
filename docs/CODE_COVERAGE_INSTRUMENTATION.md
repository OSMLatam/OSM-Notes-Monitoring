# Code Coverage Instrumentation Guide

## Overview

This guide explains how to use code instrumentation tools (`kcov` or `bashcov`) to measure **actual code coverage** for Bash scripts, rather than relying on estimates based on test file presence.

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

**Easiest method - use the installation script:**
```bash
./scripts/install_coverage_tools.sh
```

This script will:
1. Check if kcov or bashcov are already installed
2. Try to install kcov (from package manager or source)
3. Fall back to bashcov if kcov installation fails
4. Provide manual installation instructions if both fail

**Manual installation from source (if script fails):**

```bash
# Install build dependencies
sudo apt-get install cmake g++ make git libcurl4-openssl-dev libelf-dev libdw-dev

# Build and install kcov
git clone https://github.com/SimonKagstrom/kcov.git
cd kcov
mkdir build && cd build
cmake ..
make
sudo make install
```

## Available Tools

### kcov (Recommended)

**kcov** is a code coverage tool that supports:
- Compiled programs
- Python scripts
- Bash/shell scripts
- HTML and XML report generation
- No special compilation required

**Advantages:**
- Fast execution
- Good HTML reports
- Works well with BATS tests
- Widely available in package managers

**Installation:**

**Option 1: Using the installation script (recommended):**
```bash
# Auto-detect and install best available tool
./scripts/install_coverage_tools.sh

# Or specify tool explicitly
./scripts/install_coverage_tools.sh kcov
./scripts/install_coverage_tools.sh bashcov
```

**Option 2: Manual installation:**

```bash
# Debian/Ubuntu (may not be in default repos)
# If not available, install from source (see below)

# Fedora/RHEL
sudo dnf install kcov

# macOS (Homebrew)
brew install kcov

# From source (most reliable method)
# Install dependencies first:
sudo apt-get install cmake g++ make git libcurl4-openssl-dev libelf-dev libdw-dev

# Then build and install:
git clone https://github.com/SimonKagstrom/kcov.git
cd kcov
mkdir build && cd build
cmake ..
make
sudo make install
```

### bashcov (Alternative)

**bashcov** is a Ruby-based coverage tool specifically for Bash scripts.

**Advantages:**
- Ruby-based (easy to install via gem)
- Good integration with test frameworks
- Detailed coverage reports

**Disadvantages:**
- Requires Ruby
- Slower than kcov
- Less widely available

**Installation:**

```bash
# Requires Ruby and RubyGems
gem install bashcov
```

## Usage

### Using the Instrumented Coverage Script

The project includes `scripts/generate_coverage_instrumented.sh` which automatically:
1. Detects available coverage tools (kcov or bashcov)
2. Runs all tests with instrumentation
3. Generates coverage reports
4. Provides summary statistics

**Basic Usage:**

```bash
# Auto-detect and use available tool
./scripts/generate_coverage_instrumented.sh

# Force use of kcov
COVERAGE_TOOL=kcov ./scripts/generate_coverage_instrumented.sh

# Force use of bashcov
COVERAGE_TOOL=bashcov ./scripts/generate_coverage_instrumented.sh
```

### Manual Usage with kcov

**Run a single test file:**

```bash
# Create output directory
mkdir -p coverage/kcov

# Run test with kcov
kcov \
    --include-path=./bin \
    --exclude-path=./tests \
    --exclude-path=./tmp \
    coverage/kcov/test_output \
    bats tests/unit/lib/test_monitoringFunctions.sh

# View HTML report
open coverage/kcov/test_output/index.html
# or
xdg-open coverage/kcov/test_output/index.html
```

**Run all tests:**

```bash
# Create output directory
mkdir -p coverage/kcov/all

# Run all unit tests
kcov \
    --include-path=./bin \
    --exclude-path=./tests \
    --exclude-path=./tmp \
    coverage/kcov/all \
    bats tests/unit/

# View combined report
open coverage/kcov/all/index.html
```

### Manual Usage with bashcov

**Run a single test file:**

```bash
# Run test with bashcov
bashcov --root . --skip-uncovered \
    bats tests/unit/lib/test_monitoringFunctions.sh

# View report (bashcov outputs to stdout and coverage.json)
cat coverage.json
```

**Run all tests:**

```bash
# Run all tests
bashcov --root . --skip-uncovered \
    bats tests/

# View report
cat coverage.json
```

## Understanding Coverage Reports

### kcov HTML Report

The kcov HTML report shows:
- **Coverage percentage** per file
- **Line-by-line coverage**:
  - Green: Covered (executed during tests)
  - Red: Not covered (never executed)
  - Yellow: Partially covered (some branches not taken)
- **Branch coverage** (if/else, case statements)
- **Function coverage**

**Key Sections:**
1. **Summary**: Overall coverage percentage
2. **File List**: Coverage per file
3. **Source View**: Annotated source code with coverage

### bashcov Report

bashcov provides:
- JSON output with coverage data
- Line-by-line coverage information
- Percentage coverage per file

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Install kcov
  run: |
    sudo apt-get update
    sudo apt-get install -y kcov

- name: Run tests with coverage
  run: |
    mkdir -p coverage
    kcov --include-path=./bin \
         --exclude-path=./tests \
         --exclude-path=./tmp \
         coverage/kcov \
         bats tests/

- name: Upload coverage reports
  uses: codecov/codecov-action@v3
  with:
    files: coverage/kcov/index.json
    flags: bash
```

### Jenkins Example

```groovy
stage('Coverage') {
    steps {
        sh '''
            mkdir -p coverage
            kcov --include-path=./bin \
                 --exclude-path=./tests \
                 --exclude-path=./tmp \
                 coverage/kcov \
                 bats tests/
        '''
        publishHTML([
            reportDir: 'coverage/kcov',
            reportFiles: 'index.html',
            reportName: 'Coverage Report'
        ])
    }
}
```

## Coverage Goals

Based on `docs/IMPLEMENTATION_PLAN.md`:

- **Libraries** (`bin/lib/`): >90% coverage
- **Monitoring Scripts** (`bin/monitor/`): >80% coverage
- **Security Scripts** (`bin/security/`): >85% coverage
- **Alert Scripts** (`bin/alerts/`): >80% coverage
- **Dashboard Scripts** (`bin/dashboard/`): >80% coverage
- **Overall**: >80% coverage

## Interpreting Results

### High Coverage (>80%)
- ✓ Most code paths are tested
- ✓ Good confidence in code quality
- ⚠ Still review untested lines (may be error handlers, edge cases)

### Medium Coverage (50-80%)
- ⚠ Some code paths untested
- ⚠ Focus on critical paths and error handling
- ⚠ Add tests for uncovered branches

### Low Coverage (<50%)
- ✗ Significant portions untested
- ✗ High risk of bugs
- ✗ Priority: Add comprehensive tests

## Common Issues and Solutions

### Issue: kcov not found

**Solution:**
```bash
# Install kcov (see Installation section above)
sudo apt-get install kcov
```

### Issue: Coverage shows 0% for all files

**Possible causes:**
1. Tests not actually executing the scripts
2. Scripts sourced incorrectly
3. Path exclusions too broad

**Solution:**
- Check that tests actually call functions from scripts
- Verify `--include-path` includes script directories
- Review test setup/teardown functions

### Issue: Coverage includes test files

**Solution:**
- Add `--exclude-path=./tests` to kcov command
- Or adjust `--include-path` to only include `./bin`

### Issue: bashcov requires Ruby

**Solution:**
- Install Ruby: `sudo apt-get install ruby ruby-dev`
- Or use kcov instead (doesn't require Ruby)

## Best Practices

1. **Run instrumented coverage regularly** (not just before releases)
2. **Set coverage thresholds** in CI/CD (fail if below 80%)
3. **Review uncovered lines** - some may be intentionally untestable (error handlers, cleanup)
4. **Focus on critical paths** - prioritize coverage for core functionality
5. **Don't aim for 100%** - some code (like error handlers) may be difficult to test
6. **Use both tools** - compare results between kcov and bashcov for validation

## Comparison: Estimated vs Instrumented Coverage

| Aspect | Estimated Coverage | Instrumented Coverage |
|--------|-------------------|----------------------|
| **Accuracy** | Low (heuristic-based) | High (actual execution) |
| **Speed** | Fast | Slower (runs all tests) |
| **Detail** | Summary only | Line-by-line analysis |
| **HTML Reports** | Basic | Detailed with source |
| **Branch Coverage** | No | Yes (with kcov) |
| **CI/CD Integration** | Easy | Requires tool installation |

## Next Steps

1. **Install kcov** (recommended) or bashcov
2. **Run instrumented coverage**: `./scripts/generate_coverage_instrumented.sh`
3. **Review HTML reports** to identify untested code
4. **Add tests** for uncovered lines
5. **Set up CI/CD** to run instrumented coverage automatically
6. **Track coverage trends** over time

## References

- [kcov GitHub](https://github.com/SimonKagstrom/kcov)
- [bashcov GitHub](https://github.com/infertux/bashcov)
- [Code Coverage Best Practices](https://www.atlassian.com/continuous-delivery/software-testing/code-coverage)
