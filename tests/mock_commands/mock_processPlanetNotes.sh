#!/usr/bin/env bash
#
# Mock processPlanetNotes.sh
# Simulates the Planet notes processing script for end-to-end testing
#
# Version: 1.0.0
# Date: 2025-12-26
#

set -euo pipefail

# Mock configuration
MOCK_LOG_DIR="${MOCK_LOG_DIR:-/tmp/mock_ingestion_logs}"
MOCK_DATA_DIR="${MOCK_DATA_DIR:-/tmp/mock_ingestion_data}"
MOCK_SUCCESS_RATE="${MOCK_SUCCESS_RATE:-100}"
MOCK_ERROR_COUNT="${MOCK_ERROR_COUNT:-0}"
MOCK_WARNING_COUNT="${MOCK_WARNING_COUNT:-0}"

# Create directories if they don't exist
mkdir -p "${MOCK_LOG_DIR}"
mkdir -p "${MOCK_DATA_DIR}"

# Log file
LOG_FILE="${MOCK_LOG_DIR}/processPlanetNotes.log"

# Function to log messages
log_message() {
    local level="${1}"
    shift
    local message="${*}"
    echo "$(date -u +"%Y-%m-%d %H:%M:%S") ${level}: ${message}" >> "${LOG_FILE}"
}

# Simulate script execution
log_message "INFO" "Starting Planet notes processing"

# Simulate processing time
sleep "${MOCK_PROCESSING_TIME:-2}"

# Simulate errors if configured
if [[ "${MOCK_ERROR_COUNT}" -gt 0 ]]; then
    for ((i=1; i<=MOCK_ERROR_COUNT; i++)); do
        log_message "ERROR" "Mock error ${i}: Simulated processing error"
    done
fi

# Simulate warnings if configured
if [[ "${MOCK_WARNING_COUNT}" -gt 0 ]]; then
    for ((i=1; i<=MOCK_WARNING_COUNT; i++)); do
        log_message "WARNING" "Mock warning ${i}: Simulated processing warning"
    done
fi

# Simulate success or failure based on success rate
if [[ "${MOCK_SUCCESS_RATE}" -lt 100 ]]; then
    random_value=$((RANDOM % 100))
    if [[ "${random_value}" -ge "${MOCK_SUCCESS_RATE}" ]]; then
        log_message "ERROR" "Planet file download failed: Simulated failure"
        exit 1
    fi
fi

# Simulate data file creation
if [[ "${MOCK_CREATE_DATA_FILE:-true}" == "true" ]]; then
    echo '{"notes": [{"id": 1, "status": "open"}]}' > "${MOCK_DATA_DIR}/planet_notes_$(date +%Y%m%d_%H%M%S).json"
    log_message "INFO" "Created data file: planet_notes_$(date +%Y%m%d_%H%M%S).json"
fi

log_message "INFO" "Planet notes processing completed successfully"
exit 0


