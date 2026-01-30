-- Create Recommended Indexes for Ingestion Monitoring Queries
-- Version: 1.0.0
-- Date: 2025-12-24
--
-- This script creates indexes to optimize query performance
-- Run this script after initial schema setup
-- See optimization_recommendations.md for details

-- Notes table indexes
-- Index: idx_notes_updated_at (updated_at DESC)
-- Benefits: Monitoring (data_freshness.sql - data freshness queries, optimized_queries/data_freshness_optimized.sql),
--           Analytics (queries identifying recently updated notes for incremental processing)
-- Used by: Monitoring data freshness queries, incremental ETL processing
CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at DESC);

-- Index: idx_notes_created_at (created_at DESC)
-- Benefits: Monitoring (queries ordering by creation date descending),
--           API (already covered by notes_created but this optimizes ORDER BY DESC specifically)
-- Used by: Monitoring queries with DESC ordering, API pagination with DESC
CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);

-- REMOVED: idx_notes_note_id - Redundant with PRIMARY KEY on note_id
-- The PK already provides an index for note_id lookups and JOINs

-- REMOVED: idx_notes_coordinates - Redundant with notes_spatial GIST index
-- The GIST spatial index (notes_spatial) is superior for all geographic queries including bounding boxes

-- Partial index for recent updates (optimizes freshness queries)
-- Index: idx_notes_recent_updates (updated_at DESC) - Partial Index
-- Benefits: Monitoring (data_freshness.sql - queries for recent updates in last 30 days)
-- Used by: Monitoring queries that only need recent data (last 30 days), optimizes freshness checks
CREATE INDEX IF NOT EXISTS idx_notes_recent_updates
ON notes(updated_at DESC)
WHERE updated_at > NOW() - INTERVAL '30 days';

-- Note comments table indexes
-- Index: idx_note_comments_note_id (note_id)
-- Benefits: Similar to note_comments_id but created by monitoring component
--           API (noteService.ts - JOINs), Analytics (ETL staging JOINs)
-- Used by: Same as note_comments_id - JOINs between notes and comments
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id ON note_comments(note_id);

-- Index: idx_note_comments_created_at (created_at DESC)
-- Benefits: Monitoring (queries ordering comments by date descending)
--           Similar to note_comments_created but with explicit DESC ordering
-- Used by: Monitoring queries with DESC ordering, API queries ordering comments descending
CREATE INDEX IF NOT EXISTS idx_note_comments_created_at ON note_comments(
    created_at DESC
);

-- Index: idx_note_comments_note_id_created_at (note_id, created_at DESC)
-- Benefits: Monitoring (queries getting most recent comments per note),
--           API (optimizes queries ordering comments descending)
--           Similar to note_comments_id_created but with explicit DESC ordering
-- Used by: Queries getting most recent comments per note, API getNoteComments with DESC ordering
CREATE INDEX IF NOT EXISTS idx_note_comments_note_id_created_at ON note_comments(
    note_id, created_at DESC
);

-- Note comment texts table indexes
-- Index: idx_note_comment_texts_comment_id (comment_id)
-- Benefits: API (noteService.ts:137 - JOIN using comment_id: LEFT JOIN note_comments_text ON nc.comment_id = nct.comment_id),
--           Analytics (JOINs relating comments with their texts)
-- Used by: JOINs between note_comments and note_comments_text using comment_id
CREATE INDEX IF NOT EXISTS idx_note_comment_texts_comment_id ON note_comment_texts(
    comment_id
);

-- Processing log table indexes (if table exists)
-- Note: These will fail silently if table doesn't exist
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'processing_log') THEN
        -- Index: idx_processing_log_execution_time (execution_time DESC)
        -- Benefits: Monitoring (queries ordering logs by execution time, performance analysis)
        -- Used by: Queries ordering logs by execution time, performance analysis
        CREATE INDEX IF NOT EXISTS idx_processing_log_execution_time ON processing_log(execution_time DESC);
        
        -- Index: idx_processing_log_status (status)
        -- Benefits: Monitoring (processing_status.sql - filters logs by status: success, failed, etc.)
        -- Used by: Monitoring queries finding failed processes, filtering by status
        CREATE INDEX IF NOT EXISTS idx_processing_log_status ON processing_log(status);
        
        -- Index: idx_processing_log_status_execution_time (status, execution_time DESC)
        -- Benefits: Monitoring (queries filtering by status and ordering by execution time)
        -- Used by: Queries finding most recent failed processes, status-based analysis with time ordering
        CREATE INDEX IF NOT EXISTS idx_processing_log_status_execution_time ON processing_log(status, execution_time DESC);
        
        -- Covering index for common queries
        -- Index: idx_processing_log_covering (status, execution_time DESC, duration_seconds, notes_processed)
        -- Benefits: Monitoring (covering index includes all columns needed for common queries, avoids table access)
        -- Used by: Common monitoring queries that need status, time, duration, and notes_processed without accessing table
        CREATE INDEX IF NOT EXISTS idx_processing_log_covering 
        ON processing_log(status, execution_time DESC, duration_seconds, notes_processed);
    END IF;
END $$;

-- Hash index for duplicate detection (if needed)
-- Index: idx_notes_note_id_hash (note_id) - HASH
-- Benefits: Monitoring (duplicate detection), Ingestion (quick note_id existence checks, though PK already exists)
-- Used by: Duplicate detection queries, fast note_id lookups (though PK already provides this)
CREATE INDEX IF NOT EXISTS idx_notes_note_id_hash ON notes USING HASH(note_id);

-- Partial index for quality checks
-- Index: idx_notes_quality_check (id) - Partial Index
-- Benefits: Monitoring (data_quality.sql - identifies notes with data quality issues)
-- Used by: Quickly finding notes with missing coordinates or inconsistent timestamps (latitude IS NULL OR longitude IS NULL OR updated_at < created_at)
CREATE INDEX IF NOT EXISTS idx_notes_quality_check
ON notes(id)
WHERE latitude IS NULL OR longitude IS NULL OR updated_at < created_at;

-- Analyze tables after creating indexes
ANALYZE notes;
ANALYZE note_comments;
ANALYZE note_comment_texts;

-- Analyze processing_log if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'processing_log') THEN
        ANALYZE processing_log;
    END IF;
END $$;
