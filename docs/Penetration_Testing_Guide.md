---
title: "Penetration Testing Guide"
description: "This guide provides instructions for performing penetration testing on the OSM-Notes-Monitoring"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "testing"
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Penetration Testing Guide

**Version:** 1.0.0  
**Last Updated:** 2025-12-31  
**Component:** Security

## Overview

This guide provides instructions for performing penetration testing on the OSM-Notes-Monitoring
system. Penetration testing (pen testing) involves simulating real-world attacks to identify
security vulnerabilities that automated scans might miss.

## Table of Contents

1. [Introduction](#introduction)
2. [Scope and Objectives](#scope-and-objectives)
3. [Pre-Testing Preparation](#pre-testing-preparation)
4. [Test Scenarios](#test-scenarios)
5. [Automated Penetration Tests](#automated-penetration-tests)
6. [Manual Testing Procedures](#manual-testing-procedures)
7. [Reporting and Remediation](#reporting-and-remediation)
8. [Best Practices](#best-practices)

---

## Introduction

### What is Penetration Testing?

Penetration testing is a security testing methodology where security professionals attempt to
exploit vulnerabilities in a controlled environment. Unlike automated vulnerability scans, pen
testing involves:

- **Manual testing**: Human testers think creatively about attack vectors
- **Exploitation attempts**: Actually trying to exploit vulnerabilities
- **Impact assessment**: Understanding the real-world impact of vulnerabilities
- **Remediation verification**: Confirming fixes work correctly

### When to Perform Penetration Testing

- **Before production deployment**: Identify and fix critical issues
- **After major changes**: Verify new code doesn't introduce vulnerabilities
- **Regularly (annually)**: Maintain security posture
- **After security incidents**: Verify remediation effectiveness

---

## Scope and Objectives

### In-Scope Components

- **Rate Limiting**: Bypass attempts, limit manipulation
- **IP Management**: Whitelist/blacklist bypass
- **Database Security**: SQL injection, unauthorized access
- **File System Security**: Path traversal, unauthorized file access
- **Input Validation**: Command injection, script injection
- **Authentication**: Credential exposure, privilege escalation
- **Configuration Security**: Sensitive data exposure

### Out-of-Scope

- **Denial of Service (DoS)**: Not tested to avoid service disruption
- **Physical Security**: Infrastructure physical access
- **Social Engineering**: Human factor attacks
- **Third-Party Services**: External dependencies

### Objectives

1. **Identify vulnerabilities** that automated scans miss
2. **Verify security controls** work as intended
3. **Assess impact** of potential exploits
4. **Validate remediation** effectiveness
5. **Improve security posture** through findings

---

## Pre-Testing Preparation

### Environment Setup

1. **Use Test Environment**: Never test in production

   ```bash
   # Use test database
   export TEST_DB_NAME="osm_notes_monitoring_test"
   export DBNAME="${TEST_DB_NAME}"
   ```

2. **Backup Test Data**: Create backups before testing

   ```bash
   pg_dump -d osm_notes_monitoring_test > backup_before_pen_test.sql
   ```

3. **Enable Logging**: Ensure all security events are logged

   ```bash
   export LOG_LEVEL="DEBUG"
   ```

4. **Isolate Network**: Test in isolated network if possible

### Required Tools

- **curl**: HTTP request testing
- **psql**: Database testing
- **nmap**: Port scanning (if network testing)
- **sqlmap**: SQL injection testing (advanced)
- **bash**: Script execution

### Authorization

- **Written Authorization**: Always get written approval before testing
- **Scope Definition**: Clearly define what can and cannot be tested
- **Time Windows**: Agree on testing windows
- **Contact Information**: Provide emergency contact details

---

## Test Scenarios

### 1. Rate Limiting Bypass

**Objective**: Attempt to bypass rate limiting mechanisms

**Test Cases**:

- Rapid request bursts
- IP rotation attempts
- Whitelist manipulation
- Time window manipulation

**Expected Result**: Rate limiting should prevent bypass attempts

### 2. SQL Injection

**Objective**: Attempt SQL injection attacks

**Test Cases**:

- Basic SQL injection: `' OR '1'='1`
- Union-based injection: `' UNION SELECT * FROM users--`
- Time-based blind injection: `'; WAITFOR DELAY '00:00:05'--`
- Error-based injection: `' AND 1=CAST((SELECT version()) AS int)--`

**Expected Result**: Input validation should prevent SQL injection

### 3. Command Injection

**Objective**: Attempt command injection attacks

**Test Cases**:

- Basic command injection: `; ls -la`
- Pipe injection: `| cat /etc/passwd`
- Backtick injection: `` `whoami` ``
- Command substitution: `$(id)`

**Expected Result**: Input sanitization should prevent command execution

### 4. Path Traversal

**Objective**: Attempt to access unauthorized files

**Test Cases**:

- Basic traversal: `../../../etc/passwd`
- Encoded traversal: `..%2F..%2Fetc%2Fpasswd`
- Double encoding: `..%252F..%252Fetc%252Fpasswd`
- Null byte injection: `../../../etc/passwd%00`

**Expected Result**: Path validation should prevent traversal

### 5. IP Blocking Bypass

**Objective**: Attempt to bypass IP blocking

**Test Cases**:

- IP spoofing attempts
- Proxy/VPN usage
- Header manipulation (X-Forwarded-For)
- IPv6 vs IPv4 manipulation

**Expected Result**: IP blocking should be effective

### 6. Authentication Bypass

**Objective**: Attempt to bypass authentication

**Test Cases**:

- Default credentials
- Credential brute force
- Session hijacking
- Token manipulation

**Expected Result**: Authentication should be secure

### 7. Information Disclosure

**Objective**: Attempt to extract sensitive information

**Test Cases**:

- Error message analysis
- Log file access
- Configuration file access
- Database schema enumeration

**Expected Result**: Sensitive information should be protected

---

## Automated Penetration Tests

### Running Automated Tests

```bash
# Run all penetration tests
./tests/security/test_penetration.sh

# Run specific test category
./tests/security/test_penetration.sh --category sql_injection

# Run with verbose output
./tests/security/test_penetration.sh --verbose
```

### Test Categories

1. **SQL Injection Tests**: Automated SQL injection attempts
2. **Command Injection Tests**: Command injection attempts
3. **Path Traversal Tests**: Path traversal attempts
4. **Rate Limiting Tests**: Rate limiting bypass attempts
5. **IP Blocking Tests**: IP blocking bypass attempts

---

## Manual Testing Procedures

### 1. SQL Injection Testing

**Step 1**: Identify input points

```bash
# Find SQL query execution points
grep -r "execute_sql_query\|psql.*-c" bin/
```

**Step 2**: Test with malicious input

```bash
# Test IP validation function
./bin/lib/securityFunctions.sh
is_valid_ip "'; DROP TABLE metrics; --"
```

**Step 3**: Verify protection

```bash
# Check if table still exists
psql -d osm_notes_monitoring_test -c "SELECT COUNT(*) FROM metrics;"
```

### 2. Rate Limiting Testing

**Step 1**: Baseline test

```bash
# Normal request rate
for i in {1..10}; do
    ./bin/security/rateLimiter.sh check 192.168.1.100 /api/test
    sleep 1
done
```

**Step 2**: Burst test

```bash
# Rapid burst of requests
for i in {1..100}; do
    ./bin/security/rateLimiter.sh check 192.168.1.100 /api/test &
done
wait
```

**Step 3**: Verify blocking

```bash
# Check if IP was blocked
./bin/security/ipBlocking.sh status 192.168.1.100
```

### 3. IP Blocking Testing

**Step 1**: Add test IP to blacklist

```bash
./bin/security/ipBlocking.sh add 192.168.1.200 blacklist "pen test"
```

**Step 2**: Attempt to bypass

```bash
# Try different IP formats
./bin/lib/securityFunctions.sh is_valid_ip "192.168.1.200"
./bin/lib/securityFunctions.sh is_valid_ip "::ffff:192.168.1.200"
```

**Step 3**: Verify blocking persists

```bash
./bin/security/ipBlocking.sh status 192.168.1.200
```

### 4. Path Traversal Testing

**Step 1**: Identify file operations

```bash
# Find file read operations
grep -r "cat\|read\|source" bin/ --include="*.sh"
```

**Step 2**: Test with traversal payloads

```bash
# Test configuration loading
export CONFIG_PATH="../../../etc/passwd"
# Attempt to load config (should fail)
```

**Step 3**: Verify protection

```bash
# Verify file wasn't accessed
ls -la /etc/passwd
```

---

## Reporting and Remediation

### Test Report Structure

1. **Executive Summary**
   - Overview of testing
   - Critical findings
   - Risk assessment

2. **Detailed Findings**
   - Vulnerability description
   - Proof of concept
   - Impact assessment
   - Remediation recommendations

3. **Test Logs**
   - All test commands executed
   - System responses
   - Error messages

4. **Remediation Tracking**
   - Status of each finding
   - Fix verification
   - Retest results

### Severity Classification

- **Critical**: Immediate threat, requires urgent fix
- **High**: Significant risk, fix within 24-48 hours
- **Medium**: Moderate risk, fix within 1-2 weeks
- **Low**: Minor issue, fix during regular maintenance

### Remediation Process

1. **Document Finding**: Create detailed report
2. **Assign Priority**: Based on severity
3. **Develop Fix**: Implement security patch
4. **Test Fix**: Verify fix works
5. **Retest**: Confirm vulnerability is resolved
6. **Document**: Update security documentation

---

## Best Practices

### Testing Ethics

- **Always get authorization**: Never test without permission
- **Use test environments**: Never test in production
- **Respect scope**: Don't test out-of-scope systems
- **Document everything**: Keep detailed logs
- **Report responsibly**: Follow responsible disclosure

### Safety Measures

- **Backup data**: Always backup before testing
- **Isolate environment**: Use isolated test network
- **Monitor impact**: Watch for unintended effects
- **Have rollback plan**: Be ready to revert changes
- **Emergency contacts**: Know who to contact

### Testing Frequency

- **Before production**: Mandatory
- **After major changes**: Recommended
- **Annually**: Good practice
- **After incidents**: Required

### Continuous Improvement

- **Learn from findings**: Update security practices
- **Update test cases**: Add new test scenarios
- **Share knowledge**: Document lessons learned
- **Automate where possible**: Create reusable tests

---

## Related Documentation

- [Security Audit Guide](./Security_Audit_Guide.md): Automated security checks
- [Vulnerability Scanning Guide](./Vulnerability_Scanning_Guide.md): Vulnerability detection
- [Security Best Practices](./Security_Best_Practices.md): Security guidelines
- [API Security Guide](./API_Security_Guide.md): API security specifics

---

## Summary

Penetration testing is a critical component of maintaining a secure monitoring system. By simulating
real-world attacks, we can identify and fix vulnerabilities before they can be exploited. Use this
guide to:

1. Plan and execute penetration tests safely
2. Identify security vulnerabilities
3. Verify security controls work correctly
4. Improve overall security posture

Remember: Always test responsibly, get proper authorization, and use test environments.
