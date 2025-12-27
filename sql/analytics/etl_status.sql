-- ETL Status Queries for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2025-12-26
--
-- These queries check ETL job execution status and history
-- Assumes connection to the analytics/data warehouse database

-- Query 1: ETL execution summary
-- Returns summary of ETL executions (if execution log table exists)
-- Note: This assumes an etl_execution_log table exists. Adjust based on actual schema.
SELECT 
    DATE_TRUNC('day', execution_time) AS execution_date,
    COUNT(*) AS execution_count,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successful_executions,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_executions,
    AVG(duration_seconds) AS avg_duration_seconds,
    MAX(duration_seconds) AS max_duration_seconds,
    MIN(duration_seconds) AS min_duration_seconds
FROM etl_execution_log
WHERE execution_time > NOW() - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', execution_time)
ORDER BY execution_date DESC;

-- Query 2: Last successful ETL execution
-- Returns the timestamp of the last successful ETL job
SELECT 
    MAX(execution_time) AS last_successful_execution,
    EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) AS seconds_since_last_execution,
    job_name,
    duration_seconds
FROM etl_execution_log
WHERE status = 'success'
GROUP BY job_name, duration_seconds
ORDER BY last_successful_execution DESC;

-- Query 3: ETL failures in last 24 hours
-- Returns details of recent ETL failures
SELECT 
    execution_time,
    job_name,
    status,
    error_message,
    duration_seconds,
    records_processed
FROM etl_execution_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '24 hours'
ORDER BY execution_time DESC;

-- Query 4: ETL performance trends
-- Shows ETL duration trends over time
SELECT 
    DATE_TRUNC('hour', execution_time) AS hour,
    job_name,
    AVG(duration_seconds) AS avg_duration,
    MIN(duration_seconds) AS min_duration,
    MAX(duration_seconds) AS max_duration,
    COUNT(*) AS execution_count,
    AVG(records_processed) AS avg_records_processed
FROM etl_execution_log
WHERE execution_time > NOW() - INTERVAL '7 days'
  AND status = 'success'
GROUP BY DATE_TRUNC('hour', execution_time), job_name
ORDER BY hour DESC, job_name;

-- Query 5: ETL success rate
-- Calculates success rate for different time periods
SELECT 
    'Last Hour' AS period,
    COUNT(*) AS total_executions,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successful_executions,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_executions,
    ROUND(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS success_rate_percent
FROM etl_execution_log
WHERE execution_time > NOW() - INTERVAL '1 hour'
UNION ALL
SELECT 
    'Last 24 Hours' AS period,
    COUNT(*) AS total_executions,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successful_executions,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_executions,
    ROUND(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS success_rate_percent
FROM etl_execution_log
WHERE execution_time > NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 
    'Last 7 Days' AS period,
    COUNT(*) AS total_executions,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successful_executions,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_executions,
    ROUND(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS success_rate_percent
FROM etl_execution_log
WHERE execution_time > NOW() - INTERVAL '7 days'
ORDER BY 
    CASE period
        WHEN 'Last Hour' THEN 1
        WHEN 'Last 24 Hours' THEN 2
        WHEN 'Last 7 Days' THEN 3
    END;

-- Query 6: ETL jobs by status
-- Groups ETL executions by status
SELECT 
    job_name,
    status,
    COUNT(*) AS execution_count,
    AVG(duration_seconds) AS avg_duration_seconds,
    MAX(duration_seconds) AS max_duration_seconds,
    MAX(execution_time) AS last_execution
FROM etl_execution_log
WHERE execution_time > NOW() - INTERVAL '7 days'
GROUP BY job_name, status
ORDER BY job_name, status;

-- Query 7: Currently running ETL jobs
-- Identifies ETL jobs that are currently executing
-- Note: This assumes a running_jobs table or similar. Adjust based on actual schema.
SELECT 
    job_name,
    start_time,
    EXTRACT(EPOCH FROM (NOW() - start_time)) AS runtime_seconds,
    pid,
    status
FROM etl_running_jobs
WHERE status = 'running'
ORDER BY start_time;

-- Query 8: ETL execution gaps
-- Detects gaps in ETL execution schedule
SELECT 
    job_name,
    MAX(execution_time) AS last_execution,
    EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) AS seconds_since_last_execution,
    CASE 
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) > 3600 THEN 'STALE'
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) > 7200 THEN 'CRITICAL'
        ELSE 'OK'
    END AS status
FROM etl_execution_log
WHERE status = 'success'
GROUP BY job_name
HAVING EXTRACT(EPOCH FROM (NOW() - MAX(execution_time))) > 3600
ORDER BY seconds_since_last_execution DESC;

