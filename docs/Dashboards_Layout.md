---
title: "Grafana Dashboards Layout"
description: "Visual documentation of panel layout in each Grafana dashboard with detailed information about data sources, value meanings, thresholds, and troubleshooting"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "monitoring"
  - "grafana"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Grafana Dashboards Layout

> **Date:** 2026-01-15  
> **Purpose:** Visual documentation of panel layout in each dashboard with detailed information
> about data sources, value meanings, thresholds, and troubleshooting  
> **Grafana URL:** http://192.168.0.7:3003

---

## 1. Overview (v3)

**Dashboard:** OSM Notes Monitoring - Overview (v3)

```
┌──────────────────────────┬──────────────────────────────────┐
│                          │                                  │
│  Component Health        │  Database Connection Time        │
│  Status                  │  (Last 24h)                      │
│                          │                                  │
│  [Table with 7           │  [Line chart]                    │
│   components]            │                                  │
│                          │                                  │
│  - analytics (degraded)  │  Y-axis: ms (40-80ms)           │
│  - api (down)            │  X-axis: time (24h)              │
│  - daemon (healthy)      │  ~287 data points                │
│  - data (healthy)        │  Average: ~40ms                  │
│  - infrastructure        │                                  │
│    (healthy)             │                                  │
│  - ingestion (healthy)   │                                  │
│  - wms (down)            │                                  │
│                          │                                  │
└──────────────────────────┴──────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Active Alerts                                               │
│                                                              │
│  [Full-width table]                                         │
│                                                              │
│  Columns: component | alert_level | alert_type |          │
│           message | created_at                               │
│                                                              │
│  Shows up to 10 most recent alerts                          │
│  (out of 1,934 total active alerts)                        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Panels:**

### 1. Component Health Status

**Type:** Table (8 columns)  
**Data Source:** `component_health` table  
**SQL Query:**
`SELECT component, status, last_check, last_success, error_count FROM component_health ORDER BY component`

**Values Meaning:**

- **status values:**
  - `healthy` (green): Component is functioning normally
  - `degraded` (yellow): Component has issues but is partially functional
  - `down` (red): Component is not functioning
  - `unknown` (gray): Status cannot be determined (no recent checks)
- **last_check:** Timestamp of last health check execution
- **last_success:** Timestamp of last successful health check
- **error_count:** Number of consecutive errors (0 = no errors)

**Color Coding:**

- Green: `healthy` status
- Yellow: `degraded` status
- Red: `down` status
- Gray: `unknown` status

**Troubleshooting:**

- **If status = `down`:** Check component logs, verify service is running, check dependencies
- **If status = `unknown`:** Verify monitoring scripts are running, check `last_check` timestamp
- **If `last_check` is old (> 1 hour):** Monitoring may not be running - check cron jobs
- **If `error_count` > 0:** Review component logs for errors, check system resources

---

### 2. Database Connection Time

**Type:** Timeseries Chart (10 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'db_connection_time_ms' AND $__timeFilter(timestamp) ORDER BY timestamp`

**Values Meaning:**

- **Low values (< 100ms):** Excellent - database is responding quickly
- **Medium values (100-1000ms):** Acceptable - slight delay but within normal range
- **High values (> 1000ms):** Poor - database connection is slow, may indicate network or DB issues
- **No data:** Monitoring not collecting this metric or ingestion component not running

**Color Thresholds:**

- Green: < 100ms (excellent)
- Yellow: 100-1000ms (acceptable)
- Red: > 1000ms (slow connection)

**Troubleshooting:**

- **If consistently > 1000ms:** Check database server load, network latency, connection pool
  settings
- **If spikes:** Check for database locks, slow queries, or network issues
- **If no data:** Verify `monitorIngestion.sh` is running and
  `check_database_connection_performance()` is enabled

---

### 3. Active Alerts

**Type:** Table (18 columns, full width)  
**Data Source:** `alerts` table  
**SQL Query:**
`SELECT component, alert_level, alert_type, message, created_at FROM alerts WHERE status = 'active' ORDER BY created_at DESC LIMIT 10`

**Values Meaning:**

- **alert_level:**
  - `critical` (red): Immediate action required, system functionality affected
  - `warning` (yellow): Attention needed, may impact performance
  - `info` (blue): Informational, no immediate action required
- **alert_type:** Category of alert (e.g., `database_connection`, `error_rate`, `system_swap_high`)
- **message:** Human-readable description of the alert
- **created_at:** When the alert was generated

**Color Coding:**

- Red: `critical` alerts
- Yellow: `warning` alerts
- Blue: `info` alerts

**Troubleshooting:**

- **For `critical` alerts:** Investigate immediately, check component status and logs
- **For `warning` alerts:** Review metrics, check if threshold needs adjustment or if issue is
  transient
- **To resolve alerts:** Fix underlying issue - alerts auto-resolve when condition clears, or
  manually resolve via alert management
- **If too many alerts:** Review alert thresholds, may need tuning based on normal operating
  conditions

---

## 2. Ingestion Monitoring

**Dashboard:** Ingestion Monitoring v5  
**Version:** 5  
**Last Updated:** 2026-01-15

**Focus:** This dashboard is focused on **operational monitoring** of the ingestion daemon and API
OSM interactions. It emphasizes behavior analysis, outlier detection, failure correlation, and
performance trends rather than configuration checks.

```
┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
│          │          │          │          │          │          │
│ Daemon   │ Daemon   │ Cycle    │ Failed   │ Daemon   │ Health   │
│ Status   │ Uptime   │ Success  │ Cycles   │ Restarts │ Status   │
│          │          │ Rate (%) │          │          │          │
│ [Stat]   │ [Stat]   │ [Gauge] │ [Stat]   │ [Stat]   │ [Stat]   │
│          │          │          │          │          │          │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
┌──────────────────────────┬──────────────────────────────────┐
│                          │                                  │
│  Daemon Cycle Duration   │  Daemon Processing Rate & Cycles │
│  (with Outliers)        │                                  │
│                          │                                  │
│  [Multi-line chart]      │  [Multi-line chart]              │
│                          │                                  │
│  - Last Cycle (blue)     │  - Notes/sec (blue)              │
│  - Average (green)       │  - Cycles/hour (green)          │
│  - Min (cyan)            │  X-axis: time (24h)              │
│  - Max (red)             │                                  │
│  X-axis: time (24h)      │  Shows processing throughput     │
│                          │                                  │
│  Detects outliers and    │                                  │
│  performance anomalies   │                                  │
│                          │                                  │
└──────────────────────────┴──────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Notes & Comments Processed Per Cycle                       │
│                                                              │
│  [Multi-line chart]                                          │
│                                                              │
│  - Notes Total (blue)                                        │
│  - Notes New (green)                                         │
│  - Notes Updated (yellow)                                    │
│  - Comments (purple)                                         │
│  X-axis: time (24h)                                          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
┌──────────────────────────┬──────────────────────────────────┐
│                          │                                  │
│  API OSM Download        │  API OSM Download Success Rate  │
│  Metrics                  │                                  │
│                          │                                  │
│  [Multi-line chart]      │  [Line chart]                    │
│                          │                                  │
│  - Total Downloads (blue) │  Y-axis: % (0-100)               │
│  - Successful (green)    │  X-axis: time (24h)              │
│  X-axis: time (24h)      │  Thresholds: green≥95%,         │
│                          │           yellow≥80%              │
│  Shows download volume    │  Shows API download reliability   │
│                          │                                  │
└──────────────────────────┴──────────────────────────────────┘
┌──────────┬──────────────────────────────────┬────────────────┐
│          │                                  │                │
│ Data     │  Notes Check Validator Status    │  Cycle Success │
│ Quality  │                                  │  Rate Over     │
│ Score    │  [Table]                         │  Time          │
│          │                                  │                │
│ [Gauge]  │  - Validator Status              │  [Line chart]  │
│          │  - Last Run                      │                │
│          │  - Notes Not in DB               │  Y-axis: %     │
│          │  - Quality Score                 │  X-axis: time  │
│          │                                  │                │
└──────────┴──────────────────────────────────┴────────────────┘
```

**Panels:**

### 1. Daemon Status

**Type:** Stat (3 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT metric_value::numeric as value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_status' ORDER BY timestamp DESC LIMIT 1`

**Values Meaning:**

- **1 (Active):** Daemon service is running and processing cycles
- **0 (Inactive):** Daemon service is stopped or not responding
- **null (No data):** No status data available

**Color Coding (via Grafana mappings):**

- Green: 1 (Active)
- Red: 0 (Inactive)
- Gray: null (No data)

**Troubleshooting:**

- **If Inactive:** Check daemon service: `systemctl status processAPINotesDaemon` or check process:
  `ps aux | grep processAPINotesDaemon`
- **If Unknown:** Verify `collectDaemonMetrics.sh` is running and collecting status

---

### 2. Daemon Uptime

**Type:** Stat (3 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT COALESCE((SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_uptime_seconds' ORDER BY timestamp DESC LIMIT 1), 0) as value`

**Values Meaning:**

- Shows how long the daemon has been running continuously (in seconds)
- **High uptime (≥ 30 days):** Daemon is stable (green - good)
- **Medium uptime (7-29 days):** Acceptable but monitor (yellow)
- **Low uptime (< 7 days):** Frequent restarts or recent restart (red - investigate)

**Color Thresholds:**

- Green: ≥ 30 days (2,592,000 seconds)
- Yellow: 7-29 days (604,800 - 2,505,600 seconds)
- Red: < 7 days (< 604,800 seconds)

**Troubleshooting:**

- **If frequently resetting:** Check for crashes, memory issues, or system restarts
- **If 0:** Daemon may not be running or metrics not being collected
- **If < 7 days:** Recent restart - check logs for crash reasons or maintenance windows

---

### 3. Cycle Success Rate

**Type:** Gauge (3 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT COALESCE((SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycle_success_rate_percent' ORDER BY timestamp DESC LIMIT 1), 100) as value`

**How It's Calculated:**

- The metric is calculated by `collectDaemonMetrics.sh` by analyzing daemon logs
- It searches for success messages: `"Cycle N completed successfully in X seconds"`
- It searches for failure messages: `"Cycle N failed"` or `"Cycle N error"`
- Formula: `(successful_cycles * 100) / (successful_cycles + failed_cycles)`
- Default: 100% if no cycle attempts detected

**Values Meaning:**

- **100%:** All cycles completed successfully (green - normal when everything works)
- **≥ 95%:** Excellent reliability (green)
- **80-94%:** Good reliability (yellow - monitor)
- **< 80%:** Poor reliability (red - investigate failures)

**When It Can Drop Below 100%:**

- **Database connection errors:** Daemon cannot connect to database
- **OSM API errors:** 4xx/5xx errors from OSM API causing cycle failures
- **Timeouts:** API or database queries timing out
- **Resource exhaustion:** Memory, disk space, or CPU limits reached
- **Network issues:** Connectivity problems preventing data retrieval
- **Permission errors:** File system or database permission issues

**Example:** If there are 10 successful cycles and 2 failed cycles: `(10 * 100) / 12 = 83.3%`

**Color Thresholds:**

- Green: ≥ 95%
- Yellow: 80-94%
- Red: < 80%

**Troubleshooting:**

- **If < 95%:** Check failed cycles panel and daemon logs for error patterns
- **If declining:** May indicate API issues, database problems, or resource constraints
- **If 100% consistently:** Normal - all cycles are completing successfully

---

### 4. Failed Cycles

**Type:** Stat (3 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT COALESCE((SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycles_failed_count' ORDER BY timestamp DESC LIMIT 1), 0) as value`

**Values Meaning:**

- Count of failed cycles in recent monitoring window
- **0:** All cycles successful (green)
- **1-4:** Some failures (yellow - investigate)
- **≥ 5:** Many failures (red - critical issue)

**Color Thresholds:**

- Green: 0 failures
- Yellow: 1-4 failures
- Red: ≥ 5 failures

**Troubleshooting:**

- **If > 0:** Check daemon logs, correlate with API error panels, check database connectivity
- **If increasing:** May indicate API rate limiting, database locks, or resource exhaustion

---

### 5. Daemon Restarts

**Type:** Stat (3 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT COALESCE((SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_restarts_count' ORDER BY timestamp DESC LIMIT 1), 0) as value`

**Values Meaning:**

- Count of daemon restarts in recent period
- **0:** No restarts (green - stable)
- **1-2:** Some restarts (yellow - investigate)
- **≥ 3:** Frequent restarts (red - critical)

**Color Thresholds:**

- Green: 0 restarts
- Yellow: 1-2 restarts
- Red: ≥ 3 restarts

**Troubleshooting:**

- **If > 0:** Check system logs, memory usage, crash dumps, or service manager logs
- **If frequent:** May indicate memory leaks, unhandled exceptions, or resource limits

---

### 6. Health Status

**Type:** Stat (3 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT metric_value::numeric as value FROM metrics WHERE component = 'ingestion' AND metric_name = 'health_status' ORDER BY timestamp DESC LIMIT 1`

**Values Meaning:**

- **1 (Healthy):** Overall ingestion component is functioning normally
- **0 (Unhealthy):** Component has issues, check dependencies and logs
- **null (No data):** Health check not running or metric not being recorded

**Color Coding (via Grafana mappings):**

- Green: 1 (Healthy)
- Red: 0 (Unhealthy)
- Gray: null (No data)

**Troubleshooting:**

- **If Unhealthy:** Check `component_health` table for details, review ingestion logs, verify
  database connectivity
- **If Unknown:** Verify `check_ingestion_health()` function is being called in monitoring script

---

### 7. Daemon Cycle Duration (with Outliers)

**Type:** Timeseries Chart (12 columns, multi-line)  
**Data Source:** `metrics` table  
**SQL Queries:**

- Last Cycle:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycle_duration_seconds' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Average:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycle_avg_duration_seconds' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Min:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycle_min_duration_seconds' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Max:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycle_max_duration_seconds' AND $__timeFilter(timestamp) ORDER BY timestamp`

**Values Meaning:**

- **Last Cycle (blue):** Duration of most recent cycle - shows current performance
- **Average (green):** Average duration over time - baseline performance
- **Min (cyan):** Minimum duration - best case performance
- **Max (red):** Maximum duration - worst case performance (outliers)

**Purpose:** Detects performance anomalies, outliers, and trends. When Max significantly exceeds
Average, indicates cycles taking unusually long.

**Troubleshooting:**

- **If Max >> Average:** Investigate what causes slow cycles - check API response times, database
  query performance, or system load
- **If Last Cycle > Average:** Current cycle is slower than normal - may indicate ongoing issues
- **If increasing trend:** Performance degradation - check for resource constraints or API slowdowns

---

### 8. Daemon Processing Rate & Cycles

**Type:** Timeseries Chart (12 columns, multi-line, dual Y-axis)  
**Data Source:** `metrics` table  
**SQL Queries:**

- Notes/sec:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_processing_rate_notes_per_second' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Cycles/hour:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycles_per_hour' AND $__timeFilter(timestamp) ORDER BY timestamp`

**Values Meaning:**

- **Notes/sec (blue, left Y-axis):** Processing throughput - notes processed per second in the last
  completed cycle
- **Cycles/hour (green, right Y-axis):** Cycle frequency - number of cycles completed in the last 60
  minutes

**Purpose:** Shows processing throughput and cycle frequency trends. Uses dual Y-axis to accommodate
different scales (Notes/sec: 0-100+, Cycles/hour: 0-70).

**Normal Behavior:**

- **Notes/sec = 0:** Normal when OSM API has no new notes to process. The daemon completes cycles
  successfully but finds nothing to process.
- **Cycles/hour = 50-60:** Expected range when daemon is running normally (approximately 1 cycle per
  minute).
- **Cycles/hour showing periodic peaks:** This is expected behavior - the metric counts cycles in
  the last hour, so values accumulate and reset as time windows shift.

**Troubleshooting:**

- **If Notes/sec = 0 for extended periods:** Normal if no OSM activity - verify daemon is running
  and check OSM API for new notes
- **If Notes/sec declining:** Processing slowing down - check API response times, database
  performance, or system resources
- **If Cycles/hour consistently < 50:** Daemon completing fewer cycles - may indicate longer cycle
  durations, delays, or daemon issues
- **If Cycles/hour = 0:** Daemon may be stopped or not processing - check daemon status and logs

---

### 9. Notes & Comments Processed Per Cycle

**Type:** Timeseries Chart (12 columns, multi-line)  
**Data Source:** `metrics` table  
**SQL Queries:**

- Notes Total:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_notes_processed_per_cycle' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Notes New:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_notes_new_count' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Notes Updated:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_notes_updated_count' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Comments:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_comments_processed_per_cycle' AND $__timeFilter(timestamp) ORDER BY timestamp`

**Values Meaning:**

- **Notes Total (blue):** Total notes processed in each cycle
- **Notes New (green):** New notes added to database
- **Notes Updated (yellow):** Existing notes updated
- **Comments (purple):** Total comments processed per cycle (a single note can have multiple
  comments)

**Purpose:** Shows processing volume per cycle for both notes and comments. Helps identify workload
patterns and correlate with performance issues. Comments are tracked separately because a single
note can have many comments, making this metric important for understanding actual processing load.

**When Values Are Zero:**

- **Normal behavior:** If the daemon is running but there's no new activity from OSM API, values
  will be 0
- **No activity:** OSM API may not have new notes/comments to process
- **Daemon idle:** The daemon completes cycles successfully but finds nothing to process

**Troubleshooting:**

- **If all values are 0 for extended period:** Normal if no OSM activity - verify daemon is running
  and check OSM API for new notes
- **If Total drops suddenly:** May indicate API issues or no new data available
- **If New = 0 for extended period:** No new notes being ingested - check API connectivity
- **If Updated >> New:** Many updates happening - may indicate data synchronization issues
- **If Comments = 0 but Notes > 0:** Notes are being processed but no comments found (normal for new
  notes without comments)

---

### 10. API OSM Download Success Rate

**Type:** Timeseries Chart (12 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'api_download_success_rate_percent' AND $__timeFilter(timestamp) ORDER BY timestamp`

**Values Meaning:**

- **≥ 95%:** Excellent API download reliability (green)
- **80-94%:** Good API download reliability (yellow)
- **< 80%:** Poor API download reliability (red - many failures)

**Color Thresholds:**

- Green: ≥ 95%
- Yellow: 80-94%
- Red: < 80%

**Purpose:** Shows API download success rate as a percentage. Low success rates correlate with
daemon failures and data ingestion gaps.

**Troubleshooting:**

- **If < 95%:** Check API OSM Download Metrics panel to see total vs successful downloads
- **If declining:** May indicate rate limiting, API issues, or network problems
- **If correlates with failed cycles:** API download failures are causing daemon cycle failures

---

### 11. API OSM Download Metrics

**Type:** Timeseries Chart (12 columns, multi-line)  
**Data Source:** `metrics` table  
**SQL Queries:**

- Total Downloads:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'api_download_total_count' AND $__timeFilter(timestamp) ORDER BY timestamp`
- Successful:
  `SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'api_download_successful_count' AND $__timeFilter(timestamp) ORDER BY timestamp`

**Values Meaning:**

- **Total Downloads (blue):** Total number of download attempts from OSM API
- **Successful (green):** Number of successful downloads

**Purpose:** Shows download volume and success counts. When both are 0, indicates no download
activity. When Total > Successful, indicates failures.

**Troubleshooting:**

- **If both are 0:** No download activity - normal if daemon is idle or no new data available
- **If Total > Successful:** Some downloads are failing - check API OSM Download Success Rate panel
- **If Total = Successful:** All downloads successful - normal operation

---

### 12. Data Quality Score

**Type:** Gauge (4 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT COALESCE((SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'data_quality_score' ORDER BY timestamp DESC LIMIT 1), 0) as value`

**How It's Calculated:**

- The metric is calculated by `check_ingestion_data_quality()` function in `monitorIngestion.sh`
- Starts at 100% and is reduced when problems are detected
- Currently penalizes when:
  1. `notesCheckVerifier.sh` finds errors or discrepancies → subtracts 10 points (line 1404)
  2. Script fails or doesn't run when expected (though current code doesn't always penalize this)

**Values Meaning:**

- **100%:** No data quality issues detected (green - normal when everything is correct)
- **90-100%:** Excellent data quality (green)
- **70-89%:** Good data quality (yellow - acceptable but monitor)
- **< 70%:** Poor data quality (red - data issues detected)

**When It Can Drop Below 100%:**

- **`notesCheckVerifier.sh` detects problems:**
  - Notes found in `notes_check` table that don't exist in main `notes` database
  - Discrepancies between expected and actual data
  - Errors during validation execution
- **Validator script fails:** If `notesCheckVerifier.sh` fails or doesn't execute when expected
- **Note:** Currently, `check_data_completeness()` and `check_data_freshness()` functions don't
  modify the score (they only record metrics), but could be extended to do so

**Example:** If validator finds issues: `100% - 10 points = 90%`

**Color Thresholds:**

- Green: ≥ 90%
- Yellow: 70-89%
- Red: < 70%

**Troubleshooting:**

- **If < 70%:** Run `notesCheckVerifier.sh` manually to see specific data quality issues
- **If 0%:** Verify `check_ingestion_data_quality()` is enabled and `notesCheckVerifier.sh` is
  executable
- **If 100% consistently:** Normal - no data quality issues detected

---

### 13. Notes Check Validator Status

**Type:** Table (10 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT 'Validator Status' as check_type, CASE WHEN COALESCE((SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'data_quality_check_status' ORDER BY timestamp DESC LIMIT 1), -1) = 1 THEN 'Passed' WHEN (SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'data_quality_check_status' ORDER BY timestamp DESC LIMIT 1) = 0 THEN 'Failed' WHEN (SELECT metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'data_quality_check_status' ORDER BY timestamp DESC LIMIT 1) = 2 THEN 'Running' ELSE 'Unknown' END as status UNION ALL SELECT 'Last Run', COALESCE(TO_CHAR((SELECT MAX(timestamp) FROM metrics WHERE component = 'ingestion' AND metric_name = 'data_quality_check_status'), 'YYYY-MM-DD HH24:MI:SS'), 'Never') UNION ALL SELECT 'Notes Not in DB', COALESCE((SELECT metric_value::text FROM metrics WHERE component = 'ingestion' AND metric_name = 'validator_notes_not_in_db_count' ORDER BY timestamp DESC LIMIT 1), 'N/A') UNION ALL SELECT 'Quality Score', COALESCE((SELECT ROUND(metric_value, 1)::text FROM metrics WHERE component = 'ingestion' AND metric_name = 'data_quality_score' ORDER BY timestamp DESC LIMIT 1), 'N/A') || '%'`

**Values Meaning:**

- **Validator Status:** Passed/Failed/Running/Unknown - status of last validation run
- **Last Run:** Timestamp of last validation execution
- **Notes Not in DB:** Count of notes found in check tables but not in main database (from
  `notesCheckValidator.sh`)
- **Quality Score:** Overall data quality percentage

**Purpose:** Shows validator execution status and count of notes not found in main database (data
quality issue).

**Troubleshooting:**

- **If Notes Not in DB > 0:** Some notes from Planet/API are not in main database - investigate data
  ingestion gaps
- **If Status = Failed:** Validation found issues - check validator logs
- **If Last Run = Never:** Validator not running - check cron job for `notesCheckValidator.sh`

---

### 14. Cycle Success Rate Over Time

**Type:** Timeseries Chart (10 columns)  
**Data Source:** `metrics` table  
**SQL Query:**
`SELECT timestamp AS time, metric_value AS value FROM metrics WHERE component = 'ingestion' AND metric_name = 'daemon_cycle_success_rate_percent' AND $__timeFilter(timestamp) ORDER BY timestamp`

**Values Meaning:**

- **≥ 95%:** Excellent reliability (green)
- **80-94%:** Good reliability (yellow)
- **< 80%:** Poor reliability (red)

**Color Thresholds:**

- Green: ≥ 95%
- Yellow: 80-94%
- Red: < 80%

**Purpose:** Shows daemon reliability trend over time. Helps identify periods of instability.

**Troubleshooting:**

- **If declining trend:** Daemon becoming less reliable - investigate recent changes, check API
  status, review logs
- **If sudden drops:** Correlate with API error panels to identify root cause
- **If consistently low:** May indicate systemic issues - check system resources, database
  performance, API connectivity

---

**Note:** This dashboard focuses on **operational monitoring** rather than configuration checks.
Script execution permissions and script counts are configuration concerns and are not included here.
Database connection time and other general database metrics are better suited for a dedicated
database monitoring dashboard.

---

## 3. Analytics Monitoring

**Dashboard:** Analytics Monitoring

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Analytics       │  Key Metrics                             │
│  Health Status   │                                          │
│                  │  [Multi-line chart]                      │
│  [Table: status] │                                          │
│                  │  Metrics:                                │
│  Status:         │  - etl_scripts_executable                 │
│  degraded/       │  - etl_scripts_running                   │
│  healthy/down    │  - etl_scripts_found                     │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Analytics Health Status** (Table, 6 columns) - Component status
2. **Key Metrics** (Chart, 18 columns) - Main ETL metrics

---

## 4. Analytics Datamarts Overview

**Dashboard:** Analytics Datamarts Overview

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Datamart        │  Row Counts                             │
│  Status          │                                          │
│                  │  [Bar chart]                             │
│  [Stat]          │                                          │
│                  │  Row count per datamart                  │
│  Running/        │                                          │
│  Not Running     │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Last Update Times                                           │
│                                                              │
│  [Table or chart]                                            │
│                                                              │
│  Last updates per datamart                                   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Panels:**

1. **Datamart Status** (Stat, 6 columns) - Datamart status (Running/Not Running)
2. **Row Counts** (Chart, 18 columns) - Row count per datamart
3. **Last Update Times** (Table/Chart) - Last updates

---

## 5. Analytics Data Quality

**Dashboard:** Analytics Data Quality

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Data Quality    │  Validation Results                      │
│  Score           │                                          │
│                  │  [Chart or table]                        │
│  [Gauge: 0-100%] │                                          │
│                  │  Validation results                      │
│  Quality score   │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────┬──────────────────────┐
│                  │                  │                      │
│  Issues by Type  │  Orphaned Facts │  Data Freshness     │
│                  │  Count          │                      │
│  [Chart]         │  [Number]        │  [Chart]             │
│                  │                  │                      │
│  Issues by type  │  Orphaned facts │  Data freshness      │
│                  │  count          │                      │
│                  │                  │                      │
└──────────────────┴──────────────────┴──────────────────────┘
```

**Panels:**

1. **Data Quality Score** (Gauge, 6 columns) - Quality score (0-100%)
2. **Validation Results** (Chart/Table, 12 columns) - Validation results
3. **Issues by Type** (Chart, 6 columns) - Issues by type
4. **Orphaned Facts Count** (Stat, 6 columns) - Orphaned facts count
5. **Data Freshness** (Chart, 6 columns) - Data freshness

---

## 6. Analytics DWH Performance

**Dashboard:** Analytics DWH Performance

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Query Performance Metrics                                  │
│                                                              │
│  [Line chart]                                                │
│                                                              │
│  Query performance metrics                                  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Slow Queries    │  Database Connections                   │
│                  │                                          │
│  [Table]         │  [Chart or stat]                         │
│                  │                                          │
│  Slow queries    │  Active connections                     │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Query Performance Metrics** (Chart, 18 columns) - Performance metrics
2. **Slow Queries** (Table, 9 columns) - Slow queries
3. **Database Connections** (Chart/Stat, 9 columns) - Database connections

---

## 7. Analytics ETL Overview

**Dashboard:** Analytics ETL Overview

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  ETL Job         │  ETL Execution Frequency                 │
│  Execution       │                                          │
│  Status          │  [Chart]                                 │
│                  │                                          │
│  [Table/Stat]    │  Execution frequency                     │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  ETL Duration    │  ETL Success Rate                        │
│                  │                                          │
│  [Chart]         │  [Gauge: 0-100%]                        │
│                  │                                          │
│  ETL job         │  Success rate                            │
│  duration        │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **ETL Job Execution Status** (Table/Stat, 9 columns) - Execution status
2. **ETL Execution Frequency** (Chart, 9 columns) - Execution frequency
3. **ETL Duration** (Chart, 9 columns) - Job duration
4. **ETL Success Rate** (Gauge, 9 columns) - Success rate (%)

---

## 8. Analytics Export Status

**Dashboard:** Analytics Export Status

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Export Status   │  GitHub Push Status                     │
│                  │                                          │
│  [Stat]          │  [Stat]                                  │
│                  │                                          │
│  Export status   │  GitHub push status                     │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────┬──────────────────────┐
│                  │                  │                      │
│  Files Exported  │  Export Size     │  Last Export         │
│                  │                  │                      │
│  [Number]        │  [Size]          │  [Time ago]          │
│                  │                  │                      │
│  Exported files  │  Total size       │  Last export         │
│                  │                  │                      │
└──────────────────┴──────────────────┴──────────────────────┘
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  JSON Schema     │  Export Duration                        │
│  Validation Rate │                                          │
│                  │  [Chart]                                 │
│  [Gauge: %]      │                                          │
│                  │  Export duration                         │
│  Validation rate │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Export Status** (Stat, 6 columns) - Export status
2. **GitHub Push Status** (Stat, 6 columns) - GitHub push status
3. **Files Exported** (Stat, 6 columns) - Exported files
4. **Export Size** (Stat, 6 columns) - Export size
5. **Last Export** (Stat, 6 columns) - Last export (time ago)
6. **JSON Schema Validation Rate** (Gauge, 6 columns) - Validation rate (%)
7. **Export Duration** (Chart, 12 columns) - Export duration

---

## 9. Analytics System Resources

**Dashboard:** Analytics System Resources

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  ETL CPU Usage   │  PostgreSQL CPU Usage (%)               │
│  (%)             │                                          │
│                  │  [Chart]                                 │
│  [Chart]         │                                          │
│                  │  PostgreSQL CPU usage                    │
│  ETL CPU usage   │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  ETL Memory      │  PostgreSQL Memory Usage                │
│  Usage           │                                          │
│                  │  [Chart]                                 │
│  [Chart]         │                                          │
│                  │  PostgreSQL memory usage                 │
│  ETL memory      │                                          │
│  usage           │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────┬──────────────────────┐
│                  │                  │                      │
│  ETL Disk I/O    │  System Disk     │  System Load        │
│                  │  Usage (%)       │  Average            │
│  [Chart]         │                  │                      │
│                  │  [Chart]         │  [Chart]             │
│  ETL disk I/O    │  System disk     │  System load         │
│                  │  usage           │  average             │
│                  │                  │                      │
└──────────────────┴──────────────────┴──────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ETL Log Disk Usage                                          │
│                                                              │
│  [Chart]                                                     │
│                                                              │
│  Disk usage for ETL logs                                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Panels:**

1. **ETL CPU Usage (%)** (Chart, 9 columns) - ETL CPU usage
2. **PostgreSQL CPU Usage (%)** (Chart, 9 columns) - PostgreSQL CPU usage
3. **ETL Memory Usage** (Chart, 9 columns) - ETL memory usage
4. **PostgreSQL Memory Usage** (Chart, 9 columns) - PostgreSQL memory usage
5. **ETL Disk I/O** (Chart, 6 columns) - ETL disk I/O
6. **System Disk Usage (%)** (Chart, 6 columns) - System disk usage
7. **System Load Average** (Chart, 6 columns) - System load average
8. **ETL Log Disk Usage** (Chart, 18 columns) - Disk usage for ETL logs

---

## 10. Wms Monitoring

**Dashboard:** Wms Monitoring

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Wms Health      │  Key Metrics                             │
│  Status          │                                          │
│                  │  [Multi-line chart]                      │
│  [Stat: status]  │                                          │
│                  │  Metrics:                                │
│  Status:         │  - error_rate_percent                    │
│  down/healthy/   │  - response_time_ms                     │
│  degraded        │  - service_availability                 │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Wms Health Status** (Stat, 6 columns) - WMS service status
2. **Key Metrics** (Chart, 18 columns) - Main metrics

---

## 11. Infrastructure Monitoring

**Dashboard:** Infrastructure Monitoring

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Infrastructure  │  Key Metrics                             │
│  Health Status   │                                          │
│                  │  [Multi-line chart]                      │
│  [Stat: status]  │                                          │
│                  │  Metrics:                                │
│  Status:         │  - cpu_usage_percent                     │
│  healthy/        │  - memory_usage_percent                  │
│  degraded        │  - disk_usage_percent                    │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Infrastructure Health Status** (Stat, 6 columns) - Infrastructure status
2. **Key Metrics** (Chart, 18 columns) - CPU, memory, disk

---

## 12. Api Monitoring

**Dashboard:** Api Monitoring

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Api Health      │  Key Metrics                             │
│  Status          │                                          │
│                  │  [Multi-line chart]                      │
│  [Stat: status]  │                                          │
│                  │  All API metrics                         │
│  Status:         │  (last 24 hours)                         │
│  down/healthy/   │                                          │
│  degraded        │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Api Health Status** (Stat, 6 columns) - API status
2. **Key Metrics** (Chart, 18 columns) - All API metrics

---

## 13. Api Integration

**Dashboard:** Api Integration

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Integration     │  API Endpoint Health                     │
│  Status          │                                          │
│                  │  [Chart or table]                        │
│  [Stat]          │                                          │
│                  │  API endpoint health                     │
│  Integration     │                                          │
│  status          │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Integration Metrics                                         │
│                                                              │
│  [Chart]                                                     │
│                                                              │
│  Integration metrics                                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Panels:**

1. **Integration Status** (Stat, 6 columns) - Integration status
2. **API Endpoint Health** (Chart/Table, 12 columns) - API endpoint health
3. **Integration Metrics** (Chart, 18 columns) - Integration metrics

---

## 14. Boundary Processing

**Dashboard:** Boundary Processing - Ingestion

```
┌──────────────────┬──────────────────┬──────────────────────┐
│                  │                  │                      │
│  Countries Last  │  Maritime        │  Notes Without      │
│  Update Age      │  Boundaries Last │  Country            │
│  (hours)         │  Update Age      │                      │
│                  │  (hours)         │  [Stat]              │
│  [Stat]          │                  │                      │
│                  │  [Stat]          │  Notes without       │
│  Countries       │                  │  country             │
│  update age      │  Maritime        │                      │
│                  │  boundaries      │                      │
│                  │  update age     │                      │
└──────────────────┴──────────────────┴──────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Processing Metrics                                          │
│                                                              │
│  [Chart]                                                     │
│                                                              │
│  Boundary processing metrics                                 │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Panels:**

1. **Countries Last Update Age** (Stat, 6 columns) - Countries update age (hours)
2. **Maritime Boundaries Last Update Age** (Stat, 6 columns) - Maritime boundaries update age
3. **Notes Without Country** (Stat, 6 columns) - Notes without country
4. **Processing Metrics** (Chart, 18 columns) - Boundary processing metrics

---

## 15. Daemon Overview

**Dashboard:** Daemon Overview

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Daemon Status   │  Cycles per Hour                         │
│                  │                                          │
│  [Gauge:         │  [Line chart]                            │
│   Active/Inactive]│                                          │
│                  │  Y-axis: cycles per hour                 │
│  Status:         │  X-axis: time (24h)                      │
│  Active (green)  │                                          │
│  Inactive (red)  │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Cycle Duration  │  Cycle Success Rate                     │
│  (seconds)       │                                          │
│                  │  [Chart]                                 │
│  [Chart]         │                                          │
│                  │  Cycle success rate                      │
│  Cycle duration  │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Daemon Status** (Gauge, 6 columns) - Daemon status (Active/Inactive)
2. **Cycles per Hour** (Chart, 12 columns) - Cycles per hour
3. **Cycle Duration** (Chart, 12 columns) - Cycle duration (seconds)
4. **Cycle Success Rate** (Chart, 12 columns) - Cycle success rate

---

## 16. Database Performance

**Dashboard:** Database Performance - Ingestion

```
┌──────────────────┬──────────────────┬──────────────────────┐
│                  │                  │                      │
│  Cache Hit       │  Table Sizes     │  Connection Usage   │
│  Ratio (%)       │  (bytes)         │  (%)                 │
│                  │                  │                      │
│  [Gauge: 0-100%] │  [Chart]         │  [Gauge: 0-100%]     │
│                  │                  │                      │
│  Cache hit ratio │  Table sizes     │  Connection usage    │
│                  │                  │                      │
└──────────────────┴──────────────────┴──────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Query Performance                                          │
│                                                              │
│  [Chart]                                                     │
│                                                              │
│  Query performance metrics                                   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Panels:**

1. **Cache Hit Ratio (%)** (Gauge, 6 columns) - Cache hit ratio
2. **Table Sizes** (Chart, 6 columns) - Table sizes (bytes)
3. **Connection Usage (%)** (Gauge, 6 columns) - Connection usage
4. **Query Performance** (Chart, 18 columns) - Query performance metrics

---

## 17. System Resources

**Dashboard:** System Resources

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  CPU Usage       │  Memory Usage                            │
│                  │                                          │
│  [Chart]         │  [Chart]                                 │
│                  │                                          │
│  CPU usage       │  Memory usage                            │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────┬──────────────────────┐
│                  │                  │                      │
│  Disk Usage      │  Network I/O     │  System Load        │
│                  │                  │                      │
│  [Chart]         │  [Chart]         │  [Chart]             │
│                  │                  │                      │
│  Disk usage      │  Network I/O     │  System load         │
│                  │                  │                      │
└──────────────────┴──────────────────┴──────────────────────┘
```

**Panels:**

1. **CPU Usage** (Chart, 9 columns) - CPU usage
2. **Memory Usage** (Chart, 9 columns) - Memory usage
3. **Disk Usage** (Chart, 6 columns) - Disk usage
4. **Network I/O** (Chart, 6 columns) - Network I/O
5. **System Load** (Chart, 6 columns) - System load

---

## 18. Log Analysis - Ingestion

**Dashboard:** Log Analysis - Ingestion

```
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Cycle Total     │  Cycles Frequency                       │
│  Duration        │  (per hour)                             │
│  (seconds)       │                                          │
│                  │  [Line chart]                           │
│  [Chart]         │                                          │
│                  │  Y-axis: cycles per hour                 │
│  Total cycle      │  X-axis: time (24h)                      │
│  duration        │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
┌──────────────────┬──────────────────────────────────────────┐
│                  │                                          │
│  Cycle Success   │  Current Cycle Number                    │
│  Rate (%)        │                                          │
│                  │  [Number]                                │
│  [Gauge: 0-100%] │                                          │
│                  │  Current cycle number                    │
│  Cycle success   │                                          │
│  rate            │                                          │
│                  │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

**Panels:**

1. **Cycle Total Duration** (Chart, 12 columns) - Total cycle duration (seconds)
2. **Cycles Frequency** (Chart, 12 columns) - Cycles frequency (per hour)
3. **Cycle Success Rate** (Gauge, 6 columns) - Cycle success rate (%)
4. **Current Cycle Number** (Stat, 6 columns) - Current cycle number

---

## General Notes

- **Total dashboard width:** 18 columns (Grafana uses 24-column grid system, but these dashboards
  use 18)
- **Default time range:** Last 24 hours
- **Auto refresh:** Every 30 seconds
- **Data source:** PostgreSQL (`notes_monitoring`)
- **Monitored components:** 7 (analytics, api, daemon, data, infrastructure, ingestion, wms)

---

**Last updated:** 2026-01-15  
**Note:** This document now includes detailed information about data sources, value meanings,
thresholds, and troubleshooting for each panel.
