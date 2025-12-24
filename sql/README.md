# SQL Scripts Directory

This directory contains SQL scripts for database initialization, migrations, and monitoring queries.

## Structure

```
sql/
├── init.sql                    # Database initialization script (run first)
├── ingestion/                  # Ingestion monitoring queries
├── analytics/                  # Analytics monitoring queries
├── wms/                        # WMS monitoring queries
├── api/                        # API monitoring queries
├── data/                       # Data freshness queries
└── infrastructure/              # Infrastructure queries
```

## Initialization

### First Time Setup

1. Create the database:
```bash
createdb osm_notes_monitoring
```

2. Run the initialization script:
```bash
psql -d osm_notes_monitoring -f sql/init.sql
```

### Testing the Schema

Test the schema initialization:
```bash
./sql/test_schema.sh
```

This script will:
- Create a test database
- Initialize the schema
- Run comprehensive tests (tables, indexes, functions, views, constraints)
- Clean up the test database

### Test Database Setup

For manual testing, create a separate database:
```bash
createdb osm_notes_monitoring_test
psql -d osm_notes_monitoring_test -f sql/init.sql
```

## Schema Overview

### Tables

- **`metrics`**: Time-series metrics storage
- **`alerts`**: Alert history and status
- **`security_events`**: Security-related events
- **`ip_management`**: IP whitelist/blacklist management
- **`component_health`**: Current health status of components

### Views

- **`metrics_summary`**: Summary of recent metrics (last 24 hours)
- **`active_alerts_summary`**: Summary of active alerts

### Functions

- **`cleanup_old_metrics(retention_days)`**: Remove old metrics
- **`cleanup_old_alerts(retention_days)`**: Remove old resolved alerts
- **`cleanup_expired_ip_blocks()`**: Remove expired temporary blocks
- **`cleanup_old_security_events(retention_days)`**: Remove old security events

## Maintenance

### Regular Cleanup

Run cleanup functions periodically (e.g., via cron):

```sql
-- Clean up metrics older than 90 days
SELECT cleanup_old_metrics(90);

-- Clean up resolved alerts older than 180 days
SELECT cleanup_old_alerts(180);

-- Clean up expired IP blocks
SELECT cleanup_expired_ip_blocks();

-- Clean up security events older than 90 days
SELECT cleanup_old_security_events(90);
```

### Performance Optimization

For high-volume deployments, consider:

1. **TimescaleDB**: Enable TimescaleDB extension for better time-series performance
2. **Partitioning**: Partition metrics table by time (if not using TimescaleDB)
3. **Index Maintenance**: Regularly analyze and vacuum tables

## Query Organization

Queries are organized by component:
- Each component directory contains SQL files for specific monitoring queries
- Use descriptive filenames: `component_check_name.sql`
- Include comments explaining query purpose and usage

## Examples

### Query Recent Metrics

```sql
SELECT * FROM metrics_summary
WHERE component = 'ingestion'
ORDER BY metric_name;
```

### Check Active Alerts

```sql
SELECT * FROM active_alerts_summary
ORDER BY alert_level DESC, alert_count DESC;
```

### Get Component Health

```sql
SELECT * FROM component_health
ORDER BY status, component;
```

## Migrations

The project uses a migration system to track and apply database schema changes.

### Migration Structure

Migrations are stored in `sql/migrations/` and follow the naming pattern:
```
YYYYMMDD_HHMMSS_description.sql
```

### Running Migrations

```bash
# List pending migrations
./sql/migrations/run_migrations.sh --list -d osm_notes_monitoring

# Run all pending migrations
./sql/migrations/run_migrations.sh -d osm_notes_monitoring

# Run specific migration
./sql/migrations/run_migrations.sh -d osm_notes_monitoring 20251224_120000_description.sql

# Verbose output
./sql/migrations/run_migrations.sh -d osm_notes_monitoring -v
```

### Creating a New Migration

1. Create a new SQL file in `sql/migrations/` with the naming pattern
2. Use transactions (BEGIN/COMMIT)
3. Include comments describing the change
4. Test on a test database first
5. See `sql/migrations/README.md` for detailed guidelines

### Migration Tracking

Applied migrations are tracked in the `schema_migrations` table, which is created automatically by `init.sql` or the first migration.

## Schema Documentation

For detailed schema documentation including ER diagrams, table descriptions, and relationships, see:
- [Database Schema Documentation](../docs/DATABASE_SCHEMA.md)

## References

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [TimescaleDB Documentation](https://docs.timescale.com/) (optional)

