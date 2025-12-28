-- WMS Performance Queries
-- Queries for monitoring WMS performance metrics

-- Get current response time statistics
-- Returns: avg_response_time_ms, min_response_time_ms, max_response_time_ms, p95_response_time_ms
SELECT 
    AVG(metric_value::numeric) as avg_response_time_ms,
    MIN(metric_value::numeric) as min_response_time_ms,
    MAX(metric_value::numeric) as max_response_time_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY metric_value::numeric) as p95_response_time_ms,
    COUNT(*) as sample_count
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'response_time_ms'
  AND timestamp > NOW() - INTERVAL '1 hour';

-- Get response time trends (last 24 hours, hourly)
-- Returns: hour, avg_response_time_ms, max_response_time_ms, p95_response_time_ms
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(metric_value::numeric) as avg_response_time_ms,
    MAX(metric_value::numeric) as max_response_time_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY metric_value::numeric) as p95_response_time_ms
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'response_time_ms'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Get tile generation performance statistics
-- Returns: avg_generation_time_ms, min_generation_time_ms, max_generation_time_ms
SELECT 
    AVG(metric_value::numeric) as avg_generation_time_ms,
    MIN(metric_value::numeric) as min_generation_time_ms,
    MAX(metric_value::numeric) as max_generation_time_ms,
    COUNT(*) as tile_count
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'tile_generation_time_ms'
  AND timestamp > NOW() - INTERVAL '1 hour';

-- Get tile generation performance by zoom level (if metadata includes zoom)
-- Returns: zoom_level, avg_generation_time_ms, count
SELECT 
    (metadata->>'zoom')::integer as zoom_level,
    AVG(metric_value::numeric) as avg_generation_time_ms,
    COUNT(*) as tile_count
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'tile_generation_time_ms'
  AND timestamp > NOW() - INTERVAL '1 hour'
  AND metadata ? 'zoom'
GROUP BY zoom_level
ORDER BY zoom_level;

-- Get cache performance statistics
-- Returns: cache_hit_rate_percent, total_requests, cache_hits, cache_misses
SELECT 
    AVG(CASE WHEN metric_name = 'cache_hit_rate_percent' THEN metric_value::numeric END) as cache_hit_rate_percent,
    SUM(CASE WHEN metric_name = 'request_count' THEN metric_value::numeric ELSE 0 END) as total_requests,
    SUM(CASE WHEN metric_name = 'cache_hits' THEN metric_value::numeric ELSE 0 END) as cache_hits,
    SUM(CASE WHEN metric_name = 'cache_misses' THEN metric_value::numeric ELSE 0 END) as cache_misses
FROM metrics
WHERE component = 'wms'
  AND metric_name IN ('cache_hit_rate_percent', 'request_count', 'cache_hits', 'cache_misses')
  AND timestamp > NOW() - INTERVAL '1 hour';

-- Get cache hit rate trends (last 24 hours, hourly)
-- Returns: hour, avg_cache_hit_rate_percent, total_requests
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'cache_hit_rate_percent' THEN metric_value::numeric END) as avg_cache_hit_rate_percent,
    SUM(CASE WHEN metric_name = 'request_count' THEN metric_value::numeric ELSE 0 END) as total_requests
FROM metrics
WHERE component = 'wms'
  AND metric_name IN ('cache_hit_rate_percent', 'request_count')
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Get performance degradation detection
-- Compare current hour vs previous hour
-- Returns: current_avg_ms, previous_avg_ms, degradation_percent
WITH current_period AS (
    SELECT AVG(metric_value::numeric) as avg_response_time
    FROM metrics
    WHERE component = 'wms'
      AND metric_name = 'response_time_ms'
      AND timestamp > NOW() - INTERVAL '1 hour'
),
previous_period AS (
    SELECT AVG(metric_value::numeric) as avg_response_time
    FROM metrics
    WHERE component = 'wms'
      AND metric_name = 'response_time_ms'
      AND timestamp > NOW() - INTERVAL '2 hours'
      AND timestamp <= NOW() - INTERVAL '1 hour'
)
SELECT 
    cp.avg_response_time as current_avg_ms,
    pp.avg_response_time as previous_avg_ms,
    CASE 
        WHEN pp.avg_response_time > 0 THEN 
            ((cp.avg_response_time - pp.avg_response_time) / pp.avg_response_time * 100)
        ELSE 0
    END as degradation_percent
FROM current_period cp
CROSS JOIN previous_period pp;

-- Get slow requests (above threshold)
-- Returns: timestamp, response_time_ms, threshold_exceeded_by_ms
SELECT 
    timestamp,
    metric_value::numeric as response_time_ms,
    (metric_value::numeric - 2000) as threshold_exceeded_by_ms
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'response_time_ms'
  AND metric_value::numeric > 2000  -- threshold
  AND timestamp > NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC;

