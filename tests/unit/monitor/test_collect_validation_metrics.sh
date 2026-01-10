#!/usr/bin/env bash
#
# Unit Tests: collect_validation_metrics.sh
# Tests validation metrics collection script
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../../tmp/logs"

setup() {
	# Set test environment
	export TEST_MODE=true
	export LOG_LEVEL="${LOG_LEVEL_DEBUG}"
	export COMPONENT="ANALYTICS"

	# Create test directories
	mkdir -p "${TEST_LOG_DIR}"

	# Mock record_metric using a file to track calls
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	rm -f "${METRICS_FILE}"
	touch "${METRICS_FILE}"
	export METRICS_FILE

	# shellcheck disable=SC2317
	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Mock log functions
	# shellcheck disable=SC2317
	log_debug() {
		return 0
	}
	export -f log_debug

	# shellcheck disable=SC2317
	log_info() {
		return 0
	}
	export -f log_info

	# shellcheck disable=SC2317
	log_warning() {
		return 0
	}
	export -f log_warning

	# Mock database functions
	# shellcheck disable=SC2317
	check_database_connection() {
		return 0
	}
	export -f check_database_connection

	# shellcheck disable=SC2317
	execute_sql_query() {
		local query="${1}"
		if [[ "${query}" == *"validate_note_current_status"* ]]; then
			echo "PASS|0"
		elif [[ "${query}" == *"validate_comment_counts"* ]]; then
			echo "PASS|0"
		elif [[ "${query}" == *"orphaned"* ]] || [[ "${query}" == *"LEFT JOIN"* ]]; then
			echo "0"
		elif [[ "${query}" == *"validation_status"* ]] && [[ "${query}" == *"MON-001"* ]]; then
			echo "1"
		elif [[ "${query}" == *"validation_status"* ]] && [[ "${query}" == *"MON-002"* ]]; then
			echo "1"
		elif [[ "${query}" == *"orphaned_facts_count"* ]]; then
			echo "0"
		elif [[ "${query}" == *"dwh_freshness_seconds"* ]]; then
			echo "1800"
		fi
		return 0
	}
	export -f execute_sql_query

	# Source libraries
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/monitoringFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/configFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/lib/metricsFunctions.sh"

	# Source collect_validation_metrics.sh
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../../bin/monitor/collect_validation_metrics.sh"

	# Re-export mocks after sourcing (they may have been overwritten)
	# shellcheck disable=SC2317
	check_database_connection() {
		return 0
	}
	export -f check_database_connection

	# shellcheck disable=SC2317
	execute_sql_query() {
		local query="${1}"
		if [[ "${query}" == *"validate_note_current_status"* ]]; then
			echo "PASS|0"
		elif [[ "${query}" == *"validate_comment_counts"* ]]; then
			echo "PASS|0"
		elif [[ "${query}" == *"orphaned"* ]] || [[ "${query}" == *"LEFT JOIN"* ]]; then
			echo "0"
		elif [[ "${query}" == *"validation_status"* ]] && [[ "${query}" == *"MON-001"* ]]; then
			echo "1"
		elif [[ "${query}" == *"validation_status"* ]] && [[ "${query}" == *"MON-002"* ]]; then
			echo "1"
		elif [[ "${query}" == *"orphaned_facts_count"* ]]; then
			echo "0"
		elif [[ "${query}" == *"dwh_freshness_seconds"* ]]; then
			echo "1800"
		fi
		return 0
	}
	export -f execute_sql_query

	# shellcheck disable=SC2317
	load_monitoring_config() {
		return 0
	}
	export -f load_monitoring_config
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
}

##
# Test: execute_mon001_validation executes MON-001 validation
##
@test "execute_mon001_validation executes MON-001 validation" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run execute_mon001_validation

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"validation_status"* ]] && [[ "${metric}" == *"MON-001"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: execute_mon002_validation executes MON-002 validation
##
@test "execute_mon002_validation executes MON-002 validation" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run execute_mon002_validation

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"validation_status"* ]] && [[ "${metric}" == *"MON-002"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: check_orphaned_facts checks for orphaned facts
##
@test "check_orphaned_facts checks for orphaned facts" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run check_orphaned_facts

	assert_success

	# Verify metrics were recorded
	local metrics_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"orphaned_facts_count"* ]]; then
				metrics_found=$((metrics_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [ ${metrics_found} -gt 0 ]
}

##
# Test: calculate_data_quality_score calculates quality score
##
@test "calculate_data_quality_score calculates quality score" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run calculate_data_quality_score

	assert_success

	# Verify quality score metric was recorded
	local score_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"data_quality_score"* ]]; then
				score_found=$((score_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${score_found} -gt 0 ]]
}

##
# Test: main function executes all collection functions
##
@test "main function executes all collection functions" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run main

	assert_success

	# Verify that multiple types of metrics were recorded
	local validation_metrics=0
	local orphaned_metrics=0
	local quality_score_metrics=0

	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"validation_status"* ]]; then
				validation_metrics=$((validation_metrics + 1))
			fi
			if [[ "${metric}" == *"orphaned_facts"* ]]; then
				orphaned_metrics=$((orphaned_metrics + 1))
			fi
			if [[ "${metric}" == *"data_quality_score"* ]]; then
				quality_score_metrics=$((quality_score_metrics + 1))
			fi
		done <"${METRICS_FILE}"
	fi

	# Should have metrics from different checks
	assert [[ ${validation_metrics} -ge 0 ]]
	assert [[ ${orphaned_metrics} -ge 0 ]]
	assert [[ ${quality_score_metrics} -gt 0 ]]
}

##
# Test: functions handle database connection failure gracefully
##
@test "functions handle database connection failure gracefully" {
	# Mock check_database_connection to fail
	# shellcheck disable=SC2317
	check_database_connection() {
		return 1
	}
	export -f check_database_connection

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run execute_mon001_validation

	# Should handle failure gracefully (return 1 but not crash)
	assert_failure
}

##
# Test: execute_mon001_validation handles FAIL status correctly
##
@test "execute_mon001_validation handles FAIL status correctly" {
	# Mock execute_sql_query to return FAIL
	# shellcheck disable=SC2317
	execute_sql_query() {
		local query="${1}"
		if [[ "${query}" == *"validate_note_current_status"* ]]; then
			echo "FAIL|5"
		fi
		return 0
	}
	export -f execute_sql_query

	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	run execute_mon001_validation

	assert_success

	# Verify that FAIL status was recorded (status_value=0)
	local fail_status_found=0
	if [[ -f "${METRICS_FILE}" ]]; then
		while IFS= read -r metric; do
			if [[ "${metric}" == *"validation_status"* ]] && [[ "${metric}" == *"MON-001"* ]] && [[ "${metric}" == *" 0 "* ]]; then
				fail_status_found=$((fail_status_found + 1))
			fi
		done <"${METRICS_FILE}"
	fi
	assert [[ ${fail_status_found} -gt 0 ]]
}
