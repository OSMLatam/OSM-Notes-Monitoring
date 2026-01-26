---
title: "Grafana Architecture - Dual Deployment"
description: "The OSM Notes ecosystem uses  to provide comprehensive monitoring coverage:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "architecture"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Grafana Architecture - Dual Deployment

> **Purpose:** Document the dual Grafana deployment architecture across OSM-Notes-API and
> OSM-Notes-Monitoring  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

The OSM Notes ecosystem uses **two complementary Grafana deployments** to provide comprehensive
monitoring coverage:

1. **OSM-Notes-API Grafana**: Operational monitoring for the API service
2. **OSM-Notes-Monitoring Grafana**: Strategic monitoring for the entire ecosystem

This dual approach provides both **real-time operational insights** and **strategic ecosystem-wide
visibility**.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    OSM Notes Ecosystem                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  OSM-Notes-API (Operational Monitoring)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐         ┌──────────────┐      ┌──────────────┐ │
│  │   API    │─────────▶│  Prometheus  │─────▶│   Grafana    │ │
│  │ (Node.js)│ Metrics  │  (Scraping)  │      │  (Port 3001) │ │
│  └──────────┘          └──────────────┘      └──────────────┘ │
│                                                                 │
│  Purpose: Real-time API performance monitoring                  │
│  Focus:   Latency, throughput, rate limiting, errors           │
│  Scope:   API service only                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  OSM-Notes-Monitoring (Strategic Monitoring)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │Ingestion │  │Analytics │  │   WMS    │  │   API    │  ...  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│       │             │             │             │              │
│       └─────────────┴─────────────┴─────────────┴──────────────┘
│                                │                                 │
│                                ▼                                 │
│                       ┌──────────────┐                          │
│                       │  PostgreSQL  │                          │
│                       │   (Metrics)  │                          │
│                       └──────┬───────┘                          │
│                              │                                   │
│                              ▼                                   │
│                       ┌──────────────┐                          │
│                       │   Grafana    │                          │
│                       │  (Port 3000)  │                          │
│                       └──────────────┘                          │
│                                                                 │
│  Purpose: Ecosystem-wide health and performance monitoring      │
│  Focus:   Component health, alerts, trends, capacity planning   │
│  Scope:   All OSM Notes components                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why Two Grafana Deployments?

### Different Purposes

| Aspect               | OSM-Notes-API Grafana         | OSM-Notes-Monitoring Grafana          |
| -------------------- | ----------------------------- | ------------------------------------- |
| **Purpose**          | Operational monitoring        | Strategic monitoring                  |
| **Time Horizon**     | Real-time (seconds/minutes)   | Historical (hours/days/weeks)         |
| **Data Source**      | Prometheus (time-series)      | PostgreSQL (relational + time-series) |
| **Update Frequency** | Continuous (scraping)         | Periodic (monitoring cycles)          |
| **Scope**            | API service only              | Entire ecosystem                      |
| **Use Cases**        | Debugging, performance tuning | Capacity planning, trend analysis     |
| **Users**            | API developers, DevOps        | System administrators, managers       |

### Different Data Models

**OSM-Notes-API (Prometheus)**:

- High-frequency metrics (every few seconds)
- Time-series data optimized for real-time queries
- Ephemeral data (short retention)
- Focus on current performance

**OSM-Notes-Monitoring (PostgreSQL)**:

- Lower-frequency metrics (every monitoring cycle)
- Relational data with metadata and context
- Long-term retention (90+ days)
- Focus on trends and patterns

---

## OSM-Notes-API Grafana

### Purpose

Monitor the **API service** in real-time for operational purposes.

### Configuration

- **Location**: `OSM-Notes-API/docker/grafana/`
- **Port**: 3001
- **Data Source**: Prometheus (scraping API `/metrics` endpoint)
- **Deployment**: Docker Compose with `--profile monitoring`

### Dashboards

1. **API Overview** (`api-overview.json`)
   - Requests per second
   - Latency percentiles (P50, P95, P99)
   - Error rates by status code
   - Response time distribution

2. **Rate Limiting** (`rate-limiting.json`)
   - Rate limit violations per second
   - Top IPs exceeding limits
   - Top User-Agents exceeding limits
   - Rate limit effectiveness

3. **User-Agents** (`user-agents.json`)
   - Requests by HTTP method
   - Top routes by request rate
   - Status code distribution
   - User-Agent analysis

### Metrics Collected

- `http_request_duration_seconds` - Request latency (histogram)
- `http_requests_total` - Total HTTP requests (counter)
- `http_errors_total` - HTTP errors (counter)
- `rate_limit_exceeded_total` - Rate limit violations (counter)
- Node.js system metrics (CPU, memory, event loop)

### Use Cases

- **Debugging**: Identify performance bottlenecks in real-time
- **Capacity Planning**: Understand API load patterns
- **Incident Response**: Quick diagnosis of API issues
- **Development**: Monitor API changes during development

### Access

```bash
# Start monitoring services
cd OSM-Notes-API
docker-compose --profile monitoring up -d prometheus grafana

# Access Grafana
# URL: http://localhost:3001
# User: admin
# Password: admin (or GRAFANA_PASSWORD from .env)
```

---

## OSM-Notes-Monitoring Grafana

### Purpose

Monitor the **entire OSM Notes ecosystem** for strategic insights and health management.

### Configuration

- **Location**: `OSM-Notes-Monitoring/dashboards/grafana/`
- **Port**: 3000 (default Grafana port)
- **Data Source**: PostgreSQL (metrics table)
- **Deployment**: Standalone Grafana instance

### Dashboards

1. **Overview** (`overview.json`)
   - Component health status
   - Error rates across all components
   - Active alerts summary
   - System-wide metrics

2. **Ingestion** (`ingestion.json`)
   - Script execution status
   - Error rates
   - Database query performance
   - Data quality metrics

3. **Analytics** (`analytics.json`)
   - ETL job status
   - Data warehouse freshness
   - Query performance
   - Storage growth

4. **WMS** (`wms.json`)
   - Service availability
   - Response times
   - Cache hit rates
   - Error rates

5. **API/Security** (`api.json`)
   - Security events
   - Rate limiting statistics
   - DDoS protection status
   - Abuse detection alerts

6. **Infrastructure** (`infrastructure.json`)
   - Server resources (CPU, memory, disk)
   - Network connectivity
   - Database health
   - Service dependencies

### Metrics Collected

- Component health status
- Error rates and counts
- Performance metrics (response times, query times)
- Resource usage (CPU, memory, disk)
- Alert history and trends
- Security events

### Use Cases

- **Health Management**: Monitor all components from one place
- **Trend Analysis**: Understand long-term patterns
- **Capacity Planning**: Plan infrastructure growth
- **Alerting**: Receive alerts for all components
- **Reporting**: Generate reports for stakeholders

### Access

```bash
# Configure Grafana to connect to PostgreSQL
# Data source: PostgreSQL
# Database: osm_notes_monitoring
# Import dashboards from dashboards/grafana/

# Access Grafana
# URL: http://localhost:3000
# User: admin
# Password: (configured during setup)
```

---

## Data Flow

### OSM-Notes-API Flow

```
API Service
    │
    │ (exposes /metrics endpoint)
    ▼
Prometheus
    │
    │ (scrapes every 15s)
    ▼
Grafana (API)
    │
    └─▶ Real-time dashboards
```

### OSM-Notes-Monitoring Flow

```
All Components
    │
    │ (monitoring scripts collect metrics)
    ▼
PostgreSQL (metrics table)
    │
    │ (queries via SQL)
    ▼
Grafana (Monitoring)
    │
    └─▶ Strategic dashboards
```

---

## Integration Points

### Option 1: Independent Deployments (Current)

- **Pros**:
  - Clear separation of concerns
  - Different update frequencies
  - Independent scaling
- **Cons**:
  - Two Grafana instances to maintain
  - No unified view

### Option 2: Unified Grafana (Future)

- **Pros**:
  - Single Grafana instance
  - Unified view of all metrics
  - Easier management
- **Cons**:
  - More complex configuration
  - Different data sources (Prometheus + PostgreSQL)

**Recommendation**: Start with Option 1, consider Option 2 as the system matures.

---

## Configuration Guide

### Setting Up OSM-Notes-API Grafana

1. **Configure Prometheus**:

   ```yaml
   # docker/prometheus/prometheus.yml
   scrape_configs:
     - job_name: "api"
       scrape_interval: 15s
       static_configs:
         - targets: ["api:3000"]
   ```

2. **Configure Grafana**:

   ```yaml
   # docker/grafana/provisioning/datasources/prometheus.yml
   datasources:
     - name: Prometheus
       type: prometheus
       url: http://prometheus:9090
   ```

3. **Import Dashboards**:
   - Dashboards are auto-provisioned from `docker/grafana/provisioning/dashboards/`

### Setting Up OSM-Notes-Monitoring Grafana

1. **Install Grafana**:

   ```bash
   # Using Docker
   docker run -d \
     -p 3000:3000 \
     -v grafana_data:/var/lib/grafana \
     grafana/grafana:latest
   ```

2. **Configure PostgreSQL Data Source**:
   - Add PostgreSQL data source in Grafana UI
   - Host: `localhost:5432` (or your DB host)
   - Database: `osm_notes_monitoring`
   - User: `postgres` (or your DB user)

3. **Import Dashboards**:

   ```bash
   # Copy dashboards to Grafana provisioning directory
   cp dashboards/grafana/*.json /etc/grafana/provisioning/dashboards/
   ```

4. **Configure Dashboard Provisioning**:
   ```yaml
   # /etc/grafana/provisioning/dashboards/dashboard.yml
   apiVersion: 1
   providers:
     - name: "OSM Notes Monitoring"
       orgId: 1
       folder: ""
       type: file
       disableDeletion: false
       updateIntervalSeconds: 10
       allowUiUpdates: true
       options:
         path: /etc/grafana/provisioning/dashboards
   ```

---

## Best Practices

### 1. Port Configuration

- **OSM-Notes-API Grafana**: Use port 3001 to avoid conflicts
- **OSM-Notes-Monitoring Grafana**: Use port 3000 (standard)

### 2. Authentication

- Use strong passwords for both instances
- Configure LDAP/OAuth if available
- Use API keys for programmatic access

### 3. Data Retention

- **Prometheus (API)**: 7-15 days (high-frequency data)
- **PostgreSQL (Monitoring)**: 90+ days (strategic data)

### 4. Alerting

- **API Grafana**: Use Prometheus Alertmanager for real-time alerts
- **Monitoring Grafana**: Use built-in alerting system (email/Slack)

### 5. Backup

- Backup Grafana dashboards regularly
- Export dashboards as JSON files
- Version control dashboard definitions

---

## Troubleshooting

### API Grafana Shows No Data

1. Verify Prometheus is running: `curl http://localhost:9090/api/v1/targets`
2. Check API metrics endpoint: `curl http://localhost:3000/metrics`
3. Verify Grafana data source configuration
4. Check Prometheus scrape configuration

### Monitoring Grafana Shows No Data

1. Verify PostgreSQL connection in Grafana data source
2. Check metrics table has data: `SELECT COUNT(*) FROM metrics;`
3. Verify monitoring scripts are running
4. Check dashboard SQL queries are correct

### Port Conflicts

- API Grafana uses port 3001
- Monitoring Grafana uses port 3000
- If conflicts occur, change ports in docker-compose.yml or Grafana config

---

## Future Enhancements

### Potential Improvements

1. **Unified Grafana Instance**: Single Grafana with both Prometheus and PostgreSQL datasources
2. **Cross-Dashboard Links**: Link from Monitoring dashboards to API dashboards
3. **Shared Alerting**: Unified alerting system across both deployments
4. **Federated Queries**: Query Prometheus from Monitoring Grafana
5. **Dashboard Templates**: Shared dashboard templates between projects

### Migration Path

If consolidating to a single Grafana instance:

1. Install Grafana with both datasources
2. Import all dashboards
3. Configure unified authentication
4. Set up cross-datasource queries
5. Deprecate separate instances

---

## References

### OSM-Notes-API

- [Monitoring Documentation](../OSM-Notes-API/docs/Monitoring.md)
- [Docker Configuration](../OSM-Notes-API/docker/README.md)
- [Grafana Dashboards](../OSM-Notes-API/docker/grafana/provisioning/dashboards/)

### OSM-Notes-Monitoring

- [Dashboard Guide](./Dashboard_Guide.md)
- [Grafana Setup Guide](./Grafana_Setup_Guide.md)
- [Dashboard Scripts](../bin/dashboard/)

---

## Summary

Both Grafana deployments serve **complementary purposes**:

- **OSM-Notes-API Grafana**: Operational, real-time monitoring for API developers
- **OSM-Notes-Monitoring Grafana**: Strategic, ecosystem-wide monitoring for system administrators

This dual approach provides:

- ✅ Real-time operational insights (API)
- ✅ Strategic ecosystem visibility (Monitoring)
- ✅ Appropriate data retention for each use case
- ✅ Optimized data models for each purpose
- ✅ Clear separation of concerns

**Recommendation**: Maintain both deployments as they serve different needs and user bases.
