#!/bin/bash
#
# Install and configure Grafana for OSM-Notes-Monitoring
# 
# This script installs Grafana and configures it to connect to the
# PostgreSQL database (notes_monitoring) and provisions dashboards.
#
# Usage:
#   ./scripts/install_grafana.sh [--user USER] [--db-name DBNAME] [--db-user DBUSER]
#
# Options:
#   --user USER      System user to run Grafana (default: grafana)
#   --db-name DBNAME Database name (default: notes_monitoring)
#   --db-user DBUSER Database user (default: notes)
#   --port PORT      Grafana port (default: 3000)
#   --admin-password PASSWORD  Set admin password (will prompt if not provided)
#
# Date: 2026-01-08

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
GRAFANA_USER="${GRAFANA_USER:-grafana}"
DB_NAME="${DB_NAME:-notes_monitoring}"
DB_USER="${DB_USER:-grafana_readonly}"  # Default to read-only user for security
DB_PASSWORD="${DB_PASSWORD:-}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine project root (if not already set via --project-root)
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    # If script is in scripts/ directory, go up one level
    if [[ "${SCRIPT_DIR}" == *"/scripts" ]]; then
        PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
    # If script is in /tmp/, try to find project in common locations
    elif [[ -d "/home/notes/OSM-Notes-Monitoring" ]]; then
        PROJECT_ROOT="/home/notes/OSM-Notes-Monitoring"
    elif [[ -d "${HOME}/OSM-Notes-Monitoring" ]]; then
        PROJECT_ROOT="${HOME}/OSM-Notes-Monitoring"
    elif [[ -d "/opt/OSM-Notes-Monitoring" ]]; then
        PROJECT_ROOT="/opt/OSM-Notes-Monitoring"
    else
        # Try to find from current directory
        if [[ -d "${PWD}/dashboards/grafana" ]]; then
            PROJECT_ROOT="${PWD}"
        else
            echo "Error: Cannot determine project root. Please specify with --project-root or set PROJECT_ROOT environment variable." >&2
            echo "Example: $0 --project-root /home/notes/OSM-Notes-Monitoring" >&2
            exit 1
        fi
    fi
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            GRAFANA_USER="$2"
            shift 2
            ;;
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        --db-user)
            DB_USER="$2"
            shift 2
            ;;
        --port)
            GRAFANA_PORT="$2"
            shift 2
            ;;
        --admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --db-password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --project-root)
            PROJECT_ROOT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --user USER           System user to run Grafana (default: grafana)"
            echo "  --db-name DBNAME      Database name (default: notes_monitoring)"
            echo "  --db-user DBUSER      Database user (default: grafana_readonly)"
            echo "                       Note: Use a read-only user for security"
            echo "  --port PORT           Grafana port (default: 3000)"
            echo "  --admin-password PASS Set admin password (will prompt if not provided)"
            echo "  --db-password PASS    PostgreSQL password (will prompt if not provided)"
            echo "  --project-root PATH   Project root directory (auto-detected if not provided)"
            echo "  --help, -h            Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  ADMIN_PASSWORD        Grafana admin password"
            echo "  DB_PASSWORD           PostgreSQL password"
            echo "  PGPASSWORD            PostgreSQL password (alternative)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Print colored message
print_message() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_message "${RED}" "Error: This script must be run as root (use sudo)"
    exit 1
fi

print_message "${BLUE}" "=========================================="
print_message "${BLUE}" "Grafana Installation for OSM-Notes-Monitoring"
print_message "${BLUE}" "=========================================="
echo ""

# Detect OS
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    OS="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
else
    print_message "${RED}" "Error: Cannot detect OS"
    exit 1
fi

print_message "${BLUE}" "Detected OS: ${OS} ${OS_VERSION}"
echo ""

# Check if Grafana is already installed
GRAFANA_INSTALLED=false
if command -v grafana-server &> /dev/null || systemctl list-units --type=service --state=loaded 2>/dev/null | grep -q grafana-server; then
    GRAFANA_INSTALLED=true
    print_message "${GREEN}" "✓ Grafana is already installed"
    print_message "${BLUE}" "Skipping installation, proceeding with configuration..."
else
    print_message "${BLUE}" "Installing Grafana..."
fi

# Only attempt installation if Grafana is not installed
if [[ "${GRAFANA_INSTALLED}" == "false" ]]; then
    print_message "${BLUE}" "Installing Grafana..."
    
    if [[ "${OS}" == "ubuntu" ]] || [[ "${OS}" == "debian" ]]; then
        # Ubuntu/Debian installation
        print_message "${BLUE}" "Installing Grafana for Ubuntu/Debian..."
        
        # Add Grafana repository
        if [[ ! -f /etc/apt/sources.list.d/grafana.list ]]; then
            apt-get update
            apt-get install -y software-properties-common apt-transport-https
            
            # Add Grafana GPG key
            mkdir -p /usr/share/keyrings
            wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
            
            # Add repository
            echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
            
            apt-get update
        fi
        
        # Install Grafana
        apt-get install -y grafana
        
    elif [[ "${OS}" == "centos" ]] || [[ "${OS}" == "rhel" ]] || [[ "${OS}" == "fedora" ]]; then
        # CentOS/RHEL/Fedora installation
        print_message "${BLUE}" "Installing Grafana for CentOS/RHEL/Fedora..."
        
        if [[ ! -f /etc/yum.repos.d/grafana.repo ]]; then
            cat <<EOF > /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
        fi
        
        yum install -y grafana
        
    else
        print_message "${RED}" "Error: Unsupported OS: ${OS}"
        print_message "${YELLOW}" "Please install Grafana manually and run this script again"
        exit 1
    fi
    
    print_message "${GREEN}" "✓ Grafana installed successfully"
    echo ""
fi

# Configure Grafana port if different from default
if [[ "${GRAFANA_PORT}" != "3000" ]]; then
    print_message "${BLUE}" "Configuring Grafana port to ${GRAFANA_PORT}..."
    
    GRAFANA_INI="/etc/grafana/grafana.ini"
    if [[ -f "${GRAFANA_INI}" ]]; then
        # Update port in grafana.ini
        sed -i "s/^;http_port = 3000/http_port = ${GRAFANA_PORT}/" "${GRAFANA_INI}" || \
        sed -i "s/^http_port = .*/http_port = ${GRAFANA_PORT}/" "${GRAFANA_INI}"
        print_message "${GREEN}" "✓ Port configured"
    fi
fi

# Set admin password
if [[ -z "${ADMIN_PASSWORD}" ]]; then
    print_message "${BLUE}" "Setting Grafana admin password..."
    read -rsp "Enter admin password: " ADMIN_PASSWORD
    echo
    if [[ -z "${ADMIN_PASSWORD}" ]]; then
        print_message "${YELLOW}" "Warning: No password provided, using default (admin)"
        ADMIN_PASSWORD="admin"
    fi
fi

# Configure admin password via environment variable (will be set in systemd service)
GRAFANA_INI="/etc/grafana/grafana.ini"
if [[ -f "${GRAFANA_INI}" ]]; then
    # Escape special characters in password for sed
    ADMIN_PASSWORD_ESCAPED=$(printf '%s\n' "${ADMIN_PASSWORD}" | sed "s/[[\\.*^\$()+?{|]/\\\\&/g")
    
    # Set admin password in grafana.ini
    if grep -q "^admin_password" "${GRAFANA_INI}"; then
        # Use a different delimiter (#) to avoid issues with special characters
        sed -i "s#^admin_password = .*#admin_password = ${ADMIN_PASSWORD_ESCAPED}#" "${GRAFANA_INI}"
        else
            # Find [security] section and add admin_password
            if grep -q "^\[security\]" "${GRAFANA_INI}"; then
                # Use sed with a different delimiter and proper escaping
                sed -i "/^\[security\]/a admin_password = ${ADMIN_PASSWORD_ESCAPED}" "${GRAFANA_INI}"
            else
                {
                    echo ""
                    echo "[security]"
                    echo "admin_password = ${ADMIN_PASSWORD_ESCAPED}"
                } >> "${GRAFANA_INI}"
            fi
    fi
    print_message "${GREEN}" "✓ Admin password configured"
fi

# Create provisioning directories
print_message "${BLUE}" "Setting up provisioning directories..."
mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
print_message "${GREEN}" "✓ Directories created"

# Configure PostgreSQL data source
print_message "${BLUE}" "Configuring PostgreSQL data source..."

# Get database password if not provided
if [[ -z "${DB_PASSWORD}" ]]; then
    # Try to get from PGPASSWORD environment variable
    if [[ -n "${PGPASSWORD:-}" ]]; then
        DB_PASSWORD="${PGPASSWORD}"
        print_message "${BLUE}" "Using PostgreSQL password from PGPASSWORD environment variable"
    else
        read -rsp "Enter PostgreSQL password for user ${DB_USER}: " DB_PASSWORD
        echo
        if [[ -z "${DB_PASSWORD}" ]]; then
            print_message "${YELLOW}" "Warning: No password provided, will use peer authentication"
            DB_PASSWORD=""
        fi
    fi
fi

DATASOURCE_FILE="/etc/grafana/provisioning/datasources/postgresql.yml"
cat > "${DATASOURCE_FILE}" <<EOF
apiVersion: 1

datasources:
  - name: PostgreSQL
    type: postgres
    access: proxy
    url: localhost:5432
    database: ${DB_NAME}
    user: ${DB_USER}
    secureJsonData:
      password: ${DB_PASSWORD}
    jsonData:
      sslmode: disable
      postgresVersion: 1200
      timescaledb: false
    isDefault: true
    editable: true
EOF

chmod 644 "${DATASOURCE_FILE}"
chown grafana:grafana "${DATASOURCE_FILE}"
print_message "${GREEN}" "✓ PostgreSQL data source configured"

# Configure dashboard provisioning
print_message "${BLUE}" "Configuring dashboard provisioning..."

DASHBOARD_PROVIDER="/etc/grafana/provisioning/dashboards/dashboard.yml"
cat > "${DASHBOARD_PROVIDER}" <<EOF
apiVersion: 1

providers:
  - name: 'OSM Notes Monitoring'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

chmod 644 "${DASHBOARD_PROVIDER}"
chown grafana:grafana "${DASHBOARD_PROVIDER}"
print_message "${GREEN}" "✓ Dashboard provider configured"

# Copy dashboards
print_message "${BLUE}" "Copying dashboards..."

# Verify PROJECT_ROOT is set correctly
if [[ -z "${PROJECT_ROOT}" ]] || [[ ! -d "${PROJECT_ROOT}" ]]; then
    print_message "${RED}" "Error: Project root not found: ${PROJECT_ROOT}"
    print_message "${YELLOW}" "Please set PROJECT_ROOT environment variable or run script from project directory"
    exit 1
fi

DASHBOARDS_SOURCE="${PROJECT_ROOT}/dashboards/grafana"
if [[ ! -d "${DASHBOARDS_SOURCE}" ]]; then
    print_message "${RED}" "Error: Dashboards directory not found: ${DASHBOARDS_SOURCE}"
    print_message "${YELLOW}" "Project root: ${PROJECT_ROOT}"
    print_message "${YELLOW}" "Please ensure dashboards are in: ${DASHBOARDS_SOURCE}"
    exit 1
fi

# Copy all JSON dashboard files
DASHBOARD_COUNT=0
for dashboard in "${DASHBOARDS_SOURCE}"/*.json; do
    if [[ -f "${dashboard}" ]]; then
        cp "${dashboard}" /etc/grafana/provisioning/dashboards/
        DASHBOARD_COUNT=$((DASHBOARD_COUNT + 1))
    fi
done

chown -R grafana:grafana /etc/grafana/provisioning/dashboards
print_message "${GREEN}" "✓ Copied ${DASHBOARD_COUNT} dashboard(s)"

# Start and enable Grafana service
print_message "${BLUE}" "Starting Grafana service..."
systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

# Wait for Grafana to start
sleep 3

if systemctl is-active --quiet grafana-server; then
    print_message "${GREEN}" "✓ Grafana service started successfully"
else
    print_message "${RED}" "✗ Failed to start Grafana service"
    print_message "${YELLOW}" "Check logs: journalctl -u grafana-server"
    exit 1
fi

# Display summary
echo ""
print_message "${GREEN}" "=========================================="
print_message "${GREEN}" "Grafana Installation Complete!"
print_message "${GREEN}" "=========================================="
echo ""
print_message "${BLUE}" "Access Grafana:"
echo "  URL: http://localhost:${GRAFANA_PORT} (or http://$(hostname -I | awk '{print $1}'):${GRAFANA_PORT})"
echo "  Username: admin"
echo "  Password: ${ADMIN_PASSWORD}"
echo ""
print_message "${BLUE}" "Configuration:"
echo "  Database: ${DB_NAME}"
echo "  Database User: ${DB_USER}"
echo "  Dashboards: ${DASHBOARD_COUNT} dashboard(s) provisioned"
echo ""
print_message "${BLUE}" "Useful commands:"
echo "  Check status: systemctl status grafana-server"
echo "  View logs: journalctl -u grafana-server -f"
echo "  Restart: systemctl restart grafana-server"
echo ""
