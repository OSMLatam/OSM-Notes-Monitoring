-- WMS Error Analysis Queries
-- Queries for analyzing WMS errors and failures

-- Get current error rate statistics
-- Returns: error_rate_percent, error_count, total_requests
SELECT 
    AVG(CASE WHEN metric_name = 'error_rate_percent' THEN metric_value::numeric END) as error_rate_percent,
    SUM(CASE WHEN metric_name = 'error_count' THEN metric_value::numeric ELSE 0 END) as error_count,
    SUM(CASE WHEN metric_name = 'request_count' THEN metric_value::numeric ELSE 0 END) as total_requests
FROM metrics
WHERE component = 'wms'
  AND metric_name IN ('error_rate_percent', 'error_count', 'request_count')
  AND timestamp > NOW() - INTERVAL '1 hour';

-- Get error rate trends (last 24 hours, hourly)
-- Returns: hour, error_rate_percent, error_count, total_requests
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_name = 'error_rate_percent' THEN metric_value::numeric END) as error_rate_percent,
    SUM(CASE WHEN metric_name = 'error_count' THEN metric_value::numeric ELSE 0 END) as error_count,
    SUM(CASE WHEN metric_name = 'request_count' THEN metric_value::numeric ELSE 0 END) as total_requests
FROM metrics
WHERE component = 'wms'
  AND metric_name IN ('error_rate_percent', 'error_count', 'request_count')
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Get error rate by alert type (from alerts table)
-- Returns: alert_type, alert_count, latest_alert_time
SELECT 
    alert_type,
    COUNT(*) as alert_count,
    MAX(created_at) as latest_alert_time
FROM alerts
WHERE component = 'WMS'
  AND alert_type LIKE '%error%'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY alert_type
ORDER BY alert_count DESC;

-- Get recent error alerts
-- Returns: alert_level, alert_type, message, created_at
SELECT 
    alert_level,
    alert_type,
    message,
    created_at
FROM alerts
WHERE component = 'WMS'
  AND alert_level IN ('error', 'critical')
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- Get error spike detection
-- Compare current hour vs previous hour
-- Returns: current_error_rate, previous_error_rate, spike_percent
WITH current_period AS (
    SELECT AVG(metric_value::numeric) as error_rate
    FROM metrics
    WHERE component = 'wms'
      AND metric_name = 'error_rate_percent'
      AND timestamp > NOW() - INTERVAL '1 hour'
),
previous_period AS (
    SELECT AVG(metric_value::numeric) as error_rate
    FROM metrics
    WHERE component = 'wms'
      AND metric_name = 'error_rate_percent'
      AND timestamp > NOW() - INTERVAL '2 hours'
      AND timestamp <= NOW() - INTERVAL '1 hour'
)
SELECT 
    cp.error_rate as current_error_rate,
    pp.error_rate as previous_error_rate,
    CASE 
        WHEN pp.error_rate > 0 THEN 
            ((cp.error_rate - pp.error_rate) / pp.error_rate * 100)
        ELSE 
            CASE WHEN cp.error_rate > 0 THEN 100 ELSE 0 END
    END as spike_percent
FROM current_period cp
CROSS JOIN previous_period pp;

-- Get error patterns over time
-- Returns: date, error_count, error_rate_percent, request_count
SELECT 
    DATE(timestamp) as date,
    SUM(CASE WHEN metric_name = 'error_count' THEN metric_value::numeric ELSE 0 END) as error_count,
    AVG(CASE WHEN metric_name = 'error_rate_percent' THEN metric_value::numeric END) as error_rate_percent,
    SUM(CASE WHEN metric_name = 'request_count' THEN metric_value::numeric ELSE 0 END) as request_count
FROM metrics
WHERE component = 'wms'
  AND metric_name IN ('error_count', 'error_rate_percent', 'request_count')
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY date
ORDER BY date DESC;

-- Get service availability during error periods
-- Returns: error_period_start, error_period_end, availability_during_error
WITH error_periods AS (
    SELECT 
        timestamp as period_start,
        LEAD(timestamp) OVER (ORDER BY timestamp) as period_end,
        metric_value::numeric as error_rate
    FROM metrics
    WHERE component = 'wms'
      AND metric_name = 'error_rate_percent'
      AND metric_value::numeric > 5  -- threshold
      AND timestamp > NOW() - INTERVAL '7 days'
)
SELECT 
    ep.period_start,
    COALESCE(ep.period_end, CURRENT_TIMESTAMP) as period_end,
    AVG(m.metric_value::numeric) as availability_during_error
FROM error_periods ep
LEFT JOIN metrics m ON m.component = 'wms'
  AND m.metric_name = 'service_availability'
  AND m.timestamp >= ep.period_start
  AND m.timestamp < COALESCE(ep.period_end, CURRENT_TIMESTAMP)
GROUP BY ep.period_start, ep.period_end
ORDER BY ep.period_start DESC;

-- Get correlation between errors and performance
-- Returns: error_rate_percent, avg_response_time_ms, correlation
WITH error_metrics AS (
    SELECT 
        DATE_TRUNC('hour', timestamp) as hour,
        AVG(CASE WHEN metric_name = 'error_rate_percent' THEN metric_value::numeric END) as error_rate,
        AVG(CASE WHEN metric_name = 'response_time_ms' THEN metric_value::numeric END) as response_time
    FROM metrics
    WHERE component = 'wms'
      AND metric_name IN ('error_rate_percent', 'response_time_ms')
      AND timestamp > NOW() - INTERVAL '7 days'
    GROUP BY hour
)
SELECT 
    AVG(error_rate) as avg_error_rate_percent,
    AVG(response_time) as avg_response_time_ms,
    COUNT(*) as data_points
FROM error_metrics
WHERE error_rate IS NOT NULL AND response_time IS NOT NULL;

