-- Error Analysis Queries for Ingestion Monitoring
-- Version: 1.0.0
-- Date: 2025-12-24
--
-- These queries analyze errors and failures in ingestion
-- Assumes connection to the ingestion database and/or monitoring database

-- Query 1: Error summary from processing log
-- Returns summary of errors from processing executions
SELECT 
    DATE_TRUNC('day', execution_time) AS error_date,
    COUNT(*) AS error_count,
    COUNT(DISTINCT error_message) AS unique_errors,
    MAX(duration_seconds) AS max_duration,
    MIN(duration_seconds) AS min_duration
FROM processing_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', execution_time)
ORDER BY error_date DESC;

-- Query 2: Most common errors
-- Returns most frequently occurring errors
SELECT 
    error_message,
    COUNT(*) AS occurrence_count,
    MAX(execution_time) AS last_occurrence,
    AVG(duration_seconds) AS avg_duration
FROM processing_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '7 days'
GROUP BY error_message
ORDER BY occurrence_count DESC
LIMIT 10;

-- Query 3: Error rate by hour
-- Shows error rate trends throughout the day
SELECT 
    EXTRACT(HOUR FROM execution_time) AS hour_of_day,
    COUNT(*) FILTER (WHERE status = 'success') AS successful,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed,
    ROUND(COUNT(*) FILTER (WHERE status = 'failed') * 100.0 / NULLIF(COUNT(*), 0), 2) AS error_rate_percent
FROM processing_log
WHERE execution_time > NOW() - INTERVAL '7 days'
GROUP BY EXTRACT(HOUR FROM execution_time)
ORDER BY hour_of_day;

-- Query 4: Error patterns
-- Identifies patterns in error messages
SELECT 
    SUBSTRING(error_message FROM 1 FOR 50) AS error_pattern,
    COUNT(*) AS count,
    MAX(execution_time) AS last_seen
FROM processing_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '7 days'
GROUP BY SUBSTRING(error_message FROM 1 FOR 50)
ORDER BY count DESC
LIMIT 20;

-- Query 5: Recovery time analysis
-- Analyzes time to recover from errors
WITH error_events AS (
    SELECT 
        execution_time,
        ROW_NUMBER() OVER (ORDER BY execution_time) AS error_seq
    FROM processing_log
    WHERE status = 'failed'
      AND execution_time > NOW() - INTERVAL '30 days'
),
recovery_events AS (
    SELECT 
        execution_time,
        ROW_NUMBER() OVER (ORDER BY execution_time) AS recovery_seq
    FROM processing_log
    WHERE status = 'success'
      AND execution_time > NOW() - INTERVAL '30 days'
)
SELECT 
    e.execution_time AS error_time,
    r.execution_time AS recovery_time,
    EXTRACT(EPOCH FROM (r.execution_time - e.execution_time)) AS recovery_seconds
FROM error_events e
JOIN recovery_events r ON r.recovery_seq = e.error_seq
ORDER BY e.execution_time DESC
LIMIT 10;

-- Query 6: Error frequency analysis
-- Shows error frequency over time
SELECT 
    DATE_TRUNC('hour', execution_time) AS hour,
    COUNT(*) AS error_count,
    COUNT(DISTINCT error_message) AS unique_errors
FROM processing_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', execution_time)
ORDER BY hour DESC;

-- Query 7: Error impact assessment
-- Assesses impact of errors (based on duration and affected records)
SELECT 
    error_message,
    COUNT(*) AS error_count,
    AVG(duration_seconds) AS avg_duration,
    MAX(duration_seconds) AS max_duration,
    SUM(COALESCE(notes_processed, 0)) AS total_notes_affected
FROM processing_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '7 days'
GROUP BY error_message
ORDER BY error_count DESC, avg_duration DESC;

-- Query 8: Error trends
-- Shows error trends over time (increasing/decreasing)
WITH daily_errors AS (
    SELECT 
        DATE_TRUNC('day', execution_time) AS day,
        COUNT(*) AS error_count
    FROM processing_log
    WHERE status = 'failed'
      AND execution_time > NOW() - INTERVAL '30 days'
    GROUP BY DATE_TRUNC('day', execution_time)
)
SELECT 
    day,
    error_count,
    LAG(error_count) OVER (ORDER BY day) AS previous_day_errors,
    error_count - LAG(error_count) OVER (ORDER BY day) AS change,
    ROUND((error_count - LAG(error_count) OVER (ORDER BY day)) * 100.0 / NULLIF(LAG(error_count) OVER (ORDER BY day), 0), 2) AS percent_change
FROM daily_errors
ORDER BY day DESC;

