#!/usr/bin/env bash
#
# ETL Log Parser Library
# Parses ETL logs and extracts detailed structured metrics
#
# Version: 1.0.0
# Date: 2026-01-09
#

set -euo pipefail

# Component name (allow override in test mode)
if [[ -z "${COMPONENT:-}" ]]; then
	COMPONENT="ANALYTICS"
fi
# Only make readonly if not in test mode
if [[ "${TEST_MODE:-false}" != "true" ]]; then
	readonly COMPONENT
fi

##
# Parse ETL execution time from logs
# Usage: parse_etl_execution_time <log_file>
##
parse_etl_execution_time() {
	local log_file="${1}"
	local time_window_hours="${2:-24}"

	if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
		log_debug "${COMPONENT}: ETL log file not accessible: ${log_file}"
		return 1
	fi

	# Calculate time threshold
	local threshold_timestamp
	threshold_timestamp=$(date -d "${time_window_hours} hours ago" +%s 2>/dev/null || date -v-"${time_window_hours}"H +%s 2>/dev/null || echo "0")

	# Get recent execution completions
	local execution_completions
	execution_completions=$(grep -E "ETL.*completed successfully|ETL.*finished successfully" "${log_file}" 2>/dev/null | tail -100 || echo "")

	if [[ -z "${execution_completions}" ]]; then
		log_debug "${COMPONENT}: No ETL execution completion messages found"
		return 0
	fi

	local last_execution_time=0
	local last_execution_number=0
	local total_executions=0
	local total_duration=0
	local successful_executions=0
	local failed_executions=0
	local min_duration=999999
	local max_duration=0
	local execution_timestamps=()

	while IFS= read -r line; do
		# Extract timestamp
		local log_timestamp=0
		if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
			log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
		fi

		# Skip if too old
		if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
			continue
		fi

		# Extract execution time and number
		if [[ "${line}" =~ completed[[:space:]]+successfully[[:space:]]+in[[:space:]]+([0-9]+)[[:space:]]+seconds ]] ||
			[[ "${line}" =~ finished[[:space:]]+successfully[[:space:]]+in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
			local exec_time="${BASH_REMATCH[1]}"
			local exec_num=0

			# Try to extract execution number
			if [[ "${line}" =~ Execution[[:space:]]+([0-9]+) ]] || [[ "${line}" =~ execution[[:space:]]+([0-9]+) ]]; then
				exec_num="${BASH_REMATCH[1]}"
			fi

			last_execution_time=${exec_time}
			last_execution_number=${exec_num}
			total_executions=$((total_executions + 1))
			total_duration=$((total_duration + exec_time))
			successful_executions=$((successful_executions + 1))
			execution_timestamps+=("${log_timestamp}")

			if [[ ${exec_time} -lt ${min_duration} ]]; then
				min_duration=${exec_time}
			fi
			if [[ ${exec_time} -gt ${max_duration} ]]; then
				max_duration=${exec_time}
			fi
		fi
	done <<<"${execution_completions}"

	# Check for failed executions
	local execution_failures
	execution_failures=$(grep -E "ETL.*failed|ETL.*error|ETL.*FATAL" "${log_file}" 2>/dev/null | tail -100 || echo "")
	if [[ -n "${execution_failures}" ]]; then
		while IFS= read -r line; do
			local log_timestamp=0
			if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
				log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
			fi
			if [[ ${log_timestamp} -ge ${threshold_timestamp} ]] || [[ ${log_timestamp} -eq 0 ]]; then
				failed_executions=$((failed_executions + 1))
			fi
		done <<<"${execution_failures}"
	fi

	# Calculate metrics
	local avg_duration=0
	if [[ ${total_executions} -gt 0 ]]; then
		avg_duration=$((total_duration / total_executions))
	fi

	local total_attempts=$((successful_executions + failed_executions))
	local success_rate=100
	if [[ ${total_attempts} -gt 0 ]]; then
		success_rate=$((successful_executions * 100 / total_attempts))
	fi

	# Calculate executions per hour
	local executions_per_hour=0
	if [[ ${#execution_timestamps[@]} -gt 0 ]]; then
		local first_timestamp="${execution_timestamps[0]}"
		local last_timestamp="${execution_timestamps[-1]}"
		if [[ ${last_timestamp} -gt ${first_timestamp} ]]; then
			local time_span_hours
			time_span_hours=$(((last_timestamp - first_timestamp) / 3600 + 1))
			if [[ ${time_span_hours} -gt 0 ]]; then
				executions_per_hour=$((total_executions / time_span_hours))
			fi
		fi
	fi

	# Record metrics
	record_metric "${COMPONENT}" "etl_execution_duration_seconds" "${last_execution_time}" "component=analytics"
	record_metric "${COMPONENT}" "etl_execution_number" "${last_execution_number}" "component=analytics"
	record_metric "${COMPONENT}" "etl_executions_total" "${total_executions}" "component=analytics"
	record_metric "${COMPONENT}" "etl_execution_avg_duration_seconds" "${avg_duration}" "component=analytics"
	record_metric "${COMPONENT}" "etl_execution_min_duration_seconds" "${min_duration}" "component=analytics"
	record_metric "${COMPONENT}" "etl_execution_max_duration_seconds" "${max_duration}" "component=analytics"
	record_metric "${COMPONENT}" "etl_execution_success_rate" "${success_rate}" "component=analytics"
	record_metric "${COMPONENT}" "etl_executions_per_hour" "${executions_per_hour}" "component=analytics"
	record_metric "${COMPONENT}" "etl_executions_successful_count" "${successful_executions}" "component=analytics"
	record_metric "${COMPONENT}" "etl_executions_failed_count" "${failed_executions}" "component=analytics"

	log_info "${COMPONENT}: ETL execution time - Duration: ${last_execution_time}s, Total: ${total_executions}, Success rate: ${success_rate}%, Executions/hour: ${executions_per_hour}"

	return 0
}

##
# Parse ETL facts processed from logs
# Usage: parse_etl_facts_processed <log_file>
##
parse_etl_facts_processed() {
	local log_file="${1}"
	local time_window_hours="${2:-24}"

	if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
		log_debug "${COMPONENT}: ETL log file not accessible: ${log_file}"
		return 1
	fi

	# Calculate time threshold
	local threshold_timestamp
	threshold_timestamp=$(date -d "${time_window_hours} hours ago" +%s 2>/dev/null || date -v-"${time_window_hours}"H +%s 2>/dev/null || echo "0")

	# Get last execution context
	local last_execution_line
	last_execution_line=$(grep -E "ETL.*completed successfully|ETL.*finished successfully" "${log_file}" 2>/dev/null | tail -1 || echo "")

	if [[ -z "${last_execution_line}" ]]; then
		log_debug "${COMPONENT}: No ETL execution found for facts processing"
		return 0
	fi

	# Get context around last execution (last 200 lines before completion)
	local execution_context
	execution_context=$(grep -B 200 "ETL.*completed successfully\|ETL.*finished successfully" "${log_file}" 2>/dev/null | tail -200 || echo "")

	# Extract facts processed
	local facts_processed=0
	local facts_new=0
	local facts_updated=0
	local dimensions_updated=0

	# Try multiple patterns for facts processed
	if [[ "${execution_context}" =~ ([0-9]+)[[:space:]]+facts[[:space:]]+processed ]]; then
		facts_processed="${BASH_REMATCH[1]}"
	elif [[ "${execution_context}" =~ Processed[[:space:]]+([0-9]+)[[:space:]]+facts ]]; then
		facts_processed="${BASH_REMATCH[1]}"
	elif [[ "${execution_context}" =~ Updated[[:space:]]+([0-9]+)[[:space:]]+facts ]]; then
		facts_processed="${BASH_REMATCH[1]}"
	elif [[ "${execution_context}" =~ Loaded[[:space:]]+([0-9]+)[[:space:]]+facts ]]; then
		facts_processed="${BASH_REMATCH[1]}"
	fi

	# Extract new facts
	if [[ "${execution_context}" =~ ([0-9]+)[[:space:]]+new[[:space:]]+facts ]]; then
		facts_new="${BASH_REMATCH[1]}"
	elif [[ "${execution_context}" =~ Inserted[[:space:]]+([0-9]+)[[:space:]]+facts ]]; then
		facts_new="${BASH_REMATCH[1]}"
	fi

	# Extract updated facts
	if [[ "${execution_context}" =~ ([0-9]+)[[:space:]]+updated[[:space:]]+facts ]]; then
		facts_updated="${BASH_REMATCH[1]}"
	elif [[ "${execution_context}" =~ Updated[[:space:]]+([0-9]+)[[:space:]]+existing[[:space:]]+facts ]]; then
		facts_updated="${BASH_REMATCH[1]}"
	fi

	# Extract dimensions updated
	if [[ "${execution_context}" =~ ([0-9]+)[[:space:]]+dimensions[[:space:]]+updated ]]; then
		dimensions_updated="${BASH_REMATCH[1]}"
	elif [[ "${execution_context}" =~ Updated[[:space:]]+([0-9]+)[[:space:]]+dimensions ]]; then
		dimensions_updated="${BASH_REMATCH[1]}"
	fi

	# Calculate processing rate (facts per second)
	local processing_rate=0
	local execution_time=0
	if [[ "${last_execution_line}" =~ in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
		execution_time="${BASH_REMATCH[1]}"
		if [[ ${execution_time} -gt 0 ]] && [[ ${facts_processed} -gt 0 ]]; then
			processing_rate=$((facts_processed / execution_time))
		fi
	fi

	# Record metrics
	record_metric "${COMPONENT}" "etl_facts_processed_total" "${facts_processed}" "component=analytics"
	record_metric "${COMPONENT}" "etl_facts_new_total" "${facts_new}" "component=analytics"
	record_metric "${COMPONENT}" "etl_facts_updated_total" "${facts_updated}" "component=analytics"
	record_metric "${COMPONENT}" "etl_dimensions_updated_total" "${dimensions_updated}" "component=analytics"
	record_metric "${COMPONENT}" "etl_processing_rate_facts_per_second" "${processing_rate}" "component=analytics"

	log_info "${COMPONENT}: ETL facts processed - Total: ${facts_processed}, New: ${facts_new}, Updated: ${facts_updated}, Rate: ${processing_rate} facts/s"

	return 0
}

##
# Parse ETL stage timing from logs
# Usage: parse_etl_stage_timing <log_file>
##
parse_etl_stage_timing() {
	local log_file="${1}"
	local time_window_hours="${2:-24}"

	if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
		log_debug "${COMPONENT}: ETL log file not accessible: ${log_file}"
		return 1
	fi

	# Calculate time threshold
	local threshold_timestamp
	threshold_timestamp=$(date -d "${time_window_hours} hours ago" +%s 2>/dev/null || date -v-"${time_window_hours}"H +%s 2>/dev/null || echo "0")

	# Get [TIMING] log entries
	local timing_logs
	timing_logs=$(grep "\[TIMING\]" "${log_file}" 2>/dev/null | tail -200 || echo "")

	if [[ -z "${timing_logs}" ]]; then
		# Try alternative patterns
		timing_logs=$(grep -E "Stage:|Duration:" "${log_file}" 2>/dev/null | tail -200 || echo "")
	fi

	if [[ -z "${timing_logs}" ]]; then
		log_debug "${COMPONENT}: No stage timing information found in logs"
		return 0
	fi

	# Parse stage durations
	declare -A stage_durations
	declare -A stage_counts
	local slowest_stage=""
	local slowest_duration=0

	while IFS= read -r line; do
		# Extract timestamp
		local log_timestamp=0
		if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
			log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
		fi

		# Skip if too old
		if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
			continue
		fi

		# Extract stage name and duration
		# Format: [TIMING] Stage: <stage_name> - Duration: <duration> seconds
		local stage_name=""
		local duration=0

		if [[ "${line}" =~ Stage:[[:space:]]+([^-]+)[[:space:]]+-[[:space:]]+Duration:[[:space:]]+([0-9.]+)[[:space:]]+seconds ]]; then
			stage_name="${BASH_REMATCH[1]}"
			stage_name=$(echo "${stage_name}" | xargs) # Trim whitespace
			duration="${BASH_REMATCH[2]}"
		elif [[ "${line}" =~ Stage:[[:space:]]+([^-]+)[[:space:]]+-[[:space:]]+([0-9.]+)[[:space:]]+seconds ]]; then
			stage_name="${BASH_REMATCH[1]}"
			stage_name=$(echo "${stage_name}" | xargs)
			duration="${BASH_REMATCH[2]}"
		elif [[ "${line}" =~ ([A-Za-z_]+)[[:space:]]+took[[:space:]]+([0-9.]+)[[:space:]]+seconds ]]; then
			stage_name="${BASH_REMATCH[1]}"
			duration="${BASH_REMATCH[2]}"
		fi

		if [[ -n "${stage_name}" ]] && [[ ${duration} != "0" ]]; then
			# Convert to integer (seconds)
			local duration_int
			duration_int=$(echo "${duration}" | awk '{printf "%.0f", $1}')

			# Accumulate durations
			if [[ -n "${stage_durations[${stage_name}]:-}" ]]; then
				stage_durations["${stage_name}"]=$((stage_durations["${stage_name}"] + duration_int))
			else
				stage_durations["${stage_name}"]=${duration_int}
			fi

			# Count occurrences
			if [[ -n "${stage_counts[${stage_name}]:-}" ]]; then
				stage_counts["${stage_name}"]=$((stage_counts["${stage_name}"] + 1))
			else
				stage_counts["${stage_name}"]=1
			fi

			# Track slowest stage
			if [[ ${duration_int} -gt ${slowest_duration} ]]; then
				slowest_duration=${duration_int}
				slowest_stage="${stage_name}"
			fi
		fi
	done <<<"${timing_logs}"

	# Record metrics for each stage
	for stage_name in "${!stage_durations[@]}"; do
		local total_duration="${stage_durations[${stage_name}]}"
		local count="${stage_counts[${stage_name}]}"
		local avg_duration=0

		if [[ ${count} -gt 0 ]]; then
			avg_duration=$((total_duration / count))
		fi

		# Record metric with stage name as label
		record_metric "${COMPONENT}" "etl_stage_duration_seconds" "${avg_duration}" "component=analytics,stage=${stage_name}"

		log_debug "${COMPONENT}: Stage ${stage_name} - Avg duration: ${avg_duration}s, Count: ${count}"
	done

	# Record slowest stage
	if [[ -n "${slowest_stage}" ]]; then
		record_metric "${COMPONENT}" "etl_slowest_stage_duration_seconds" "${slowest_duration}" "component=analytics,stage=${slowest_stage}"
		log_info "${COMPONENT}: Slowest stage - ${slowest_stage}: ${slowest_duration}s"
	fi

	return 0
}

##
# Parse ETL validation results from logs
# Usage: parse_etl_validations <log_file>
##
parse_etl_validations() {
	local log_file="${1}"
	local time_window_hours="${2:-24}"

	if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
		log_debug "${COMPONENT}: ETL log file not accessible: ${log_file}"
		return 1
	fi

	# Calculate time threshold
	local threshold_timestamp
	threshold_timestamp=$(date -d "${time_window_hours} hours ago" +%s 2>/dev/null || date -v-"${time_window_hours}"H +%s 2>/dev/null || echo "0")

	# Get validation messages
	local validation_logs
	validation_logs=$(grep -E "MON-001|MON-002|validation|Validation|VALIDATION" "${log_file}" 2>/dev/null | tail -100 || echo "")

	if [[ -z "${validation_logs}" ]]; then
		log_debug "${COMPONENT}: No validation messages found in logs"
		return 0
	fi

	# Parse validation results
	local mon001_status="UNKNOWN"
	local mon001_issues=0
	local mon001_duration=0
	local mon002_status="UNKNOWN"
	local mon002_issues=0
	local mon002_duration=0
	local total_validations=0
	local passed_validations=0
	local failed_validations=0

	while IFS= read -r line; do
		# Extract timestamp
		local log_timestamp=0
		if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
			log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
		fi

		# Skip if too old
		if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
			continue
		fi

		total_validations=$((total_validations + 1))

		# Parse MON-001
		if [[ "${line}" =~ MON-001 ]]; then
			if [[ "${line}" =~ PASS|PASSED|SUCCESS ]]; then
				mon001_status="PASS"
				passed_validations=$((passed_validations + 1))
			elif [[ "${line}" =~ FAIL|FAILED|ERROR ]]; then
				mon001_status="FAIL"
				failed_validations=$((failed_validations + 1))
			fi

			# Extract issues count
			if [[ "${line}" =~ ([0-9]+)[[:space:]]+issues ]]; then
				mon001_issues="${BASH_REMATCH[1]}"
			fi

			# Extract duration
			if [[ "${line}" =~ ([0-9.]+)[[:space:]]+seconds ]]; then
				mon001_duration=$(echo "${BASH_REMATCH[1]}" | awk '{printf "%.0f", $1}')
			fi
		fi

		# Parse MON-002
		if [[ "${line}" =~ MON-002 ]]; then
			if [[ "${line}" =~ PASS|PASSED|SUCCESS ]]; then
				mon002_status="PASS"
				passed_validations=$((passed_validations + 1))
			elif [[ "${line}" =~ FAIL|FAILED|ERROR ]]; then
				mon002_status="FAIL"
				failed_validations=$((failed_validations + 1))
			fi

			# Extract issues count
			if [[ "${line}" =~ ([0-9]+)[[:space:]]+issues ]]; then
				mon002_issues="${BASH_REMATCH[1]}"
			fi

			# Extract duration
			if [[ "${line}" =~ ([0-9.]+)[[:space:]]+seconds ]]; then
				mon002_duration=$(echo "${BASH_REMATCH[1]}" | awk '{printf "%.0f", $1}')
			fi
		fi
	done <<<"${validation_logs}"

	# Calculate validation success rate
	local validation_success_rate=100
	if [[ ${total_validations} -gt 0 ]]; then
		validation_success_rate=$((passed_validations * 100 / total_validations))
	fi

	# Record metrics
	record_metric "${COMPONENT}" "etl_validation_status" "$([[ "${mon001_status}" == "PASS" ]] && echo "1" || echo "0")" "component=analytics,validation=MON-001,status=${mon001_status}"
	record_metric "${COMPONENT}" "etl_validation_issues" "${mon001_issues}" "component=analytics,validation=MON-001"
	record_metric "${COMPONENT}" "etl_validation_duration_seconds" "${mon001_duration}" "component=analytics,validation=MON-001"

	record_metric "${COMPONENT}" "etl_validation_status" "$([[ "${mon002_status}" == "PASS" ]] && echo "1" || echo "0")" "component=analytics,validation=MON-002,status=${mon002_status}"
	record_metric "${COMPONENT}" "etl_validation_issues" "${mon002_issues}" "component=analytics,validation=MON-002"
	record_metric "${COMPONENT}" "etl_validation_duration_seconds" "${mon002_duration}" "component=analytics,validation=MON-002"

	record_metric "${COMPONENT}" "etl_validations_total" "${total_validations}" "component=analytics"
	record_metric "${COMPONENT}" "etl_validations_success_rate" "${validation_success_rate}" "component=analytics"

	log_info "${COMPONENT}: ETL validations - MON-001: ${mon001_status} (${mon001_issues} issues), MON-002: ${mon002_status} (${mon002_issues} issues), Success rate: ${validation_success_rate}%"

	return 0
}

##
# Parse ETL errors and warnings from logs
# Usage: parse_etl_errors <log_file>
##
parse_etl_errors() {
	local log_file="${1}"
	local time_window_hours="${2:-24}"

	if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
		log_debug "${COMPONENT}: ETL log file not accessible: ${log_file}"
		return 1
	fi

	# Calculate time threshold
	local threshold_timestamp
	threshold_timestamp=$(date -d "${time_window_hours} hours ago" +%s 2>/dev/null || date -v-"${time_window_hours}"H +%s 2>/dev/null || echo "0")

	# Get error and warning messages
	local error_logs
	error_logs=$(grep -E "ERROR|FATAL|WARN|WARNING" "${log_file}" 2>/dev/null | tail -500 || echo "")

	if [[ -z "${error_logs}" ]]; then
		log_debug "${COMPONENT}: No error or warning messages found in logs"
		record_metric "${COMPONENT}" "etl_errors_count" "0" "component=analytics"
		record_metric "${COMPONENT}" "etl_warnings_count" "0" "component=analytics"
		record_metric "${COMPONENT}" "etl_error_rate_percent" "0" "component=analytics"
		return 0
	fi

	local error_count=0
	local warning_count=0
	local fatal_count=0
	declare -A error_patterns

	while IFS= read -r line; do
		# Extract timestamp
		local log_timestamp=0
		if [[ "${line}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
			log_timestamp=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo "0")
		fi

		# Skip if too old
		if [[ ${log_timestamp} -lt ${threshold_timestamp} ]] && [[ ${log_timestamp} -gt 0 ]]; then
			continue
		fi

		# Count errors
		if [[ "${line}" =~ ERROR|FATAL ]]; then
			if [[ "${line}" =~ FATAL ]]; then
				fatal_count=$((fatal_count + 1))
			else
				error_count=$((error_count + 1))
			fi

			# Extract error pattern (first few words after ERROR/FATAL)
			local error_pattern
			error_pattern=$(echo "${line}" | sed -n 's/.*\(ERROR\|FATAL\)[[:space:]]*\([^:]*\).*/\2/p' | head -c 50 | xargs)
			if [[ -n "${error_pattern}" ]]; then
				if [[ -n "${error_patterns[${error_pattern}]:-}" ]]; then
					error_patterns["${error_pattern}"]=$((error_patterns["${error_pattern}"] + 1))
				else
					error_patterns["${error_pattern}"]=1
				fi
			fi
		fi

		# Count warnings
		if [[ "${line}" =~ WARN|WARNING ]]; then
			warning_count=$((warning_count + 1))
		fi
	done <<<"${error_logs}"

	# Count total log lines for error rate calculation
	local total_log_lines=0
	total_log_lines=$(wc -l <"${log_file}" 2>/dev/null || echo "0")
	total_log_lines=$((total_log_lines + 0))

	# Calculate error rate
	local error_rate=0
	if [[ ${total_log_lines} -gt 0 ]]; then
		local total_errors=$((error_count + fatal_count))
		error_rate=$((total_errors * 100 / total_log_lines))
	fi

	# Record metrics
	record_metric "${COMPONENT}" "etl_errors_count" "${error_count}" "component=analytics"
	record_metric "${COMPONENT}" "etl_warnings_count" "${warning_count}" "component=analytics"
	record_metric "${COMPONENT}" "etl_fatal_count" "${fatal_count}" "component=analytics"
	record_metric "${COMPONENT}" "etl_error_rate_percent" "${error_rate}" "component=analytics"

	# Record most common error patterns (top 5)
	local pattern_count=0
	for pattern in "${!error_patterns[@]}"; do
		if [[ ${pattern_count} -lt 5 ]]; then
			record_metric "${COMPONENT}" "etl_error_pattern_count" "${error_patterns[${pattern}]}" "component=analytics,pattern=${pattern}"
			pattern_count=$((pattern_count + 1))
		fi
	done

	log_info "${COMPONENT}: ETL errors - Errors: ${error_count}, Warnings: ${warning_count}, Fatal: ${fatal_count}, Error rate: ${error_rate}%"

	return 0
}

##
# Detect ETL execution mode (initial_load vs incremental_update)
# Usage: detect_etl_mode <log_file>
##
detect_etl_mode() {
	local log_file="${1}"

	if [[ ! -f "${log_file}" ]] || [[ ! -r "${log_file}" ]]; then
		log_debug "${COMPONENT}: ETL log file not accessible: ${log_file}"
		return 1
	fi

	# Get last execution context
	local last_execution_context
	last_execution_context=$(grep -E "ETL.*completed|ETL.*finished|ETL.*started|ETL.*running" "${log_file}" 2>/dev/null | tail -50 || echo "")

	local execution_mode="unknown"
	local mode_confidence=0

	# Check for explicit mode indicators
	if [[ "${last_execution_context}" =~ initial[[:space:]]+load|Initial[[:space:]]+Load|INITIAL[[:space:]]+LOAD ]]; then
		execution_mode="initial_load"
		mode_confidence=100
	elif [[ "${last_execution_context}" =~ incremental|Incremental|INCREMENTAL ]]; then
		execution_mode="incremental_update"
		mode_confidence=100
	else
		# Try to infer from execution patterns
		# Initial loads typically process more facts and take longer
		local facts_processed=0
		local execution_time=0

		if [[ "${last_execution_context}" =~ ([0-9]+)[[:space:]]+facts ]]; then
			facts_processed="${BASH_REMATCH[1]}"
		fi

		if [[ "${last_execution_context}" =~ in[[:space:]]+([0-9]+)[[:space:]]+seconds ]]; then
			execution_time="${BASH_REMATCH[1]}"
		fi

		# Heuristic: if processing many facts (> 100000) or long execution (> 3600s), likely initial load
		if [[ ${facts_processed} -gt 100000 ]] || [[ ${execution_time} -gt 3600 ]]; then
			execution_mode="initial_load"
			mode_confidence=70
		else
			execution_mode="incremental_update"
			mode_confidence=70
		fi
	fi

	# Record metrics
	record_metric "${COMPONENT}" "etl_mode" "$([[ "${execution_mode}" == "initial_load" ]] && echo "1" || echo "0")" "component=analytics,mode=${execution_mode}"
	record_metric "${COMPONENT}" "etl_mode_confidence" "${mode_confidence}" "component=analytics,mode=${execution_mode}"

	log_info "${COMPONENT}: ETL execution mode detected - Mode: ${execution_mode}, Confidence: ${mode_confidence}%"

	return 0
}
