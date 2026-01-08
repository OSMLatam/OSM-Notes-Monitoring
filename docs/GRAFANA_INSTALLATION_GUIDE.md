# Grafana Installation Guide

> **Date:** 2026-01-08  
> **Purpose:** Install and configure Grafana to visualize OSM-Notes-Monitoring metrics

## Summary

This guide will help you install Grafana on the production server and connect it to the `notes_monitoring` database to visualize metrics collected by the monitoring system.

---

## Automatic Installation (Recommended)

### Step 1: Copy installation script

From your local machine:

```bash
cd /home/angoca/github/OSM-Notes-Monitoring
scp scripts/install_grafana.sh angoca@192.168.0.7:/tmp/
```

### Step 2: Create read-only database user (Recommended)

For security, Grafana should use a read-only database user:

```bash
# Connect to PostgreSQL
sudo -u postgres psql -d notes_monitoring

# Create read-only user
CREATE USER grafana_readonly WITH PASSWORD 'your_secure_password';

# Grant SELECT permissions on all tables
GRANT CONNECT ON DATABASE notes_monitoring TO grafana_readonly;
GRANT USAGE ON SCHEMA public TO grafana_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_readonly;

# Grant SELECT on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_readonly;

# Exit
\q
```

**Note:** If you prefer to use the existing `notes` user, you can skip this step, but it's less secure.

### Step 3: Run script on production

Connect to server and execute:

```bash
ssh angoca@192.168.0.7
sudo bash /tmp/install_grafana.sh --db-user grafana_readonly
```

The script will prompt for:
- PostgreSQL password for the database user (use the password you set above)
- Grafana admin password (or press Enter to use "admin")

**Alternative:** Pass passwords as parameters:

```bash
sudo bash /tmp/install_grafana.sh \
  --db-user grafana_readonly \
  --db-password "your_db_password" \
  --admin-password "your_grafana_password"
```

### Step 4: Access Grafana

Once installed, access:

```
http://192.168.0.7:3000
```

**Default credentials:**
- Username: `admin`
- Password: The one you configured during installation

---

## Manual Installation

If you prefer to install manually:

### 1. Install Grafana (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y software-properties-common apt-transport-https

# Add GPG key
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key

# Add repository
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Install
sudo apt-get update
sudo apt-get install -y grafana

# Start service
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
```

### 2. Configure PostgreSQL Data Source

1. Access Grafana: `http://192.168.0.7:3000`
2. Log in with `admin` / `admin` (you'll change the password)
3. Go to **Configuration** → **Data Sources** → **Add data source**
4. Select **PostgreSQL**
5. Configure:
   - **Name**: `PostgreSQL`
   - **Host**: `localhost:5432`
   - **Database**: `notes_monitoring`
   - **User**: `grafana_readonly` (or `notes` if you didn't create a read-only user)
   - **Password**: (your PostgreSQL password)
   - **SSL Mode**: `disable`
6. Click **Save & Test**

### 3. Import Dashboards

#### Option A: Manual Import

1. Go to **Dashboards** → **Import**
2. For each dashboard in `/home/notes/OSM-Notes-Monitoring/dashboards/grafana/`:
   - Click **Upload JSON file**
   - Select the JSON file
   - Select the `PostgreSQL` data source
   - Click **Import**

#### Option B: Automatic Provisioning

```bash
# Create provisioning directory
sudo mkdir -p /etc/grafana/provisioning/dashboards

# Create configuration file
sudo tee /etc/grafana/provisioning/dashboards/dashboard.yml <<EOF
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

# Copy dashboards
sudo cp /home/notes/OSM-Notes-Monitoring/dashboards/grafana/*.json /etc/grafana/provisioning/dashboards/

# Set permissions
sudo chown -R grafana:grafana /etc/grafana/provisioning/dashboards

# Restart Grafana
sudo systemctl restart grafana-server
```

---

## Available Dashboards

The following dashboards are included:

1. **Overview** (`overview.json`) - System overview
2. **Ingestion** (`ingestion.json`) - Data ingestion metrics
3. **Analytics** (`analytics.json`) - Analytics metrics
4. **WMS** (`wms.json`) - WMS service metrics
5. **API** (`api.json`) - API metrics
6. **Infrastructure** (`infrastructure.json`) - Infrastructure metrics

---

## Verification

### Verify Grafana is running

```bash
sudo systemctl status grafana-server
```

### Check logs

```bash
sudo journalctl -u grafana-server -f
```

### Verify database connection

1. In Grafana, go to **Configuration** → **Data Sources**
2. Click **PostgreSQL**
3. Click **Save & Test**
4. Should show: "Data source is working"

### Verify dashboards

1. Go to **Dashboards** → **Browse**
2. You should see dashboards from "OSM Notes Monitoring"

---

## Troubleshooting

### Grafana won't start

```bash
# Check detailed logs
sudo journalctl -u grafana-server -n 50

# Verify configuration
sudo grafana-server -config /etc/grafana/grafana.ini -config /etc/grafana/grafana.ini
```

### Can't connect to PostgreSQL

1. Verify PostgreSQL is running:
   ```bash
   sudo systemctl status postgresql
   ```

2. Verify database exists:
   ```bash
   psql -U grafana_readonly -d notes_monitoring -c "SELECT 1;"
   ```

3. Verify credentials in Grafana (Configuration → Data Sources → PostgreSQL)

### Dashboards don't appear

1. Verify JSON files are in `/etc/grafana/provisioning/dashboards/`
2. Check permissions:
   ```bash
   sudo ls -la /etc/grafana/provisioning/dashboards/
   ```
3. Restart Grafana:
   ```bash
   sudo systemctl restart grafana-server
   ```

### Error "invalid input syntax for type json"

This error has been fixed in the code. If it appears, make sure you have the latest version of monitoring scripts.

---

## Advanced Configuration

### Change Grafana port

Edit `/etc/grafana/grafana.ini`:

```ini
[server]
http_port = 3001
```

Then restart:
```bash
sudo systemctl restart grafana-server
```

### Configure LDAP authentication

See [official Grafana documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/ldap/).

### Configure Grafana alerts

1. Go to **Alerting** → **Alert rules**
2. Create rules based on PostgreSQL metrics
3. Configure notification channels (email, Slack, etc.)

---

## Security Best Practices

### Database User Permissions

**Recommended:** Use a read-only database user (`grafana_readonly`)

**Why:**
- Grafana only needs to **read** data (SELECT queries)
- Does **not** need to modify data (INSERT, UPDATE, DELETE)
- Follows **principle of least privilege**
- Reduces security risk if Grafana is compromised

**Permissions needed:**
- `CONNECT` on database
- `USAGE` on schema
- `SELECT` on all tables (current and future)

**Not needed:**
- `INSERT`, `UPDATE`, `DELETE`
- `CREATE`, `DROP`, `ALTER`
- `TRUNCATE`

---

## References

- [Grafana Setup Guide](./GRAFANA_SETUP_GUIDE.md) - Complete guide in English
- [Grafana Architecture](./GRAFANA_ARCHITECTURE.md) - System architecture
- [Dashboard Guide](./DASHBOARD_GUIDE.md) - Dashboard usage guide

---

## Next Steps

1. ✅ Install Grafana
2. ✅ Configure PostgreSQL data source
3. ✅ Import dashboards
4. 🔄 Customize dashboards as needed
5. 🔄 Configure alerts
6. 🔄 Configure users and permissions
