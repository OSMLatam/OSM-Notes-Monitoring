# Ingestion SQL Queries

> **Last Updated:** 2025-12-24  
> **Version:** 1.0.0

SQL queries for monitoring the OSM-Notes-Ingestion component.

## Overview

These queries are designed to be executed against the **ingestion database** (not the monitoring database). They provide insights into:

- Data freshness
- Processing status
- Performance metrics
- Data quality
- Error analysis

## Query Files

### 1. `data_freshness.sql`

Queries to check data freshness and update timestamps.

**Queries included:**
- Last update timestamp for notes
- Last update timestamp for note comments
- Data freshness summary across all tables
- Notes by update frequency
- Stale data detection
- Recent activity summary

**Usage:**
```bash
psql -d osm_notes -f sql/ingestion/data_freshness.sql
```

**Key Metrics:**
- `last_note_update`: Most recent note update
- `age_seconds`: Age of most recent data
- `notes_updated_last_hour`: Notes updated in last hour

### 2. `processing_status.sql`

Queries to check processing execution status and history.

**Queries included:**
- Processing execution summary
- Last successful processing execution
- Processing failures in last 24 hours
- Processing performance trends
- Processing success rate
- Notes processed per execution
- Processing gaps detection

**Usage:**
```bash
psql -d osm_notes -f sql/ingestion/processing_status.sql
```

**Note:** Assumes a `processing_log` table exists. Adjust queries based on actual schema.

**Key Metrics:**
- `last_successful_execution`: Timestamp of last success
- `success_rate_percent`: Success rate percentage
- `execution_count`: Number of executions

### 3. `performance_analysis.sql`

Queries to analyze database performance.

**Queries included:**
- Table sizes and growth
- Index usage statistics
- Table statistics and bloat
- Slow queries (if pg_stat_statements enabled)
- Connection statistics
- Lock information
- Database activity summary
- Sequential scan vs index scan ratio

**Usage:**
```bash
psql -d osm_notes -f sql/ingestion/performance_analysis.sql
```

**Key Metrics:**
- `total_size`: Total table size
- `cache_hit_ratio`: Database cache hit ratio
- `index_scans`: Number of index scans
- `sequential_scans`: Number of sequential scans

### 4. `data_quality.sql`

Queries to check data quality metrics.

**Queries included:**
- Missing or null data checks
- Data completeness percentage
- Duplicate detection
- Orphaned records
- Data consistency checks
- Invalid coordinate ranges
- Date consistency
- Data quality score

**Usage:**
```bash
psql -d osm_notes -f sql/ingestion/data_quality.sql
```

**Key Metrics:**
- `completeness_percent`: Data completeness percentage
- `duplicate_count`: Number of duplicates
- `orphaned_comments`: Comments without parent notes
- `quality_score_percent`: Overall quality score

### 5. `error_analysis.sql`

Queries to analyze errors and failures.

**Queries included:**
- Error summary from processing log
- Most common errors
- Error rate by hour
- Error patterns
- Recovery time analysis
- Error frequency analysis
- Error impact assessment
- Error trends

**Usage:**
```bash
psql -d osm_notes -f sql/ingestion/error_analysis.sql
```

**Note:** Assumes a `processing_log` table exists with error information.

**Key Metrics:**
- `error_count`: Number of errors
- `error_rate_percent`: Error rate percentage
- `recovery_seconds`: Time to recover from errors

## Database Schema Assumptions

These queries assume the following tables exist in the ingestion database:

- `notes` - Main notes table
- `note_comments` - Note comments table
- `note_comment_texts` - Comment text content
- `processing_log` - Processing execution log (optional)

**Table Structure (assumed):**

```sql
-- Notes table
CREATE TABLE notes (
    id BIGINT PRIMARY KEY,
    note_id BIGINT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    latitude DECIMAL,
    longitude DECIMAL,
    ...
);

-- Note comments table
CREATE TABLE note_comments (
    id BIGINT PRIMARY KEY,
    note_id BIGINT,
    created_at TIMESTAMP,
    ...
);

-- Processing log (optional)
CREATE TABLE processing_log (
    execution_time TIMESTAMP,
    status VARCHAR,  -- 'success' or 'failed'
    duration_seconds INTEGER,
    error_message TEXT,
    notes_processed INTEGER,
    ...
);
```

## Usage Examples

### Run all queries

```bash
# Connect to ingestion database
psql -d osm_notes -f sql/ingestion/data_freshness.sql
psql -d osm_notes -f sql/ingestion/processing_status.sql
psql -d osm_notes -f sql/ingestion/performance_analysis.sql
psql -d osm_notes -f sql/ingestion/data_quality.sql
psql -d osm_notes -f sql/ingestion/error_analysis.sql
```

### Run specific query

```bash
# Check data freshness only
psql -d osm_notes -f sql/ingestion/data_freshness.sql

# Check data quality only
psql -d osm_notes -f sql/ingestion/data_quality.sql
```

### Extract specific query

```bash
# Extract and run a specific query from a file
psql -d osm_notes -c "$(grep -A 20 'Query 1:' sql/ingestion/data_freshness.sql | tail -n +2)"
```

## Integration with Monitoring Scripts

These queries can be called from monitoring scripts:

```bash
# In monitorIngestion.sh
result=$(execute_sql_query "$(cat sql/ingestion/data_freshness.sql | grep -A 10 'Query 1:')")
```

## Performance Considerations

- Some queries may be slow on large tables
- Consider adding indexes if queries are slow
- Use `EXPLAIN ANALYZE` to optimize queries
- Some queries use `pg_stat_statements` which must be enabled

## Customization

Queries may need to be adjusted based on:

- Actual database schema
- Table names
- Column names
- Indexes available
- PostgreSQL version

## Related Documentation

- [Database Schema](./../../docs/DATABASE_SCHEMA.md)
- [Monitoring Architecture](./../../docs/Monitoring_Architecture_Proposal.md)
- [Existing Monitoring Components](./../../docs/Existing_Monitoring_Components.md)

---

**Last Updated:** 2025-12-24

