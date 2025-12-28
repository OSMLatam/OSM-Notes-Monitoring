-- WMS Service Status Queries
-- Queries for monitoring WMS service status and availability

-- Get current service availability status
-- Returns: availability (1=available, 0=unavailable), last_check_time, response_time_ms
SELECT 
    metric_value::numeric as availability,
    timestamp as last_check_time,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'wms' 
          AND m2.metric_name = 'service_response_time_ms'
          AND m2.timestamp = (
              SELECT MAX(timestamp) 
              FROM metrics m3 
              WHERE m3.component = 'wms' 
                AND m3.metric_name = 'service_response_time_ms'
          )
    ) as response_time_ms
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'service_availability'
ORDER BY timestamp DESC
LIMIT 1;

-- Get service availability over time (last 24 hours)
-- Returns: hour, availability_percent, avg_response_time_ms
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(metric_value::numeric) * 100 as availability_percent,
    (
        SELECT AVG(m2.metric_value::numeric)
        FROM metrics m2
        WHERE m2.component = 'wms'
          AND m2.metric_name = 'service_response_time_ms'
          AND DATE_TRUNC('hour', m2.timestamp) = DATE_TRUNC('hour', m.timestamp)
    ) as avg_response_time_ms
FROM metrics m
WHERE component = 'wms'
  AND metric_name = 'service_availability'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Get current health status
-- Returns: health_status (1=healthy, 0=unhealthy), last_check_time, response_time_ms
SELECT 
    metric_value::numeric as health_status,
    timestamp as last_check_time,
    (
        SELECT metric_value::numeric 
        FROM metrics m2 
        WHERE m2.component = 'wms' 
          AND m2.metric_name = 'health_check_response_time_ms'
          AND m2.timestamp = (
              SELECT MAX(timestamp) 
              FROM metrics m3 
              WHERE m3.component = 'wms' 
                AND m3.metric_name = 'health_check_response_time_ms'
          )
    ) as response_time_ms
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'health_status'
ORDER BY timestamp DESC
LIMIT 1;

-- Get service uptime percentage (last 7 days)
-- Returns: uptime_percent, total_checks, available_checks
SELECT 
    COUNT(*) as total_checks,
    SUM(metric_value::numeric)::bigint as available_checks,
    (SUM(metric_value::numeric)::numeric / COUNT(*)::numeric * 100) as uptime_percent
FROM metrics
WHERE component = 'wms'
  AND metric_name = 'service_availability'
  AND timestamp > NOW() - INTERVAL '7 days';

-- Get recent service outages
-- Returns: outage_start, outage_end, duration_seconds
WITH availability_changes AS (
    SELECT 
        timestamp,
        metric_value::numeric as availability,
        LAG(metric_value::numeric) OVER (ORDER BY timestamp) as prev_availability
    FROM metrics
    WHERE component = 'wms'
      AND metric_name = 'service_availability'
      AND timestamp > NOW() - INTERVAL '7 days'
    ORDER BY timestamp
),
outage_starts AS (
    SELECT timestamp as outage_start
    FROM availability_changes
    WHERE availability = 0 AND (prev_availability IS NULL OR prev_availability = 1)
),
outage_ends AS (
    SELECT timestamp as outage_end
    FROM availability_changes
    WHERE availability = 1 AND prev_availability = 0
)
SELECT 
    os.outage_start,
    COALESCE(oe.outage_end, CURRENT_TIMESTAMP) as outage_end,
    EXTRACT(EPOCH FROM (COALESCE(oe.outage_end, CURRENT_TIMESTAMP) - os.outage_start))::bigint as duration_seconds
FROM outage_starts os
LEFT JOIN outage_ends oe ON oe.outage_end > os.outage_start
ORDER BY os.outage_start DESC;

