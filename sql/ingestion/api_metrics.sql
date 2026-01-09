-- API Integration Metrics Queries
-- Queries for monitoring API integration and synchronization

-- Query 1: Get latest API metrics
-- Returns: Latest values for all API metrics
SELECT 
    metric_name,
    metric_value,
    timestamp,
    metadata
FROM metrics
WHERE component = 'ingestion'
  AND metric_name IN (
    'api_response_time_ms',
    'api_success_rate_percent',
    'api_timeout_rate_percent',
    'api_errors_4xx_count',
    'api_errors_5xx_count',
    'api_requests_per_minute',
    'api_requests_per_hour',
    'api_rate_limit_hits_count',
    'api_response_size_bytes',
    'api_notes_per_request',
    'api_last_note_timestamp',
    'api_sync_gap_seconds'
  )
ORDER BY timestamp DESC, metric_name;

-- Query 2: API success rate trend (last 24 hours)
-- Returns: Hour, average success rate
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'api_success_rate_percent' THEN metric_value::numeric END) as avg_success_rate_percent,
    COUNT(CASE WHEN metric_name = 'api_success_rate_percent' THEN 1 END) as data_points
FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'api_success_rate_percent'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Query 3: API response time trend (last 24 hours)
-- Returns: Hour, average response time
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'api_response_time_ms' THEN metric_value::numeric END) as avg_response_time_ms,
    MIN(CASE WHEN metric_name = 'api_response_time_ms' THEN metric_value::numeric END) as min_response_time_ms,
    MAX(CASE WHEN metric_name = 'api_response_time_ms' THEN metric_value::numeric END) as max_response_time_ms
FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'api_response_time_ms'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Query 4: API error rates (last 24 hours)
-- Returns: Hour, 4xx errors, 5xx errors
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    SUM(CASE WHEN metric_name = 'api_errors_4xx_count' THEN metric_value::numeric ELSE 0 END) as errors_4xx_count,
    SUM(CASE WHEN metric_name = 'api_errors_5xx_count' THEN metric_value::numeric ELSE 0 END) as errors_5xx_count
FROM metrics
WHERE component = 'ingestion'
  AND metric_name IN ('api_errors_4xx_count', 'api_errors_5xx_count')
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Query 5: API request rate (last 24 hours)
-- Returns: Hour, requests per minute, requests per hour
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'api_requests_per_minute' THEN metric_value::numeric END) as avg_requests_per_minute,
    AVG(CASE WHEN metric_name = 'api_requests_per_hour' THEN metric_value::numeric END) as avg_requests_per_hour
FROM metrics
WHERE component = 'ingestion'
  AND metric_name IN ('api_requests_per_minute', 'api_requests_per_hour')
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Query 6: Rate limit hits (last 24 hours)
-- Returns: Hour, rate limit hits count
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    SUM(CASE WHEN metric_name = 'api_rate_limit_hits_count' THEN metric_value::numeric ELSE 0 END) as rate_limit_hits
FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'api_rate_limit_hits_count'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Query 7: API sync gap analysis
-- Returns: Current sync gap, last note timestamp from API, last note timestamp from DB
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics 
        WHERE component = 'ingestion' 
          AND metric_name = 'api_sync_gap_seconds'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as sync_gap_seconds,
    (
        SELECT metric_value::numeric 
        FROM metrics 
        WHERE component = 'ingestion' 
          AND metric_name = 'api_last_note_timestamp'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as api_last_note_timestamp,
    (
        SELECT EXTRACT(EPOCH FROM MAX(created_at))::numeric
        FROM notes
    ) as db_last_note_timestamp,
    (
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))::integer
        FROM notes
    ) as db_last_note_age_seconds;

-- Query 8: API throughput (download speed)
-- Returns: Hour, average response size, average notes per request
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'api_response_size_bytes' THEN metric_value::numeric END) as avg_response_size_bytes,
    AVG(CASE WHEN metric_name = 'api_notes_per_request' THEN metric_value::numeric END) as avg_notes_per_request
FROM metrics
WHERE component = 'ingestion'
  AND metric_name IN ('api_response_size_bytes', 'api_notes_per_request')
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Query 9: API availability summary (last hour)
-- Returns: Total requests, successful requests, failed requests, timeout requests
SELECT 
    (
        SELECT SUM(metric_value::numeric)
        FROM metrics
        WHERE component = 'ingestion'
          AND metric_name = 'api_requests_per_minute'
          AND timestamp > NOW() - INTERVAL '1 hour'
    ) * 60 as total_requests_estimate,
    (
        SELECT AVG(metric_value::numeric)
        FROM metrics
        WHERE component = 'ingestion'
          AND metric_name = 'api_success_rate_percent'
          AND timestamp > NOW() - INTERVAL '1 hour'
    ) as avg_success_rate_percent,
    (
        SELECT SUM(metric_value::numeric)
        FROM metrics
        WHERE component = 'ingestion'
          AND metric_name = 'api_timeout_rate_percent'
          AND timestamp > NOW() - INTERVAL '1 hour'
    ) as timeout_rate_percent;

-- Query 10: Missing notes detection (compare API timestamp with DB)
-- Returns: Potential missing notes count based on sync gap
SELECT 
    (
        SELECT metric_value::numeric 
        FROM metrics 
        WHERE component = 'ingestion' 
          AND metric_name = 'api_last_note_timestamp'
        ORDER BY timestamp DESC 
        LIMIT 1
    ) as api_last_note_timestamp,
    (
        SELECT EXTRACT(EPOCH FROM MAX(created_at))::numeric
        FROM notes
    ) as db_last_note_timestamp,
    (
        SELECT COUNT(*)::numeric
        FROM notes
        WHERE created_at > (
            SELECT MAX(created_at) - INTERVAL '1 hour'
            FROM notes
        )
    ) as notes_in_last_hour,
    CASE 
        WHEN (
            SELECT metric_value::numeric 
            FROM metrics 
            WHERE component = 'ingestion' 
              AND metric_name = 'api_sync_gap_seconds'
            ORDER BY timestamp DESC 
            LIMIT 1
        ) > 3600 THEN
            ROUND((
                SELECT metric_value::numeric 
                FROM metrics 
                WHERE component = 'ingestion' 
                  AND metric_name = 'api_notes_per_request'
                ORDER BY timestamp DESC 
                LIMIT 1
            ) * (
                SELECT metric_value::numeric 
                FROM metrics 
                WHERE component = 'ingestion' 
                  AND metric_name = 'api_sync_gap_seconds'
                ORDER BY timestamp DESC 
                LIMIT 1
            ) / 60)
        ELSE 0
    END as estimated_missing_notes;
