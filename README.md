# OSM-Notes-Monitoring

**Centralized Monitoring, Alerting, and API Security for OpenStreetMap Notes**

This repository provides centralized monitoring, alerting, and security for the entire OSM Notes ecosystem. It monitors all components, provides unified dashboards, and protects the API against abuse and attacks.

## Overview

OSM-Notes-Monitoring is the operational command center for the OSM Notes ecosystem, providing:

- **Centralized Monitoring**: Single dashboard for all OSM Notes repositories
- **Unified Alerting**: Email, Slack, and other alert channels
- **API Security**: Rate limiting, DDoS protection, and abuse detection
- **Data Freshness**: Monitor data freshness across all sources
- **Performance Tracking**: Monitor performance metrics across all components
- **Security Monitoring**: Detect and respond to security incidents

## Monitored Components

This system monitors the following repositories:

- **OSM-Notes-Ingestion**: Data ingestion status, processing health, data quality
  - Integrates with existing monitoring scripts: `notesCheckVerifier.sh`, `processCheckPlanetNotes.sh`, `analyzeDatabasePerformance.sh`
  - See [Existing Monitoring Components](./docs/Existing_Monitoring_Components.md) for details
- **OSM-Notes-Analytics**: DWH/ETL job status, data freshness, query performance
- **OSM-Notes-WMS**: Service availability, response times, tile generation
- **OSM-Notes-API**: API availability, rate limiting, security incidents
- **OSM-Notes-Data**: Backup freshness, repository sync status
- **Infrastructure**: Server resources, database health, network connectivity

## Quick Start

### Prerequisites

- PostgreSQL (for metrics storage)
- Bash 4.0+
- `mutt` (for email alerts)
- `curl` (for HTTP health checks)
- Access to databases of monitored repositories

### Installation

1. Clone the repository:
```bash
git clone https://github.com/OSMLatam/OSM-Notes-Monitoring.git
cd OSM-Notes-Monitoring
```

2. Configure monitoring:
```bash
cp etc/properties.sh.example etc/properties.sh
# Edit etc/properties.sh with your configuration
```

3. Set up monitoring database:
```bash
# Create monitoring database
createdb osm_notes_monitoring

# Run initialization scripts
psql -d osm_notes_monitoring -f sql/init.sql
```

4. Configure alerts:
```bash
# Edit config/alerts.conf
export ADMIN_EMAIL="admin@example.com"
export SEND_ALERT_EMAIL="true"
```

## Architecture

For detailed architecture documentation, see:
- [Monitoring Architecture Proposal](./docs/Monitoring_Architecture_Proposal.md)
- [API Security Design](./docs/API_Security_Design.md)
- [Monitoring Resumen Ejecutivo](./docs/Monitoring_Resumen_Ejecutivo.md) (Spanish)
- [Existing Monitoring Components](./docs/Existing_Monitoring_Components.md): Integration with OSM-Notes-Ingestion monitoring scripts

## Features

### Monitoring

- **Component Health**: Monitor all OSM Notes repositories
- **Data Quality**: Track data integrity and freshness
- **Performance**: Monitor response times and resource usage
- **Dependencies**: Track cross-repository dependencies

### Security

- **Rate Limiting**: Per-IP, per-API-key, per-endpoint limits
- **DDoS Protection**: Automatic detection and mitigation
- **Abuse Detection**: Pattern analysis and automatic blocking
- **IP Management**: Whitelist, blacklist, temporary blocks

### Alerting

- **Email Alerts**: Immediate notifications for critical issues
- **Slack Integration**: Team notifications
- **Escalation**: Automatic escalation for critical alerts
- **Alert Management**: Deduplication and alert history

### Dashboards

- **Grafana Dashboards**: Professional time-series visualization
- **Custom Dashboards**: HTML-based dashboards for quick checks
- **CLI Tools**: Command-line dashboards

## Project Structure

```
OSM-Notes-Monitoring/
├── bin/                    # Executable scripts
│   ├── monitor/           # Monitoring scripts per component
│   ├── security/          # Security scripts (rate limiting, DDoS)
│   ├── alerts/            # Alerting system
│   ├── dashboard/         # Dashboard generation
│   └── lib/               # Shared library functions
├── sql/                   # SQL monitoring queries
│   ├── ingestion/         # Ingestion monitoring queries
│   ├── analytics/         # Analytics monitoring queries
│   ├── wms/               # WMS monitoring queries
│   ├── api/               # API monitoring queries
│   ├── data/              # Data freshness queries
│   ├── infrastructure/    # Infrastructure queries
│   └── init.sql           # Database initialization script
├── config/                # Configuration files
│   ├── monitoring.conf.example    # Monitoring configuration template
│   ├── alerts.conf.example        # Alert configuration template
│   ├── security.conf.example      # Security configuration template
│   └── dashboards/                # Dashboard configuration files
│       ├── grafana/               # Grafana dashboard configs
│       └── custom/                # Custom dashboard configs
├── dashboards/            # Dashboard files (Grafana JSON, HTML)
│   ├── grafana/           # Grafana dashboard JSON files
│   └── html/              # HTML dashboard files
├── metrics/               # Metrics storage (runtime data)
│   ├── ingestion/         # Ingestion metrics
│   ├── analytics/         # Analytics metrics
│   ├── wms/               # WMS metrics
│   ├── api/               # API metrics
│   └── infrastructure/    # Infrastructure metrics
├── etc/                   # Main configuration
│   └── properties.sh.example  # Main properties template
├── logs/                  # Monitoring logs (runtime)
├── docs/                  # Documentation
└── tests/                 # Test suite
    ├── unit/              # Unit tests
    ├── integration/       # Integration tests
    └── mock_commands/     # Mock commands for testing
```

**Note:** 
- `config/dashboards/` contains configuration files for dashboards
- `dashboards/` contains the actual dashboard files (Grafana JSON, HTML)
- `etc/properties.sh` is the main system configuration file (copy from `.example`)
- `config/monitoring.conf` contains monitoring-specific settings (copy from `.example`)
- `config/alerts.conf` and `config/security.conf` are component-specific configurations (copy from `.example`)

## Usage

### Monitor Ingestion

```bash
./bin/monitor/monitorIngestion.sh
```

### Monitor Analytics

```bash
./bin/monitor/monitorAnalytics.sh
```

### Monitor API Security

```bash
./bin/security/rateLimiter.sh check 192.168.1.100 /api/notes
```

### View Dashboard

```bash
# Start Grafana (if configured)
# Or view HTML dashboard
open dashboards/html/overview.html
```

## Configuration

### Quick Setup

Generate configuration files:
```bash
# Interactive mode (recommended)
./scripts/generate_config.sh -i

# Or generate with defaults
./scripts/generate_config.sh -a
```

### Configuration Files

- **Main Config**: `etc/properties.sh` - Database, intervals, logging
- **Monitoring Config**: `config/monitoring.conf` - Component-specific settings
- **Alert Config**: `config/alerts.conf` - Email, Slack, alert routing
- **Security Config**: `config/security.conf` - Rate limiting, DDoS protection
- **Log Rotation**: `config/logrotate.conf` - Log rotation configuration

### Documentation

For complete configuration reference, see:
- **[Configuration Reference](./docs/CONFIGURATION_REFERENCE.md)**: All configuration options documented
- **[Logging Guide](./docs/LOGGING.md)**: Logging setup, rotation, and best practices

## Documentation

- **[Task List](./TASKS.md)**: **Ordered implementation task list - follow this for development**
- **[Architecture Proposal](./docs/Monitoring_Architecture_Proposal.md)**: Complete system architecture
- **[API Security Design](./docs/API_Security_Design.md)**: Security and protection mechanisms
- **[Implementation Plan](./docs/IMPLEMENTATION_PLAN.md)**: Detailed implementation plan with testing and standards
- **[Coding Standards](./docs/CODING_STANDARDS.md)**: Coding standards and best practices
- **[Setup Guide](./docs/Monitoring_SETUP_Guide.md)**: Initial setup guide
- **[Resumen Ejecutivo](./docs/Monitoring_Resumen_Ejecutivo.md)**: Executive summary (Spanish)
- **[Existing Monitoring Components](./docs/Existing_Monitoring_Components.md)**: Integration with OSM-Notes-Ingestion monitoring scripts

## Related Repositories

- [OSM-Notes-Ingestion](https://github.com/OSMLatam/OSM-Notes-Ingestion) - Data ingestion
- [OSM-Notes-Analytics](https://github.com/OSMLatam/OSM-Notes-Analytics) - DWH and analytics
- [OSM-Notes-WMS](https://github.com/OSMLatam/OSM-Notes-WMS) - WMS service
- [OSM-Notes-Data](https://github.com/OSMLatam/OSM-Notes-Data) - Data backups
- [OSM-Notes-Common](https://github.com/OSMLatam/OSM-Notes-Common) - Shared libraries

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for contribution guidelines.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](./LICENSE) file for details.

## Status

🚧 **In Development** - This repository is currently being set up. Initial implementation is in progress.

---

**Author:** Andres Gomez (AngocA)  
**Version:** 2025-12-24

