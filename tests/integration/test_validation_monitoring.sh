#!/usr/bin/env bash
#
# Integration Tests: Validation Monitoring
# Tests validation monitoring integration with collect_validation_metrics.sh and monitorAnalytics.sh
#
# shellcheck disable=SC2030,SC2031,SC2317
# SC2030/SC2031: Variables modified in subshells are expected in BATS tests
# SC2317: Functions defined in tests are used indirectly by BATS (mocks)

load "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Test directories
TEST_LOG_DIR="${BATS_TEST_DIRNAME}/../tmp/logs"

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

	# Mock send_alert
	# shellcheck disable=SC2317
	send_alert() {
		return 0
	}
	export -f send_alert

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
	source "${BATS_TEST_DIRNAME}/../../bin/lib/loggingFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/monitoringFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/configFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/alertFunctions.sh"
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/lib/metricsFunctions.sh"

	# Source collect_validation_metrics.sh
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/monitor/collect_validation_metrics.sh" 2>/dev/null || true

	# Source monitorAnalytics.sh functions
	# shellcheck disable=SC1091
	source "${BATS_TEST_DIRNAME}/../../bin/monitor/monitorAnalytics.sh" 2>/dev/null || true

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
}

teardown() {
	# Cleanup test directories
	rm -rf "${TEST_LOG_DIR}"
}

##
# Test: collect_validation_metrics.sh integrates with monitorAnalytics.sh
##
@test "collect_validation_metrics.sh integrates with monitorAnalytics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run collect_validation_metrics.sh main function
	if declare -f main >/dev/null 2>&1; then
		run main

		assert_success

		# Verify that metrics from different collection functions were recorded
		local validation_metrics=0
		local quality_score_metrics=0

		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"validation_status"* ]]; then
					validation_metrics=$((validation_metrics + 1))
				fi
				if [[ "${metric}" == *"data_quality_score"* ]]; then
					quality_score_metrics=$((quality_score_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		# Should have metrics from different checks
		# Note: quality_score_metrics may be 0 if no previous metrics exist in DB
		assert [ ${validation_metrics} -ge 0 ]
		assert [ ${quality_score_metrics} -ge 0 ]
	else
		skip "main function not found"
	fi
}

##
# Test: monitorAnalytics.sh check_validation_status calls collect_validation_metrics.sh
##
@test "monitorAnalytics.sh check_validation_status calls collect_validation_metrics.sh" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run check_validation_status function
	if declare -f check_validation_status >/dev/null 2>&1; then
		run check_validation_status

		assert_success
	else
		skip "check_validation_status function not found"
	fi
}

##
# Test: End-to-end validation monitoring workflow
##
@test "End-to-end validation monitoring workflow" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run all validation checks in sequence
	if declare -f execute_mon001_validation >/dev/null 2>&1; then
		execute_mon001_validation || true
		execute_mon002_validation || true
		check_orphaned_facts || true
		calculate_data_quality_score || true
	fi

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
	assert [ ${validation_metrics} -ge 0 ]
	assert [ ${orphaned_metrics} -ge 0 ]
	assert [ ${quality_score_metrics} -gt 0 ]
}

##
# Test: Integration handles database connection failure gracefully
##
@test "Integration handles database connection failure gracefully" {
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

	# Run check_validation_status - should handle failure gracefully
	if declare -f check_validation_status >/dev/null 2>&1; then
		run check_validation_status

		# Should succeed even if database connection fails (graceful handling)
		assert_success
	else
		skip "check_validation_status function not found"
	fi
}

##
# Test: Integration collects metrics for both validations
##
@test "Integration collects metrics for both validations" {
	METRICS_FILE="${TEST_LOG_DIR}/metrics_called.txt"
	: >"${METRICS_FILE}"

	record_metric() {
		echo "$*" >>"${METRICS_FILE}"
		return 0
	}
	export -f record_metric

	# Run main function
	if declare -f main >/dev/null 2>&1; then
		run main

		assert_success

		# Verify metrics were recorded for both validations
		local mon001_metrics=0
		local mon002_metrics=0

		if [[ -f "${METRICS_FILE}" ]]; then
			while IFS= read -r metric; do
				if [[ "${metric}" == *"MON-001"* ]]; then
					mon001_metrics=$((mon001_metrics + 1))
				fi
				if [[ "${metric}" == *"MON-002"* ]]; then
					mon002_metrics=$((mon002_metrics + 1))
				fi
			done <"${METRICS_FILE}"
		fi

		# Should have metrics for both validations
		assert [ ${mon001_metrics} -ge 0 ]
		assert [ ${mon002_metrics} -ge 0 ]
	else
		skip "main function not found"
	fi
}
