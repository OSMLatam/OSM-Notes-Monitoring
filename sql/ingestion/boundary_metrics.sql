-- Boundary Processing Metrics Queries
-- Queries for monitoring country and maritime boundary processing

-- Query 1: Get last update timestamps for boundaries
-- Returns: Countries last update, maritime boundaries last update
SELECT 
    (
        SELECT MAX(updated_at) 
        FROM countries 
        WHERE updated_at IS NOT NULL
    ) as countries_last_update,
    (
        SELECT MAX(updated_at) 
        FROM maritime_boundaries 
        WHERE updated_at IS NOT NULL
    ) as maritime_boundaries_last_update;

-- Query 2: Calculate update frequency (hours since last update)
-- Returns: Hours since last update for countries and maritime boundaries
SELECT 
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM countries 
        WHERE updated_at IS NOT NULL
    )::integer as countries_update_age_hours,
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM maritime_boundaries 
        WHERE updated_at IS NOT NULL
    )::integer as maritime_update_age_hours;

-- Query 3: Count notes without country assignment
-- Returns: Total notes, notes without country, notes with country, percentage without country
SELECT 
    COUNT(*) as total_notes,
    COUNT(*) FILTER (WHERE country_id IS NULL) as notes_without_country,
    COUNT(*) FILTER (WHERE country_id IS NOT NULL) as notes_with_country,
    ROUND(COUNT(*) FILTER (WHERE country_id IS NULL) * 100.0 / NULLIF(COUNT(*), 0), 2) as percentage_without_country
FROM notes;

-- Query 4: Notes with invalid coordinates (out of bounds)
-- Returns: Count of notes with coordinates outside valid ranges
SELECT COUNT(*) as notes_out_of_bounds
FROM notes
WHERE latitude < -90 OR latitude > 90 
   OR longitude < -180 OR longitude > 180;

-- Query 5: Notes with country_id that doesn't exist in countries table
-- Returns: Count of notes with invalid country_id references
SELECT COUNT(*) as notes_wrong_country
FROM notes n
WHERE n.country_id IS NOT NULL 
  AND NOT EXISTS (
      SELECT 1 FROM countries c WHERE c.id = n.country_id
  );

-- Query 5a: Notes with spatial mismatch (coordinates outside assigned country)
-- This detects notes that need reassignment after boundary updates
-- Returns: Count of notes geographically outside their assigned country
-- Note: This query uses PostGIS if available, otherwise uses bounding box check
SELECT COUNT(*) as notes_spatial_mismatch
FROM notes n
WHERE n.country_id IS NOT NULL
  AND n.latitude IS NOT NULL
  AND n.longitude IS NOT NULL
  AND EXISTS (
      SELECT 1 FROM countries c 
      WHERE c.id = n.country_id
        AND (
            -- Bounding box check (fallback if PostGIS not available)
            n.latitude < COALESCE(c.min_latitude, -90)
            OR n.latitude > COALESCE(c.max_latitude, 90)
            OR n.longitude < COALESCE(c.min_longitude, -180)
            OR n.longitude > COALESCE(c.max_longitude, 180)
            -- PostGIS spatial check (if geometry column exists)
            OR (
                c.geometry IS NOT NULL
                AND NOT ST_Contains(
                    c.geometry,
                    ST_SetSRID(ST_MakePoint(n.longitude, n.latitude), 4326)
                )
            )
        )
  );

-- Query 5b: Notes affected by boundary changes
-- Returns: Count of notes that were assigned before last boundary update
-- and might need reassignment
SELECT COUNT(*) as notes_affected_by_changes
FROM notes n
WHERE n.country_id IS NOT NULL
  AND n.latitude IS NOT NULL
  AND n.longitude IS NOT NULL
  AND n.updated_at < (SELECT MAX(updated_at) FROM countries WHERE updated_at IS NOT NULL)
  AND EXISTS (
      SELECT 1 FROM countries c 
      WHERE c.id = n.country_id
        AND c.updated_at > n.updated_at
  );

-- Query 6: Country assignment statistics by country
-- Returns: Country name, total notes, percentage of all notes
SELECT 
    c.name as country_name,
    COUNT(n.id) as notes_count,
    ROUND(COUNT(n.id) * 100.0 / NULLIF((SELECT COUNT(*) FROM notes), 0), 2) as percentage_of_total
FROM countries c
LEFT JOIN notes n ON n.country_id = c.id
GROUP BY c.id, c.name
ORDER BY notes_count DESC
LIMIT 20;

-- Query 7: Notes without country by creation date (trend)
-- Returns: Date, total notes created, notes without country, percentage without country
SELECT 
    DATE(created_at) as date,
    COUNT(*) as total_notes_created,
    COUNT(*) FILTER (WHERE country_id IS NULL) as notes_without_country,
    ROUND(COUNT(*) FILTER (WHERE country_id IS NULL) * 100.0 / NULLIF(COUNT(*), 0), 2) as percentage_without_country
FROM notes
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Query 8: Boundary update history (if updated_at tracking exists)
-- Returns: Update date, type (countries/maritime), number of records updated
SELECT 
    DATE(updated_at) as update_date,
    'countries' as boundary_type,
    COUNT(*) as records_count
FROM countries
WHERE updated_at IS NOT NULL
  AND updated_at > NOW() - INTERVAL '90 days'
GROUP BY DATE(updated_at)

UNION ALL

SELECT 
    DATE(updated_at) as update_date,
    'maritime_boundaries' as boundary_type,
    COUNT(*) as records_count
FROM maritime_boundaries
WHERE updated_at IS NOT NULL
  AND updated_at > NOW() - INTERVAL '90 days'
GROUP BY DATE(updated_at)

ORDER BY update_date DESC;

-- Query 9: Notes with coordinates near country boundaries (potential misassignments)
-- This is a simplified check - full implementation would require PostGIS spatial queries
-- Returns: Notes that might be misassigned (simplified check)
SELECT 
    n.id as note_id,
    n.latitude,
    n.longitude,
    c.name as assigned_country,
    COUNT(*) as potential_issues
FROM notes n
JOIN countries c ON c.id = n.country_id
WHERE n.latitude IS NOT NULL 
  AND n.longitude IS NOT NULL
GROUP BY n.id, n.latitude, n.longitude, c.name
HAVING COUNT(*) > 1  -- Simplified: notes that appear multiple times (potential duplicates)
LIMIT 100;

-- Query 10: Summary of boundary processing health
-- Returns: Overall health metrics
SELECT 
    (
        SELECT COUNT(*) FROM notes WHERE country_id IS NULL
    ) as notes_without_country,
    (
        SELECT COUNT(*) FROM notes WHERE country_id IS NOT NULL
    ) as notes_with_country,
    (
        SELECT COUNT(*) FROM notes 
        WHERE latitude < -90 OR latitude > 90 
           OR longitude < -180 OR longitude > 180
    ) as notes_out_of_bounds,
    (
        SELECT COUNT(*) FROM notes n
        WHERE n.country_id IS NOT NULL 
          AND NOT EXISTS (SELECT 1 FROM countries c WHERE c.id = n.country_id)
    ) as notes_wrong_country,
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM countries 
        WHERE updated_at IS NOT NULL
    )::integer as countries_update_age_hours,
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(updated_at))) / 3600
        FROM maritime_boundaries 
        WHERE updated_at IS NOT NULL
    )::integer as maritime_update_age_hours;
