---
title: "Testing Deployment Guide"
description: "Guide for testing the deployment process before going to production."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "testing"
  - "installation"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Testing Deployment Guide

> **Last Updated:** 2026-01-01  
> **Version:** 1.0.0

Guide for testing the deployment process before going to production.

## Table of Contents

1. [Quick Test](#quick-test)
2. [Full Test Suite](#full-test-suite)
3. [Step-by-Step Testing](#step-by-step-testing)
4. [Test Environment Setup](#test-environment-setup)
5. [Validation Checklist](#validation-checklist)

---

## Quick Test

Run a quick validation to verify all scripts and configuration:

```bash
./scripts/test_deployment.sh --quick
```

This checks:

- Prerequisites (bash, psql, curl)
- Configuration files exist
- Scripts syntax is valid

---

## Full Test Suite

Run the complete test suite:

```bash
./scripts/test_deployment.sh --full
```

This includes:

- Prerequisites check
- Configuration testing
- Script syntax validation
- Monitoring scripts validation
- Database setup test
- Backup/restore test

### Test Database

The test suite uses a test database: `osm_notes_monitoring_test`

To clean up after testing:

```bash
./scripts/test_deployment.sh --full --cleanup
```

---

## Step-by-Step Testing

### Step 1: Test Configuration

```bash
./scripts/test_deployment.sh --config
```

Verifies:

- Configuration template files exist
- Config generation script works
- Config validation script works

### Step 2: Test Scripts

```bash
./scripts/test_deployment.sh --scripts
```

Verifies:

- All deployment scripts have valid syntax
- Scripts are executable
- Scripts can be found

### Step 3: Test Database Operations

```bash
./scripts/test_deployment.sh --database
```

**WARNING**: This creates a test database and may require cleanup.

Verifies:

- Database can be created
- Schema can be initialized
- Migrations can be run

---

## Test Environment Setup

### Option 1: Use Test Database

Create a separate test database:

```bash
# Create test database
createdb osm_notes_monitoring_test

# Run setup on test database
DBNAME=osm_notes_monitoring_test ./scripts/production_setup.sh --skip-checks
```

### Option 2: Use Docker (Recommended)

If you have Docker available:

```bash
# Start PostgreSQL container
docker run -d \
  --name postgres-test \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=osm_notes_monitoring_test \
  -p 5433:5432 \
  postgres:12

# Set environment
export PGPASSWORD=test
export DBHOST=localhost
export DBPORT=5433
export DBUSER=postgres
export DBNAME=osm_notes_monitoring_test

# Run tests
./scripts/test_deployment.sh --full
```

### Option 3: Use Existing Development Database

If you have a development database:

```bash
# Use development database
DBNAME=osm_notes_monitoring ./scripts/test_deployment.sh --database
```

---

## Validation Checklist

After running tests, verify:

### Scripts

- [ ] All scripts have valid syntax
- [ ] All scripts are executable
- [ ] Scripts can find their dependencies

### Configuration

- [ ] Configuration templates exist
- [ ] Config generation works
- [ ] Config validation works

### Database

- [ ] Database can be created
- [ ] Schema initializes correctly
- [ ] Migrations run successfully
- [ ] Backup/restore works

### Monitoring Scripts

- [ ] Monitoring scripts have valid syntax
- [ ] Scripts can be executed (may fail without proper config, that's OK)

---

## Testing Production Setup

Test the production setup script in a safe way:

```bash
# Test with skip flags (doesn't modify anything)
./scripts/production_setup.sh --skip-database --skip-config --skip-security

# Or test on test database
DBNAME=osm_notes_monitoring_test ./scripts/production_setup.sh --skip-checks
```

---

## Testing Deployment Script

Test the complete deployment:

```bash
# Dry run (validation only)
./scripts/deploy_production.sh --validate-only

# Test with skips (doesn't modify production)
./scripts/deploy_production.sh \
  --skip-setup \
  --skip-migration \
  --skip-security \
  --skip-cron \
  --skip-backups \
  --skip-logrotate
```

---

## Troubleshooting Tests

### Test Fails: Database Connection

**Error**: Cannot connect to database

**Solution**:

```bash
# Check PostgreSQL is running
systemctl status postgresql

# Test connection manually
psql -d osm_notes_monitoring_test -c "SELECT 1;"
```

### Test Fails: Script Syntax

**Error**: Syntax error in script

**Solution**:

```bash
# Check syntax manually
bash -n scripts/production_setup.sh

# Fix syntax errors
nano scripts/production_setup.sh
```

### Test Fails: Missing Files

**Error**: File not found

**Solution**:

```bash
# Verify file exists
ls -la sql/init.sql

# Check path in script
grep -n "sql/init.sql" scripts/production_setup.sh
```

---

## Next Steps

After successful testing:

1. **Review Test Results**: Check all tests passed
2. **Document Issues**: Note any warnings or issues found
3. **Fix Issues**: Resolve any problems before production
4. **Re-test**: Run tests again after fixes
5. **Proceed to Production**: When all tests pass

---

**Last Updated:** 2026-01-01
