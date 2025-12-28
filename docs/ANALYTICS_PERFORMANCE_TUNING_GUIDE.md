# Analytics Performance Tuning Guide

> **Purpose:** Comprehensive guide for optimizing analytics monitoring and data warehouse performance  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Table of Contents

1. [Overview](#overview)
2. [Performance Monitoring](#performance-monitoring)
3. [Query Optimization](#query-optimization)
4. [ETL Optimization](#etl-optimization)
5. [Database Optimization](#database-optimization)
6. [Storage Optimization](#storage-optimization)
7. [Monitoring System Optimization](#monitoring-system-optimization)
8. [Best Practices](#best-practices)
9. [Troubleshooting Performance Issues](#troubleshooting-performance-issues)
10. [Reference](#reference)

---

## Overview

This guide provides comprehensive strategies and techniques for optimizing the performance of:
- Analytics monitoring queries
- ETL job execution
- Data warehouse operations
- Data mart updates
- Storage management
- Monitoring system overhead

### Performance Goals

- **Query Performance**: < 500ms for simple queries, < 2s for complex queries
- **ETL Duration**: < 30 minutes average, < 2 hours maximum
- **Monitoring Overhead**: < 5% of system resources
- **Database Response**: < 100ms for monitoring queries
- **Storage Growth**: Predictable and manageable

---

## Performance Monitoring

### Key Metrics to Monitor

#### Query Performance Metrics

```sql
-- Average query time
SELECT AVG(metric_value::numeric) as avg_query_time_ms
FROM metrics
WHERE component = 'analytics'
  AND metric_name = 'query_avg_time_ms'
  AND timestamp > NOW() - INTERVAL '24 hours';

-- Maximum query time
SELECT MAX(metric_value::numeric) as max_query_time_ms
FROM metrics
WHERE component = 'analytics'
  AND metric_name = 'query_max_time_ms'
  AND timestamp > NOW() - INTERVAL '24 hours';

-- Slow query count
SELECT SUM(metric_value::numeric) as slow_query_count
FROM metrics
WHERE component = 'analytics'
  AND metric_name = 'slow_query_count'
  AND timestamp > NOW() - INTERVAL '24 hours';
```

#### ETL Performance Metrics

```sql
-- Average ETL duration
SELECT AVG(metric_value::numeric) as avg_duration_seconds
FROM metrics
WHERE component = 'analytics'
  AND metric_name = 'etl_processing_duration_avg_seconds'
  AND timestamp > NOW() - INTERVAL '7 days';

-- Maximum ETL duration
SELECT MAX(metric_value::numeric) as max_duration_seconds
FROM metrics
WHERE component = 'analytics'
  AND metric_name = 'etl_processing_duration_max_seconds'
  AND timestamp > NOW() - INTERVAL '7 days';
```

#### Storage Metrics

```sql
-- Database size trend
SELECT 
  DATE_TRUNC('day', timestamp) as day,
  AVG(metric_value::numeric) as avg_size_bytes
FROM metrics
WHERE component = 'analytics'
  AND metric_name = 'database_size_bytes'
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY day
ORDER BY day DESC;
```

### Using pg_stat_statements

Enable `pg_stat_statements` extension for detailed query analysis:

```sql
-- Enable extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- View slowest queries
SELECT 
  query,
  calls,
  mean_exec_time,
  max_exec_time,
  total_exec_time,
  (total_exec_time / 1000 / 60) as total_minutes
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Reset statistics (if needed)
SELECT pg_stat_statements_reset();
```

---

## Query Optimization

### 1. Index Optimization

#### Identify Missing Indexes

```sql
-- Find tables with high sequential scans
SELECT 
  schemaname,
  tablename,
  seq_scan,
  seq_tup_read,
  idx_scan,
  seq_tup_read / seq_scan as avg_seq_read
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC
LIMIT 20;

-- Find unused indexes
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan,
  pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(indexrelid) DESC;
```

#### Create Strategic Indexes

```sql
-- Index on frequently queried columns
CREATE INDEX IF NOT EXISTS idx_data_warehouse_updated_at 
  ON test_data_warehouse(updated_at DESC);

-- Index on foreign keys
CREATE INDEX IF NOT EXISTS idx_data_mart_name 
  ON test_data_mart(mart_name);

-- Composite index for common query patterns
CREATE INDEX IF NOT EXISTS idx_data_warehouse_timestamp_value 
  ON test_data_warehouse(data_timestamp, data_value);

-- Partial index for filtered queries
CREATE INDEX IF NOT EXISTS idx_recent_updates 
  ON test_data_warehouse(updated_at) 
  WHERE updated_at > CURRENT_TIMESTAMP - INTERVAL '7 days';
```

### 2. Query Rewriting

#### Avoid SELECT *

```sql
-- Bad: Selects all columns
SELECT * FROM test_data_warehouse WHERE id = 1;

-- Good: Select only needed columns
SELECT id, data_timestamp, data_value 
FROM test_data_warehouse 
WHERE id = 1;
```

#### Use LIMIT Appropriately

```sql
-- Bad: Fetches all rows then limits
SELECT * FROM test_data_warehouse ORDER BY updated_at DESC LIMIT 10;

-- Good: Uses index efficiently
SELECT * FROM test_data_warehouse 
ORDER BY updated_at DESC 
LIMIT 10;
```

#### Optimize JOINs

```sql
-- Ensure JOIN columns are indexed
CREATE INDEX IF NOT EXISTS idx_join_column ON table1(join_column);

-- Use appropriate JOIN type
-- INNER JOIN for required matches
-- LEFT JOIN for optional matches
-- Avoid CROSS JOIN unless necessary
```

### 3. Query Analysis

#### Use EXPLAIN ANALYZE

```sql
-- Analyze query execution plan
EXPLAIN ANALYZE
SELECT 
  mart_name,
  COUNT(*) as record_count,
  MAX(last_update) as last_update
FROM test_data_mart
GROUP BY mart_name;
```

**Key things to look for:**
- **Seq Scan**: Consider adding index
- **High cost**: Optimize query or add index
- **Nested Loop**: May be slow for large datasets
- **Hash Join**: Good for large datasets
- **Index Scan**: Optimal

#### Monitor Query Performance

```sql
-- Enable query logging for slow queries
-- In postgresql.conf:
-- log_min_duration_statement = 1000  # Log queries > 1 second

-- View slow queries from logs
SELECT 
  query,
  mean_exec_time,
  calls,
  (mean_exec_time * calls) as total_time
FROM pg_stat_statements
WHERE mean_exec_time > 1000
ORDER BY total_time DESC;
```

---

## ETL Optimization

### 1. Batch Processing

#### Process in Batches

```bash
# Instead of processing all records at once
# Process in batches of 1000
BATCH_SIZE=1000
OFFSET=0

while true; do
    # Process batch
    psql -d analytics_db -c "
        UPDATE test_data_warehouse 
        SET processed = true 
        WHERE id IN (
            SELECT id FROM test_data_warehouse 
            WHERE processed = false 
            LIMIT ${BATCH_SIZE} OFFSET ${OFFSET}
        );
    "
    
    # Check if done
    COUNT=$(psql -d analytics_db -t -c "SELECT COUNT(*) FROM test_data_warehouse WHERE processed = false;")
    if [ "$COUNT" -eq 0 ]; then
        break
    fi
    
    OFFSET=$((OFFSET + BATCH_SIZE))
done
```

### 2. Parallel Processing

#### Run Independent Jobs in Parallel

```bash
# Run independent ETL jobs in parallel
etl_job1.sh &
PID1=$!

etl_job2.sh &
PID2=$!

etl_job3.sh &
PID3=$!

# Wait for all to complete
wait $PID1 $PID2 $PID3
```

### 3. Incremental Processing

#### Process Only Changed Data

```sql
-- Track last processed timestamp
CREATE TABLE IF NOT EXISTS etl_state (
    job_name VARCHAR(100) PRIMARY KEY,
    last_processed_timestamp TIMESTAMP
);

-- Process only new/updated records
SELECT * 
FROM source_table
WHERE updated_at > (
    SELECT last_processed_timestamp 
    FROM etl_state 
    WHERE job_name = 'data_warehouse_etl'
)
ORDER BY updated_at;
```

### 4. Optimize ETL Queries

#### Use Bulk Operations

```sql
-- Bad: Row-by-row inserts
INSERT INTO target_table VALUES (...);
INSERT INTO target_table VALUES (...);
-- ... many times

-- Good: Bulk insert
INSERT INTO target_table 
SELECT ... FROM source_table 
WHERE conditions;
```

#### Use COPY for Large Data

```bash
# Export data
psql -d analytics_db -c "
    COPY (SELECT * FROM source_table) 
    TO '/tmp/data.csv' 
    WITH CSV HEADER;
"

# Import data
psql -d analytics_db -c "
    COPY target_table 
    FROM '/tmp/data.csv' 
    WITH CSV HEADER;
"
```

### 5. Resource Management

#### Limit Resource Usage

```bash
# Use nice to lower priority
nice -n 10 etl_job.sh

# Limit CPU usage with cpulimit
cpulimit -l 50 -p $PID

# Limit memory usage
ulimit -v 2097152  # 2GB limit
```

---

## Database Optimization

### 1. Vacuum and Analyze

#### Regular Maintenance

```sql
-- Vacuum specific table
VACUUM ANALYZE test_data_warehouse;

-- Vacuum all tables
VACUUM ANALYZE;

-- Aggressive vacuum for heavily updated tables
VACUUM FULL ANALYZE test_data_warehouse;

-- Vacuum with verbose output
VACUUM VERBOSE ANALYZE test_data_warehouse;
```

#### Automated Maintenance

```bash
# Add to cron for regular maintenance
# Run daily at 2 AM
0 2 * * * psql -d analytics_db -c "VACUUM ANALYZE;" >> /var/log/vacuum.log 2>&1
```

### 2. Table Partitioning

#### Partition Large Tables

```sql
-- Create partitioned table
CREATE TABLE data_warehouse_partitioned (
    id SERIAL,
    data_timestamp TIMESTAMP,
    data_value TEXT
) PARTITION BY RANGE (data_timestamp);

-- Create partitions
CREATE TABLE data_warehouse_2025_01 
    PARTITION OF data_warehouse_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE data_warehouse_2025_02 
    PARTITION OF data_warehouse_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
```

### 3. Connection Pooling

#### Use Connection Pooler

```bash
# Install pgBouncer
# Configure pgbouncer.ini
[databases]
analytics_db = host=localhost port=5432 dbname=analytics_db

[pgbouncer]
pool_mode = transaction
max_client_conn = 100
default_pool_size = 20
```

### 4. Configuration Tuning

#### PostgreSQL Configuration

```bash
# In postgresql.conf, adjust for analytics workload:

# Memory settings
shared_buffers = 4GB              # 25% of RAM
effective_cache_size = 12GB      # 75% of RAM
work_mem = 64MB                   # Per operation
maintenance_work_mem = 1GB        # For VACUUM, CREATE INDEX

# Query planner
random_page_cost = 1.1            # For SSD
effective_io_concurrency = 200     # For SSD

# Checkpoint settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB

# Logging
log_min_duration_statement = 1000  # Log slow queries
```

---

## Storage Optimization

### 1. Data Archival

#### Archive Old Data

```sql
-- Create archive table
CREATE TABLE data_warehouse_archive (
    LIKE data_warehouse INCLUDING ALL
);

-- Move old data to archive
INSERT INTO data_warehouse_archive
SELECT * FROM data_warehouse
WHERE data_timestamp < CURRENT_TIMESTAMP - INTERVAL '1 year';

-- Delete archived data
DELETE FROM data_warehouse
WHERE data_timestamp < CURRENT_TIMESTAMP - INTERVAL '1 year';
```

### 2. Table Compression

#### Use TOAST Compression

```sql
-- Large text columns are automatically compressed
-- Ensure TEXT columns use TOAST
ALTER TABLE test_data_warehouse 
ALTER COLUMN data_value SET STORAGE EXTENDED;
```

### 3. Index Maintenance

#### Rebuild Fragmented Indexes

```sql
-- Rebuild index
REINDEX INDEX idx_data_warehouse_updated_at;

-- Rebuild all indexes on table
REINDEX TABLE test_data_warehouse;

-- Rebuild all indexes in database
REINDEX DATABASE analytics_db;
```

### 4. Monitor Storage Growth

```sql
-- Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

-- Check database size
SELECT 
    pg_database.datname,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
WHERE datname = current_database();
```

---

## Monitoring System Optimization

### 1. Reduce Monitoring Frequency

```bash
# Instead of every 15 minutes, run hourly for non-critical systems
# In crontab:
0 * * * * /path/to/monitorAnalytics.sh

# Or use different frequencies for different checks
# Critical checks: every 15 minutes
*/15 * * * * /path/to/monitorAnalytics.sh --critical-only

# Non-critical checks: hourly
0 * * * * /path/to/monitorAnalytics.sh --standard-checks
```

### 2. Optimize Monitoring Queries

#### Cache Expensive Queries

```bash
# Cache query results for 5 minutes
CACHE_FILE="/tmp/query_cache_$(date +%Y%m%d%H%M)"
CACHE_AGE=300  # 5 minutes

if [ -f "$CACHE_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE"))) -lt $CACHE_AGE ]; then
    # Use cached result
    cat "$CACHE_FILE"
else
    # Run query and cache result
    psql -d analytics_db -c "SELECT ..." > "$CACHE_FILE"
    cat "$CACHE_FILE"
fi
```

### 3. Limit Query Execution Time

```sql
-- Set statement timeout for monitoring queries
SET statement_timeout = '30s';

-- Or in postgresql.conf:
-- statement_timeout = 30s
```

### 4. Batch Metric Writes

```bash
# Instead of writing metrics one by one
# Collect metrics and write in batch
METRICS_FILE="/tmp/metrics_batch_$$"

# Collect metrics
echo "metric1,value1" >> "$METRICS_FILE"
echo "metric2,value2" >> "$METRICS_FILE"

# Write batch
psql -d monitoring_db -c "
    COPY metrics(component, metric_name, metric_value, metric_unit)
    FROM '$METRICS_FILE'
    WITH CSV;
"
```

---

## Best Practices

### 1. Regular Performance Reviews

- **Weekly**: Review slow query logs
- **Monthly**: Analyze query performance trends
- **Quarterly**: Review and optimize indexes
- **Annually**: Capacity planning and optimization review

### 2. Baseline and Trend Analysis

```sql
-- Establish performance baselines
CREATE TABLE performance_baselines (
    metric_name VARCHAR(100),
    baseline_value NUMERIC,
    threshold_warning NUMERIC,
    threshold_critical NUMERIC,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Compare current performance to baseline
SELECT 
    m.metric_name,
    m.current_value,
    b.baseline_value,
    ((m.current_value - b.baseline_value) / b.baseline_value * 100) as percent_change
FROM (
    SELECT metric_name, AVG(metric_value::numeric) as current_value
    FROM metrics
    WHERE component = 'analytics'
      AND timestamp > NOW() - INTERVAL '24 hours'
    GROUP BY metric_name
) m
JOIN performance_baselines b ON m.metric_name = b.metric_name;
```

### 3. Index Strategy

- **Create indexes** on frequently queried columns
- **Remove unused indexes** to reduce write overhead
- **Monitor index usage** regularly
- **Use partial indexes** for filtered queries
- **Consider composite indexes** for multi-column queries

### 4. Query Design

- **Select only needed columns**
- **Use appropriate data types**
- **Avoid unnecessary JOINs**
- **Use WHERE clauses effectively**
- **Limit result sets**
- **Use EXPLAIN ANALYZE** before deploying

### 5. ETL Design

- **Process incrementally** when possible
- **Use batch operations**
- **Parallelize independent jobs**
- **Monitor ETL duration trends**
- **Optimize before scaling**

### 6. Storage Management

- **Archive old data** regularly
- **Monitor storage growth** trends
- **Plan for capacity** expansion
- **Use partitioning** for large tables
- **Clean up temporary data**

---

## Troubleshooting Performance Issues

### Issue: Slow Queries

**Symptoms:**
- Query execution time > 2 seconds
- High CPU usage during queries
- Timeout errors

**Investigation:**
1. Identify slow queries:
   ```sql
   SELECT query, mean_exec_time, calls
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 10;
   ```

2. Analyze query plan:
   ```sql
   EXPLAIN ANALYZE <slow_query>;
   ```

3. Check for missing indexes:
   ```sql
   SELECT * FROM pg_stat_user_tables
   WHERE seq_scan > 1000
   ORDER BY seq_tup_read DESC;
   ```

**Resolution:**
1. Add missing indexes
2. Rewrite inefficient queries
3. Optimize JOINs
4. Consider partitioning
5. Increase `work_mem` if needed

---

### Issue: High ETL Duration

**Symptoms:**
- ETL jobs taking longer than expected
- Alerts for duration thresholds

**Investigation:**
1. Check ETL duration trends:
   ```sql
   SELECT 
     DATE_TRUNC('hour', timestamp) as hour,
     AVG(metric_value::numeric) as avg_duration
   FROM metrics
   WHERE component = 'analytics'
     AND metric_name = 'etl_processing_duration_avg_seconds'
   GROUP BY hour
   ORDER BY hour DESC;
   ```

2. Review ETL logs for bottlenecks
3. Check system resources
4. Analyze data volume trends

**Resolution:**
1. Optimize ETL queries
2. Process in smaller batches
3. Parallelize independent operations
4. Optimize data transformations
5. Scale resources if needed

---

### Issue: Database Size Growth

**Symptoms:**
- Database size alerts
- Disk space warnings
- Slow queries on large tables

**Investigation:**
1. Check table sizes:
   ```sql
   SELECT 
     tablename,
     pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
   FROM pg_tables
   ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
   ```

2. Analyze growth trends
3. Identify old data

**Resolution:**
1. Archive old data
2. Implement data retention policies
3. Partition large tables
4. Clean up temporary data
5. Vacuum and reindex

---

### Issue: High Monitoring Overhead

**Symptoms:**
- Monitoring queries slow
- System resource usage high
- Monitoring alerts delayed

**Investigation:**
1. Measure monitoring execution time:
   ```bash
   time ./bin/monitor/monitorAnalytics.sh
   ```

2. Check monitoring query performance
3. Review monitoring frequency

**Resolution:**
1. Reduce monitoring frequency
2. Optimize monitoring queries
3. Cache expensive queries
4. Batch metric writes
5. Disable non-critical checks

---

## Reference

### Performance Targets

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Simple Query Time | < 100ms | > 500ms | > 2000ms |
| Complex Query Time | < 500ms | > 2000ms | > 5000ms |
| ETL Average Duration | < 30 min | > 1 hour | > 2 hours |
| ETL Max Duration | < 1 hour | > 2 hours | > 4 hours |
| Database Size Growth | < 10GB/month | > 20GB/month | > 50GB/month |
| Monitoring Overhead | < 1% CPU | > 5% CPU | > 10% CPU |

### Useful Commands

```bash
# Check query performance
psql -d analytics_db -c "
  SELECT query, mean_exec_time, calls
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 10;
"

# Analyze table
psql -d analytics_db -c "ANALYZE test_data_warehouse;"

# Vacuum table
psql -d analytics_db -c "VACUUM ANALYZE test_data_warehouse;"

# Check index usage
psql -d analytics_db -c "
  SELECT schemaname, tablename, indexname, idx_scan
  FROM pg_stat_user_indexes
  WHERE schemaname = 'public'
  ORDER BY idx_scan;
"

# Check table bloat
psql -d analytics_db -c "
  SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_dead_tup,
    n_live_tup,
    ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct
  FROM pg_stat_user_tables
  WHERE n_dead_tup > 1000
  ORDER BY n_dead_tup DESC;
"
```

### Related Documentation

- **[ANALYTICS_MONITORING_GUIDE.md](./ANALYTICS_MONITORING_GUIDE.md)**: Complete monitoring guide
- **[ETL_MONITORING_RUNBOOK.md](./ETL_MONITORING_RUNBOOK.md)**: ETL alert response procedures
- **[ANALYTICS_METRICS.md](./ANALYTICS_METRICS.md)**: Metric definitions

---

**Last Updated**: 2025-12-27  
**Version**: 1.0.0

