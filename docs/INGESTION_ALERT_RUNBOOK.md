# Ingestion Alert Runbook

> **Purpose:** Comprehensive guide for understanding and responding to ingestion alerts  
> **Version:** 1.0.0  
> **Date:** 2025-12-25  
> **Status:** Active

## Overview

This runbook provides detailed information about each alert type for the OSM-Notes-Ingestion component, including:
- What the alert means
- What causes it
- How to investigate
- How to resolve
- Prevention strategies

## Alert Severity Levels

### CRITICAL
- **Response Time:** Immediate (within 15 minutes)
- **Impact:** System is non-functional or data is at risk
- **Action:** Escalate immediately, investigate root cause

### WARNING
- **Response Time:** Within 1 hour
- **Impact:** Performance degradation or potential issues
- **Action:** Investigate and resolve, monitor closely

### INFO
- **Response Time:** Within 24 hours
- **Impact:** Informational, no immediate action required
- **Action:** Review and document, may indicate trends

## Alert Categories

### 1. Script Execution Alerts

#### Alert: Low number of scripts found

**Alert Message:** `Low number of scripts found: X (threshold: Y)`

**Severity:** WARNING

**What it means:**
- Fewer ingestion scripts than expected are found in the repository
- Expected scripts: processAPINotes.sh, processPlanetNotes.sh, notesCheckVerifier.sh, processCheckPlanetNotes.sh, analyzeDatabasePerformance.sh

**Common Causes:**
- Scripts were deleted or moved
- Repository path is incorrect
- File system issues
- Repository not properly cloned/updated

**Investigation Steps:**
1. Check `INGESTION_REPO_PATH` configuration
2. Verify repository exists: `ls -la ${INGESTION_REPO_PATH}/bin`
3. Check if scripts are in expected location
4. Verify repository was not accidentally deleted
5. Check file system health

**Resolution:**
1. Restore missing scripts from backup or version control
2. Update repository: `cd ${INGESTION_REPO_PATH} && git pull`
3. Verify script permissions: `chmod +x ${INGESTION_REPO_PATH}/bin/*.sh`
4. Update `INGESTION_REPO_PATH` if scripts moved
5. Restart monitoring after fixing

**Prevention:**
- Use version control for all scripts
- Regular backups of repository
- Monitor repository path configuration
- Automated deployment checks

---

#### Alert: Scripts executable count is less than scripts found

**Alert Message:** `Scripts executable count (X) is less than scripts found (Y)`

**Severity:** WARNING

**What it means:**
- Some scripts exist but are not executable
- Scripts cannot be run due to missing execute permissions

**Common Causes:**
- File permissions changed accidentally
- Scripts copied without preserving permissions
- File system issues
- Manual permission changes

**Investigation Steps:**
1. Check script permissions: `ls -la ${INGESTION_REPO_PATH}/bin/*.sh`
2. Identify which scripts are not executable
3. Check if scripts were recently modified
4. Review file system logs

**Resolution:**
1. Make scripts executable: `chmod +x ${INGESTION_REPO_PATH}/bin/*.sh`
2. Verify permissions: `ls -la ${INGESTION_REPO_PATH}/bin/*.sh`
3. Test script execution manually
4. Restart monitoring

**Prevention:**
- Set proper permissions in deployment scripts
- Use version control with executable bit preserved
- Regular permission audits
- Automated permission checks in CI/CD

---

#### Alert: No recent activity detected

**Alert Message:** `No recent activity detected: last log is X hours old (threshold: Y hours)`

**Severity:** WARNING

**What it means:**
- No log files have been created or modified recently
- Ingestion scripts may not be running
- Processing may have stopped

**Common Causes:**
- Cron jobs not running
- Scripts crashed and not restarting
- System time issues
- Log directory issues
- Scripts disabled

**Investigation Steps:**
1. Check cron jobs: `crontab -l` or check cron service
2. Check if scripts are running: `ps aux | grep -E "processAPINotes|processPlanetNotes"`
3. Check log directory: `ls -lah ${INGESTION_REPO_PATH}/logs`
4. Check system time: `date`
5. Review system logs: `journalctl -u cron` or `/var/log/cron`
6. Check script exit codes in logs

**Resolution:**
1. Restart cron service if needed: `systemctl restart cron`
2. Manually run ingestion script to test
3. Fix any errors found in logs
4. Verify cron job configuration
5. Check disk space for log directory
6. Restart monitoring

**Prevention:**
- Monitor cron service health
- Set up script auto-restart mechanisms
- Regular log rotation to prevent disk issues
- Monitor system time synchronization

---

### 2. Error and Logging Alerts

#### Alert: High error count detected

**Alert Message:** `High error count detected: X errors in 24h (threshold: Y)`

**Severity:** WARNING

**What it means:**
- Large number of errors occurred in the last 24 hours
- May indicate systemic issues or repeated failures

**Common Causes:**
- Database connectivity issues
- API connectivity problems
- Data format issues
- Configuration errors
- Resource exhaustion (memory, disk, CPU)
- Network issues

**Investigation Steps:**
1. Review error logs: `grep -i error ${INGESTION_REPO_PATH}/logs/*.log | tail -50`
2. Identify error patterns and frequency
3. Check database connectivity: `psql -h ${DBHOST} -U ${DBUSER} -d ${DBNAME} -c "SELECT 1"`
4. Check API connectivity: `curl -I ${API_URL}`
5. Review system resources: `df -h`, `free -h`, `top`
6. Check for recent configuration changes

**Resolution:**
1. Fix root cause based on error patterns
2. Restart affected services
3. Update configuration if needed
4. Clear error conditions
5. Monitor error rate after fix

**Prevention:**
- Regular log analysis
- Proactive monitoring of dependencies
- Configuration change management
- Resource capacity planning
- Error rate trending

---

#### Alert: High error rate detected

**Alert Message:** `High error rate detected: X% (threshold: Y%, errors: A/B)`

**Severity:** WARNING

**What it means:**
- Percentage of errors relative to total log lines exceeds threshold
- Indicates high error frequency in operations

**Common Causes:**
- Same as "High error count" but more focused on rate
- May indicate degradation rather than complete failure
- Could be temporary spike or ongoing issue

**Investigation Steps:**
1. Same as "High error count"
2. Calculate error rate trend over time
3. Identify if errors are clustered in time
4. Check if errors are from specific operations

**Resolution:**
1. Same as "High error count"
2. Focus on reducing error rate, not just count
3. Implement retry logic if appropriate
4. Add circuit breakers for failing operations

**Prevention:**
- Same as "High error count"
- Set up error rate alerts in addition to count
- Monitor error rate trends

---

#### Alert: Error spike detected

**Alert Message:** `Error spike detected: X% in last hour (Y errors)`

**Severity:** WARNING

**What it means:**
- Sudden increase in error rate in the last hour
- May indicate an incident or attack
- Error rate is 2x or more the normal threshold

**Common Causes:**
- Service outage or degradation
- Network issues
- DDoS attack
- Configuration change gone wrong
- Dependency failure
- Data corruption

**Investigation Steps:**
1. **Immediate:** Check if service is down
2. Review recent changes (last hour)
3. Check system status: `systemctl status`
4. Review error logs for patterns: `tail -100 ${INGESTION_REPO_PATH}/logs/*.log | grep -i error`
5. Check network connectivity
6. Review monitoring dashboards
7. Check for security incidents

**Resolution:**
1. **If service down:** Restart service immediately
2. **If configuration issue:** Rollback recent changes
3. **If dependency issue:** Check and fix dependency
4. **If attack:** Implement rate limiting, block IPs
5. Document incident and root cause

**Prevention:**
- Change management process
- Staging environment testing
- Monitoring for anomalies
- Incident response procedures
- Regular security audits

---

#### Alert: High warning count detected

**Alert Message:** `High warning count detected: X warnings in 24h (threshold: Y)`

**Severity:** INFO

**What it means:**
- Large number of warnings in logs
- May indicate configuration issues or suboptimal performance

**Common Causes:**
- Configuration warnings
- Performance warnings
- Deprecation warnings
- Resource warnings

**Investigation Steps:**
1. Review warning logs: `grep -i warning ${INGESTION_REPO_PATH}/logs/*.log | tail -50`
2. Categorize warnings by type
3. Identify recurring warnings
4. Check configuration files

**Resolution:**
1. Fix configuration issues
2. Update deprecated features
3. Optimize performance if needed
4. Document acceptable warnings

**Prevention:**
- Regular configuration reviews
- Keep software updated
- Monitor warning trends

---

#### Alert: High warning rate detected

**Alert Message:** `High warning rate detected: X% (threshold: Y%, warnings: A/B)`

**Severity:** WARNING

**What it means:**
- High percentage of warnings in logs
- May indicate systemic configuration or performance issues

**Common Causes:**
- Same as "High warning count" but rate-based
- May indicate degradation

**Investigation Steps:**
1. Same as "High warning count"
2. Focus on rate trends

**Resolution:**
1. Same as "High warning count"
2. Address root causes of warnings

**Prevention:**
- Same as "High warning count"

---

### 3. Database Performance Alerts

#### Alert: Slow database connection

**Alert Message:** `Slow database connection: Xms`

**Severity:** WARNING

**What it means:**
- Database connection takes longer than 1000ms
- May indicate database server issues or network problems

**Common Causes:**
- Database server overloaded
- Network latency issues
- Connection pool exhaustion
- Database server resource constraints
- Network congestion

**Investigation Steps:**
1. Check database server status: `systemctl status postgresql`
2. Check database connections: `psql -c "SELECT count(*) FROM pg_stat_activity"`
3. Check database load: `psql -c "SELECT * FROM pg_stat_activity WHERE state = 'active'"`
4. Check network latency: `ping ${DBHOST}`
5. Review database logs: `tail -50 /var/log/postgresql/postgresql-*.log`
6. Check database server resources: `top`, `iostat`

**Resolution:**
1. **If overloaded:** Scale database resources or optimize queries
2. **If network issue:** Check network infrastructure
3. **If connection pool:** Increase pool size or reduce connections
4. **If resource constraint:** Add resources or optimize database
5. Restart database if needed (with caution)

**Prevention:**
- Database performance monitoring
- Connection pool tuning
- Query optimization
- Capacity planning
- Network monitoring

---

#### Alert: Slow query detected

**Alert Message:** `Slow query detected: Xms`

**Severity:** WARNING

**What it means:**
- Database query takes longer than threshold (default 1000ms)
- May indicate missing indexes or inefficient queries

**Common Causes:**
- Missing indexes
- Inefficient query plans
- Large table scans
- Database locks
- Resource constraints

**Investigation Steps:**
1. Identify slow queries: `psql -c "SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10"`
2. Check query execution plans: `EXPLAIN ANALYZE <query>`
3. Check for missing indexes
4. Review table statistics: `ANALYZE <table>`
5. Check for locks: `psql -c "SELECT * FROM pg_locks WHERE NOT granted"`

**Resolution:**
1. Add missing indexes
2. Optimize query structure
3. Update table statistics: `ANALYZE`
4. Consider partitioning large tables
5. Review and optimize application queries

**Prevention:**
- Regular query performance analysis
- Index maintenance
- Query review process
- Database tuning
- Performance testing

---

### 4. Performance Check Alerts

#### Alert: Performance check took too long

**Alert Message:** `Performance check took too long: Xs (threshold: Ys)`

**Severity:** WARNING

**What it means:**
- Performance analysis script took longer than 5 minutes
- May indicate system performance issues

**Common Causes:**
- System resource constraints
- Database performance issues
- Script inefficiencies
- Large data volumes

**Investigation Steps:**
1. Check system resources: `top`, `iostat`, `free -h`
2. Review performance check script output
3. Check database performance
4. Review script execution time breakdown

**Resolution:**
1. Optimize performance check script
2. Improve system resources
3. Optimize database queries in script
4. Consider running checks less frequently

**Prevention:**
- Optimize performance check scripts
- Monitor system resources
- Regular script reviews

---

#### Alert: Performance check found failures

**Alert Message:** `Performance check found X failures, Y warnings`

**Severity:** WARNING

**What it means:**
- Performance analysis detected failures
- System performance issues identified

**Common Causes:**
- Database performance issues
- Missing indexes
- Table bloat
- Resource constraints
- **Command not found (exit code 127)**: `psql` or other tools not in PATH when script runs from cron
- **Missing dependencies**: Required tools not installed or not accessible

**Investigation Steps:**
1. Review performance check output:
   ```bash
   # Check latest performance check output
   ls -lt logs/performance_output/analyzeDatabasePerformance_*.txt | head -1 | awk '{print $NF}' | xargs cat
   ```
2. Check for exit code 127 (command not found):
   ```bash
   # If you see "exit code: 127", check if psql is in PATH
   which psql
   # Or check the error details in the output file
   ```
3. Verify analyzeDatabasePerformance.sh can find psql:
   ```bash
   cd /path/to/OSM-Notes-Ingestion
   ./bin/monitor/analyzeDatabasePerformance.sh --verbose
   ```
4. Check database connection variables are set correctly
5. Identify specific failures from output
6. Check database statistics
7. Review system resources

**Resolution:**
1. **If exit code 127 (command not found)**:
   - Ensure `psql` is in PATH: `export PATH="/usr/bin:/usr/local/bin:$PATH"`
   - Or set full path to psql in analyzeDatabasePerformance.sh configuration
   - Check that INGESTION_REPO_PATH points to correct OSM-Notes-Ingestion directory
   - Verify analyzeDatabasePerformance.sh has execute permissions
2. Address specific failures identified
3. Optimize database
4. Add missing indexes
5. Clean up table bloat

**Prevention:**
- Regular performance checks
- Proactive optimization
- Capacity planning

---

#### Alert: Performance check found excessive warnings

**Alert Message:** `Performance check found X warnings (threshold: Y)`

**Severity:** WARNING

**What it means:**
- Performance check found more warnings than threshold
- May indicate performance degradation

**Common Causes:**
- Performance issues accumulating
- Multiple minor issues

**Investigation Steps:**
1. Review performance check warnings
2. Prioritize warnings by impact
3. Check trends over time

**Resolution:**
1. Address high-priority warnings
2. Plan optimization work
3. Monitor improvement

**Prevention:**
- Regular performance optimization
- Warning trend monitoring

---

#### Alert: Performance analysis failed

**Alert Message:** `Performance analysis failed: exit_code=X`

**Severity:** ERROR

**What it means:**
- Performance check script failed to execute
- Cannot assess performance

**Common Causes:**
- Script errors
- Database connectivity issues
- Permission issues
- Resource exhaustion

**Investigation Steps:**
1. Check script error output
2. Verify database connectivity
3. Check script permissions
4. Review system resources

**Resolution:**
1. Fix script errors
2. Restore database connectivity
3. Fix permissions
4. Resolve resource issues

**Prevention:**
- Script error handling
- Regular script testing
- Resource monitoring

---

### 5. Data Quality Alerts

#### Alert: Data quality below threshold

**Alert Message:** `Data quality below threshold: X% (threshold: Y%)`

**Severity:** WARNING

**What it means:**
- Data quality score is below acceptable threshold (default 95%)
- Data integrity issues detected

**Common Causes:**
- Data validation failures
- Data corruption
- Missing data
- Data format issues
- Processing errors

**Investigation Steps:**
1. Review data quality check output
2. Identify specific quality issues
3. Check data validation logs
4. Review recent data processing
5. Check for data corruption

**Resolution:**
1. Fix data quality issues identified
2. Reprocess affected data if needed
3. Fix root cause of quality issues
4. Verify data quality after fix

**Prevention:**
- Data validation at ingestion
- Regular data quality checks
- Data backup and recovery procedures
- Data integrity monitoring

---

#### Alert: Data quality check took too long

**Alert Message:** `Data quality check took too long: Xs (threshold: Ys)`

**Severity:** WARNING

**What it means:**
- Data quality verification took longer than 10 minutes
- May indicate large data volumes or performance issues

**Common Causes:**
- Large data volumes
- Slow database queries
- System resource constraints
- Inefficient validation queries

**Investigation Steps:**
1. Check data volume
2. Review validation query performance
3. Check system resources
4. Review check script efficiency

**Resolution:**
1. Optimize validation queries
2. Consider sampling for large datasets
3. Improve system resources
4. Optimize check script

**Prevention:**
- Query optimization
- Regular performance tuning
- Capacity planning

---

#### Alert: Data freshness exceeded

**Alert Message:** `Data freshness exceeded: Xs (threshold: Ys)`

**Severity:** WARNING

**What it means:**
- Most recent data update is older than threshold (default 1 hour)
- Data is stale, processing may have stopped

**Common Causes:**
- Processing stopped
- No new data available
- Processing delays
- System issues

**Investigation Steps:**
1. Check if processing is running
2. Check for new data availability
3. Review processing logs
4. Check processing schedule
5. Verify data source availability

**Resolution:**
1. Restart processing if stopped
2. Fix processing errors
3. Check data source availability
4. Verify processing schedule

**Prevention:**
- Monitor processing status
- Alert on processing failures
- Regular processing verification

---

### 6. Processing Latency Alerts

#### Alert: High processing latency

**Alert Message:** `High processing latency: Xs (threshold: Ys)`

**Severity:** WARNING

**What it means:**
- Time between data arrival and processing exceeds threshold (default 5 minutes)
- Processing is delayed

**Common Causes:**
- Processing queue backlog
- Slow processing
- Resource constraints
- Processing errors causing retries

**Investigation Steps:**
1. Check processing queue length
2. Review processing performance
3. Check system resources
4. Review processing logs for errors
5. Check processing frequency

**Resolution:**
1. Process queue backlog
2. Optimize processing performance
3. Add processing resources
4. Fix processing errors
5. Increase processing frequency if needed

**Prevention:**
- Monitor processing queue
- Optimize processing performance
- Capacity planning
- Error handling improvements

---

### 7. Disk Space Alerts

#### Alert: High disk usage

**Alert Message:** `High disk usage: X% on <directory> (threshold: Y%, available: Z)`

**Severity:** WARNING

**What it means:**
- Disk usage exceeds threshold (default 90%)
- Risk of running out of disk space

**Common Causes:**
- Log files accumulating
- Data files growing
- Temporary files not cleaned
- Backup files accumulating

**Investigation Steps:**
1. Check disk usage: `df -h`
2. Identify large files: `du -sh ${INGESTION_REPO_PATH}/*`
3. Check log file sizes
4. Review cleanup procedures
5. Check for large temporary files

**Resolution:**
1. **Immediate:** Clean up old log files
2. Rotate logs: `logrotate -f /etc/logrotate.d/ingestion`
3. Remove old temporary files
4. Archive old data if needed
5. Expand disk if necessary

**Prevention:**
- Log rotation configuration
- Regular cleanup procedures
- Disk space monitoring
- Capacity planning
- Automated cleanup scripts

---

### 8. Health Status Alerts

#### Alert: Health check failed

**Alert Message:** `Health check failed: <error_message>`

**Severity:** CRITICAL

**What it means:**
- Component health check failed
- Component is not functioning properly

**Common Causes:**
- Repository not found
- Critical dependencies missing
- System failures
- Configuration errors

**Investigation Steps:**
1. Check error message details
2. Verify repository exists
3. Check all dependencies
4. Review system status
5. Check configuration

**Resolution:**
1. Fix root cause identified in error message
2. Restore missing components
3. Fix configuration errors
4. Restart component
5. Verify health check passes

**Prevention:**
- Regular health checks
- Dependency monitoring
- Configuration validation
- Automated recovery procedures

---

#### Alert: Health check warning

**Alert Message:** `Health check warning: <warning_message>`

**Severity:** WARNING

**What it means:**
- Health check passed but with warnings
- Component is degraded but functional

**Common Causes:**
- Missing optional components
- Suboptimal configuration
- Minor issues

**Investigation Steps:**
1. Review warning message
2. Check optional components
3. Review configuration

**Resolution:**
1. Address warnings if critical
2. Update configuration if needed
3. Monitor for degradation

**Prevention:**
- Regular health check reviews
- Configuration optimization

---

### 9. API Download Alerts

#### Alert: No recent API download activity detected

**Alert Message:** `No recent API download activity detected`

**Severity:** WARNING

**What it means:**
- No API download activity in the last hour
- API downloads may have stopped

**Common Causes:**
- API download script not running
- API unavailable
- Network issues
- Configuration errors

**Investigation Steps:**
1. Check if download script is running
2. Test API connectivity: `curl -I ${API_URL}`
3. Check network connectivity
4. Review download script logs
5. Check cron schedule

**Resolution:**
1. Restart download script
2. Fix API connectivity issues
3. Fix network issues
4. Update configuration if needed
5. Verify downloads resume

**Prevention:**
- Monitor API availability
- Network monitoring
- Script health checks

---

#### Alert: Low API download success rate

**Alert Message:** `Low API download success rate: X% (threshold: Y%, successful/total)`

**Severity:** WARNING

**What it means:**
- API download success rate below threshold (default 95%)
- Many download attempts are failing

**Common Causes:**
- API errors
- Network issues
- Rate limiting
- Authentication issues
- API changes
- **False positives:** Log patterns counting non-API download operations (fixed in recent versions)

**Investigation Steps:**
1. Review download logs for errors
2. Check API status
3. Test API manually: `curl ${API_URL}`
4. Check for rate limiting
5. Verify authentication
6. **Verify log patterns:** Check if logs contain the expected success messages:
   - `Successfully downloaded notes from API`
   - `SEQUENTIAL API XML PROCESSING COMPLETED SUCCESSFULLY`
7. **Check for false positives:** Review if non-API operations are being counted (see `docs/API_DOWNLOAD_SUCCESS_RATE_ANALYSIS.md`)

**Resolution:**
1. Fix API connectivity issues
2. Handle rate limiting
3. Update authentication if needed
4. Contact API provider if API issues
5. Implement retry logic
6. **If false positive:** Ensure daemon logs contain the expected success message patterns

**Prevention:**
- API monitoring
- Rate limiting handling
- Retry mechanisms
- API status monitoring
- Ensure consistent logging patterns in daemon code

**Note:** The monitoring code counts API download attempts by searching for `__getNewNotesFromApi` or `getNewNotesFromApi` function calls, and counts successes by searching for specific success messages. If your logs don't contain these exact patterns, you may see false warnings. See `docs/API_DOWNLOAD_SUCCESS_RATE_ANALYSIS.md` for detailed analysis.

---

## General Troubleshooting Steps

### 1. Verify Alert
- Check alert details in monitoring dashboard
- Review alert message and metadata
- Verify alert is not a false positive

### 2. Check Logs
- Review component logs: `${INGESTION_REPO_PATH}/logs/*.log`
- Check system logs: `journalctl -u <service>`
- Review monitoring logs: `${LOG_DIR}/ingestion.log`

### 3. Check System Status
- Verify component is running
- Check system resources (CPU, memory, disk)
- Verify network connectivity
- Check database connectivity

### 4. Review Recent Changes
- Check recent configuration changes
- Review recent deployments
- Check for system updates
- Review change logs

### 5. Escalate if Needed
- If issue persists or escalates, escalate to team lead
- Document investigation steps and findings
- Create incident report if critical

## Alert Response Checklist

- [ ] Acknowledge alert within response time SLA
- [ ] Review alert details and severity
- [ ] Check if alert is duplicate or resolved
- [ ] Investigate root cause
- [ ] Implement fix or workaround
- [ ] Verify resolution
- [ ] Document incident and resolution
- [ ] Update monitoring if needed
- [ ] Review prevention measures

## Escalation Path

1. **Level 1 (On-Call):** Initial response and investigation
2. **Level 2 (Team Lead):** If issue persists > 1 hour or escalates
3. **Level 3 (Architecture Team):** If issue requires architectural changes
4. **Level 4 (Management):** For critical business impact

## References

- [Ingestion Metrics Definition](INGESTION_METRICS.md)
- [Ingestion Alert Thresholds](INGESTION_ALERT_THRESHOLDS.md)
- [Configuration Reference](CONFIGURATION_REFERENCE.md)
- [Monitoring Architecture](Monitoring_Architecture_Proposal.md)

---

**Last Updated:** 2025-12-25  
**Version:** 1.0.0  
**Status:** Active

