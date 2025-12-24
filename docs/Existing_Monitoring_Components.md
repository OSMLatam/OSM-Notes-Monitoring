# Existing Monitoring Components in OSM-Notes-Ingestion

> **Purpose:** Document existing monitoring components in OSM-Notes-Ingestion that OSM-Notes-Monitoring should integrate with or reference  
> **Author:** Andres Gomez (AngocA)  
> **Version:** 2025-01-23

## Overview

OSM-Notes-Ingestion already contains several monitoring components that are specific to data ingestion verification. OSM-Notes-Monitoring should be aware of these components and integrate with them where appropriate.

## Monitoring Scripts in OSM-Notes-Ingestion

### Location: `bin/monitor/`

#### 1. `notesCheckVerifier.sh`

**Purpose:** Validates note data integrity by comparing Planet file data with API calls.

**What it does:**
- Downloads the latest Planet notes file
- Creates check tables (`notes_check`, `note_comments_check`, `note_comment_texts_check`)
- Compares Planet data with API-processed data
- Generates reports of differences
- Sends email alerts if discrepancies are found
- Can insert missing data from check tables into main tables

**Key Features:**
- Data integrity verification
- Discrepancy detection
- Email alerting (uses `mutt`)
- Automatic data correction (optional)

**Usage:**
```bash
cd /path/to/OSM-Notes-Ingestion
./bin/monitor/notesCheckVerifier.sh
```

**Configuration:**
- `EMAILS`: Comma-separated list of email recipients
- `LOG_LEVEL`: Log level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
- `CLEAN`: Whether to clean temporary files (default: true)

**When to run:**
- Daily automated check (recommended: 4 AM UTC)
- After Planet processing
- When data quality issues are suspected

**Integration with OSM-Notes-Monitoring:**
- OSM-Notes-Monitoring should call this script as part of ingestion monitoring
- OSM-Notes-Monitoring should parse its output and logs
- OSM-Notes-Monitoring should track its execution status

#### 2. `processCheckPlanetNotes.sh`

**Purpose:** Verifies Planet notes processing by comparing loaded notes with a fresh Planet download.

**What it does:**
- Downloads the latest Planet notes file
- Creates check tables
- Converts notes to CSV using AWK scripts
- Imports into check tables
- Allows comparison between main tables and check tables

**Key Features:**
- Planet data verification
- Table comparison
- Data validation

**Usage:**
```bash
cd /path/to/OSM-Notes-Ingestion
./bin/monitor/processCheckPlanetNotes.sh
```

**When to run:**
- Around 6h UTC (when OSM Planet file is published)
- After Planet processing to verify correctness
- When investigating data discrepancies

**Integration with OSM-Notes-Monitoring:**
- OSM-Notes-Monitoring should schedule this script
- OSM-Notes-Monitoring should monitor its execution
- OSM-Notes-Monitoring should track Planet file freshness

#### 3. `analyzeDatabasePerformance.sh`

**Purpose:** Analyzes database performance by running SQL analysis scripts.

**What it does:**
- Executes all SQL analysis scripts from `sql/analysis/`
- Generates performance reports
- Checks if performance thresholds are met
- Provides colored output (PASS/FAIL/WARNING)

**Key Features:**
- Performance analysis
- Query optimization validation
- Index usage analysis
- Scalability checks

**Usage:**
```bash
cd /path/to/OSM-Notes-Ingestion
./bin/monitor/analyzeDatabasePerformance.sh [--db DATABASE] [--output DIR] [--verbose]
```

**Configuration:**
- `DBNAME`: Database name (from `etc/properties.sh`)
- `LOG_LEVEL`: Log level

**When to run:**
- Weekly (recommended: Sunday 4 AM)
- After database schema changes
- When performance issues are suspected
- Before scaling operations

**Integration with OSM-Notes-Monitoring:**
- OSM-Notes-Monitoring should call this script for infrastructure monitoring
- OSM-Notes-Monitoring should track performance trends
- OSM-Notes-Monitoring should alert on performance degradation

## SQL Monitoring Queries

### Location: `sql/monitor/`

#### Notes Check Verifier Queries

- **`notesCheckVerifier_51_insertMissingNotes.sql`**: Inserts missing notes from check tables
- **`notesCheckVerifier_52_insertMissingComments.sql`**: Inserts missing comments
- **`notesCheckVerifier_53_insertMissingTextComments.sql`**: Inserts missing text comments
- **`notesCheckVerifier_54_markMissingNotesAsHidden.sql`**: Marks notes as hidden if not in Planet
- **`notesCheckVerifier-report.sql`**: Generates verification reports

#### Process Check Planet Notes Queries

- **`processCheckPlanetNotes_11_dropCheckTables.sql`**: Drops existing check tables
- **`processCheckPlanetNotes_21_createCheckTables.sql`**: Creates check tables
- **`processCheckPlanetNotes_31_loadCheckNotes.sql`**: Loads notes into check tables
- **`processCheckPlanetNotes_41_analyzeAndVacuum.sql`**: Analyzes and vacuums check tables

## SQL Analysis Queries

### Location: `sql/analysis/`

These queries are used by `analyzeDatabasePerformance.sh`:

- Performance analysis scripts
- Query optimization validation
- Index usage analysis
- Scalability checks

See `sql/analysis/README.md` for details.

## Alerting System

### Location: Integrated in processing scripts

OSM-Notes-Ingestion has an integrated alerting system:

- **Email alerts** for script failures
- **Failed execution markers** to prevent repeated failures
- **Alert functions** in `lib/osm-common/alertFunctions.sh`

See `docs/Alerting_System.md` in OSM-Notes-Ingestion for details.

## Integration Strategy

### Phase 1: Awareness

OSM-Notes-Monitoring should:
1. Document these existing components
2. Reference them in monitoring documentation
3. Understand their purpose and usage

### Phase 2: Integration

OSM-Notes-Monitoring should:
1. Call these scripts as part of ingestion monitoring
2. Parse their output and logs
3. Track their execution status
4. Aggregate their results

### Phase 3: Enhancement

OSM-Notes-Monitoring could:
1. Provide unified dashboards showing results from these scripts
2. Add additional monitoring layers on top
3. Correlate results with other repository monitoring
4. Provide cross-repository insights

## Monitoring Scripts Mapping

| OSM-Notes-Ingestion Script | OSM-Notes-Monitoring Integration |
|---------------------------|----------------------------------|
| `notesCheckVerifier.sh` | Ingestion data quality monitoring |
| `processCheckPlanetNotes.sh` | Ingestion Planet verification |
| `analyzeDatabasePerformance.sh` | Infrastructure performance monitoring |

## Configuration Dependencies

OSM-Notes-Monitoring needs access to:

1. **OSM-Notes-Ingestion repository path**
   - To execute monitoring scripts
   - To read configuration files

2. **Database access**
   - Same database as OSM-Notes-Ingestion
   - Read-only access for monitoring queries

3. **Email configuration**
   - Same `ADMIN_EMAIL` or `EMAILS` configuration
   - Or redirect alerts through OSM-Notes-Monitoring

## Example Integration

```bash
# OSM-Notes-Monitoring script calling Ingestion monitoring
#!/bin/bash
# bin/monitor/monitorIngestion.sh

INGESTION_REPO="/path/to/OSM-Notes-Ingestion"

# Run data quality check
"${INGESTION_REPO}/bin/monitor/notesCheckVerifier.sh"

# Check execution status
if [[ $? -eq 0 ]]; then
    echo "Data quality check passed"
else
    echo "Data quality check failed"
    # Send alert through OSM-Notes-Monitoring alerting system
fi

# Run performance analysis
"${INGESTION_REPO}/bin/monitor/analyzeDatabasePerformance.sh" --db "${DBNAME}"

# Parse and store results
# ...
```

## References

- [OSM-Notes-Ingestion README](https://github.com/OSMLatam/OSM-Notes-Ingestion/blob/main/README.md)
- [OSM-Notes-Ingestion Documentation](https://github.com/OSMLatam/OSM-Notes-Ingestion/blob/main/docs/Documentation.md)
- [OSM-Notes-Ingestion Alerting System](https://github.com/OSMLatam/OSM-Notes-Ingestion/blob/main/docs/Alerting_System.md)
- [OSM-Notes-Ingestion bin/README](https://github.com/OSMLatam/OSM-Notes-Ingestion/blob/main/bin/README.md)

---

**Note:** These components remain in OSM-Notes-Ingestion as they are specific to ingestion data quality verification. OSM-Notes-Monitoring provides centralized monitoring that integrates with and enhances these local monitoring capabilities.

