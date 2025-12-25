-- Data Quality Queries for Ingestion Monitoring
-- Version: 1.0.0
-- Date: 2025-12-24
--
-- These queries check data quality metrics
-- Assumes connection to the ingestion database

-- Query 1: Missing or null data checks
-- Checks for missing or null values in critical fields
SELECT 
    'notes' AS table_name,
    COUNT(*) FILTER (WHERE id IS NULL) AS null_ids,
    COUNT(*) FILTER (WHERE created_at IS NULL) AS null_created_at,
    COUNT(*) FILTER (WHERE updated_at IS NULL) AS null_updated_at,
    COUNT(*) FILTER (WHERE latitude IS NULL OR longitude IS NULL) AS null_coordinates,
    COUNT(*) AS total_records
FROM notes
UNION ALL
SELECT 
    'note_comments' AS table_name,
    COUNT(*) FILTER (WHERE id IS NULL) AS null_ids,
    COUNT(*) FILTER (WHERE note_id IS NULL) AS null_note_id,
    COUNT(*) FILTER (WHERE created_at IS NULL) AS null_created_at,
    NULL AS null_coordinates,
    COUNT(*) AS total_records
FROM note_comments;

-- Query 2: Data completeness percentage
-- Calculates data completeness for each table
SELECT 
    'notes' AS table_name,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE id IS NOT NULL 
                      AND created_at IS NOT NULL 
                      AND updated_at IS NOT NULL 
                      AND latitude IS NOT NULL 
                      AND longitude IS NOT NULL) AS complete_records,
    ROUND(COUNT(*) FILTER (WHERE id IS NOT NULL 
                            AND created_at IS NOT NULL 
                            AND updated_at IS NOT NULL 
                            AND latitude IS NOT NULL 
                            AND longitude IS NOT NULL) * 100.0 / NULLIF(COUNT(*), 0), 2) AS completeness_percent
FROM notes;

-- Query 3: Duplicate detection
-- Checks for duplicate note IDs (should not exist)
SELECT 
    note_id,
    COUNT(*) AS duplicate_count
FROM notes
GROUP BY note_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- Query 4: Orphaned records
-- Checks for orphaned comments (comments without parent notes)
SELECT 
    COUNT(*) AS orphaned_comments
FROM note_comments nc
LEFT JOIN notes n ON nc.note_id = n.id
WHERE n.id IS NULL;

-- Query 5: Data consistency checks
-- Checks for data consistency issues
SELECT 
    'notes_without_comments' AS check_type,
    COUNT(*) AS count
FROM notes n
LEFT JOIN note_comments nc ON n.id = nc.note_id
WHERE nc.id IS NULL
UNION ALL
SELECT 
    'comments_without_text' AS check_type,
    COUNT(*) AS count
FROM note_comments nc
LEFT JOIN note_comment_texts nct ON nc.id = nct.comment_id
WHERE nct.id IS NULL;

-- Query 6: Invalid coordinate ranges
-- Checks for notes with invalid coordinates (outside valid ranges)
SELECT 
    COUNT(*) FILTER (WHERE latitude < -90 OR latitude > 90) AS invalid_latitude,
    COUNT(*) FILTER (WHERE longitude < -180 OR longitude > 180) AS invalid_longitude,
    COUNT(*) FILTER (WHERE latitude IS NULL OR longitude IS NULL) AS null_coordinates,
    COUNT(*) AS total_notes
FROM notes;

-- Query 7: Date consistency
-- Checks for dates that don't make sense (future dates, created after updated)
SELECT 
    COUNT(*) FILTER (WHERE created_at > NOW()) AS future_created_dates,
    COUNT(*) FILTER (WHERE updated_at > NOW()) AS future_updated_dates,
    COUNT(*) FILTER (WHERE updated_at < created_at) AS updated_before_created,
    COUNT(*) AS total_notes
FROM notes;

-- Query 8: Data quality score
-- Calculates overall data quality score
WITH quality_metrics AS (
    SELECT 
        COUNT(*) AS total_notes,
        COUNT(*) FILTER (WHERE id IS NOT NULL 
                          AND created_at IS NOT NULL 
                          AND updated_at IS NOT NULL 
                          AND latitude IS NOT NULL 
                          AND longitude IS NOT NULL
                          AND latitude BETWEEN -90 AND 90
                          AND longitude BETWEEN -180 AND 180
                          AND created_at <= NOW()
                          AND updated_at >= created_at) AS valid_notes
    FROM notes
)
SELECT 
    total_notes,
    valid_notes,
    total_notes - valid_notes AS invalid_notes,
    ROUND(valid_notes * 100.0 / NULLIF(total_notes, 0), 2) AS quality_score_percent
FROM quality_metrics;

