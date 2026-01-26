---
title: "Dashboard Customization Guide"
description: "This guide explains how to customize both HTML and Grafana dashboards to meet your specific monitoring needs."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "monitoring"
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Dashboard Customization Guide

> **Purpose:** Guide for customizing OSM Notes Monitoring dashboards  
> **Version:** 1.0.0  
> **Date:** 2025-12-27  
> **Status:** Active

## Overview

This guide explains how to customize both HTML and Grafana dashboards to meet your specific
monitoring needs.

---

## HTML Dashboard Customization

### Overview Dashboard

**File:** `dashboards/html/overview.html`

#### Adding a New Component

1. **Add component to JavaScript array:**

```javascript
const components = [
  "ingestion",
  "analytics",
  "wms",
  "api",
  "infrastructure",
  "data",
  "new_component",
];
```

2. **Update `updateStatusGrid` function:**

```javascript
// Add component to the components array
// The function will automatically generate cards for all components
```

3. **Ensure data file exists:**

```bash
# Generate data for new component
./bin/dashboard/generateMetrics.sh new_component json > dashboards/html/new_component_data.json
```

#### Customizing Metrics Display

**Modify `calculateAvgMetrics` function:**

```javascript
function calculateAvgMetrics(metrics) {
  const grouped = {};

  metrics.forEach((metric) => {
    if (!grouped[metric.metric_name]) {
      grouped[metric.metric_name] = [];
    }
    if (metric.metric_value !== null && metric.metric_value !== undefined) {
      grouped[metric.metric_name].push(parseFloat(metric.metric_value));
    }
  });

  // Add custom filtering or processing here
  const avgMetrics = {};
  Object.keys(grouped).forEach((key) => {
    const values = grouped[key];
    if (values.length > 0) {
      // Custom calculation
      avgMetrics[key] = values.reduce((a, b) => a + b, 0) / values.length;
    }
  });

  return avgMetrics;
}
```

#### Changing Refresh Interval

**Modify auto-refresh:**

```javascript
// Change from 5 minutes (300000ms) to 2 minutes (120000ms)
setInterval(loadData, 120000);
```

#### Customizing Colors

**Modify CSS:**

```css
.status-card.healthy {
  border-left-color: #27ae60; /* Change to your color */
}

.status-badge.healthy {
  background: #d4edda; /* Change to your color */
  color: #155724;
}
```

### Component Status Dashboard

**File:** `dashboards/html/component_status.html`

#### Adding Custom Metrics

**Modify `getKeyMetrics` function:**

```javascript
function getKeyMetrics(metricsByType) {
  const keyMetrics = [];

  Object.keys(metricsByType).forEach((metricName) => {
    // Add custom filtering
    if (metricName.startsWith("custom_")) {
      // Process custom metrics
    }

    // ... existing logic
  });

  return keyMetrics;
}
```

#### Changing Table Columns

**Modify table structure:**

```html
<thead>
  <tr>
    <th>Metric</th>
    <th>Current Value</th>
    <th>Average</th>
    <th>Min</th>
    <th>Max</th>
    <th>Last Update</th>
    <!-- Add custom column -->
    <th>Trend</th>
  </tr>
</thead>
```

### Health Check Dashboard

**File:** `dashboards/html/health_check.html`

#### Customizing Health Calculation

**Modify `calculateOverallHealth` function:**

```javascript
function calculateOverallHealth(healthData) {
  // Add custom logic
  let healthyCount = 0;
  let degradedCount = 0;
  let downCount = 0;
  let unknownCount = 0;

  components.forEach((component) => {
    const status = healthData[component]?.status || "unknown";
    // Add custom weighting or logic
    switch (status) {
      case "healthy":
        healthyCount++;
        break;
      // ... rest of logic
    }
  });

  // Custom overall health calculation
  return { status: "healthy", count: healthyCount, total: components.length };
}
```

---

## Grafana Dashboard Customization

### Adding a New Panel

1. **Export current dashboard:**

```bash
# Export dashboard JSON
cp dashboards/grafana/overview.json overview_backup.json
```

2. **Edit JSON file:**

```json
{
  "dashboard": {
    "panels": [
      {
        "id": 1,
        "title": "Existing Panel"
        // ... existing panel config
      },
      {
        "id": 2,
        "title": "New Custom Panel",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
        "targets": [
          {
            "expr": "SELECT timestamp, metric_value FROM metrics WHERE component = 'ingestion' AND metric_name = 'custom_metric' ORDER BY timestamp",
            "format": "time_series",
            "rawSql": true,
            "refId": "A"
          }
        ]
      }
    ]
  }
}
```

3. **Import updated dashboard:**
   - Upload JSON file in Grafana UI
   - Or use provisioning directory

### Customizing SQL Queries

**Example: Custom aggregation query:**

```sql
SELECT
    DATE_TRUNC('hour', timestamp) as time,
    AVG(metric_value::numeric) as avg_value,
    COUNT(*) as sample_count
FROM metrics
WHERE component = 'ingestion'
  AND metric_name = 'error_rate_percent'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY time
ORDER BY time;
```

### Adding Custom Variables

**Add template variables:**

```json
{
  "dashboard": {
    "templating": {
      "list": [
        {
          "name": "component",
          "type": "query",
          "query": "SELECT DISTINCT component FROM metrics",
          "current": {
            "value": "ingestion"
          }
        }
      ]
    }
  }
}
```

**Use in queries:**

```sql
SELECT * FROM metrics WHERE component = '$component'
```

### Customizing Time Ranges

**Modify default time range:**

```json
{
  "dashboard": {
    "time": {
      "from": "now-7d",
      "to": "now"
    },
    "timepicker": {
      "refresh_intervals": ["10s", "30s", "1m", "5m", "15m", "30m", "1h"]
    }
  }
}
```

### Adding Alerts

**Configure panel alerts:**

```json
{
  "alert": {
    "name": "High Error Rate",
    "message": "Error rate exceeds threshold",
    "conditions": [
      {
        "evaluator": {
          "params": [5],
          "type": "gt"
        },
        "operator": {
          "type": "and"
        },
        "query": {
          "params": ["A", "5m", "now"]
        },
        "reducer": {
          "type": "avg"
        },
        "type": "query"
      }
    ],
    "executionErrorState": "alerting",
    "for": "5m",
    "frequency": "10s"
  }
}
```

---

## Creating Custom Dashboards

### HTML Dashboard Template

**Create new HTML dashboard:**

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <title>Custom Dashboard</title>
    <style>
      /* Add your custom styles */
    </style>
  </head>
  <body>
    <div class="container">
      <h1>Custom Dashboard</h1>
      <div id="content"></div>
    </div>

    <script>
      // Load data
      async function loadData() {
        const response = await fetch("custom_data.json");
        const data = await response.json();
        // Process and display data
      }

      // Auto-refresh
      setInterval(loadData, 300000);
      loadData();
    </script>
  </body>
</html>
```

### Grafana Dashboard Template

**Create new Grafana dashboard:**

```json
{
  "dashboard": {
    "title": "Custom Dashboard",
    "tags": ["custom", "osm"],
    "timezone": "browser",
    "schemaVersion": 27,
    "version": 1,
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "title": "Custom Metric",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
        "targets": [
          {
            "expr": "SELECT timestamp, metric_value FROM metrics WHERE component = 'custom' ORDER BY timestamp",
            "format": "time_series",
            "rawSql": true,
            "refId": "A"
          }
        ]
      }
    ],
    "time": {
      "from": "now-24h",
      "to": "now"
    }
  }
}
```

---

## Advanced Customization

### Custom Metric Formatting

**HTML Dashboard:**

```javascript
function formatMetricValue(name, value) {
  // Custom formatting logic
  if (name.includes("custom_format")) {
    return formatCustom(value);
  }

  // Default formatting
  if (name.includes("percent")) {
    return `${value.toFixed(1)}%`;
  }
  return value.toFixed(2);
}
```

**Grafana Dashboard:**

```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "custom",
      "decimals": 2,
      "custom": {
        "format": "custom_format"
      }
    }
  }
}
```

### Custom Aggregations

**Add custom aggregation functions:**

```sql
-- Custom percentile calculation
SELECT
    metric_name,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY metric_value::numeric) as p95_value
FROM metrics
WHERE component = 'ingestion'
GROUP BY metric_name;
```

### Custom Visualizations

**Grafana panel types:**

- `graph` - Time series graphs
- `stat` - Single stat displays
- `table` - Tabular data
- `gauge` - Gauge displays
- `heatmap` - Heatmaps
- `bargauge` - Bar gauges
- `piechart` - Pie charts

**Example gauge panel:**

```json
{
  "type": "gauge",
  "fieldConfig": {
    "defaults": {
      "min": 0,
      "max": 100,
      "thresholds": {
        "steps": [
          { "value": 0, "color": "green" },
          { "value": 70, "color": "yellow" },
          { "value": 90, "color": "red" }
        ]
      }
    }
  }
}
```

---

## Best Practices

### 1. Version Control

- Keep dashboard JSON files in version control
- Use descriptive commit messages
- Tag dashboard versions

### 2. Testing

- Test dashboards with real data
- Verify queries perform well
- Check visualizations render correctly

### 3. Documentation

- Document custom metrics
- Explain custom queries
- Note any special configurations

### 4. Performance

- Optimize SQL queries
- Use appropriate time ranges
- Limit data points in panels

### 5. Consistency

- Use consistent color schemes
- Follow naming conventions
- Maintain similar panel layouts

---

## Examples

### Example 1: Custom Component Dashboard

**Create `dashboards/html/custom_component.html`:**

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Custom Component Dashboard</title>
    <style>
      /* Custom styles */
    </style>
  </head>
  <body>
    <div id="custom-metrics"></div>
    <script>
      // Load and display custom metrics
    </script>
  </body>
</html>
```

### Example 2: Custom Grafana Panel

**Add to dashboard JSON:**

```json
{
  "id": 10,
  "title": "Custom Aggregation",
  "type": "stat",
  "targets": [
    {
      "expr": "SELECT COUNT(DISTINCT metric_name) FROM metrics WHERE component = 'ingestion'",
      "format": "table",
      "rawSql": true
    }
  ]
}
```

### Example 3: Custom Alert Dashboard

**Create alert-focused dashboard:**

```json
{
  "dashboard": {
    "title": "Alert Dashboard",
    "panels": [
      {
        "title": "Active Alerts",
        "type": "table",
        "targets": [
          {
            "expr": "SELECT component, alert_level, message, created_at FROM alerts WHERE status = 'active' ORDER BY created_at DESC",
            "format": "table",
            "rawSql": true
          }
        ]
      }
    ]
  }
}
```

---

## Troubleshooting Customizations

### HTML Dashboard Not Updating

**Check:**

1. JavaScript console for errors
2. Data file paths are correct
3. CORS settings if accessing remotely
4. Browser cache (hard refresh)

### Grafana Panel Shows Error

**Check:**

1. SQL query syntax
2. Data source connection
3. Column names match query
4. Time range is valid

### Custom Metrics Not Appearing

**Check:**

1. Metrics are being collected
2. Metric names match exactly
3. Component names are correct
4. Time range includes data

---

## Reference

### Related Documentation

- [Dashboard Guide](./Dashboard_Guide.md) - Using dashboards
- [Grafana Setup Guide](./Grafana_Setup_Guide.md) - Grafana configuration

### Resources

- [Grafana Documentation](https://grafana.com/docs/)
- [Grafana Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/json-model/)
- [PostgreSQL SQL Reference](https://www.postgresql.org/docs/)

---

## Summary

Customize dashboards to meet your specific monitoring needs. Start with small changes, test
thoroughly, and maintain version control. Use consistent patterns and document customizations for
future reference.
