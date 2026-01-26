# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Maintenance

- Regular code reviews
- Update dependencies
- Security patches
- Performance optimization
- Documentation updates
- Add new monitoring checks as needed
- Improve alert thresholds based on experience
- Optimize queries based on usage
- Add new dashboards as needed

## [1.2.0] - 2026-01-10

### Added

#### Complete Analytics Monitoring Implementation (7 Phases)

##### Phase 1: ETL Metrics Collection

- **ETL metrics collection** (`bin/monitor/collect_etl_metrics.sh`)
  - ETL log parsing from `/tmp/ETL_*/ETL.log`
  - Execution time tracking
  - Facts processed (new vs updated)
  - Stage timing metrics
  - Validation status
  - Error detection and classification
  - Execution mode detection (initial/incremental)
- **ETL log parser library** (`bin/lib/etlLogParser.sh`)
  - Structured log parsing functions
  - Metrics extraction from ETL logs
- **SQL queries** (`sql/analytics/etl_execution_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/analytics_etl_overview.json`) - 8 panels
- **Alert rules** (`config/alerts/analytics_etl_alerts.yml`) - 12 rules
- **Unit tests** (`tests/unit/monitor/test_collect_etl_metrics.sh`,
  `tests/unit/lib/test_etlLogParser.sh`)
- **Integration tests** (`tests/integration/test_etl_monitoring.sh`)

##### Phase 2: Database Performance Metrics

- **Database metrics collection** (`bin/monitor/collect_database_metrics.sh`)
  - Cache hit ratio monitoring
  - Active connections tracking
  - Slow queries detection
  - Active locks monitoring
  - Table bloat analysis
  - Schema size tracking
  - Facts partition sizes
- **SQL queries** (`sql/analytics/database_performance.sql`, `sql/analytics/database_sizes.sql`)
- **Grafana dashboard** (`dashboards/grafana/analytics_dwh_performance.json`) - 7 panels
- **Alert rules** (`config/alerts/analytics_db_alerts.yml`) - 12 rules
- **Unit tests** (`tests/unit/monitor/test_collect_database_metrics.sh`)
- **Integration tests** (`tests/integration/test_database_monitoring.sh`)

##### Phase 3: Datamart Metrics

- **Datamart metrics collection** (`bin/monitor/collect_datamart_metrics.sh`)
  - Last successful execution tracking
  - Execution duration monitoring
  - Execution frequency analysis
  - Countries processed (datamart countries)
  - Parallel processing metrics
  - Users processed (datamart users)
  - Global duration tracking
  - Last update time monitoring
  - Record counts and growth
  - Staleness detection
- **Datamart log parser library** (`bin/lib/datamartLogParser.sh`)
- **SQL queries** (`sql/analytics/datamart_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/analytics_datamarts_overview.json`) - 6 panels
- **Alert rules** (`config/alerts/analytics_datamart_alerts.yml`) - 10 rules
- **Unit tests** (`tests/unit/monitor/test_collect_datamart_metrics.sh`,
  `tests/unit/lib/test_datamartLogParser.sh`)
- **Integration tests** (`tests/integration/test_datamart_monitoring.sh`)

##### Phase 4: Validation Metrics

- **Validation metrics collection** (`bin/monitor/collect_validation_metrics.sh`)
  - MON-001 validation (validate_note_current_status)
  - MON-002 validation (validate_comment_counts)
  - Orphaned facts detection
  - Overall data quality score calculation
  - Validation execution time tracking
- **SQL queries** (uses existing validation functions)
- **Grafana dashboard** (`dashboards/grafana/analytics_data_quality.json`) - 7 panels
- **Alert rules** (`config/alerts/analytics_quality_alerts.yml`) - 10 rules
- **Unit tests** (`tests/unit/monitor/test_collect_validation_metrics.sh`)
- **Integration tests** (`tests/integration/test_validation_monitoring.sh`)

##### Phase 5: System Resources

- **System metrics collection** (`bin/monitor/collect_analytics_system_metrics.sh`)
  - ETL CPU usage monitoring
  - ETL memory usage tracking
  - ETL disk I/O statistics
  - ETL log disk usage
  - PostgreSQL CPU usage
  - PostgreSQL memory usage
  - System load average (1min, 5min, 15min)
  - Root filesystem disk usage
- **Grafana dashboard** (`dashboards/grafana/analytics_system_resources.json`) - 8 panels
- **Alert rules** (`config/alerts/analytics_system_alerts.yml`) - 10 rules
- **Unit tests** (`tests/unit/monitor/test_collect_analytics_system_metrics.sh`)
- **Integration tests** (`tests/integration/test_system_resources.sh`)

##### Phase 6: Export Metrics

- **Export metrics collection** (`bin/monitor/collect_export_metrics.sh`)
  - JSON export file tracking
  - CSV export file tracking
  - Export file sizes monitoring
  - Last successful export timestamp
  - JSON schema validation
  - GitHub push status verification
  - Export log parsing
  - Export duration tracking
- **Grafana dashboard** (`dashboards/grafana/analytics_export_status.json`) - 9 panels
- **Alert rules** (`config/alerts/analytics_export_alerts.yml`) - 10 rules
- **Unit tests** (`tests/unit/monitor/test_collect_export_metrics.sh`)
- **Integration tests** (`tests/integration/test_export_monitoring.sh`)

##### Phase 7: Cron Job Monitoring

- **Cron metrics collection** (`bin/monitor/collect_cron_metrics.sh`)
  - ETL cron execution monitoring (every 15 minutes)
  - Datamart cron execution monitoring (daily)
  - Export cron execution monitoring (daily)
  - Lock files detection
  - Execution gaps detection
  - Execution count tracking (24h)
  - Last execution timestamp tracking
- **Grafana dashboard** (metrics available in existing dashboards)
- **Alert rules** (`config/alerts/analytics_cron_alerts.yml`) - 10 rules
- **Unit tests** (`tests/unit/monitor/test_collect_cron_metrics.sh`)
- **Integration tests** (`tests/integration/test_cron_monitoring.sh`)

### Changed

- **Enhanced `monitorAnalytics.sh`** with new check functions:
  - `check_etl_log_analysis()` - Phase 1
  - `check_database_performance()` - Phase 2
  - `check_datamart_status()` - Phase 3
  - `check_validation_status()` - Phase 4
  - `check_system_resources()` - Phase 5
  - `check_export_status()` - Phase 6
  - `check_cron_jobs()` - Phase 7
- **Updated `Analytics_Monitoring_Guide.md`** with comprehensive documentation for all 7 phases
- **Removed obsolete documentation**:
  - `docs/ANALYTICS_MONITORING_REPORT.md` (implementation complete)
  - `docs/ANALYTICS_IMPLEMENTATION_PLAN.md` (implementation complete)
  - `docs/ANALYTICS_TODO_LIST.md` (all tasks completed)

### Technical Details

- **Total new metrics**: 100+ metrics across 7 phases
- **New scripts**: 7 collection scripts, 2 parser libraries
- **New dashboards**: 6 Grafana dashboards
- **New SQL queries**: 4 SQL files with 40+ queries
- **Test coverage**: 50+ new unit and integration tests, all passing
- **Alert rules**: 70+ alert rules across 7 alert files

### Notes

- All 7 phases of the Analytics monitoring implementation plan have been successfully completed
- Complete monitoring coverage for ETL, database, datamarts, validations, system resources, exports,
  and cron jobs
- See `docs/ANALYTICS_MONITORING_GUIDE.md` for complete operational guidance

## [1.1.0] - 2026-01-09

### Added

#### Phase 1: Daemon Process Monitoring (High Priority)

- **Daemon metrics collection** (`bin/monitor/collectDaemonMetrics.sh`)
  - Systemd service status monitoring
  - Process information (PID, uptime, memory, CPU)
  - Lock file verification
  - Cycle metrics parsing from logs (duration, success rate, frequency)
  - Processing metrics (notes processed, new vs updated, comments)
- **SQL queries** (`sql/ingestion/daemon_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/daemon_overview.json`) - 9 panels
- **Unit tests** (`tests/unit/monitor/test_collectDaemonMetrics.sh`,
  `test_monitorIngestion_daemon.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 2: Advanced Database Performance Monitoring (High Priority)

- **Database metrics collection** (`bin/monitor/collectDatabaseMetrics.sh`)
  - Table sizes and growth tracking
  - Index usage and bloat analysis
  - Unused indexes detection
  - Slow queries tracking
  - Cache hit ratio monitoring
  - Connection statistics
  - Lock statistics
- **SQL queries** (`sql/ingestion/database_performance_advanced.sql`)
- **Grafana dashboard** (`dashboards/grafana/database_performance.json`) - 11 panels
- **Unit tests** (`tests/unit/monitor/test_collectDatabaseMetrics.sh`,
  `test_monitorIngestion_database.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 3: Complete System Resources Monitoring (Medium Priority)

- **System metrics collection** (`bin/monitor/collectSystemMetrics.sh`)
  - Load average monitoring
  - CPU usage by process (daemon, PostgreSQL)
  - Memory usage by process
  - Swap usage
  - Disk I/O statistics
  - Network traffic monitoring
- **Integration** (`bin/monitor/monitorInfrastructure.sh`)
- **Grafana dashboard** (`dashboards/grafana/system_resources.json`) - 10 panels
- **Unit tests** (`tests/unit/monitor/test_collectSystemMetrics.sh`,
  `test_monitorInfrastructure_system.sh`)
- **Documentation** (updated `docs/INFRASTRUCTURE_MONITORING_GUIDE.md`)

#### Phase 4: Enhanced API Integration Metrics (Medium Priority)

- **API logs parser** (`bin/lib/parseApiLogs.sh`)
  - HTTP request parsing
  - Response time extraction
  - Success/failure rate calculation
  - Rate limit detection
  - Error classification (4xx, 5xx)
  - Synchronization gap detection
- **SQL queries** (`sql/ingestion/api_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/api_integration.json`) - 10 panels
- **Unit tests** (`tests/unit/lib/test_parseApiLogs.sh`, `test_monitorIngestion_api_advanced.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 5: Boundary Processing Monitoring (Low Priority)

- **Boundary metrics collection** (`bin/monitor/collectBoundaryMetrics.sh`)
  - Countries and maritime boundaries last update tracking
  - Update frequency calculation
  - Notes without country detection
  - Notes with wrong country assignment detection (referential integrity + spatial mismatch)
  - Notes affected by boundary changes detection
- **SQL queries** (`sql/ingestion/boundary_metrics.sql`)
- **Grafana dashboard** (`dashboards/grafana/boundary_processing.json`) - 7 panels
- **Unit tests** (`tests/unit/monitor/test_collectBoundaryMetrics.sh`,
  `test_monitorIngestion_boundary.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

#### Phase 6: Structured Log Analysis Metrics (Medium Priority)

- **Structured logs parser** (`bin/lib/parseStructuredLogs.sh`)
  - Cycle metrics extraction (duration, frequency, success rate)
  - Processing metrics (notes, comments, rates)
  - Stage timing metrics from [TIMING] logs
  - Optimization metrics (ANALYZE cache effectiveness, integrity optimizations, sequence syncs)
- **Grafana dashboard** (`dashboards/grafana/log_analysis.json`) - 14 panels
- **Unit tests** (`tests/unit/lib/test_parseStructuredLogs.sh`,
  `test_monitorIngestion_log_analysis.sh`)
- **Documentation** (updated `docs/INGESTION_METRICS.md`)

### Changed

- **Enhanced `monitorIngestion.sh`** with new check functions:
  - `check_daemon_metrics()` - Phase 1
  - `check_advanced_database_metrics()` - Phase 2
  - `check_advanced_system_metrics()` - Phase 3 (in `monitorInfrastructure.sh`)
  - `check_advanced_api_metrics()` - Phase 4
  - `check_boundary_metrics()` - Phase 5
  - `check_structured_log_metrics()` - Phase 6
- **Updated configuration** (`config/monitoring.conf.example`):
  - Added thresholds for daemon monitoring
  - Added thresholds for advanced database monitoring
  - Added thresholds for system resources
  - Added thresholds for API monitoring
  - Added thresholds for boundary processing
  - Added thresholds for log analysis
- **Documentation updates**:
  - `docs/INGESTION_METRICS.md` - Added 60+ new metrics
  - `docs/INFRASTRUCTURE_MONITORING_GUIDE.md` - Added system resources metrics
  - All metrics properly documented with descriptions, units, thresholds, and alert conditions

### Technical Details

- **Total new metrics**: 60+ metrics across 6 phases
- **New scripts**: 6 collection scripts, 2 parser libraries
- **New dashboards**: 6 Grafana dashboards
- **New SQL queries**: 3 SQL files with 30+ queries
- **Test coverage**: 30+ new unit tests, all passing
- **Configuration options**: 15+ new configurable thresholds

### Notes

- All 6 phases of the monitoring enhancement plan have been successfully implemented
- See `docs/INGESTION_METRICS.md` for complete metric documentation
- See `docs/INGESTION_MONITORING_GUIDE.md` for operational guidance

## [1.0.0] - 2026-01-09

### Added

- Complete monitoring system for all OSM Notes components
- Ingestion monitoring scripts (`bin/monitor/monitorIngestion.sh`)
- Analytics monitoring scripts (`bin/monitor/monitorAnalytics.sh`)
- WMS monitoring scripts (`bin/monitor/monitorWMS.sh`)
- Data freshness monitoring (`bin/monitor/monitorData.sh`)
- Infrastructure monitoring (`bin/monitor/monitorInfrastructure.sh`)
- API security monitoring (`bin/monitor/monitorAPI.sh`)
- Rate limiting implementation (`bin/security/rateLimiter.sh`)
- DDoS protection (`bin/security/ddosProtection.sh`)
- Abuse detection (`bin/security/abuseDetection.sh`)
- IP blocking management (`bin/security/ipBlocking.sh`)
- Unified alerting system (`bin/alerts/`)
- Grafana dashboards (6 dashboards)
- HTML dashboards (3 dashboards)
- Comprehensive test suite (>80% coverage)
- Complete documentation (50+ guides and references)

### Changed

- All planned features from v0.1.0 have been implemented
- System ready for production deployment

## [0.1.0] - 2025-12-24

### Added

- Repository structure
- Documentation:
  - Monitoring Architecture Proposal
  - API Security Design
  - Monitoring Resumen Ejecutivo (Spanish)
- README.md with project overview
- CHANGELOG.md
- .gitignore
- LICENSE (GPL v3)

---

[Unreleased]: https://github.com/OSM-Notes/OSM-Notes-Monitoring/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/OSM-Notes/OSM-Notes-Monitoring/releases/tag/v1.0.0
[0.1.0]: https://github.com/OSM-Notes/OSM-Notes-Monitoring/releases/tag/v0.1.0
