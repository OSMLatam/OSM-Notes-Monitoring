---
title: "Query Performance Optimization Guide"
description: "This guide provides strategies and tools for optimizing SQL query performance in the"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "performance"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Query Performance Optimization Guide

**Version:** 1.0.0  
**Date:** 2025-12-31  
**Status:** Active

## Overview

This guide provides strategies and tools for optimizing SQL query performance in the
OSM-Notes-Monitoring system. It covers index optimization, query analysis, and performance
monitoring.

## Table of Contents

1. [Index Optimization](#index-optimization)
2. [Query Analysis](#query-analysis)
3. [Performance Monitoring](#performance-monitoring)
4. [Optimization Scripts](#optimization-scripts)
5. [Best Practices](#best-practices)
6. [Troubleshooting](#troubleshooting)

## Index Optimization

### Existing Indexes

The monitoring system includes the following indexes (from `sql/init.sql`):

**Metrics Table:**

- `idx_metrics_component_timestamp` - Component and timestamp
- `idx_metrics_metric_name` - Metric name
- `idx_metrics_timestamp` - Timestamp (descending)
- `idx_metrics_component_metric_timestamp` - Component, metric name, and timestamp
- `idx_metrics_metadata` - GIN index on metadata JSONB

**Alerts Table:**

- `idx_alerts_component_status` - Component and status
- `idx_alerts_level_created` - Alert level and creation time
- `idx_alerts_status_created` - Status and creation time
- `idx_alerts_component_type` - Component and alert type
- `idx_alerts_metadata` - GIN index on metadata JSONB

### Additional Optimization Indexes

Run `sql/optimize_queries.sql` to create additional indexes:

```bash
psql -d osm_notes_monitoring -f sql/optimize_queries.sql
```

**New Indexes:**

- `idx_metrics_component_metric_name_timestamp` - Optimizes `get_latest_metric_value()` queries
- `idx_alerts_active_status_created` - Partial index for active alerts (most common query)
- `idx_alerts_component_type_level_created` - Optimizes alert deduplication queries
- `idx_security_events_ip_timestamp` - Optimizes rate limiting queries
- `idx_security_events_type_timestamp` - Optimizes security event queries
- `idx_ip_management_ip_type_active` - Optimizes IP whitelist/blacklist lookups

### Index Maintenance

**Check for unused indexes:**

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

**Monitor index sizes:**

```sql
SELECT
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Query Analysis

### Frequently Executed Queries

**1. Get Latest Metric Value**

```sql
SELECT metric_value
FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'error_rate_percent'
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '1 hour'
ORDER BY timestamp DESC
LIMIT 1;
```

**Optimization:** Uses `idx_metrics_component_metric_name_timestamp`

**2. Get Metrics Summary**

```sql
SELECT
    metric_name,
    AVG(metric_value) as avg_value,
    MIN(metric_value) as min_value,
    MAX(metric_value) as max_value,
    COUNT(*) as sample_count
FROM metrics
WHERE component = 'ingestion'
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY metric_name;
```

**Optimization:** Uses `idx_metrics_component_timestamp`

**3. Get Active Alerts**

```sql
SELECT *
FROM alerts
WHERE status = 'active'
ORDER BY created_at DESC
LIMIT 10;
```

**Optimization:** Uses `idx_alerts_active_status_created` (partial index)

**4. Check Duplicate Alert**

```sql
SELECT COUNT(*)
FROM alerts
WHERE component = 'ingestion'
  AND alert_type = 'data_quality'
  AND alert_level = 'warning'
  AND created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';
```

**Optimization:** Uses `idx_alerts_component_type_level_created`

### Query Performance Testing

Use `scripts/analyze_query_performance.sh` to test query performance:

```bash
./scripts/analyze_query_performance.sh
```

This script:

- Analyzes index usage
- Checks for table bloat
- Identifies sequential scans
- Tests query execution times
- Generates optimization recommendations

## Performance Monitoring

### Enable Query Statistics

**Enable pg_stat_statements extension:**

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

**View slow queries:**

```sql
SELECT
    query,
    calls,
    mean_exec_time,
    max_exec_time,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS cache_hit_ratio
FROM pg_stat_statements
WHERE mean_exec_time > 1000  -- Queries > 1 second
ORDER BY mean_exec_time DESC
LIMIT 20;
```

### Monitor Table Bloat

**Check for table bloat:**

```sql
SELECT
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

**Run VACUUM:**

```sql
VACUUM ANALYZE metrics;
VACUUM ANALYZE alerts;
VACUUM ANALYZE security_events;
```

### Monitor Sequential Scans

**Identify tables with high sequential scan ratio:**

```sql
SELECT
    schemaname,
    tablename,
    seq_scan AS sequential_scans,
    idx_scan AS index_scans,
    ROUND(seq_scan * 100.0 / NULLIF(seq_scan + idx_scan, 0), 2) AS seq_scan_percent
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND seq_scan > 100
ORDER BY seq_scan DESC;
```

## Optimization Scripts

### 1. Apply Optimizations

```bash
psql -d osm_notes_monitoring -f sql/optimize_queries.sql
```

This script:

- Creates additional indexes
- Updates table statistics
- Provides monitoring queries

### 2. Analyze Performance

```bash
./scripts/analyze_query_performance.sh
```

This script:

- Analyzes current performance
- Identifies optimization opportunities
- Generates recommendations

### 3. Update Statistics

```bash
psql -d osm_notes_monitoring -c "ANALYZE metrics; ANALYZE alerts; ANALYZE component_health;"
```

## Best Practices

### 1. Regular Maintenance

**Daily:**

- Monitor query performance
- Check for slow queries

**Weekly:**

- Run `ANALYZE` on all tables
- Review index usage statistics

**Monthly:**

- Run `VACUUM ANALYZE` on high-write tables
- Review and remove unused indexes
- Analyze query patterns

### 2. Query Optimization Tips

**Use LIMIT early:**

```sql
-- Good: LIMIT applied early
SELECT * FROM (
    SELECT * FROM metrics
    WHERE component = 'ingestion'
    ORDER BY timestamp DESC
    LIMIT 100
) subquery;

-- Bad: LIMIT applied after aggregation
SELECT * FROM (
    SELECT * FROM metrics
    WHERE component = 'ingestion'
) subquery
ORDER BY timestamp DESC
LIMIT 100;
```

**Use EXISTS instead of COUNT:**

```sql
-- Good: EXISTS stops at first match
WHERE EXISTS (SELECT 1 FROM alerts WHERE status = 'active')

-- Bad: COUNT scans entire table
WHERE (SELECT COUNT(*) FROM alerts WHERE status = 'active') > 0
```

**Filter on indexed columns:**

```sql
-- Good: Uses index on component and timestamp
WHERE component = 'ingestion'
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'

-- Bad: Function on indexed column prevents index use
WHERE DATE(timestamp) = CURRENT_DATE
```

### 3. Index Guidelines

**Create indexes for:**

- Foreign keys
- Frequently filtered columns
- Columns used in JOINs
- Columns used in ORDER BY
- Columns used in WHERE clauses

**Avoid indexes for:**

- Very small tables (< 1000 rows)
- Columns with low cardinality
- Frequently updated columns (unless necessary)

**Partial indexes:** Use partial indexes for common query patterns:

```sql
-- Only index active alerts (most common query)
CREATE INDEX idx_alerts_active
    ON alerts(status, created_at DESC)
    WHERE status = 'active';
```

## Troubleshooting

### Slow Queries

**1. Check query plan:**

```sql
EXPLAIN ANALYZE SELECT * FROM metrics WHERE component = 'ingestion';
```

**2. Verify indexes are used:** Look for "Index Scan" or "Index Only Scan" in EXPLAIN output.

**3. Check for table bloat:** Run `VACUUM ANALYZE` if dead tuples > 10% of live tuples.

### High Sequential Scans

**1. Identify tables:**

```sql
SELECT tablename, seq_scan, idx_scan
FROM pg_stat_user_tables
WHERE seq_scan > idx_scan * 10;
```

**2. Create missing indexes:** Review queries and create appropriate indexes.

**3. Update statistics:** Run `ANALYZE` to help query planner choose indexes.

### Index Not Used

**1. Check query plan:**

```sql
EXPLAIN SELECT * FROM metrics WHERE component = 'ingestion';
```

**2. Verify index exists:**

```sql
SELECT indexname FROM pg_indexes
WHERE tablename = 'metrics' AND indexname LIKE '%component%';
```

**3. Update statistics:**

```sql
ANALYZE metrics;
```

**4. Check for function calls:** Functions on indexed columns prevent index use:

```sql
-- Bad: Function prevents index use
WHERE DATE(timestamp) = CURRENT_DATE

-- Good: Direct comparison uses index
WHERE timestamp >= CURRENT_DATE AND timestamp < CURRENT_DATE + INTERVAL '1 day'
```

## Performance Targets

**Query Performance Targets:**

- Simple lookups: < 10ms
- Aggregations: < 100ms
- Complex queries: < 500ms
- Reports: < 2000ms

**Index Usage:**

- Index scan ratio: > 90%
- Sequential scan ratio: < 10%

**Table Health:**

- Dead tuple ratio: < 10%
- Cache hit ratio: > 95%

## Related Documentation

- [Database Schema](./Database_Schema.md)
- [Monitoring Functions](../bin/lib/README.md)
- [SQL Queries](../sql/README.md)

## Support

For issues or questions:

1. Run `scripts/analyze_query_performance.sh`
2. Check query plans with `EXPLAIN ANALYZE`
3. Review this guide for optimization strategies
4. Consult PostgreSQL documentation for advanced optimization
