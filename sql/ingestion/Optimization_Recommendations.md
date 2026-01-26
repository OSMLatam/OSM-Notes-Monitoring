# SQL Query Optimization Recommendations

> **Last Updated:** 2025-12-24  
> **Version:** 1.0.0

This document provides optimization recommendations for ingestion monitoring SQL queries.

## Index Recommendations

### Critical Indexes

These indexes are essential for query performance:

```sql
-- Notes table indexes
CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_note_id ON notes(note_id);
CREATE INDEX IF NOT EXISTS idx_notes_coordinates ON notes(latitude, longitude);

-- Note comments table indexes
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id ON note_comments(note_id);
CREATE INDEX IF NOT EXISTS idx_note_comments_created_at ON note_comments(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id_created_at ON note_comments(note_id, created_at DESC);

-- Note comment texts table indexes
CREATE INDEX IF NOT EXISTS idx_note_comment_texts_comment_id ON note_comment_texts(comment_id);

-- Processing log table indexes (if exists)
CREATE INDEX IF NOT EXISTS idx_processing_log_execution_time ON processing_log(execution_time DESC);
CREATE INDEX IF NOT EXISTS idx_processing_log_status ON processing_log(status);
CREATE INDEX IF NOT EXISTS idx_processing_log_status_execution_time ON processing_log(status, execution_time DESC);
```

### Composite Indexes

For queries that filter on multiple columns:

```sql
-- For data freshness queries filtering by date ranges
CREATE INDEX IF NOT EXISTS idx_notes_updated_at_status ON notes(updated_at DESC) WHERE updated_at IS NOT NULL;

-- For processing status queries
CREATE INDEX IF NOT EXISTS idx_processing_log_status_time ON processing_log(status, execution_time DESC) WHERE status IN ('success', 'failed');
```

## Query Optimizations

### 1. Data Freshness Queries

**Optimization 1: Use partial indexes for recent data**

```sql
-- Instead of scanning all rows, use partial index for recent updates
CREATE INDEX IF NOT EXISTS idx_notes_recent_updates
ON notes(updated_at DESC)
WHERE updated_at > NOW() - INTERVAL '30 days';
```

**Optimization 2: Materialized view for freshness summary**

```sql
-- Create materialized view for frequently accessed freshness data
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_data_freshness_summary AS
SELECT
    'notes' AS table_name,
    MAX(updated_at) AS last_update,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 hour') AS records_last_hour,
    COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '24 hours') AS records_last_24h
FROM notes;

-- Refresh periodically (e.g., every 5 minutes)
CREATE UNIQUE INDEX ON mv_data_freshness_summary(table_name);
```

**Optimization 3: Optimize date range queries**

```sql
-- Use date_trunc for better index usage
-- Instead of: WHERE updated_at > NOW() - INTERVAL '1 hour'
-- Use: WHERE updated_at >= date_trunc('hour', NOW())
```

### 2. Processing Status Queries

**Optimization 1: Partition processing_log table**

```sql
-- Partition by date for better query performance
CREATE TABLE processing_log (
    execution_time TIMESTAMP NOT NULL,
    status VARCHAR NOT NULL,
    duration_seconds INTEGER,
    error_message TEXT,
    notes_processed INTEGER
) PARTITION BY RANGE (execution_time);

-- Create monthly partitions
CREATE TABLE processing_log_2025_12 PARTITION OF processing_log
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
```

**Optimization 2: Use covering indexes**

```sql
-- Covering index for common queries
CREATE INDEX IF NOT EXISTS idx_processing_log_covering
ON processing_log(status, execution_time DESC, duration_seconds, notes_processed);
```

### 3. Performance Analysis Queries

**Optimization 1: Cache pg_stat tables**

The `pg_stat_*` tables are updated asynchronously. For real-time monitoring, consider:

```sql
-- Refresh statistics before querying
ANALYZE notes;
ANALYZE note_comments;
```

**Optimization 2: Use pg_stat_statements extension**

```sql
-- Enable pg_stat_statements for query performance tracking
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Requires PostgreSQL configuration:
-- shared_preload_libraries = 'pg_stat_statements'
-- pg_stat_statements.track = all
```

### 4. Data Quality Queries

**Optimization 1: Use CHECK constraints**

```sql
-- Add constraints to prevent invalid data
ALTER TABLE notes
ADD CONSTRAINT check_valid_latitude CHECK (latitude BETWEEN -90 AND 90),
ADD CONSTRAINT check_valid_longitude CHECK (longitude BETWEEN -180 AND 180),
ADD CONSTRAINT check_updated_after_created CHECK (updated_at >= created_at);
```

**Optimization 2: Optimize duplicate detection**

```sql
-- Use hash index for faster duplicate detection
CREATE INDEX IF NOT EXISTS idx_notes_note_id_hash ON notes USING hash(note_id);
```

**Optimization 3: Use partial indexes for quality checks**

```sql
-- Index only records that might have quality issues
CREATE INDEX IF NOT EXISTS idx_notes_quality_check
ON notes(id)
WHERE latitude IS NULL OR longitude IS NULL OR updated_at < created_at;
```

### 5. Error Analysis Queries

**Optimization 1: GIN index for error message search**

```sql
-- Use GIN index for text search in error messages
CREATE INDEX IF NOT EXISTS idx_processing_log_error_message_gin
ON processing_log USING gin(to_tsvector('english', error_message));
```

**Optimization 2: Pre-aggregate error statistics**

```sql
-- Materialized view for error statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_error_statistics AS
SELECT
    DATE_TRUNC('hour', execution_time) AS hour,
    status,
    COUNT(*) AS error_count,
    AVG(duration_seconds) AS avg_duration
FROM processing_log
WHERE status = 'failed'
  AND execution_time > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', execution_time), status;

CREATE INDEX ON mv_error_statistics(hour DESC, status);
```

## General Optimization Strategies

### 1. Query Rewriting

**Use EXISTS instead of COUNT for existence checks:**

```sql
-- Instead of: WHERE (SELECT COUNT(*) FROM ...) > 0
-- Use: WHERE EXISTS (SELECT 1 FROM ...)
```

**Use LIMIT early:**

```sql
-- Add LIMIT early in subqueries when possible
SELECT * FROM (
    SELECT * FROM notes ORDER BY updated_at DESC LIMIT 1000
) subquery;
```

### 2. Statistics and Vacuum

```sql
-- Keep statistics up to date
ANALYZE notes;
ANALYZE note_comments;

-- Regular vacuum to prevent bloat
VACUUM ANALYZE notes;
VACUUM ANALYZE note_comments;
```

### 3. Connection Pooling

Use connection pooling (e.g., PgBouncer) to reduce connection overhead.

### 4. Query Timeout

Set appropriate query timeouts:

```sql
-- Set statement timeout (in milliseconds)
SET statement_timeout = 30000;  -- 30 seconds
```

## Performance Monitoring

### Track Query Performance

```sql
-- Enable query logging for slow queries
-- In postgresql.conf:
-- log_min_duration_statement = 1000  -- Log queries > 1 second
```

### Monitor Index Usage

```sql
-- Check unused indexes
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Implementation Script

Create `sql/ingestion/create_indexes.sql`:

```sql
-- Create all recommended indexes
-- Run this script after initial schema setup

-- Notes indexes
CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_note_id ON notes(note_id);
CREATE INDEX IF NOT EXISTS idx_notes_coordinates ON notes(latitude, longitude);

-- Note comments indexes
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id ON note_comments(note_id);
CREATE INDEX IF NOT EXISTS idx_note_comments_created_at ON note_comments(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id_created_at ON note_comments(note_id, created_at DESC);

-- Note comment texts indexes
CREATE INDEX IF NOT EXISTS idx_note_comment_texts_comment_id ON note_comment_texts(comment_id);

-- Processing log indexes (if table exists)
CREATE INDEX IF NOT EXISTS idx_processing_log_execution_time ON processing_log(execution_time DESC);
CREATE INDEX IF NOT EXISTS idx_processing_log_status ON processing_log(status);
CREATE INDEX IF NOT EXISTS idx_processing_log_status_execution_time ON processing_log(status, execution_time DESC);

-- Analyze tables after creating indexes
ANALYZE notes;
ANALYZE note_comments;
ANALYZE note_comment_texts;
```

## Testing Optimizations

After applying optimizations:

1. Run `EXPLAIN ANALYZE` on queries to verify index usage
2. Compare query execution times before/after
3. Monitor index sizes and usage statistics
4. Adjust based on actual query patterns

## Notes

- Indexes improve read performance but slow down writes
- Monitor index bloat and rebuild if necessary
- Use `EXPLAIN ANALYZE` to verify query plans
- Consider table partitioning for very large tables (>10M rows)

---

**Last Updated:** 2025-12-24
