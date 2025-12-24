#!/bin/bash

# ------------------------
# Zabbix Agent Deployment Script
# Handles installation, upgrade with configuration preservation
# Auto-detects and configures system metadata
# ------------------------

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration files
AGENT_REPOS_JSON="$SCRIPT_DIR/zabbix-agent-repos.json"
CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
CONFIG_BACKUP_DIR="/opt/zabbix-config-backup"
LOG_FILE="/var/log/zabbix_agent_install.log"

# Global variables
ACTION=""
VERSION=""
SERVER_IP=""
INSTALL_PLUGINS="no"
AUTO_CONFIRM="no"
DETECTED_HOSTNAME=""
DETECTED_IP=""
AGENT_TYPE=""  # Will be 'agent' or 'agent2'
SERVICE_NAME=""  # Will be 'zabbix-agent' or 'zabbix-agent2'

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

# Detect which agent type is installed
detect_agent_type() {
    # Check if agent2 is installed
    if command -v zabbix_agent2 &> /dev/null || systemctl list-unit-files | grep -q "zabbix-agent2.service"; then
        AGENT_TYPE="agent2"
        CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
        SERVICE_NAME="zabbix-agent2"
        log INFO "Detected: Zabbix Agent 2"
    # Check if agent1 is installed
    elif command -v zabbix_agentd &> /dev/null || systemctl list-unit-files | grep -q "zabbix-agent.service"; then
        AGENT_TYPE="agent"
        CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
        SERVICE_NAME="zabbix-agent"
        log INFO "Detected: Zabbix Agent 1"
    else
        # Default to agent2 for new installations
        AGENT_TYPE="agent2"
        CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
        SERVICE_NAME="zabbix-agent2"
        log INFO "No existing agent detected, will install: Zabbix Agent 2"
    fi
}

# Display usage
usage() {
    cat << EOF
Zabbix Agent Deployment Script

Usage: $0 --action <install|upgrade|uninstall> [OPTIONS]

Required:
  --action <action>       Action: install, upgrade, or uninstall

Required for install/upgrade:
  --version <version>     Zabbix version: 6.0, 7.0, 7.2, 7.4
  --server-ip <ip>        Zabbix server IP address

Optional:
  --plugins               Install additional plugins (mongodb, mssql, postgresql)
  --hostname <name>       Override auto-detected hostname
  --yes, -y               Auto-confirm all prompts
  --help, -h              Show this help message

Examples:
  # Install Zabbix Agent
  $0 --action install --version 7.4 --server-ip 192.168.1.100

  # Install with plugins
  $0 --action install --version 7.4 --server-ip 192.168.1.100 --plugins

  # Upgrade (preserves configuration)
  $0 --action upgrade --version 7.4 --server-ip 192.168.1.100 --yes

  # Install with custom hostname
  $0 --action install --version 7.4 --server-ip 192.168.1.100 --hostname web-server-01

  # Uninstall Zabbix Agent
  $0 --action uninstall --yes

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
            --plugins)
                INSTALL_PLUGINS="yes"
                shift
                ;;
            --hostname)
                DETECTED_HOSTNAME="$2"
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

    if [[ ! "$ACTION" =~ ^(install|upgrade|uninstall)$ ]]; then
        log ERROR "Invalid action: $ACTION. Must be: install, upgrade, or uninstall"
        exit 1
    fi

    # Version and server-ip not required for uninstall
    if [[ "$ACTION" != "uninstall" ]]; then
        if [[ -z "$VERSION" ]]; then
            log ERROR "Missing required argument: --version"
            usage
        fi

        if [[ -z "$SERVER_IP" ]]; then
            log ERROR "Missing required argument: --server-ip"
            usage
        fi

        # Validate version exists in JSON
        if ! jq -e ".versions.\"$VERSION\"" "$AGENT_REPOS_JSON" > /dev/null 2>&1; then
            log ERROR "Version $VERSION not found in configuration"
            exit 1
        fi
    fi
}

# Get repository URL from JSON
get_repo_url() {
    local version="$1"
    local os="$2"
    local os_version="$3"
    local arch="$4"

    local url=$(jq -r ".versions.\"$version\".\"$os\".\"$os_version\".\"$arch\"" "$AGENT_REPOS_JSON" 2>/dev/null)

    if [[ "$url" == "null" || -z "$url" ]]; then
        log ERROR "No repository URL found for: $os $os_version $arch (version $version)"
        exit 1
    fi

    echo "$url"
}

# Get packages list from JSON
get_packages() {
    local version="$1"
    local include_plugins="$2"

    local packages=$(jq -r ".versions.\"$version\".packages.basic[]" "$AGENT_REPOS_JSON" 2>/dev/null)

    if [[ "$include_plugins" == "yes" ]]; then
        local plugins=$(jq -r ".versions.\"$version\".packages.plugins[]?" "$AGENT_REPOS_JSON" 2>/dev/null)
        if [[ -n "$plugins" ]]; then
            packages="$packages $plugins"
        fi
    fi

    echo "$packages"
}

# Backup existing configuration
backup_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local backup_name="zabbix_agent2.conf.backup.$(date +%Y%m%d_%H%M%S)"
        local backup_path="$CONFIG_BACKUP_DIR/$backup_name"

        mkdir -p "$CONFIG_BACKUP_DIR"
        cp "$CONFIG_FILE" "$backup_path"

        log SUCCESS "Configuration backed up to: $backup_path"
        echo "$backup_path"
    fi
}

# Extract configuration values from existing config
extract_config_values() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        return
    fi

    # Extract all non-commented configuration values
    declare -gA EXISTING_CONFIG
    while IFS='=' read -r key value; do
        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        if [[ -n "$key" && -n "$value" ]]; then
            EXISTING_CONFIG["$key"]="$value"
        fi
    done < <(grep -E "^[^#]" "$config_file" | grep "=")
}

# Install repository
install_repository() {
    local repo_url="$1"

    log INFO "Installing Zabbix repository..."

    case "$OS_ID" in
        ubuntu|debian)
            local deb_file="/tmp/zabbix-release.deb"
            local local_deb=""

            # Check for local .deb files first (fallback for unavailable online repos)
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
                # Try to download from URL
                log INFO "Downloading from: $repo_url"
                if ! wget -q "$repo_url" -O "$deb_file" 2>/dev/null; then
                    # If download fails, try to find any local .deb file for this version
                    local_deb=$(ls "$SCRIPT_DIR"/zabbix-release*${VERSION}*.deb 2>/dev/null | head -1)
                    if [[ -n "$local_deb" ]]; then
                        log WARNING "Download failed, using available local package: $(basename $local_deb)"
                        cp "$local_deb" "$deb_file" || { log ERROR "Failed to copy local repository package"; exit 1; }
                    else
                        log ERROR "Failed to download repository package and no local package found"
                        log ERROR "Please download the repository package manually or use version 7.0"
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

# Configure agent
configure_agent() {
    local server_ip="$1"
    local hostname="$2"

    log INFO "Configuring Zabbix Agent ($AGENT_TYPE)..."

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    # Backup original config
    cp "$CONFIG_FILE" "$CONFIG_FILE.pre-configure.bak"

    # Update Server parameter (or add if not present)
    if grep -q "^Server=" "$CONFIG_FILE"; then
        sed -i "s/^Server=.*/Server=$server_ip/" "$CONFIG_FILE"
    elif grep -q "^# Server=" "$CONFIG_FILE"; then
        sed -i "s/^# Server=.*/Server=$server_ip/" "$CONFIG_FILE"
    else
        echo "Server=$server_ip" >> "$CONFIG_FILE"
    fi

    # Update ServerActive parameter (or add if not present)
    if grep -q "^ServerActive=" "$CONFIG_FILE"; then
        sed -i "s/^ServerActive=.*/ServerActive=$server_ip/" "$CONFIG_FILE"
    elif grep -q "^# ServerActive=" "$CONFIG_FILE"; then
        sed -i "s/^# ServerActive=.*/ServerActive=$server_ip/" "$CONFIG_FILE"
    else
        echo "ServerActive=$server_ip" >> "$CONFIG_FILE"
    fi

    # Update Hostname parameter (or add if not present)
    if grep -q "^Hostname=" "$CONFIG_FILE"; then
        sed -i "s/^Hostname=.*/Hostname=$hostname/" "$CONFIG_FILE"
    elif grep -q "^# Hostname=" "$CONFIG_FILE"; then
        sed -i "s/^# Hostname=.*/Hostname=$hostname/" "$CONFIG_FILE"
    else
        echo "Hostname=$hostname" >> "$CONFIG_FILE"
    fi

    # Add ListenIP if not present
    if ! grep -q "^ListenIP=" "$CONFIG_FILE"; then
        if grep -q "^# ListenIP=" "$CONFIG_FILE"; then
            sed -i "s/^# ListenIP=.*/ListenIP=0.0.0.0/" "$CONFIG_FILE"
        else
            echo "ListenIP=0.0.0.0" >> "$CONFIG_FILE"
        fi
    fi

    # Add HostMetadataItem (for dynamic metadata using system.uname)
    if ! grep -q "^HostMetadataItem=" "$CONFIG_FILE"; then
        if grep -q "^# HostMetadataItem=" "$CONFIG_FILE"; then
            sed -i "s/^# HostMetadataItem=.*/HostMetadataItem=system.uname/" "$CONFIG_FILE"
        else
            echo "HostMetadataItem=system.uname" >> "$CONFIG_FILE"
        fi
        log INFO "  Added: HostMetadataItem=system.uname"
    else
        sed -i "s/^HostMetadataItem=.*/HostMetadataItem=system.uname/" "$CONFIG_FILE"
        log INFO "  Updated: HostMetadataItem=system.uname"
    fi

    log SUCCESS "Agent configured successfully"
    log INFO "  Config file: $CONFIG_FILE"
    log INFO "  Server: $server_ip"
    log INFO "  ServerActive: $server_ip"
    log INFO "  Hostname: $hostname"
    log INFO "  HostMetadataItem: system.uname"
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
    log INFO "Starting and enabling $SERVICE_NAME service..."

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" || { log ERROR "Failed to enable service"; exit 1; }
    systemctl restart "$SERVICE_NAME" || { log ERROR "Failed to start service"; exit 1; }

    # Wait a moment and check status
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log SUCCESS "$SERVICE_NAME service is running"
    else
        log ERROR "$SERVICE_NAME service failed to start"
        log ERROR "Check logs: journalctl -u $SERVICE_NAME -n 50"
        exit 1
    fi
}

# Check agent connectivity
check_connectivity() {
    local server_ip="$1"

    log INFO "Checking connectivity to Zabbix server..."

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log SUCCESS "$SERVICE_NAME is active and running"

        # Check if agent can reach server
        if timeout 5 bash -c "echo > /dev/tcp/$server_ip/10051" 2>/dev/null; then
            log SUCCESS "Can reach Zabbix server at $server_ip:10051"
        else
            log WARNING "Cannot reach Zabbix server at $server_ip:10051"
            log WARNING "Please check firewall rules and network connectivity"
        fi
    else
        log ERROR "$SERVICE_NAME service is not running"
        exit 1
    fi
}

# Display summary
display_summary() {
    local test_cmd="zabbix_agent2"
    if [[ "$AGENT_TYPE" == "agent" ]]; then
        test_cmd="zabbix_agentd"
    fi

    echo ""
    log SUCCESS "======================================"
    log SUCCESS "Zabbix Agent Deployment Complete!"
    log SUCCESS "======================================"
    echo ""
    log INFO "Configuration Summary:"
    log INFO "  Agent Type: $AGENT_TYPE"
    log INFO "  Hostname: $DETECTED_HOSTNAME"
    log INFO "  IP Address: $DETECTED_IP"
    log INFO "  Server: $SERVER_IP"
    log INFO "  Version: $VERSION"
    log INFO "  Config File: $CONFIG_FILE"
    echo ""
    log INFO "Useful Commands:"
    log INFO "  Check status: systemctl status $SERVICE_NAME"
    log INFO "  View logs: journalctl -u $SERVICE_NAME -f"
    log INFO "  Restart: systemctl restart $SERVICE_NAME"
    log INFO "  Test config: $test_cmd -t"
    echo ""
    log INFO "Next Steps:"
    log INFO "  1. Add this host in Zabbix server web interface"
    log INFO "  2. Link appropriate templates to the host"
    log INFO "  3. Wait for data to start flowing (~1-2 minutes)"
    echo ""
}

# Uninstall action
do_uninstall() {
    log INFO "========================================"
    log INFO "Uninstalling Zabbix Agent"
    log INFO "========================================"
    echo ""

    # Detect which agent is installed
    detect_agent_type
    echo ""

    # Check if agent is actually installed
    if ! command -v zabbix_agent2 &> /dev/null && ! command -v zabbix_agentd &> /dev/null; then
        log WARNING "Zabbix Agent does not appear to be installed"
        log INFO "Nothing to uninstall"
        exit 0
    fi

    log INFO "Detected agent type: $AGENT_TYPE"
    log INFO "Service name: $SERVICE_NAME"
    echo ""

    # Confirm with user
    if [[ "$AUTO_CONFIRM" != "yes" ]]; then
        log WARNING "This will completely remove Zabbix Agent and all configurations"
        read -p "Continue with uninstall? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Uninstall cancelled by user"
            exit 0
        fi
    fi

    # Stop and disable service
    log INFO "Stopping and disabling $SERVICE_NAME service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    log SUCCESS "Service stopped and disabled"

    # Remove packages
    log INFO "Removing Zabbix Agent packages..."
    case "$OS_ID" in
        ubuntu|debian)
            if [[ "$AGENT_TYPE" == "agent2" ]]; then
                apt purge -y zabbix-agent2 zabbix-agent2-plugin-* 2>/dev/null || apt remove -y zabbix-agent2 zabbix-agent2-plugin-* 2>/dev/null || true
            else
                apt purge -y zabbix-agent zabbix-sender 2>/dev/null || apt remove -y zabbix-agent zabbix-sender 2>/dev/null || true
            fi
            apt autoremove -y 2>/dev/null || true
            ;;
        rhel|centos|rocky|alma|oracle)
            if [[ "$AGENT_TYPE" == "agent2" ]]; then
                dnf remove -y zabbix-agent2 zabbix-agent2-plugin-* 2>/dev/null || yum remove -y zabbix-agent2 zabbix-agent2-plugin-* 2>/dev/null || true
            else
                dnf remove -y zabbix-agent zabbix-sender 2>/dev/null || yum remove -y zabbix-agent zabbix-sender 2>/dev/null || true
            fi
            ;;
        *)
            log WARNING "Unsupported OS for package removal: $OS_ID"
            log INFO "Please remove packages manually"
            ;;
    esac
    log SUCCESS "Packages removed"

    # Remove configuration files
    log INFO "Removing configuration files..."
    rm -f "$CONFIG_FILE" 2>/dev/null || true
    rm -f "$CONFIG_FILE.pre-configure.bak" 2>/dev/null || true
    rm -f "$CONFIG_FILE."*.bak 2>/dev/null || true
    rm -rf /etc/zabbix/zabbix_agent*.d/ 2>/dev/null || true
    log SUCCESS "Configuration files removed"

    # Remove logs
    log INFO "Removing log files..."
    rm -f "$LOG_FILE" 2>/dev/null || true
    rm -rf /var/log/zabbix/ 2>/dev/null || true
    log SUCCESS "Log files removed"

    # Remove backup directory
    log INFO "Removing backup directory..."
    rm -rf "$CONFIG_BACKUP_DIR" 2>/dev/null || true
    log SUCCESS "Backup directory removed"

    # Remove user and group (optional - only if not used by other Zabbix components)
    if ! command -v zabbix_server &> /dev/null && ! command -v zabbix_proxy &> /dev/null; then
        log INFO "Removing zabbix user and group..."
        userdel zabbix 2>/dev/null || true
        groupdel zabbix 2>/dev/null || true
        log SUCCESS "User and group removed"
    else
        log INFO "Keeping zabbix user/group (other Zabbix components detected)"
    fi

    echo ""
    log SUCCESS "======================================"
    log SUCCESS "Zabbix Agent Uninstalled Successfully!"
    log SUCCESS "======================================"
    echo ""
    log INFO "Summary:"
    log INFO "  Agent type: $AGENT_TYPE"
    log INFO "  Service: $SERVICE_NAME (stopped and disabled)"
    log INFO "  Packages: Removed"
    log INFO "  Configuration: Removed"
    log INFO "  Logs: Removed"
    log INFO "  Backups: Removed"
    echo ""
}

# Install action
do_install() {
    log INFO "========================================"
    log INFO "Installing Zabbix Agent $VERSION"
    log INFO "========================================"
    echo ""

    # Detect system metadata
    detect_system_metadata
    echo ""

    # Detect agent type (agent1 or agent2)
    detect_agent_type
    echo ""

    # Get repository URL and packages
    REPO_URL=$(get_repo_url "$VERSION" "$OS_ID" "$OS_VERSION_ID" "$ARCH")
    PACKAGES=$(get_packages "$VERSION" "$INSTALL_PLUGINS")

    log INFO "Repository: $REPO_URL"
    log INFO "Packages: $PACKAGES"
    echo ""

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

    # Configure agent
    configure_agent "$SERVER_IP" "$DETECTED_HOSTNAME"

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
    log INFO "Upgrading Zabbix Agent to version $VERSION"
    log INFO "========================================"
    echo ""

    # Check if agent is installed
    if ! command -v zabbix_agent2 &> /dev/null && ! command -v zabbix_agentd &> /dev/null; then
        log ERROR "Zabbix Agent is not installed. Use --action install instead"
        exit 1
    fi

    # Detect system metadata
    detect_system_metadata
    echo ""

    # Detect agent type (agent1 or agent2)
    detect_agent_type
    echo ""

    # Get current version
    if [[ "$AGENT_TYPE" == "agent2" ]]; then
        CURRENT_VERSION=$(zabbix_agent2 -V | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    else
        CURRENT_VERSION=$(zabbix_agentd -V | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    fi
    log INFO "Current version: $CURRENT_VERSION"
    log INFO "Target version: $VERSION"
    echo ""

    # Backup configuration
    log INFO "Backing up configuration..."
    BACKUP_FILE=$(backup_configuration)
    echo ""

    # Confirm with user
    if [[ "$AUTO_CONFIRM" != "yes" ]]; then
        log WARNING "This will upgrade the agent and preserve your configuration"
        read -p "Continue with upgrade? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Upgrade cancelled by user"
            exit 0
        fi
    fi

    # Stop service
    log INFO "Stopping $SERVICE_NAME service..."
    systemctl stop "$SERVICE_NAME" || true

    # Get repository URL and packages
    REPO_URL=$(get_repo_url "$VERSION" "$OS_ID" "$OS_VERSION_ID" "$ARCH")
    PACKAGES=$(get_packages "$VERSION" "$INSTALL_PLUGINS")

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
    if [[ "$AGENT_TYPE" == "agent2" ]]; then
        NEW_VERSION=$(zabbix_agent2 -V | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    else
        NEW_VERSION=$(zabbix_agentd -V | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    fi
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

    # Check if JSON file exists (only for install/upgrade)
    if [[ "$ACTION" != "uninstall" ]]; then
        if [[ ! -f "$AGENT_REPOS_JSON" ]]; then
            log ERROR "Configuration file not found: $AGENT_REPOS_JSON"
            exit 1
        fi
    fi

    # Execute action
    case "$ACTION" in
        install)
            do_install
            ;;
        upgrade)
            do_upgrade
            ;;
        uninstall)
            do_uninstall
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
