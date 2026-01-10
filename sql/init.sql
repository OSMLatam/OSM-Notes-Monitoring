-- OSM-Notes-Monitoring Database Initialization Script
-- Version: 2025-12-24
-- Purpose: Create database schema for monitoring metrics and alerts
--
-- This script creates all necessary tables, indexes, functions, and views
-- for the OSM-Notes-Monitoring system.
--
-- Usage:
--   psql -d osm_notes_monitoring -f sql/init.sql
--
-- Requirements:
--   - PostgreSQL 12+ (for JSONB and other features)
--   - Extensions: uuid-ossp, pg_trgm
--   - Optional: TimescaleDB extension for better time-series performance

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Optional: Enable TimescaleDB for better time-series performance
-- Uncomment if TimescaleDB is installed:
-- CREATE EXTENSION IF NOT EXISTS "timescaledb";

-- Metrics table for storing time-series monitoring data
CREATE TABLE IF NOT EXISTS metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    component VARCHAR(50) NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    metric_value NUMERIC,
    metric_unit VARCHAR(20),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB,
    CONSTRAINT metrics_component_check CHECK (component IN ('ingestion', 'analytics', 'wms', 'api', 'data', 'infrastructure'))
);

-- Create indexes for efficient time-series queries
CREATE INDEX IF NOT EXISTS idx_metrics_component_timestamp ON metrics(component, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_metric_name ON metrics(metric_name);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_component_metric_timestamp ON metrics(component, metric_name, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_metadata ON metrics USING GIN(metadata) WHERE metadata IS NOT NULL;

-- Alerts table for storing alert history
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    component VARCHAR(50) NOT NULL,
    alert_level VARCHAR(20) NOT NULL,
    alert_type VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB,
    CONSTRAINT alerts_level_check CHECK (alert_level IN ('critical', 'warning', 'info')),
    CONSTRAINT alerts_status_check CHECK (status IN ('active', 'resolved', 'acknowledged'))
);

-- Create indexes for alert queries
CREATE INDEX IF NOT EXISTS idx_alerts_component_status ON alerts(component, status);
CREATE INDEX IF NOT EXISTS idx_alerts_level_created ON alerts(alert_level, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_status_created ON alerts(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_component_type ON alerts(component, alert_type);
CREATE INDEX IF NOT EXISTS idx_alerts_metadata ON alerts USING GIN(metadata) WHERE metadata IS NOT NULL;

-- Security events table for API security monitoring
CREATE TABLE IF NOT EXISTS security_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL,
    ip_address INET,
    endpoint VARCHAR(255),
    user_agent TEXT,
    request_count INTEGER DEFAULT 1,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB,
    CONSTRAINT security_events_type_check CHECK (event_type IN ('rate_limit', 'ddos', 'abuse', 'block', 'unblock'))
);

-- Create indexes for security event queries
CREATE INDEX IF NOT EXISTS idx_security_events_type_timestamp ON security_events(event_type, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_security_events_ip ON security_events(ip_address);
CREATE INDEX IF NOT EXISTS idx_security_events_timestamp ON security_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_security_events_ip_timestamp ON security_events(ip_address, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_security_events_metadata ON security_events USING GIN(metadata) WHERE metadata IS NOT NULL;

-- IP management table for whitelist/blacklist
CREATE TABLE IF NOT EXISTS ip_management (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ip_address INET NOT NULL UNIQUE,
    list_type VARCHAR(20) NOT NULL,
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_by VARCHAR(100),
    CONSTRAINT ip_management_type_check CHECK (list_type IN ('whitelist', 'blacklist', 'temp_block'))
);

-- Create index for IP management queries
CREATE INDEX IF NOT EXISTS idx_ip_management_ip_type ON ip_management(ip_address, list_type);
CREATE INDEX IF NOT EXISTS idx_ip_management_expires ON ip_management(expires_at) WHERE expires_at IS NOT NULL;

-- Component health status table
CREATE TABLE IF NOT EXISTS component_health (
    component VARCHAR(50) PRIMARY KEY,
    status VARCHAR(20) NOT NULL,
    last_check TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_success TIMESTAMP WITH TIME ZONE,
    error_count INTEGER DEFAULT 0,
    metadata JSONB,
    CONSTRAINT component_health_component_check CHECK (component IN ('ingestion', 'analytics', 'wms', 'api', 'data', 'infrastructure', 'daemon')),
    CONSTRAINT component_health_status_check CHECK (status IN ('healthy', 'degraded', 'down', 'unknown'))
);

-- Create function to clean up old metrics (retention policy)
CREATE OR REPLACE FUNCTION cleanup_old_metrics(retention_days INTEGER DEFAULT 90)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM metrics
    WHERE timestamp < CURRENT_TIMESTAMP - (retention_days || ' days')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create function to clean up old alerts
CREATE OR REPLACE FUNCTION cleanup_old_alerts(retention_days INTEGER DEFAULT 180)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM alerts
    WHERE created_at < CURRENT_TIMESTAMP - (retention_days || ' days')::INTERVAL
    AND status = 'resolved';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create function to clean up expired IP blocks
CREATE OR REPLACE FUNCTION cleanup_expired_ip_blocks()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM ip_management
    WHERE list_type = 'temp_block'
    AND expires_at IS NOT NULL
    AND expires_at < CURRENT_TIMESTAMP;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create function to clean up old security events
CREATE OR REPLACE FUNCTION cleanup_old_security_events(retention_days INTEGER DEFAULT 90)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM security_events
    WHERE timestamp < CURRENT_TIMESTAMP - (retention_days || ' days')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create migration tracking table (for future migrations)
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);

COMMENT ON TABLE schema_migrations IS 'Tracks which database migrations have been applied';

-- Record initial schema version
INSERT INTO schema_migrations (version, description) VALUES
    ('init', 'Initial database schema from init.sql')
ON CONFLICT (version) DO NOTHING;

-- Insert initial component health records
INSERT INTO component_health (component, status) VALUES
    ('ingestion', 'unknown'),
    ('analytics', 'unknown'),
    ('wms', 'unknown'),
    ('api', 'unknown'),
    ('data', 'unknown'),
    ('infrastructure', 'unknown')
ON CONFLICT (component) DO NOTHING;

-- Create view for recent metrics summary
CREATE OR REPLACE VIEW metrics_summary AS
SELECT 
    component,
    metric_name,
    AVG(metric_value) as avg_value,
    MIN(metric_value) as min_value,
    MAX(metric_value) as max_value,
    COUNT(*) as sample_count,
    MAX(timestamp) as last_updated
FROM metrics
WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY component, metric_name;

-- Create view for active alerts
CREATE OR REPLACE VIEW active_alerts_summary AS
SELECT 
    component,
    alert_level,
    COUNT(*) as alert_count,
    MAX(created_at) as latest_alert
FROM alerts
WHERE status = 'active'
GROUP BY component, alert_level;

-- Grant permissions
-- Note: After running this script, you must grant permissions to your monitoring database user.
-- The GRANT commands are documented in the installation guides (README.md, DEPLOYMENT_GUIDE.md, etc.)
-- 
-- Example (replace 'osm_notes_monitoring_user' with your actual database user):
-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO osm_notes_monitoring_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO osm_notes_monitoring_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO osm_notes_monitoring_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO osm_notes_monitoring_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO osm_notes_monitoring_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO osm_notes_monitoring_user;
-- GRANT USAGE ON SCHEMA public TO osm_notes_monitoring_user;

-- Table comments
COMMENT ON TABLE metrics IS 'Time-series metrics storage for all monitored components';
COMMENT ON TABLE alerts IS 'Alert history and status tracking';
COMMENT ON TABLE security_events IS 'Security-related events (rate limiting, DDoS, abuse detection)';
COMMENT ON TABLE ip_management IS 'IP whitelist, blacklist, and temporary blocks';
COMMENT ON TABLE component_health IS 'Current health status of each monitored component';

-- Column comments for metrics table
COMMENT ON COLUMN metrics.component IS 'Component name: ingestion, analytics, wms, api, data, infrastructure';
COMMENT ON COLUMN metrics.metric_name IS 'Name of the metric being tracked';
COMMENT ON COLUMN metrics.metric_value IS 'Numeric value of the metric';
COMMENT ON COLUMN metrics.metric_unit IS 'Unit of measurement (ms, %, count, etc.)';
COMMENT ON COLUMN metrics.metadata IS 'Additional metadata as JSON (tags, labels, etc.)';

-- Column comments for alerts table
COMMENT ON COLUMN alerts.alert_level IS 'Alert severity: critical, warning, info';
COMMENT ON COLUMN alerts.alert_type IS 'Type/category of alert (e.g., data_quality, performance, availability)';
COMMENT ON COLUMN alerts.status IS 'Alert status: active, resolved, acknowledged';
COMMENT ON COLUMN alerts.metadata IS 'Additional alert context as JSON';

-- Column comments for security_events table
COMMENT ON COLUMN security_events.event_type IS 'Type of security event: rate_limit, ddos, abuse, block, unblock';
COMMENT ON COLUMN security_events.ip_address IS 'IP address associated with the event';
COMMENT ON COLUMN security_events.endpoint IS 'API endpoint accessed (if applicable)';
COMMENT ON COLUMN security_events.request_count IS 'Number of requests in this event';

-- Column comments for ip_management table
COMMENT ON COLUMN ip_management.list_type IS 'Type of list: whitelist, blacklist, temp_block';
COMMENT ON COLUMN ip_management.reason IS 'Reason for adding IP to list';
COMMENT ON COLUMN ip_management.expires_at IS 'Expiration time for temporary blocks (NULL for permanent)';

-- Column comments for component_health table
COMMENT ON COLUMN component_health.status IS 'Health status: healthy, degraded, down, unknown';
COMMENT ON COLUMN component_health.last_check IS 'Timestamp of last health check';
COMMENT ON COLUMN component_health.last_success IS 'Timestamp of last successful check';
COMMENT ON COLUMN component_health.error_count IS 'Consecutive error count';

-- Function comments
COMMENT ON FUNCTION cleanup_old_metrics(INTEGER) IS 'Remove metrics older than retention_days (default: 90)';
COMMENT ON FUNCTION cleanup_old_alerts(INTEGER) IS 'Remove resolved alerts older than retention_days (default: 180)';
COMMENT ON FUNCTION cleanup_expired_ip_blocks() IS 'Remove expired temporary IP blocks';
COMMENT ON FUNCTION cleanup_old_security_events(INTEGER) IS 'Remove security events older than retention_days (default: 90)';

-- View comments
COMMENT ON VIEW metrics_summary IS 'Summary of metrics from last 24 hours grouped by component and metric name';
COMMENT ON VIEW active_alerts_summary IS 'Summary of active alerts grouped by component and alert level';

