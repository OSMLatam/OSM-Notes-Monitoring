---
title: "Guía de Setup Inicial - OSM-Notes-Monitoring"
description: "1. Ve a https://github.com/OSM-Notes"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "monitoring"
  - "installation"
  - "guide"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Monitoring"
status: "active"
---


# Guía de Setup Inicial - OSM-Notes-Monitoring

> **Propósito:** Guía paso a paso para crear y configurar el repositorio OSM-Notes-Monitoring  
> **Autor:** Andres Gomez (AngocA)  
> **Versión:** 2025-12-24

## Paso 1: Crear el Repositorio en GitHub

1. Ve a https://github.com/OSM-Notes
2. Click en "New repository"
3. Configuración:
   - **Name:** `OSM-Notes-Monitoring`
   - **Description:** `Centralized Monitoring, Alerting, and API Security for OpenStreetMap Notes`
   - **Visibility:** Public (o Private según prefieras)
   - **Initialize:** NO marcar ninguna opción (crearemos los archivos manualmente)
4. Click en "Create repository"

## Paso 2: Clonar y Preparar el Repositorio Local

```bash
# Clonar el repositorio vacío
git clone https://github.com/OSM-Notes/OSM-Notes-Monitoring.git
cd OSM-Notes-Monitoring
```

## Paso 3: Copiar Archivos de Documentación

Desde el repositorio OSM-Notes-Ingestion, copia los archivos de documentación:

```bash
# Desde OSM-Notes-Ingestion/docs/
cp Monitoring_Architecture_Proposal.md ../OSM-Notes-Monitoring/docs/
cp API_Security_Design.md ../OSM-Notes-Monitoring/docs/
cp Monitoring_Resumen_Ejecutivo.md ../OSM-Notes-Monitoring/docs/
```

## Paso 4: Crear Estructura Básica

```bash
# Crear estructura de directorios
mkdir -p bin/{monitor,security,alerts,dashboard,lib}
mkdir -p sql/{ingestion,analytics,wms,api,data,infrastructure}
mkdir -p config/dashboards/{grafana,custom}
mkdir -p dashboards/{grafana,html}
mkdir -p metrics/{ingestion,analytics,wms,api,infrastructure}
mkdir -p logs
mkdir -p etc
mkdir -p tests/{unit,integration,mock_commands}
mkdir -p docs
```

## Paso 5: Crear Archivos Iniciales

### README.md

Copia el contenido de `Monitoring_README_Template.md` y guárdalo como `README.md`:

```bash
# Desde OSM-Notes-Ingestion/docs/
cp Monitoring_README_Template.md ../OSM-Notes-Monitoring/README.md
```

### CHANGELOG.md

Copia el contenido de `Monitoring_CHANGELOG_Template.md`:

```bash
cp Monitoring_CHANGELOG_Template.md ../OSM-Notes-Monitoring/CHANGELOG.md
```

### .gitignore

Copia el contenido de `Monitoring_gitignore_Template.md`:

```bash
cp Monitoring_gitignore_Template.md ../OSM-Notes-Monitoring/.gitignore
```

### LICENSE

Copia el LICENSE de OSM-Notes-Ingestion:

```bash
cp ../OSM-Notes-Ingestion/LICENSE ../OSM-Notes-Monitoring/
```

## Paso 6: Crear Archivos de Configuración Iniciales

### etc/properties.sh.example

```bash
cat > etc/properties.sh.example << 'EOF'
# Properties for OSM-Notes-Monitoring
# Copy this file to properties.sh and configure

# Database
# Monitoring Database (this project's own database)
# Development: osm_notes_monitoring
# Production: notes_monitoring
DBNAME="osm_notes_monitoring"

# Monitored Databases (databases from other projects)
# Ingestion database (OSM-Notes-Ingestion)
INGESTION_DBNAME="${INGESTION_DBNAME:-notes}"
# Analytics database (OSM-Notes-Analytics)
ANALYTICS_DBNAME="${ANALYTICS_DBNAME:-notes_dwh}"
DBHOST="localhost"
DBPORT="5432"
DBUSER="postgres"

# Alerting
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"
SLACK_WEBHOOK_URL=""  # Optional

# Monitoring Intervals (in seconds)
INGESTION_CHECK_INTERVAL=300      # 5 minutes
ANALYTICS_CHECK_INTERVAL=900       # 15 minutes
WMS_CHECK_INTERVAL=300             # 5 minutes
API_CHECK_INTERVAL=60              # 1 minute
DATA_CHECK_INTERVAL=3600           # 1 hour
INFRASTRUCTURE_CHECK_INTERVAL=300  # 5 minutes

# Logging
LOG_LEVEL="INFO"
LOG_DIR="/var/log/osm-notes-monitoring"
TMP_DIR="/var/tmp/osm-notes-monitoring"
LOCK_DIR="/var/run/osm-notes-monitoring"

# Repository Paths (adjust to your setup)
INGESTION_REPO_PATH="/path/to/OSM-Notes-Ingestion"
ANALYTICS_REPO_PATH="/path/to/OSM-Notes-Analytics"
WMS_REPO_PATH="/path/to/OSM-Notes-WMS"
DATA_REPO_PATH="/path/to/OSM-Notes-Data"
EOF
```

### config/security.conf.example

```bash
cat > config/security.conf.example << 'EOF'
# Security Configuration for OSM-Notes-Monitoring

# Rate Limiting
RATE_LIMIT_PER_IP_PER_MINUTE=60
RATE_LIMIT_PER_IP_PER_HOUR=1000
RATE_LIMIT_PER_IP_PER_DAY=10000
RATE_LIMIT_BURST_SIZE=10

# Connection Limits
MAX_CONCURRENT_CONNECTIONS_PER_IP=10
MAX_TOTAL_CONNECTIONS=1000

# DDoS Protection
DDOS_THRESHOLD_REQUESTS_PER_SECOND=100
DDOS_THRESHOLD_CONCURRENT_CONNECTIONS=500
DDOS_AUTO_BLOCK_DURATION_MINUTES=15

# Abuse Detection
ABUSE_DETECTION_ENABLED=true
ABUSE_RAPID_REQUEST_THRESHOLD=10
ABUSE_ERROR_RATE_THRESHOLD=50
ABUSE_EXCESSIVE_REQUESTS_THRESHOLD=1000

# Blocking
TEMP_BLOCK_FIRST_VIOLATION_MINUTES=15
TEMP_BLOCK_SECOND_VIOLATION_HOURS=1
TEMP_BLOCK_THIRD_VIOLATION_HOURS=24
EOF
```

### config/alerts.conf.example

```bash
cat > config/alerts.conf.example << 'EOF'
# Alerting Configuration

# Email
ADMIN_EMAIL="admin@example.com"
SEND_ALERT_EMAIL="true"

# Slack (optional)
SLACK_ENABLED="false"
SLACK_WEBHOOK_URL=""
SLACK_CHANNEL="#monitoring"

# Alert Levels
CRITICAL_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
WARNING_ALERT_RECIPIENTS="${ADMIN_EMAIL}"
INFO_ALERT_RECIPIENTS=""  # Optional, leave empty to disable

# Alert Deduplication
ALERT_DEDUPLICATION_ENABLED="true"
ALERT_DEDUPLICATION_WINDOW_MINUTES=60
EOF
```

## Paso 7: Crear Archivos Placeholder

```bash
# Crear archivos .gitkeep para mantener directorios vacíos
touch bin/monitor/.gitkeep
touch bin/security/.gitkeep
touch bin/alerts/.gitkeep
touch bin/dashboard/.gitkeep
touch sql/ingestion/.gitkeep
touch sql/analytics/.gitkeep
touch sql/wms/.gitkeep
touch sql/api/.gitkeep
touch sql/data/.gitkeep
touch sql/infrastructure/.gitkeep
touch metrics/ingestion/.gitkeep
touch metrics/analytics/.gitkeep
touch metrics/wms/.gitkeep
touch metrics/api/.gitkeep
touch metrics/infrastructure/.gitkeep
touch dashboards/grafana/.gitkeep
touch dashboards/html/.gitkeep
touch tests/unit/.gitkeep
touch tests/integration/.gitkeep
touch tests/mock_commands/.gitkeep
```

## Paso 8: Mover Documentación

```bash
# Mover los archivos de documentación a docs/
mv Monitoring_Architecture_Proposal.md docs/
mv API_Security_Design.md docs/
mv Monitoring_Resumen_Ejecutivo.md docs/
```

## Paso 9: Commit Inicial

```bash
# Agregar todos los archivos
git add .

# Commit inicial
git commit -m "Initial repository setup

- Add architecture documentation
- Add API security design
- Add executive summary (Spanish)
- Add README, CHANGELOG, LICENSE
- Add basic directory structure
- Add configuration templates"

# Push al repositorio
git push -u origin main
```

## Paso 10: Verificar

1. Ve a https://github.com/OSM-Notes/OSM-Notes-Monitoring
2. Verifica que todos los archivos estén presentes
3. Verifica que el README se muestre correctamente
4. Verifica que la estructura de directorios sea correcta

## Próximos Pasos

Una vez creado el repositorio, puedes comenzar con:

1. **Fase 1**: Setup del repositorio (completado)
2. **Fase 2**: Migrar monitoreo de Ingestion
3. **Fase 3**: Crear monitoreo para otros repositorios
4. **Fase 4**: Implementar seguridad del API
5. **Fase 5**: Crear dashboards y alertas

## Notas

- Los archivos `.gitkeep` mantienen los directorios vacíos en git
- Los archivos `.example` son plantillas que deben copiarse y configurarse
- La estructura puede ajustarse según necesidades
- Los paths de repositorios deben configurarse según tu setup

---

**¡Listo!** El repositorio está creado y listo para comenzar el desarrollo.
