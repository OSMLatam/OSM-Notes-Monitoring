-- Performance Queries for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2025-12-26
--
-- These queries analyze query performance and database performance for analytics
-- Assumes connection to the analytics/data warehouse database

-- Query 1: Slow queries (if pg_stat_statements is enabled)
-- Returns slowest queries by execution time
SELECT 
    LEFT(query, 100) AS query_preview,
    calls AS call_count,
    total_exec_time AS total_time_ms,
    mean_exec_time AS avg_time_ms,
    max_exec_time AS max_time_ms,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS cache_hit_ratio
FROM pg_stat_statements
WHERE mean_exec_time > 1000  -- Queries taking more than 1 second on average
  AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Query 2: Query performance summary
-- Summary of query performance statistics
SELECT 
    COUNT(*) AS slow_query_count,
    SUM(mean_exec_time) AS total_time_ms,
    MAX(mean_exec_time) AS max_time_ms,
    AVG(mean_exec_time) AS avg_time_ms,
    SUM(calls) AS total_calls
FROM pg_stat_statements
WHERE mean_exec_time > 1000
  AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database());

-- Query 3: Index usage statistics
-- Returns index usage statistics to identify unused indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid) AS index_size_bytes
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;

-- Query 4: Unused indexes
-- Identifies indexes that are never used
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid) AS index_size_bytes
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;

-- Query 5: Table statistics and bloat
-- Returns table statistics including estimated bloat
SELECT 
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC;

-- Query 6: Sequential scan vs index scan ratio
-- Shows ratio of sequential scans to index scans
SELECT 
    schemaname,
    tablename,
    seq_scan AS sequential_scans,
    idx_scan AS index_scans,
    CASE 
        WHEN seq_scan + idx_scan > 0 THEN
            ROUND(seq_scan * 100.0 / (seq_scan + idx_scan), 2)
        ELSE 0
    END AS seq_scan_percent,
    CASE 
        WHEN seq_scan + idx_scan > 0 THEN
            ROUND(idx_scan * 100.0 / (seq_scan + idx_scan), 2)
        ELSE 0
    END AS idx_scan_percent
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND seq_scan + idx_scan > 0
ORDER BY seq_scan DESC
LIMIT 20;

-- Query 7: Connection statistics
-- Returns active connection information
SELECT 
    COUNT(*) AS total_connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active_connections,
    COUNT(*) FILTER (WHERE state = 'idle') AS idle_connections,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction,
    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting_connections
FROM pg_stat_activity
WHERE datname = current_database();

-- Query 8: Lock information
-- Shows current locks in the database
SELECT 
    locktype,
    mode,
    COUNT(*) AS lock_count
FROM pg_locks
WHERE database = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY locktype, mode
ORDER BY lock_count DESC;

-- Query 9: Database activity summary
-- Summary of database activity
SELECT 
    SUM(xact_commit) AS transactions_committed,
    SUM(xact_rollback) AS transactions_rolled_back,
    SUM(blks_read) AS disk_blocks_read,
    SUM(blks_hit) AS cache_blocks_hit,
    ROUND(SUM(blks_hit) * 100.0 / NULLIF(SUM(blks_hit) + SUM(blks_read), 0), 2) AS cache_hit_ratio,
    SUM(tup_returned) AS tuples_returned,
    SUM(tup_fetched) AS tuples_fetched,
    SUM(tup_inserted) AS tuples_inserted,
    SUM(tup_updated) AS tuples_updated,
    SUM(tup_deleted) AS tuples_deleted
FROM pg_stat_database
WHERE datname = current_database();

-- Query 10: Query execution time distribution
-- Distribution of query execution times
SELECT 
    CASE 
        WHEN mean_exec_time < 100 THEN '< 100ms'
        WHEN mean_exec_time < 500 THEN '100-500ms'
        WHEN mean_exec_time < 1000 THEN '500ms-1s'
        WHEN mean_exec_time < 5000 THEN '1s-5s'
        ELSE '> 5s'
    END AS execution_time_range,
    COUNT(*) AS query_count,
    SUM(calls) AS total_calls,
    AVG(mean_exec_time) AS avg_time_ms
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY execution_time_range
ORDER BY 
    CASE execution_time_range
        WHEN '< 100ms' THEN 1
        WHEN '100-500ms' THEN 2
        WHEN '500ms-1s' THEN 3
        WHEN '1s-5s' THEN 4
        WHEN '> 5s' THEN 5
    END;

