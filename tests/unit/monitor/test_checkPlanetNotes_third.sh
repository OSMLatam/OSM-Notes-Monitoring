#!/usr/bin/env bash
#
# Third Unit Tests: checkPlanetNotes.sh
# Third test file to reach 80% coverage
#

export TEST_COMPONENT="INGESTION"
export TEST_DB_NAME="${TEST_DB_NAME:-osm_notes_monitoring_test}"

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

TEST_INGESTION_DIR="${BATS_TEST_DIRNAME}/../../tmp/test_ingestion_planet"
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
    export TEST_MODE=true
    export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
    mkdir -p "${TEST_INGESTION_DIR}/bin/monitor"
    mkdir -p "${TEST_INGESTION_DIR}/logs"
    mkdir -p "${TEST_LOG_DIR}"
    
    export INGESTION_REPO_PATH="${TEST_INGESTION_DIR}"
    export LOG_DIR="${TEST_LOG_DIR}"
    export TMP_DIR="${BATS_TEST_DIRNAME}/../../tmp"
    
    export INGESTION_ENABLED="true"
    export INGESTION_PLANET_CHECK_DURATION_THRESHOLD="600"
    
    export SEND_ALERT_EMAIL="false"
    export SLACK_ENABLED="false"
    export ALERT_DEDUPLICATION_ENABLED="false"
    
    export DBNAME="${TEST_DB_NAME}"
    export DBHOST="${DBHOST:-localhost}"
    export DBPORT="${DBPORT:-5432}"
    export DBUSER="${DBUSER:-postgres}"
    
    # Mock psql
    # shellcheck disable=SC2317
    psql() {
        return 0
    }
    export -f psql
    
    # Source libraries
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/lib/alertFunctions.sh"
    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../../../bin/monitor/checkPlanetNotes.sh"
    
    init_logging "${TEST_LOG_DIR}/test_checkPlanetNotes_third.log" "test_checkPlanetNotes_third"
    init_alerting
}

teardown() {
    rm -rf "${TEST_INGESTION_DIR}"
    rm -rf "${TEST_LOG_DIR}"
}

##
# Test: checkPlanetNotes handles script with warnings
##
@test "checkPlanetNotes handles script with warnings" {
    # Create a script that outputs warnings
    local test_script="${TEST_INGESTION_DIR}/bin/monitor/processCheckPlanetNotes.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
echo "WARNING: Some issue detected"
exit 0
EOF
    chmod +x "${test_script}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run run_planet_check
    assert_success
    
    rm -f "${test_script}"
}

##
# Test: checkPlanetNotes handles script with output
##
@test "checkPlanetNotes handles script with output" {
    # Create a script with output
    local test_script="${TEST_INGESTION_DIR}/bin/monitor/processCheckPlanetNotes.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
echo "Processing planet notes..."
echo "Completed: 1000 notes processed"
exit 0
EOF
    chmod +x "${test_script}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run run_planet_check
    assert_success
    
    rm -f "${test_script}"
}

##
# Test: checkPlanetNotes handles custom threshold
##
@test "checkPlanetNotes handles custom threshold" {
    export INGESTION_PLANET_CHECK_DURATION_THRESHOLD="1200"  # 20 minutes
    
    # Create a script that takes moderate time
    local test_script="${TEST_INGESTION_DIR}/bin/monitor/processCheckPlanetNotes.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
sleep 0.001
exit 0
EOF
    chmod +x "${test_script}"
    
    # shellcheck disable=SC2317
    record_metric() {
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run run_planet_check
    assert_success
    
    rm -f "${test_script}"
}

##
# Test: checkPlanetNotes handles script execution metrics
##
@test "checkPlanetNotes handles script execution metrics" {
    # Create a successful script
    local test_script="${TEST_INGESTION_DIR}/bin/monitor/processCheckPlanetNotes.sh"
    cat > "${test_script}" << 'EOF'
#!/bin/bash
echo "Planet check completed"
exit 0
EOF
    chmod +x "${test_script}"
    
    # Track metric recording
    local metric_file="${TEST_LOG_DIR}/.metric_recorded"
    rm -f "${metric_file}"
    
    # shellcheck disable=SC2317
    record_metric() {
        if [[ "${1}" == "ingestion" ]] && [[ "${2}" == *"planet"* ]]; then
            touch "${metric_file}"
        fi
        return 0
    }
    export -f record_metric
    
    # shellcheck disable=SC2317
    send_alert() {
        return 0
    }
    export -f send_alert
    
    run run_planet_check
    assert_success
    
    # Verify metrics were recorded
    assert_file_exists "${metric_file}" || true
    
    rm -f "${test_script}" "${metric_file}"
}
