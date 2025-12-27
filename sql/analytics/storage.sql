-- Storage Queries for Analytics Monitoring
-- Version: 1.0.0
-- Date: 2025-12-26
--
-- These queries check database storage size and growth
-- Assumes connection to the analytics/data warehouse database

-- Query 1: Database size
-- Returns the total size of the current database
SELECT 
    pg_database.datname,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size,
    pg_database_size(pg_database.datname) AS size_bytes
FROM pg_database
WHERE datname = current_database();

-- Query 2: Table sizes and growth
-- Returns sizes of all tables to monitor growth
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 3: Largest tables
-- Returns the largest tables in the database
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

-- Query 4: Index sizes
-- Returns sizes of all indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid) AS index_size_bytes
FROM pg_stat_user_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;

-- Query 5: Total storage by schema
-- Returns total storage used by each schema
SELECT 
    schemaname,
    pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename))) AS total_size,
    SUM(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size_bytes,
    COUNT(*) AS table_count
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname
ORDER BY SUM(pg_total_relation_size(schemaname||'.'||tablename)) DESC;

-- Query 6: Storage growth estimation
-- Estimates storage growth based on table statistics
-- Note: This requires historical data. Adjust based on your monitoring setup.
SELECT 
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS current_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS current_size_bytes,
    CASE 
        WHEN n_live_tup > 0 THEN
            pg_total_relation_size(schemaname||'.'||tablename)::numeric / n_live_tup
        ELSE 0
    END AS bytes_per_tuple
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 7: Database bloat estimation
-- Estimates bloat in tables and indexes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  AND n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 20;

-- Query 8: Storage capacity check
-- Checks available disk space (requires superuser or appropriate permissions)
-- Note: This query may require additional setup. Adjust based on your environment.
SELECT 
    pg_size_pretty(pg_database_size(current_database())) AS database_size,
    pg_database_size(current_database()) AS database_size_bytes;

-- Query 9: Table row counts and sizes
-- Returns row counts and sizes for all tables
SELECT 
    schemaname,
    tablename,
    n_live_tup AS row_count,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
    CASE 
        WHEN n_live_tup > 0 THEN
            ROUND(pg_total_relation_size(schemaname||'.'||tablename)::numeric / n_live_tup, 2)
        ELSE 0
    END AS bytes_per_row
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Query 10: Index bloat
-- Estimates bloat in indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid) AS index_size_bytes,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read
FROM pg_stat_user_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;

