-- Processing Status Queries for Ingestion Monitoring
-- Version: 1.0.0
-- Date: 2025-12-24
--
-- These queries check processing status and execution history
-- Assumes connection to the ingestion database

-- Query 1: Processing execution summary
-- Returns summary of processing executions (if execution log table exists)
-- Note: This assumes a processing_log table exists. Adjust based on actual schema.
SELECT 
    DATE_TRUNC('day', execution_time) AS execution_date,
    COUNT(*) AS execution_count,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successful_executions,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_executions,
    AVG(duration_seconds) AS avg_duration_seconds,
    MAX(duration_seconds) AS max_duration_seconds
FROM processing_log
WHERE execution_time > NOW() - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', execution_time)
ORDER BY execution_date DESC;

-- Query 2: Last successful processing execution
-- Returns the timestamp of the last successful processing
SELECT 
    MAX(execution_time) AS last_successful_execution,
    EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) AS seconds_since_last_execution
FROM processing_log
WHERE status = 'success';

-- Query 3: Processing failures in last 24 hours
-- Returns details of recent processing failures
SELECT 
    execution_time,
    status,
    error_message,
    duration_seconds
FROM processing_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '24 hours'
ORDER BY execution_time DESC;

-- Query 4: Processing performance trends
-- Shows processing duration trends over time
SELECT 
    DATE_TRUNC('hour', execution_time) AS hour,
    AVG(duration_seconds) AS avg_duration,
    MIN(duration_seconds) AS min_duration,
    MAX(duration_seconds) AS max_duration,
    COUNT(*) AS execution_count
FROM processing_log
WHERE execution_time > NOW() - INTERVAL '7 days'
  AND status = 'success'
GROUP BY DATE_TRUNC('hour', execution_time)
ORDER BY hour DESC;

-- Query 5: Processing success rate
-- Calculates success rate for different time periods
SELECT 
    'Last Hour' AS period,
    COUNT(*) FILTER (WHERE status = 'success') AS successful,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed,
    ROUND(COUNT(*) FILTER (WHERE status = 'success') * 100.0 / NULLIF(COUNT(*), 0), 2) AS success_rate_percent
FROM processing_log
WHERE execution_time > NOW() - INTERVAL '1 hour'
UNION ALL
SELECT 
    'Last 24 Hours' AS period,
    COUNT(*) FILTER (WHERE status = 'success') AS successful,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed,
    ROUND(COUNT(*) FILTER (WHERE status = 'success') * 100.0 / NULLIF(COUNT(*), 0), 2) AS success_rate_percent
FROM processing_log
WHERE execution_time > NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 
    'Last 7 Days' AS period,
    COUNT(*) FILTER (WHERE status = 'success') AS successful,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed,
    ROUND(COUNT(*) FILTER (WHERE status = 'success') * 100.0 / NULLIF(COUNT(*), 0), 2) AS success_rate_percent
FROM processing_log
WHERE execution_time > NOW() - INTERVAL '7 days';

-- Query 6: Notes processed per execution
-- Returns number of notes processed per execution (if available)
SELECT 
    execution_time,
    notes_processed,
    duration_seconds,
    ROUND(notes_processed / NULLIF(duration_seconds, 0), 2) AS notes_per_second
FROM processing_log
WHERE execution_time > NOW() - INTERVAL '7 days'
  AND notes_processed IS NOT NULL
ORDER BY execution_time DESC;

-- Query 7: Processing gaps detection
-- Detects gaps in processing (missing expected executions)
-- Assumes processing should run every X hours
WITH expected_executions AS (
    SELECT generate_series(
        NOW() - INTERVAL '7 days',
        NOW(),
        INTERVAL '1 hour'
    ) AS expected_time
),
actual_executions AS (
    SELECT DATE_TRUNC('hour', execution_time) AS execution_time
    FROM processing_log
    WHERE execution_time > NOW() - INTERVAL '7 days'
      AND status = 'success'
)
SELECT 
    e.expected_time AS missing_execution_time,
    EXTRACT(EPOCH FROM (NOW() - e.expected_time)) / 3600 AS hours_ago
FROM expected_executions e
LEFT JOIN actual_executions a ON DATE_TRUNC('hour', e.expected_time) = a.execution_time
WHERE a.execution_time IS NULL
ORDER BY e.expected_time DESC;

