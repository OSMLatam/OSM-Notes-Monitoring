-- Advanced Database Performance Queries for Ingestion Monitoring
-- Version: 1.0.0
-- Date: 2026-01-08
--
-- These queries provide advanced database performance metrics
-- Assumes connection to the ingestion database

-- ============================================================================
-- TABLE METRICS
-- ============================================================================

-- Query 1: Table sizes for main tables (notes, note_comments, etc.)
-- Returns: table_name, total_size_bytes, table_size_bytes, indexes_size_bytes
SELECT 
    schemaname,
    tablename,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
    pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename) AS indexes_size_bytes
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('notes', 'note_comments', 'note_comment_texts', 'countries', 'maritime_boundaries')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 2: Table growth (daily growth estimate)
-- Returns: table_name, current_size_bytes, estimated_daily_growth_bytes
-- Note: This requires historical data, so we'll calculate based on recent changes
SELECT 
    schemaname,
    tablename,
    pg_total_relation_size(schemaname||'.'||tablename) AS current_size_bytes,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND tablename IN ('notes', 'note_comments', 'note_comment_texts')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 3: Table bloat ratio
-- Returns: table_name, bloat_ratio_percent, dead_tuples, last_vacuum
SELECT 
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS bloat_ratio_percent,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND tablename IN ('notes', 'note_comments', 'note_comment_texts')
ORDER BY n_dead_tup DESC;

-- ============================================================================
-- INDEX METRICS
-- ============================================================================

-- Query 4: Index sizes by table
-- Returns: table_name, index_name, index_size_bytes
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_relation_size(indexrelid) AS index_size_bytes,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND tablename IN ('notes', 'note_comments', 'note_comment_texts')
ORDER BY pg_relation_size(indexrelid) DESC;

-- Query 5: Index usage statistics (index scans vs sequential scans)
-- Returns: table_name, index_scans, sequential_scans, index_scan_ratio
SELECT 
    t.schemaname,
    t.tablename,
    COALESCE(SUM(i.idx_scan), 0) AS total_index_scans,
    t.seq_scan AS sequential_scans,
    CASE 
        WHEN t.seq_scan + COALESCE(SUM(i.idx_scan), 0) > 0 
        THEN ROUND(COALESCE(SUM(i.idx_scan), 0) * 100.0 / (t.seq_scan + COALESCE(SUM(i.idx_scan), 0)), 2)
        ELSE 0
    END AS index_scan_ratio_percent
FROM pg_stat_user_tables t
LEFT JOIN pg_stat_user_indexes i ON t.schemaname = i.schemaname AND t.tablename = i.tablename
WHERE t.schemaname = 'public'
  AND t.tablename IN ('notes', 'note_comments', 'note_comment_texts')
GROUP BY t.schemaname, t.tablename, t.seq_scan
ORDER BY sequential_scans DESC;

-- Query 6: Unused indexes
-- Returns: table_name, index_name, index_size_bytes, last_scan
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_relation_size(indexrelid) AS index_size_bytes,
    idx_scan AS index_scans
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND idx_scan = 0
  AND tablename IN ('notes', 'note_comments', 'note_comment_texts')
ORDER BY pg_relation_size(indexrelid) DESC;

-- ============================================================================
-- QUERY PERFORMANCE METRICS
-- ============================================================================

-- Query 7: Slow queries (if pg_stat_statements is enabled)
-- Returns: query_hash, query_preview, calls, avg_time_ms, max_time_ms, cache_hit_ratio
SELECT 
    LEFT(query, 100) AS query_preview,
    calls AS call_count,
    ROUND(total_exec_time::numeric, 2) AS total_time_ms,
    ROUND(mean_exec_time::numeric, 2) AS avg_time_ms,
    ROUND(max_exec_time::numeric, 2) AS max_time_ms,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS cache_hit_ratio
FROM pg_stat_statements
WHERE mean_exec_time > 1000  -- Queries taking more than 1 second on average
  AND dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Query 8: Most frequent queries
-- Returns: query_preview, call_count, avg_time_ms
SELECT 
    LEFT(query, 100) AS query_preview,
    calls AS call_count,
    ROUND(mean_exec_time::numeric, 2) AS avg_time_ms
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY calls DESC
LIMIT 10;

-- Query 9: Query cache hit ratio (if pg_stat_statements is enabled)
-- Returns: overall_cache_hit_ratio_percent
SELECT 
    ROUND(100.0 * SUM(shared_blks_hit) / NULLIF(SUM(shared_blks_hit + shared_blks_read), 0), 2) AS cache_hit_ratio_percent
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database());

-- ============================================================================
-- CONNECTION METRICS
-- ============================================================================

-- Query 10: Active connections by application
-- Returns: application_name, connection_count, state
SELECT 
    application_name,
    state,
    COUNT(*) AS connection_count
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY application_name, state
ORDER BY connection_count DESC;

-- Query 11: Connection statistics summary
-- Returns: total_connections, active_connections, idle_connections, waiting_connections
SELECT 
    COUNT(*) AS total_connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active_connections,
    COUNT(*) FILTER (WHERE state = 'idle') AS idle_connections,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction_connections,
    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting_connections,
    MAX(backend_start) AS oldest_connection_start
FROM pg_stat_activity
WHERE datname = current_database();

-- Query 12: Max connections configuration
-- Returns: max_connections, current_connections, connection_usage_percent
SELECT 
    current_setting('max_connections')::integer AS max_connections,
    COUNT(*) AS current_connections,
    ROUND(COUNT(*) * 100.0 / current_setting('max_connections')::integer, 2) AS connection_usage_percent
FROM pg_stat_activity
WHERE datname = current_database();

-- ============================================================================
-- LOCK METRICS
-- ============================================================================

-- Query 13: Active locks summary
-- Returns: lock_type, lock_mode, granted, lock_count
SELECT 
    locktype,
    mode,
    granted,
    COUNT(*) AS lock_count
FROM pg_locks
GROUP BY locktype, mode, granted
ORDER BY lock_count DESC;

-- Query 14: Blocking locks (locks waiting for other locks)
-- Returns: blocked_pid, blocking_pid, lock_mode, wait_duration_ms
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocking_locks.pid AS blocking_pid,
    blocked_locks.mode AS blocked_mode,
    blocking_locks.mode AS blocking_mode,
    blocked_activity.query AS blocked_query,
    blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- Query 15: Deadlocks count (from pg_stat_database)
-- Returns: deadlocks_count
SELECT 
    deadlocks AS deadlocks_count
FROM pg_stat_database
WHERE datname = current_database();

-- ============================================================================
-- OVERALL DATABASE METRICS
-- ============================================================================

-- Query 16: Database cache hit ratio
-- Returns: cache_hit_ratio_percent
SELECT 
    ROUND(blks_hit * 100.0 / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_ratio_percent,
    blks_hit AS cache_hits,
    blks_read AS disk_reads,
    blks_hit + blks_read AS total_reads
FROM pg_stat_database
WHERE datname = current_database();

-- Query 17: Database activity summary
-- Returns: transactions, tuples, cache_stats
SELECT 
    xact_commit AS transactions_committed,
    xact_rollback AS transactions_rolled_back,
    tup_returned AS tuples_returned,
    tup_fetched AS tuples_fetched,
    tup_inserted AS tuples_inserted,
    tup_updated AS tuples_updated,
    tup_deleted AS tuples_deleted,
    blks_read AS disk_blocks_read,
    blks_hit AS cache_blocks_hit
FROM pg_stat_database
WHERE datname = current_database();
