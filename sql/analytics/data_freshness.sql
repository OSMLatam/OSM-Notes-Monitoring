-- Data Freshness Queries for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2025-12-26
--
-- These queries check data warehouse freshness and update timestamps
-- Assumes connection to the analytics/data warehouse database

-- Query 1: Data warehouse freshness summary
-- Returns freshness information across all data warehouse tables
SELECT 
    'notes' AS table_name,
    MAX(updated_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS age_seconds,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') AS records_updated_last_hour
FROM notes
UNION ALL
SELECT 
    'note_comments' AS table_name,
    MAX(created_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) AS age_seconds,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour') AS records_updated_last_hour
FROM note_comments
UNION ALL
SELECT 
    'notes_summary' AS table_name,
    MAX(updated_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS age_seconds,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') AS records_updated_last_hour
FROM notes_summary
UNION ALL
SELECT 
    'notes_statistics' AS table_name,
    MAX(updated_at) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS age_seconds,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') AS records_updated_last_hour
FROM notes_statistics
ORDER BY age_seconds DESC;

-- Query 2: Data mart freshness
-- Returns freshness information for data marts
SELECT 
    'data_mart' AS mart_name,
    COALESCE(
        MAX(updated_at),
        MAX(last_updated),
        MAX(timestamp)
    ) AS last_update,
    EXTRACT(EPOCH FROM (NOW() - COALESCE(
        MAX(updated_at),
        MAX(last_updated),
        MAX(timestamp)
    ))) AS age_seconds,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE 
        updated_at > NOW() - INTERVAL '1 hour' OR
        last_updated > NOW() - INTERVAL '1 hour' OR
        timestamp > NOW() - INTERVAL '1 hour'
    ) AS recent_updates
FROM (
    SELECT updated_at, last_updated, timestamp
    FROM notes_summary
    UNION ALL
    SELECT updated_at, last_updated, timestamp
    FROM notes_statistics
    UNION ALL
    SELECT updated_at, last_updated, timestamp
    FROM notes_aggregated
) AS mart_tables;

-- Query 3: Stale data detection
-- Identifies data that hasn't been updated recently
SELECT 
    'notes' AS table_name,
    COUNT(*) AS stale_records_count,
    MIN(updated_at) AS oldest_update,
    MAX(updated_at) AS newest_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS max_age_seconds
FROM notes
WHERE updated_at < NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 
    'note_comments' AS table_name,
    COUNT(*) AS stale_records_count,
    MIN(created_at) AS oldest_update,
    MAX(created_at) AS newest_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) AS max_age_seconds
FROM note_comments
WHERE created_at < NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 
    'notes_summary' AS table_name,
    COUNT(*) AS stale_records_count,
    MIN(updated_at) AS oldest_update,
    MAX(updated_at) AS newest_update,
    EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS max_age_seconds
FROM notes_summary
WHERE updated_at < NOW() - INTERVAL '24 hours';

-- Query 4: Recent update activity
-- Summary of recent data warehouse updates
SELECT 
    DATE_TRUNC('hour', updated_at) AS hour,
    COUNT(*) AS records_updated,
    COUNT(DISTINCT note_id) AS unique_notes_updated
FROM notes
WHERE updated_at > NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', updated_at)
ORDER BY hour DESC
LIMIT 24;

-- Query 5: Data freshness by table
-- Groups tables by freshness status
SELECT 
    table_name,
    last_update,
    age_seconds,
    CASE 
        WHEN age_seconds < 3600 THEN 'FRESH'
        WHEN age_seconds < 7200 THEN 'STALE'
        WHEN age_seconds < 86400 THEN 'VERY_STALE'
        ELSE 'CRITICAL'
    END AS freshness_status
FROM (
    SELECT 
        'notes' AS table_name,
        MAX(updated_at) AS last_update,
        EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS age_seconds
    FROM notes
    UNION ALL
    SELECT 
        'note_comments' AS table_name,
        MAX(created_at) AS last_update,
        EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) AS age_seconds
    FROM note_comments
    UNION ALL
    SELECT 
        'notes_summary' AS table_name,
        MAX(updated_at) AS last_update,
        EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS age_seconds
    FROM notes_summary
    UNION ALL
    SELECT 
        'notes_statistics' AS table_name,
        MAX(updated_at) AS last_update,
        EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) AS age_seconds
    FROM notes_statistics
) AS freshness_data
ORDER BY age_seconds DESC;

-- Query 6: Data mart update frequency
-- Shows update frequency for data marts
SELECT 
    DATE_TRUNC('hour', updated_at) AS hour,
    COUNT(*) AS update_count,
    COUNT(DISTINCT note_id) AS unique_notes
FROM notes_summary
WHERE updated_at > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', updated_at)
ORDER BY hour DESC
LIMIT 168;

