#!/bin/bash

# ------------------------
# Zabbix Proxy Deployment Script
# Handles installation, upgrade with configuration preservation
# Supports MySQL, PostgreSQL, and SQLite databases
# Auto-detects and configures system metadata
# ------------------------

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration files
PROXY_REPOS_JSON="$SCRIPT_DIR/zabbix-proxy-repos.json"
CONFIG_FILE="/etc/zabbix/zabbix_proxy.conf"
CONFIG_BACKUP_DIR="/opt/zabbix-config-backup"
LOG_FILE="/var/log/zabbix_proxy_install.log"

# Global variables
ACTION=""
VERSION=""
SERVER_IP=""
DB_TYPE=""
DB_PASSWORD=""
PASSWORD_MODE=""  # 'default' or 'manual'
AUTO_CONFIRM="no"
DETECTED_HOSTNAME=""
DETECTED_IP=""
PROXY_MODE="0"  # 0 = active (default), 1 = passive

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local msg="$@"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$timestamp [$level] $msg" >> "$LOG_FILE"

    case "$level" in
        INFO)
            echo -e "${BLUE}ℹ${NC} $msg"
            ;;
        SUCCESS)
            echo -e "${GREEN}✓${NC} $msg"
            ;;
        WARNING)
            echo -e "${YELLOW}⚠${NC} $msg"
            ;;
        ERROR)
            echo -e "${RED}✗${NC} $msg"
            ;;
        METADATA)
            echo -e "${CYAN}●${NC} $msg"
            ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
}

# Check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        log INFO "jq is not installed. Installing jq..."
        case "$(. /etc/os-release && echo $ID)" in
            ubuntu|debian)
                apt update && apt install -y jq || { log ERROR "Failed to install jq"; exit 1; }
                ;;
            rhel|centos|rocky|alma|oracle)
                dnf install -y jq || yum install -y jq || { log ERROR "Failed to install jq"; exit 1; }
                ;;
            *)
                log ERROR "Please install jq manually and try again"
                exit 1
                ;;
        esac
        log SUCCESS "jq installed successfully"
    fi
}

# Detect OS information
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION_ID="$VERSION_ID"
        OS_PRETTY_NAME="$PRETTY_NAME"
    else
        log ERROR "Cannot detect OS information"
        exit 1
    fi

    # Get architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            log ERROR "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
}

# Detect system metadata
detect_system_metadata() {
    log INFO "Detecting system metadata..."

    # Hostname
    DETECTED_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    log METADATA "Hostname: $DETECTED_HOSTNAME"

    # Primary IP address
    DETECTED_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')
    log METADATA "IP Address: $DETECTED_IP"

    # CPU info
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    log METADATA "CPU: $CPU_MODEL ($CPU_CORES cores)"

    # Memory info
    TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
    log METADATA "Memory: $TOTAL_MEM"

    # Disk info
    TOTAL_DISK=$(df -h / | tail -1 | awk '{print $2}')
    log METADATA "Root Disk: $TOTAL_DISK"

    # OS info
    log METADATA "OS: $OS_PRETTY_NAME"
    log METADATA "Architecture: $ARCH"

    # Kernel version
    KERNEL_VERSION=$(uname -r)
    log METADATA "Kernel: $KERNEL_VERSION"
}

# Display usage
usage() {
    cat << EOF
Zabbix Proxy Deployment Script

Usage: $0 --action <install|upgrade> --version <version> --server-ip <ip> --db <type> [OPTIONS]

Required:
  --action <action>       Action: install or upgrade
  --version <version>     Zabbix version: 6.0, 7.0, 7.2, 7.4
  --server-ip <ip>        Zabbix server IP address
  --db <type>             Database type: mysql, pgsql, sqlite

Password Mode (required for install with mysql/pgsql):
  --default               Use default password 'zabbix_password' (dev/test only)
  --manual                Prompt for custom password (production)

Optional:
  --hostname <name>       Override auto-detected hostname
  --proxy-mode <mode>     Proxy mode: 0=active (default), 1=passive
  --yes, -y               Auto-confirm all prompts
  --help, -h              Show this help message

Examples:
  # Install Proxy with MySQL (development - default password)
  $0 --action install --version 7.4 --server-ip 192.168.1.100 --db mysql --default

  # Install Proxy with MySQL (production - custom password)
  $0 --action install --version 7.4 --server-ip 192.168.1.100 --db mysql --manual

  # Install Proxy with SQLite (no password needed)
  $0 --action install --version 7.4 --server-ip 192.168.1.100 --db sqlite --yes

  # Upgrade Proxy (preserves configuration)
  $0 --action upgrade --version 7.4 --server-ip 192.168.1.100 --db mysql --yes

  # Install with custom hostname and passive mode
  $0 --action install --version 7.4 --server-ip 192.168.1.100 --db mysql --hostname proxy-01 --proxy-mode 1 --default

EOF
    exit 0
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action)
                ACTION="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --server-ip)
                SERVER_IP="$2"
                shift 2
                ;;
            --db)
                DB_TYPE="$2"
                shift 2
                ;;
            --default)
                PASSWORD_MODE="default"
                shift
                ;;
            --manual)
                PASSWORD_MODE="manual"
                shift
                ;;
            --hostname)
                DETECTED_HOSTNAME="$2"
                shift 2
                ;;
            --proxy-mode)
                PROXY_MODE="$2"
                shift 2
                ;;
            --yes|-y)
                AUTO_CONFIRM="yes"
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Validate arguments
validate_args() {
    if [[ -z "$ACTION" ]]; then
        log ERROR "Missing required argument: --action"
        usage
    fi

    if [[ ! "$ACTION" =~ ^(install|upgrade)$ ]]; then
        log ERROR "Invalid action: $ACTION. Must be: install or upgrade"
        exit 1
    fi

    if [[ -z "$VERSION" ]]; then
        log ERROR "Missing required argument: --version"
        usage
    fi

    if [[ -z "$SERVER_IP" ]]; then
        log ERROR "Missing required argument: --server-ip"
        usage
    fi

    if [[ -z "$DB_TYPE" ]]; then
        log ERROR "Missing required argument: --db"
        usage
    fi

    if [[ ! "$DB_TYPE" =~ ^(mysql|pgsql|sqlite)$ ]]; then
        log ERROR "Invalid database type: $DB_TYPE. Must be: mysql, pgsql, or sqlite"
        exit 1
    fi

    # Validate password mode for install action with mysql/pgsql
    if [[ "$ACTION" == "install" && ("$DB_TYPE" == "mysql" || "$DB_TYPE" == "pgsql") ]]; then
        if [[ -z "$PASSWORD_MODE" ]]; then
            log ERROR "Password mode required for install with mysql/pgsql. Use --default or --manual"
            usage
        fi

        if [[ "$PASSWORD_MODE" == "manual" && "$AUTO_CONFIRM" == "yes" ]]; then
            log ERROR "Cannot use --manual with --yes flag (manual mode requires interactive password input)"
            exit 1
        fi
    fi

    # Validate version exists in JSON
    if ! jq -e ".versions.\"$VERSION\"" "$PROXY_REPOS_JSON" > /dev/null 2>&1; then
        log ERROR "Version $VERSION not found in configuration"
        exit 1
    fi

    # Validate proxy mode
    if [[ ! "$PROXY_MODE" =~ ^[01]$ ]]; then
        log ERROR "Invalid proxy mode: $PROXY_MODE. Must be: 0 (active) or 1 (passive)"
        exit 1
    fi
}

# Get repository URL from JSON
get_repo_url() {
    local version="$1"
    local os="$2"
    local os_version="$3"
    local arch="$4"

    local url=$(jq -r ".versions.\"$version\".\"$os\".\"$os_version\".\"$arch\"" "$PROXY_REPOS_JSON" 2>/dev/null)

    if [[ "$url" == "null" || -z "$url" ]]; then
        log ERROR "No repository URL found for: $os $os_version $arch (version $version)"
        exit 1
    fi

    echo "$url"
}

# Get packages list from JSON
get_packages() {
    local version="$1"
    local db_type="$2"

    local packages=$(jq -r ".versions.\"$version\".packages.\"$db_type\"[]" "$PROXY_REPOS_JSON" 2>/dev/null)

    if [[ -z "$packages" ]]; then
        log ERROR "No packages found for version $version with database $db_type"
        exit 1
    fi

    echo "$packages"
}

# Backup existing configuration
backup_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local backup_name="zabbix_proxy.conf.backup.$(date +%Y%m%d_%H%M%S)"
        local backup_path="$CONFIG_BACKUP_DIR/$backup_name"

        mkdir -p "$CONFIG_BACKUP_DIR"
        cp "$CONFIG_FILE" "$backup_path"

        log SUCCESS "Configuration backed up to: $backup_path"
        echo "$backup_path"
    fi
}

# Install repository
install_repository() {
    local repo_url="$1"

    log INFO "Installing Zabbix repository..."

    case "$OS_ID" in
        ubuntu|debian)
            local deb_file="/tmp/zabbix-release.deb"
            local local_deb=""

            # Check for local .deb files first
            if [[ -f "$SCRIPT_DIR/zabbix-release_latest_${VERSION}+${OS_ID}${OS_VERSION_ID}_all.deb" ]]; then
                local_deb="$SCRIPT_DIR/zabbix-release_latest_${VERSION}+${OS_ID}${OS_VERSION_ID}_all.deb"
            elif [[ -f "$SCRIPT_DIR/zabbix-release_${VERSION}-1+${OS_ID}${OS_VERSION_ID}_all.deb" ]]; then
                local_deb="$SCRIPT_DIR/zabbix-release_${VERSION}-1+${OS_ID}${OS_VERSION_ID}_all.deb"
            fi

            # Try local file first, then download
            if [[ -n "$local_deb" ]]; then
                log INFO "Using local repository package: $(basename $local_deb)"
                cp "$local_deb" "$deb_file" || { log ERROR "Failed to copy local repository package"; exit 1; }
            else
                log INFO "Downloading from: $repo_url"
                if ! wget -q "$repo_url" -O "$deb_file" 2>/dev/null; then
                    local_deb=$(ls "$SCRIPT_DIR"/zabbix-release*${VERSION}*.deb 2>/dev/null | head -1)
                    if [[ -n "$local_deb" ]]; then
                        log WARNING "Download failed, using available local package: $(basename $local_deb)"
                        cp "$local_deb" "$deb_file" || { log ERROR "Failed to copy local repository package"; exit 1; }
                    else
                        log ERROR "Failed to download repository package and no local package found"
                        exit 1
                    fi
                fi
            fi

            dpkg -i "$deb_file" || { log ERROR "Failed to install repository package"; exit 1; }
            rm -f "$deb_file"
            apt update || { log ERROR "Failed to update package lists"; exit 1; }
            ;;
        rhel|centos|rocky|alma|oracle)
            rpm -Uvh "$repo_url" || { log ERROR "Failed to install repository package"; exit 1; }
            dnf clean all || yum clean all || true
            ;;
        *)
            log ERROR "Unsupported OS: $OS_ID"
            exit 1
            ;;
    esac

    log SUCCESS "Repository installed successfully"
}

# Install packages
install_packages() {
    local packages="$1"

    log INFO "Installing packages: $packages"

    case "$OS_ID" in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt install -y $packages || { log ERROR "Failed to install packages"; exit 1; }
            ;;
        rhel|centos|rocky|alma|oracle)
            dnf install -y $packages || yum install -y $packages || { log ERROR "Failed to install packages"; exit 1; }
            ;;
        *)
            log ERROR "Unsupported OS: $OS_ID"
            exit 1
            ;;
    esac

    log SUCCESS "Packages installed successfully"
}

# Setup database
setup_database() {
    local db_type="$1"
    local db_password="$2"

    log INFO "Setting up database for $db_type..."

    case "$db_type" in
        mysql)
            setup_mysql_database "$db_password"
            ;;
        pgsql)
            setup_postgresql_database "$db_password"
            ;;
        sqlite)
            setup_sqlite_database
            ;;
        *)
            log ERROR "Unsupported database type: $db_type"
            exit 1
            ;;
    esac
}

# Setup MySQL database
setup_mysql_database() {
    local db_password="$1"

    log INFO "Configuring MySQL database..."

    # Check if MySQL is installed
    if ! command -v mysql &> /dev/null; then
        log INFO "MySQL not found. Installing MySQL server..."
        case "$OS_ID" in
            ubuntu|debian)
                DEBIAN_FRONTEND=noninteractive apt install -y mysql-server || { log ERROR "Failed to install MySQL"; exit 1; }
                ;;
            rhel|centos|rocky|alma|oracle)
                dnf install -y mysql-server || yum install -y mysql-server || { log ERROR "Failed to install MySQL"; exit 1; }
                ;;
        esac
        systemctl enable mysql || systemctl enable mysqld || true
        systemctl start mysql || systemctl start mysqld || { log ERROR "Failed to start MySQL"; exit 1; }
        log SUCCESS "MySQL installed and started"
    fi

    # Create database and user
    log INFO "Creating Zabbix database and user..."

    mysql -uroot <<EOF || { log ERROR "Failed to create database"; exit 1; }
CREATE DATABASE IF NOT EXISTS zabbix_proxy CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON zabbix_proxy.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

    log SUCCESS "MySQL database created successfully"

    # Import schema if it's a fresh installation
    if [[ -f "/usr/share/zabbix-sql-scripts/mysql/proxy.sql" ]]; then
        log INFO "Importing database schema..."
        cat /usr/share/zabbix-sql-scripts/mysql/proxy.sql | mysql -uzabbix -p"$db_password" zabbix_proxy || {
            log WARNING "Schema import failed. It may have been already imported."
        }

        # Disable log_bin_trust_function_creators after import
        mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;" || true

        log SUCCESS "Database schema imported"
    fi
}

# Setup PostgreSQL database
setup_postgresql_database() {
    local db_password="$1"

    log INFO "Configuring PostgreSQL database..."

    # Check if PostgreSQL is installed
    if ! command -v psql &> /dev/null; then
        log INFO "PostgreSQL not found. Installing PostgreSQL server..."
        case "$OS_ID" in
            ubuntu|debian)
                DEBIAN_FRONTEND=noninteractive apt install -y postgresql || { log ERROR "Failed to install PostgreSQL"; exit 1; }
                ;;
            rhel|centos|rocky|alma|oracle)
                dnf install -y postgresql-server || yum install -y postgresql-server || { log ERROR "Failed to install PostgreSQL"; exit 1; }
                postgresql-setup --initdb || true
                ;;
        esac
        systemctl enable postgresql
        systemctl start postgresql || { log ERROR "Failed to start PostgreSQL"; exit 1; }
        log SUCCESS "PostgreSQL installed and started"
    fi

    # Create database and user
    log INFO "Creating Zabbix database and user..."

    sudo -u postgres psql <<EOF || { log ERROR "Failed to create database"; exit 1; }
CREATE DATABASE zabbix_proxy ENCODING 'UTF8';
CREATE USER zabbix WITH PASSWORD '$db_password';
GRANT ALL PRIVILEGES ON DATABASE zabbix_proxy TO zabbix;
\c zabbix_proxy
GRANT ALL ON SCHEMA public TO zabbix;
EOF

    log SUCCESS "PostgreSQL database created successfully"

    # Import schema if it's a fresh installation
    if [[ -f "/usr/share/zabbix-sql-scripts/postgresql/proxy.sql" ]]; then
        log INFO "Importing database schema..."
        cat /usr/share/zabbix-sql-scripts/postgresql/proxy.sql | sudo -u zabbix psql zabbix_proxy || {
            log WARNING "Schema import failed. It may have been already imported."
        }
        log SUCCESS "Database schema imported"
    fi
}

# Setup SQLite database
setup_sqlite_database() {
    log INFO "Configuring SQLite database..."

    # SQLite database file will be created automatically by Zabbix proxy
    # No setup needed, but ensure the directory exists with proper permissions

    mkdir -p /var/lib/zabbix
    chown -R zabbix:zabbix /var/lib/zabbix

    log SUCCESS "SQLite database directory configured"
}

# Configure proxy
configure_proxy() {
    local server_ip="$1"
    local hostname="$2"
    local db_type="$3"
    local db_password="$4"

    log INFO "Configuring Zabbix Proxy..."

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    # Backup original config
    cp "$CONFIG_FILE" "$CONFIG_FILE.pre-configure.bak"

    # Update Server parameter
    if grep -q "^Server=" "$CONFIG_FILE"; then
        sed -i "s/^Server=.*/Server=$server_ip/" "$CONFIG_FILE"
    elif grep -q "^# Server=" "$CONFIG_FILE"; then
        sed -i "s/^# Server=.*/Server=$server_ip/" "$CONFIG_FILE"
    else
        echo "Server=$server_ip" >> "$CONFIG_FILE"
    fi

    # Update Hostname parameter
    if grep -q "^Hostname=" "$CONFIG_FILE"; then
        sed -i "s/^Hostname=.*/Hostname=$hostname/" "$CONFIG_FILE"
    elif grep -q "^# Hostname=" "$CONFIG_FILE"; then
        sed -i "s/^# Hostname=.*/Hostname=$hostname/" "$CONFIG_FILE"
    else
        echo "Hostname=$hostname" >> "$CONFIG_FILE"
    fi

    # Update ProxyMode parameter
    if grep -q "^ProxyMode=" "$CONFIG_FILE"; then
        sed -i "s/^ProxyMode=.*/ProxyMode=$PROXY_MODE/" "$CONFIG_FILE"
    elif grep -q "^# ProxyMode=" "$CONFIG_FILE"; then
        sed -i "s/^# ProxyMode=.*/ProxyMode=$PROXY_MODE/" "$CONFIG_FILE"
    else
        echo "ProxyMode=$PROXY_MODE" >> "$CONFIG_FILE"
    fi

    # Configure database-specific parameters
    case "$db_type" in
        mysql)
            # DBHost
            if grep -q "^DBHost=" "$CONFIG_FILE"; then
                sed -i "s/^DBHost=.*/DBHost=localhost/" "$CONFIG_FILE"
            elif grep -q "^# DBHost=" "$CONFIG_FILE"; then
                sed -i "s/^# DBHost=.*/DBHost=localhost/" "$CONFIG_FILE"
            else
                echo "DBHost=localhost" >> "$CONFIG_FILE"
            fi

            # DBName
            if grep -q "^DBName=" "$CONFIG_FILE"; then
                sed -i "s/^DBName=.*/DBName=zabbix_proxy/" "$CONFIG_FILE"
            elif grep -q "^# DBName=" "$CONFIG_FILE"; then
                sed -i "s/^# DBName=.*/DBName=zabbix_proxy/" "$CONFIG_FILE"
            else
                echo "DBName=zabbix_proxy" >> "$CONFIG_FILE"
            fi

            # DBUser
            if grep -q "^DBUser=" "$CONFIG_FILE"; then
                sed -i "s/^DBUser=.*/DBUser=zabbix/" "$CONFIG_FILE"
            elif grep -q "^# DBUser=" "$CONFIG_FILE"; then
                sed -i "s/^# DBUser=.*/DBUser=zabbix/" "$CONFIG_FILE"
            else
                echo "DBUser=zabbix" >> "$CONFIG_FILE"
            fi

            # DBPassword
            if grep -q "^DBPassword=" "$CONFIG_FILE"; then
                sed -i "s/^DBPassword=.*/DBPassword=$db_password/" "$CONFIG_FILE"
            elif grep -q "^# DBPassword=" "$CONFIG_FILE"; then
                sed -i "s/^# DBPassword=.*/DBPassword=$db_password/" "$CONFIG_FILE"
            else
                echo "DBPassword=$db_password" >> "$CONFIG_FILE"
            fi
            ;;

        pgsql)
            # DBHost
            if grep -q "^DBHost=" "$CONFIG_FILE"; then
                sed -i "s/^DBHost=.*/DBHost=localhost/" "$CONFIG_FILE"
            elif grep -q "^# DBHost=" "$CONFIG_FILE"; then
                sed -i "s/^# DBHost=.*/DBHost=localhost/" "$CONFIG_FILE"
            else
                echo "DBHost=localhost" >> "$CONFIG_FILE"
            fi

            # DBName
            if grep -q "^DBName=" "$CONFIG_FILE"; then
                sed -i "s/^DBName=.*/DBName=zabbix_proxy/" "$CONFIG_FILE"
            elif grep -q "^# DBName=" "$CONFIG_FILE"; then
                sed -i "s/^# DBName=.*/DBName=zabbix_proxy/" "$CONFIG_FILE"
            else
                echo "DBName=zabbix_proxy" >> "$CONFIG_FILE"
            fi

            # DBUser
            if grep -q "^DBUser=" "$CONFIG_FILE"; then
                sed -i "s/^DBUser=.*/DBUser=zabbix/" "$CONFIG_FILE"
            elif grep -q "^# DBUser=" "$CONFIG_FILE"; then
                sed -i "s/^# DBUser=.*/DBUser=zabbix/" "$CONFIG_FILE"
            else
                echo "DBUser=zabbix" >> "$CONFIG_FILE"
            fi

            # DBPassword
            if grep -q "^DBPassword=" "$CONFIG_FILE"; then
                sed -i "s/^DBPassword=.*/DBPassword=$db_password/" "$CONFIG_FILE"
            elif grep -q "^# DBPassword=" "$CONFIG_FILE"; then
                sed -i "s/^# DBPassword=.*/DBPassword=$db_password/" "$CONFIG_FILE"
            else
                echo "DBPassword=$db_password" >> "$CONFIG_FILE"
            fi
            ;;

        sqlite)
            # DBName (file path for SQLite)
            if grep -q "^DBName=" "$CONFIG_FILE"; then
                sed -i "s|^DBName=.*|DBName=/var/lib/zabbix/zabbix_proxy.db|" "$CONFIG_FILE"
            elif grep -q "^# DBName=" "$CONFIG_FILE"; then
                sed -i "s|^# DBName=.*|DBName=/var/lib/zabbix/zabbix_proxy.db|" "$CONFIG_FILE"
            else
                echo "DBName=/var/lib/zabbix/zabbix_proxy.db" >> "$CONFIG_FILE"
            fi
            ;;
    esac

    log SUCCESS "Proxy configured successfully"
    log INFO "  Config file: $CONFIG_FILE"
    log INFO "  Server: $server_ip"
    log INFO "  Hostname: $hostname"
    log INFO "  ProxyMode: $PROXY_MODE ($([ "$PROXY_MODE" == "0" ] && echo "active" || echo "passive"))"
    log INFO "  Database: $db_type"
}

# Restore configuration values from backup
restore_configuration_values() {
    local backup_file="$1"

    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        return
    fi

    log INFO "Restoring configuration values from backup..."

    # Extract old config values
    declare -A OLD_CONFIG
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        if [[ -n "$key" && -n "$value" ]]; then
            OLD_CONFIG["$key"]="$value"
        fi
    done < <(grep -E "^[^#]" "$backup_file" | grep "=")

    # Restore values to new config
    for key in "${!OLD_CONFIG[@]}"; do
        local value="${OLD_CONFIG[$key]}"

        # Check if key exists in new config
        if grep -q "^$key=" "$CONFIG_FILE"; then
            # Update existing value
            sed -i "s|^$key=.*|$key=$value|" "$CONFIG_FILE"
            log INFO "  Restored: $key=$value"
        else
            # Add new value
            echo "$key=$value" >> "$CONFIG_FILE"
            log INFO "  Added: $key=$value"
        fi
    done

    log SUCCESS "Configuration values restored from backup"
}

# Start and enable service
start_service() {
    log INFO "Starting and enabling zabbix-proxy service..."

    systemctl daemon-reload
    systemctl enable zabbix-proxy || { log ERROR "Failed to enable service"; exit 1; }
    systemctl restart zabbix-proxy || { log ERROR "Failed to start service"; exit 1; }

    # Wait a moment and check status
    sleep 2
    if systemctl is-active --quiet zabbix-proxy; then
        log SUCCESS "zabbix-proxy service is running"
    else
        log ERROR "zabbix-proxy service failed to start"
        log ERROR "Check logs: journalctl -u zabbix-proxy -n 50"
        exit 1
    fi
}

# Check proxy connectivity
check_connectivity() {
    local server_ip="$1"

    log INFO "Checking connectivity to Zabbix server..."

    if systemctl is-active --quiet zabbix-proxy; then
        log SUCCESS "zabbix-proxy is active and running"

        # Check if proxy can reach server
        if timeout 5 bash -c "echo > /dev/tcp/$server_ip/10051" 2>/dev/null; then
            log SUCCESS "Can reach Zabbix server at $server_ip:10051"
        else
            log WARNING "Cannot reach Zabbix server at $server_ip:10051"
            log WARNING "Please check firewall rules and network connectivity"
        fi
    else
        log ERROR "zabbix-proxy service is not running"
        exit 1
    fi
}

# Display summary
display_summary() {
    echo ""
    log SUCCESS "======================================"
    log SUCCESS "Zabbix Proxy Deployment Complete!"
    log SUCCESS "======================================"
    echo ""
    log INFO "Configuration Summary:"
    log INFO "  Hostname: $DETECTED_HOSTNAME"
    log INFO "  IP Address: $DETECTED_IP"
    log INFO "  Server: $SERVER_IP"
    log INFO "  Version: $VERSION"
    log INFO "  Database: $DB_TYPE"
    log INFO "  Proxy Mode: $([ "$PROXY_MODE" == "0" ] && echo "Active" || echo "Passive")"
    log INFO "  Config File: $CONFIG_FILE"
    echo ""
    log INFO "Useful Commands:"
    log INFO "  Check status: systemctl status zabbix-proxy"
    log INFO "  View logs: journalctl -u zabbix-proxy -f"
    log INFO "  Restart: systemctl restart zabbix-proxy"
    log INFO "  Test config: zabbix_proxy -t"
    echo ""
    log INFO "Next Steps:"
    log INFO "  1. Add this proxy in Zabbix server web interface"
    log INFO "  2. Assign hosts to this proxy"
    log INFO "  3. Wait for proxy to connect and sync (~1-2 minutes)"
    echo ""
}

# Install action
do_install() {
    log INFO "========================================"
    log INFO "Installing Zabbix Proxy $VERSION"
    log INFO "========================================"
    echo ""

    # Detect system metadata
    detect_system_metadata
    echo ""

    # Get repository URL and packages
    REPO_URL=$(get_repo_url "$VERSION" "$OS_ID" "$OS_VERSION_ID" "$ARCH")
    PACKAGES=$(get_packages "$VERSION" "$DB_TYPE")

    log INFO "Repository: $REPO_URL"
    log INFO "Packages: $PACKAGES"
    log INFO "Database: $DB_TYPE"
    echo ""

    # Handle password for MySQL/PostgreSQL
    if [[ "$DB_TYPE" == "mysql" || "$DB_TYPE" == "pgsql" ]]; then
        if [[ "$PASSWORD_MODE" == "default" ]]; then
            DB_PASSWORD="zabbix_password"
            log WARNING "Using default password: zabbix_password"
            log WARNING "CHANGE THIS PASSWORD in production environments!"
        elif [[ "$PASSWORD_MODE" == "manual" ]]; then
            read -s -p "Enter database password for zabbix user: " DB_PASSWORD
            echo ""
            read -s -p "Confirm database password: " DB_PASSWORD_CONFIRM
            echo ""

            if [[ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]]; then
                log ERROR "Passwords do not match"
                exit 1
            fi

            if [[ -z "$DB_PASSWORD" ]]; then
                log ERROR "Password cannot be empty"
                exit 1
            fi
        fi
    fi

    # Confirm with user
    if [[ "$AUTO_CONFIRM" != "yes" ]]; then
        read -p "Continue with installation? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Installation cancelled by user"
            exit 0
        fi
    fi

    # Install repository
    install_repository "$REPO_URL"

    # Install packages
    install_packages "$PACKAGES"

    # Setup database
    setup_database "$DB_TYPE" "$DB_PASSWORD"

    # Configure proxy
    configure_proxy "$SERVER_IP" "$DETECTED_HOSTNAME" "$DB_TYPE" "$DB_PASSWORD"

    # Start service
    start_service

    # Check connectivity
    check_connectivity "$SERVER_IP"

    # Display summary
    display_summary
}

# Upgrade action
do_upgrade() {
    log INFO "========================================"
    log INFO "Upgrading Zabbix Proxy to version $VERSION"
    log INFO "========================================"
    echo ""

    # Check if proxy is installed
    if ! command -v zabbix_proxy &> /dev/null; then
        log ERROR "Zabbix Proxy is not installed. Use --action install instead"
        exit 1
    fi

    # Detect system metadata
    detect_system_metadata
    echo ""

    # Get current version
    CURRENT_VERSION=$(zabbix_proxy -V | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    log INFO "Current version: $CURRENT_VERSION"
    log INFO "Target version: $VERSION"
    echo ""

    # Backup configuration
    log INFO "Backing up configuration..."
    BACKUP_FILE=$(backup_configuration)
    echo ""

    # Extract database password from current config if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        DB_PASSWORD=$(grep "^DBPassword=" "$CONFIG_FILE" | cut -d'=' -f2 | xargs || echo "")
    fi

    # Confirm with user
    if [[ "$AUTO_CONFIRM" != "yes" ]]; then
        log WARNING "This will upgrade the proxy and preserve your configuration"
        read -p "Continue with upgrade? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Upgrade cancelled by user"
            exit 0
        fi
    fi

    # Stop service
    log INFO "Stopping zabbix-proxy service..."
    systemctl stop zabbix-proxy || true

    # Get repository URL and packages
    REPO_URL=$(get_repo_url "$VERSION" "$OS_ID" "$OS_VERSION_ID" "$ARCH")
    PACKAGES=$(get_packages "$VERSION" "$DB_TYPE")

    # Install new repository
    install_repository "$REPO_URL"

    # Upgrade packages
    log INFO "Upgrading packages: $PACKAGES"
    case "$OS_ID" in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt install --only-upgrade -y $PACKAGES || { log ERROR "Failed to upgrade packages"; exit 1; }
            ;;
        rhel|centos|rocky|alma|oracle)
            dnf upgrade -y $PACKAGES || yum upgrade -y $PACKAGES || { log ERROR "Failed to upgrade packages"; exit 1; }
            ;;
    esac
    log SUCCESS "Packages upgraded successfully"

    # Restore configuration values
    if [[ -n "$BACKUP_FILE" ]]; then
        restore_configuration_values "$BACKUP_FILE"
    fi

    # Start service
    start_service

    # Check connectivity
    check_connectivity "$SERVER_IP"

    # Display upgraded version
    NEW_VERSION=$(zabbix_proxy -V | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    log SUCCESS "Upgraded from $CURRENT_VERSION to $NEW_VERSION"

    # Display summary
    display_summary
}

# Main execution
main() {
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    # Check prerequisites
    check_root
    check_jq

    # Detect OS
    detect_os

    # Parse and validate arguments
    parse_args "$@"
    validate_args

    # Check if JSON file exists
    if [[ ! -f "$PROXY_REPOS_JSON" ]]; then
        log ERROR "Configuration file not found: $PROXY_REPOS_JSON"
        exit 1
    fi

    # Execute action
    case "$ACTION" in
        install)
            do_install
            ;;
        upgrade)
            do_upgrade
            ;;
        *)
            log ERROR "Invalid action: $ACTION"
            exit 1
            ;;
    esac

    log SUCCESS "All operations completed successfully!"
}

# Run main
main "$@"
