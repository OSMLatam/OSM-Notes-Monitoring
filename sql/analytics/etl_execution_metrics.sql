-- ETL Execution Metrics Queries for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2026-01-09
--
-- These queries extract ETL execution metrics from the data warehouse
-- Assumes connection to the analytics/data warehouse database (schema: dwh)

-- Query 1: Last processed timestamp
-- Returns the most recent timestamp processed by the ETL
SELECT 
    MAX(action_at) AS last_fact_timestamp,
    EXTRACT(EPOCH FROM (NOW() - MAX(action_at))) AS seconds_since_last_fact
FROM dwh.facts;

-- Query 2: Facts processed in last execution (last hour)
-- Returns count of facts processed in the last hour
SELECT 
    COUNT(*) AS facts_processed_last_hour,
    COUNT(DISTINCT note_id) AS unique_notes_processed
FROM dwh.facts
WHERE action_at > NOW() - INTERVAL '1 hour';

-- Query 3: Facts processed in last execution window (last 15 minutes for incremental)
-- Returns count of facts processed in the last 15 minutes (typical ETL execution window)
SELECT 
    COUNT(*) AS facts_processed_last_execution,
    COUNT(DISTINCT note_id) AS unique_notes_processed,
    MIN(action_at) AS first_fact_timestamp,
    MAX(action_at) AS last_fact_timestamp
FROM dwh.facts
WHERE action_at > NOW() - INTERVAL '15 minutes';

-- Query 4: Facts statistics by execution mode
-- Returns facts count for initial load vs incremental updates
-- (Initial loads typically have older timestamps, incrementals have recent timestamps)
SELECT 
    CASE 
        WHEN action_at > NOW() - INTERVAL '1 day' THEN 'incremental'
        ELSE 'initial_load'
    END AS execution_mode,
    COUNT(*) AS facts_count,
    COUNT(DISTINCT note_id) AS unique_notes_count,
    MIN(action_at) AS first_timestamp,
    MAX(action_at) AS last_timestamp
FROM dwh.facts
GROUP BY 
    CASE 
        WHEN action_at > NOW() - INTERVAL '1 day' THEN 'incremental'
        ELSE 'initial_load'
    END;

-- Query 5: Facts processed by hour (for execution frequency analysis)
-- Returns facts processed per hour to detect execution frequency
SELECT 
    DATE_TRUNC('hour', action_at) AS hour,
    COUNT(*) AS facts_processed,
    COUNT(DISTINCT note_id) AS unique_notes_processed
FROM dwh.facts
WHERE action_at > NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', action_at)
ORDER BY hour DESC;

-- Query 6: Facts growth rate
-- Returns facts growth rate to detect processing rate
SELECT 
    DATE_TRUNC('hour', action_at) AS hour,
    COUNT(*) AS facts_count,
    COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY DATE_TRUNC('hour', action_at)) AS facts_growth,
    ROUND(COUNT(*) * 1.0 / NULLIF(LAG(COUNT(*)) OVER (ORDER BY DATE_TRUNC('hour', action_at)), 0), 2) AS growth_rate
FROM dwh.facts
WHERE action_at > NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', action_at)
ORDER BY hour DESC;

-- Query 7: Facts by year (for partition analysis)
-- Returns facts count by year to analyze partition distribution
SELECT 
    DATE_PART('year', action_at) AS year,
    COUNT(*) AS fact_count,
    COUNT(DISTINCT note_id) AS unique_notes_count,
    MIN(action_at) AS first_timestamp,
    MAX(action_at) AS last_timestamp
FROM dwh.facts
GROUP BY DATE_PART('year', action_at)
ORDER BY year DESC;

-- Query 8: Data freshness gap
-- Returns the gap between ingestion and DWH processing
-- (Assumes there's a way to compare with ingestion timestamps)
SELECT 
    MAX(action_at) AS last_dwh_timestamp,
    NOW() AS current_timestamp,
    EXTRACT(EPOCH FROM (NOW() - MAX(action_at))) AS freshness_gap_seconds,
    CASE 
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(action_at))) > 7200 THEN 'STALE'
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(action_at))) > 3600 THEN 'WARNING'
        ELSE 'FRESH'
    END AS freshness_status
FROM dwh.facts;

-- Query 9: Dimensions update statistics
-- Returns statistics about dimensions updates
-- (Adjust table names based on actual schema)
SELECT 
    'dimension_countries' AS dimension_name,
    COUNT(*) AS record_count,
    MAX(updated_at) AS last_update
FROM dwh.dimension_countries
UNION ALL
SELECT 
    'dimension_users' AS dimension_name,
    COUNT(*) AS record_count,
    MAX(updated_at) AS last_update
FROM dwh.dimension_users
UNION ALL
SELECT 
    'dimension_dates' AS dimension_name,
    COUNT(*) AS record_count,
    MAX(updated_at) AS last_update
FROM dwh.dimension_dates
ORDER BY dimension_name;

-- Query 10: Validation functions execution
-- Executes validation functions MON-001 and MON-002
-- Note: These functions should return structured results
-- Adjust based on actual function signatures

-- MON-001: Validate note_current_status
SELECT * FROM dwh.validate_note_current_status();

-- MON-002: Validate comment counts
SELECT * FROM dwh.validate_comment_counts();

-- Query 11: Orphaned facts detection
-- Detects facts without valid dimension references
SELECT 
    COUNT(*) AS orphaned_facts_count
FROM dwh.facts f
LEFT JOIN dwh.dimension_countries c ON f.dimension_id_country = c.dimension_country_id
WHERE c.dimension_country_id IS NULL;

-- Query 12: Facts processing rate estimation
-- Estimates facts processing rate based on recent activity
SELECT 
    COUNT(*) AS facts_processed,
    EXTRACT(EPOCH FROM (MAX(action_at) - MIN(action_at))) AS time_span_seconds,
    CASE 
        WHEN EXTRACT(EPOCH FROM (MAX(action_at) - MIN(action_at))) > 0 
        THEN ROUND(COUNT(*) * 1.0 / EXTRACT(EPOCH FROM (MAX(action_at) - MIN(action_at))), 2)
        ELSE 0
    END AS facts_per_second
FROM dwh.facts
WHERE action_at > NOW() - INTERVAL '1 hour';

-- Query 13: ETL execution gaps detection
-- Detects gaps in ETL execution by analyzing facts timestamps
WITH fact_hours AS (
    SELECT 
        DATE_TRUNC('hour', action_at) AS hour,
        COUNT(*) AS facts_count
    FROM dwh.facts
    WHERE action_at > NOW() - INTERVAL '24 hours'
    GROUP BY DATE_TRUNC('hour', action_at)
),
hour_gaps AS (
    SELECT 
        hour,
        facts_count,
        LAG(hour) OVER (ORDER BY hour) AS prev_hour,
        EXTRACT(EPOCH FROM (hour - LAG(hour) OVER (ORDER BY hour))) / 3600 AS hours_gap
    FROM fact_hours
)
SELECT 
    hour,
    prev_hour,
    hours_gap,
    CASE 
        WHEN hours_gap > 2 THEN 'GAP_DETECTED'
        WHEN hours_gap IS NULL THEN 'FIRST_HOUR'
        ELSE 'OK'
    END AS gap_status
FROM hour_gaps
WHERE hours_gap > 1.5 OR hours_gap IS NULL
ORDER BY hour DESC;

-- Query 14: Facts by action type (if available)
-- Returns facts count by action type to understand processing patterns
SELECT 
    action_type,
    COUNT(*) AS facts_count,
    COUNT(DISTINCT note_id) AS unique_notes_count,
    MIN(action_at) AS first_timestamp,
    MAX(action_at) AS last_timestamp
FROM dwh.facts
WHERE action_at > NOW() - INTERVAL '24 hours'
GROUP BY action_type
ORDER BY facts_count DESC;

-- Query 15: Facts processing summary for last execution
-- Comprehensive summary of last ETL execution
SELECT 
    COUNT(*) AS total_facts,
    COUNT(DISTINCT note_id) AS unique_notes,
    COUNT(DISTINCT DATE_TRUNC('hour', action_at)) AS hours_covered,
    MIN(action_at) AS first_fact_timestamp,
    MAX(action_at) AS last_fact_timestamp,
    EXTRACT(EPOCH FROM (MAX(action_at) - MIN(action_at))) AS execution_window_seconds,
    CASE 
        WHEN EXTRACT(EPOCH FROM (MAX(action_at) - MIN(action_at))) > 0 
        THEN ROUND(COUNT(*) * 1.0 / EXTRACT(EPOCH FROM (MAX(action_at) - MIN(action_at))), 2)
        ELSE 0
    END AS processing_rate_facts_per_second
FROM dwh.facts
WHERE action_at > NOW() - INTERVAL '15 minutes';
