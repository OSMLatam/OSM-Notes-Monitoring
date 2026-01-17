#!/usr/bin/env bash
#
# Alert Rules Management Script
# Manages alert rule definitions, routing, and templates
#
# Version: 1.0.0
# Date: 2025-12-27
#

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
readonly PROJECT_ROOT

# Source libraries
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/loggingFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/monitoringFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/configFunctions.sh"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/bin/lib/alertFunctions.sh"

# Set default LOG_DIR if not set
# In test mode, use TEST_LOG_DIR if available, otherwise use PROJECT_ROOT/logs
if [[ "${TEST_MODE:-false}" == "true" ]] && [[ -n "${TEST_LOG_DIR:-}" ]]; then
    export LOG_DIR="${TEST_LOG_DIR}"
elif [[ -z "${LOG_DIR:-}" ]]; then
    export LOG_DIR="${PROJECT_ROOT}/logs"
fi

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Initialize logging
init_logging "${LOG_DIR}/alert_rules.log" "alertRules"

# Initialize alerting
init_alerting

##
# Show usage
##
usage() {
    cat << EOF
Alert Rules Management Script

Usage: ${0} [OPTIONS] [ACTION] [ARGS...]

Actions:
    list [COMPONENT]                   List alert rules
    add COMPONENT LEVEL TYPE ROUTE      Add alert rule
    remove RULE_ID                      Remove alert rule
    route COMPONENT LEVEL TYPE          Get routing for alert
    template list                       List alert templates
    template show TEMPLATE_ID           Show template details
    template add TEMPLATE_ID CONTENT    Add/update template

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -q, --quiet         Suppress non-error output
    -c, --config FILE   Use specific configuration file

Examples:
    ${0} list                          # List all rules
    ${0} list INGESTION                # List rules for INGESTION
    ${0} add INGESTION critical data_quality "admin@example.com"  # Add rule
    ${0} route INGESTION critical data_quality  # Get routing
    ${0} template list                 # List templates
    ${0} template show default         # Show default template

EOF
}

##
# Load configuration
##
load_config() {
    local config_file="${1:-${PROJECT_ROOT}/config/monitoring.conf}"
    
    if [[ -f "${config_file}" ]]; then
        # shellcheck disable=SC1090
        source "${config_file}" || true
    fi
    
    # Load alerts config if available
    if [[ -f "${PROJECT_ROOT}/config/alerts.conf" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/config/alerts.conf" || true
    elif [[ -f "${PROJECT_ROOT}/config/alerts.conf.example" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/config/alerts.conf.example" || true
    fi
    
    # Set defaults
    export ALERT_RULES_FILE="${ALERT_RULES_FILE:-${PROJECT_ROOT}/config/alert_rules.conf}"
    export ALERT_TEMPLATES_DIR="${ALERT_TEMPLATES_DIR:-${PROJECT_ROOT}/config/alert_templates}"
}

##
# List alert rules
#
# Arguments:
#   $1 - Component (optional)
##
list_rules() {
    local component="${1:-}"
    
    if [[ ! -f "${ALERT_RULES_FILE:-}" ]]; then
        echo "No alert rules file found"
        return 0
    fi
    
    if [[ -n "${component}" ]]; then
        grep "^${component}:" "${ALERT_RULES_FILE}" 2>/dev/null || echo "No rules found for ${component}"
    else
        cat "${ALERT_RULES_FILE}" 2>/dev/null || echo "No rules found"
    fi
}

##
# Add alert rule
#
# Arguments:
#   $1 - Component
#   $2 - Alert level
#   $3 - Alert type
#   $4 - Route (email, slack channel, etc.)
##
add_rule() {
    local component="${1:?Component required}"
    local alert_level="${2:?Alert level required}"
    local alert_type="${3:?Alert type required}"
    local route="${4:?Route required}"
    
    # Create rules file if it doesn't exist
    mkdir -p "$(dirname "${ALERT_RULES_FILE}")"
    touch "${ALERT_RULES_FILE}"
    
    # Add rule (format: component:level:type:route)
    echo "${component}:${alert_level}:${alert_type}:${route}" >> "${ALERT_RULES_FILE}"
    
    log_info "Alert rule added: ${component}:${alert_level}:${alert_type} -> ${route}"
    echo "Rule added: ${component}:${alert_level}:${alert_type} -> ${route}"
}

##
# Remove alert rule
#
# Arguments:
#   $1 - Rule ID (line number or pattern)
##
remove_rule() {
    local rule_id="${1:?Rule ID required}"
    
    if [[ ! -f "${ALERT_RULES_FILE:-}" ]]; then
        echo "No alert rules file found"
        return 1
    fi
    
    # If rule_id is a number, remove that line
    if [[ "${rule_id}" =~ ^[0-9]+$ ]]; then
        sed -i "${rule_id}d" "${ALERT_RULES_FILE}"
        log_info "Alert rule removed (line ${rule_id})"
        echo "Rule removed"
    else
        # Otherwise, treat as pattern and remove matching lines
        # Escape special regex characters in pattern for sed
        local escaped_pattern
        escaped_pattern=$(printf '%s\n' "${rule_id}" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "/${escaped_pattern}/d" "${ALERT_RULES_FILE}"
        log_info "Alert rule removed (pattern: ${rule_id})"
        echo "Rules matching '${rule_id}' removed"
    fi
}

##
# Get routing for an alert
#
# Arguments:
#   $1 - Component
#   $2 - Alert level
#   $3 - Alert type
##
get_routing() {
    local component="${1:?Component required}"
    local alert_level="${2:?Alert level required}"
    local alert_type="${3:?Alert type required}"
    
    # Check for specific rule (exact match)
    local rule
    rule=$(grep "^${component}:${alert_level}:${alert_type}:" "${ALERT_RULES_FILE:-/dev/null}" 2>/dev/null | head -1)
    
    if [[ -n "${rule}" ]]; then
        local route
        route=$(echo "${rule}" | cut -d':' -f4)
        echo "${route}"
        return 0
    fi
    
    # Check for component-level-type rule with level wildcard (component:*:type)
    rule=$(grep "^${component}:\\*:${alert_type}:" "${ALERT_RULES_FILE:-/dev/null}" 2>/dev/null | head -1)
    if [[ -n "${rule}" ]]; then
        route=$(echo "${rule}" | cut -d':' -f4)
        echo "${route}"
        return 0
    fi
    
    # Check for component-level rule with type wildcard (component:level:*)
    rule=$(grep "^${component}:${alert_level}:\\*:" "${ALERT_RULES_FILE:-/dev/null}" 2>/dev/null | head -1)
    if [[ -n "${rule}" ]]; then
        route=$(echo "${rule}" | cut -d':' -f4)
        echo "${route}"
        return 0
    fi
    
    # Check for component-level rule (component:level:)
    rule=$(grep "^${component}:${alert_level}:" "${ALERT_RULES_FILE:-/dev/null}" 2>/dev/null | head -1)
    if [[ -n "${rule}" ]]; then
        route=$(echo "${rule}" | cut -d':' -f4)
        echo "${route}"
        return 0
    fi
    
    # Check for full wildcard (*:*:*:route)
    rule=$(grep "^\\*:\\*:\\*:" "${ALERT_RULES_FILE:-/dev/null}" 2>/dev/null | head -1)
    if [[ -n "${rule}" ]]; then
        route=$(echo "${rule}" | cut -d':' -f4)
        echo "${route}"
        return 0
    fi
    
    # Fall back to default routing based on alert level
    case "${alert_level}" in
        critical)
            echo "${CRITICAL_ALERT_RECIPIENTS:-${ADMIN_EMAIL}}"
            ;;
        warning)
            echo "${WARNING_ALERT_RECIPIENTS:-${ADMIN_EMAIL}}"
            ;;
        info)
            echo "${INFO_ALERT_RECIPIENTS:-}"
            ;;
        *)
            echo "${ADMIN_EMAIL}"
            ;;
    esac
}

##
# List alert templates
##
list_templates() {
    local templates_dir="${ALERT_TEMPLATES_DIR}"
    
    if [[ ! -d "${templates_dir}" ]]; then
        echo "No templates directory found"
        return 0
    fi
    
    find "${templates_dir}" -maxdepth 1 -name "*.template" -type f 2>/dev/null | sed 's|.*/||' | sed 's|\.template$||' || echo "No templates found"
}

##
# Show template
#
# Arguments:
#   $1 - Template ID
##
show_template() {
    local template_id="${1:?Template ID required}"
    local templates_dir="${ALERT_TEMPLATES_DIR}"
    local template_file="${templates_dir}/${template_id}.template"
    
    if [[ ! -f "${template_file}" ]]; then
        echo "Template not found: ${template_id}"
        return 1
    fi
    
    cat "${template_file}"
}

##
# Add/update template
#
# Arguments:
#   $1 - Template ID
#   $2 - Template content (file path or - for stdin)
##
add_template() {
    local template_id="${1:?Template ID required}"
    local content="${2:?Content required}"
    local templates_dir="${ALERT_TEMPLATES_DIR}"
    
    mkdir -p "${templates_dir}"
    local template_file="${templates_dir}/${template_id}.template"
    
    if [[ "${content}" == "-" ]]; then
        cat > "${template_file}"
    elif [[ -f "${content}" ]]; then
        cp "${content}" "${template_file}"
    else
        echo "${content}" > "${template_file}"
    fi
    
    log_info "Template ${template_id} added/updated"
    echo "Template ${template_id} saved"
}

##
# Main function
##
main() {
    local action="${1:-}"
    
    # Load configuration
    load_config "${CONFIG_FILE:-}"
    
    # Strip leading -- from action if present
    if [[ "${action}" =~ ^-- ]]; then
        action="${action#--}"
    fi
    
    case "${action}" in
        list|--list)
            list_rules "${2:-}"
            ;;
        add|--add)
            if [[ $# -lt 5 ]]; then
                echo "Error: Component, level, type, and route required"
                usage
                exit 1
            fi
            add_rule "${2}" "${3}" "${4}" "${5}"
            ;;
        remove|--remove)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Rule ID or pattern required"
                usage
                exit 1
            fi
            # If multiple arguments provided, construct pattern component:level:type
            if [[ -n "${3:-}" ]] && [[ -n "${4:-}" ]]; then
                local pattern="${2}:${3}:${4}"
                remove_rule "${pattern}"
            else
                remove_rule "${2}"
            fi
            ;;
        route|--route)
            if [[ $# -lt 4 ]]; then
                echo "Error: Component, level, and type required"
                usage
                exit 1
            fi
            get_routing "${2}" "${3}" "${4}"
            ;;
        template|--template|templates|--templates)
            local template_action="${2:-}"
            # If no action specified, default to list
            if [[ -z "${template_action}" ]]; then
                list_templates
                return 0
            fi
            # Strip leading -- from template_action if present
            if [[ "${template_action}" =~ ^-- ]]; then
                template_action="${template_action#--}"
            fi
            case "${template_action}" in
                list)
                    list_templates
                    ;;
                show)
                    if [[ -z "${3:-}" ]]; then
                        echo "Error: Template ID required"
                        usage
                        exit 1
                    fi
                    show_template "${3}"
                    ;;
                add|--add)
                    if [[ $# -lt 4 ]]; then
                        echo "Error: Template ID and content required"
                        usage
                        exit 1
                    fi
                    add_template "${3}" "${4}"
                    ;;
                *)
                    echo "Error: Unknown template action: ${template_action}"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        add-template|--add-template)
            if [[ $# -lt 3 ]]; then
                echo "Error: Template ID and content required"
                usage
                exit 1
            fi
            add_template "${2}" "${3}"
            ;;
        show-template|--show-template)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Template ID required"
                usage
                exit 1
            fi
            show_template "${2}"
            ;;
        -h|--help|help)
            usage
            ;;
        "")
            echo "Error: Action required"
            usage
            exit 1
            ;;
        *)
            echo "Error: Unknown action: ${action}"
            usage
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

