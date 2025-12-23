#!/bin/bash

# ------------------------
# Zabbix Master Manager Script
# Unified interface for Server, Proxy, and Agent management
# Uses JSON configuration files for repository URLs
# ------------------------

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables
COMPONENT=""
ACTION=""
VERSION=""
DB=""
WEBSERVER=""
SERVER_IP=""
AUTO_CONFIRM="no"
LOG_FILE="/var/log/zabbix_manager.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    esac
}

# Check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        log ERROR "jq is not installed. Installing jq..."
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

# Display usage
usage() {
    cat << EOF
Zabbix Master Manager Script

Usage: $0 --component <server|proxy|agent> --action <install|upgrade|uninstall> [OPTIONS]

Required:
  --component <type>      Component type: server, proxy, or agent
  --action <action>       Action: install, upgrade, or uninstall
  --version <version>     Zabbix version: 6.0, 7.0, 7.2, 7.4

Component-Specific Options:

  Server:
    --db <type>           Database: mysql or pgsql
    --webserver <type>    Web server: apache or nginx
    --default             Use default password
    --manual              Prompt for password

  Proxy:
    --db <type>           Database: mysql, pgsql, or sqlite
    --server-ip <ip>      Zabbix server IP address
    --mode <mode>         Proxy mode: active (0) or passive (1), default: active

  Agent:
    --server-ip <ip>      Zabbix server IP address
    --plugins             Install additional plugins (mongodb, mssql, postgresql)

General Options:
  --yes, -y               Auto-confirm all prompts
  --help, -h              Show this help message

Examples:
  # Install Zabbix Server
  $0 --component server --action install --version 7.4 --db mysql --webserver apache --default

  # Upgrade Zabbix Server
  $0 --component server --action upgrade --version 7.4 --db mysql --webserver apache --yes

  # Install Zabbix Proxy
  $0 --component proxy --action install --version 7.4 --db mysql --server-ip 192.168.1.100

  # Install Zabbix Agent
  $0 --component agent --action install --version 7.4 --server-ip 192.168.1.100

  # Install Agent with plugins
  $0 --component agent --action install --version 7.4 --server-ip 192.168.1.100 --plugins

EOF
    exit 0
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --component)
                COMPONENT="$2"
                shift 2
                ;;
            --action)
                ACTION="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --db)
                DB="$2"
                shift 2
                ;;
            --webserver)
                WEBSERVER="$2"
                shift 2
                ;;
            --server-ip)
                SERVER_IP="$2"
                shift 2
                ;;
            --default|--manual)
                MODE_FLAG="$1"
                shift
                ;;
            --yes|-y)
                AUTO_CONFIRM="yes"
                shift
                ;;
            --plugins)
                INSTALL_PLUGINS="yes"
                shift
                ;;
            --mode)
                PROXY_MODE="$2"
                shift 2
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
    # Check required arguments
    if [[ -z "$COMPONENT" || -z "$ACTION" ]]; then
        log ERROR "Missing required arguments: --component and --action"
        usage
    fi

    # Validate component type
    if [[ ! "$COMPONENT" =~ ^(server|proxy|agent)$ ]]; then
        log ERROR "Invalid component: $COMPONENT. Must be: server, proxy, or agent"
        exit 1
    fi

    # Validate action
    if [[ ! "$ACTION" =~ ^(install|upgrade|uninstall)$ ]]; then
        log ERROR "Invalid action: $ACTION. Must be: install, upgrade, or uninstall"
        exit 1
    fi

    # Version required for install/upgrade
    if [[ "$ACTION" != "uninstall" && -z "$VERSION" ]]; then
        log ERROR "Version required for $ACTION action"
        exit 1
    fi

    # Component-specific validation
    case "$COMPONENT" in
        server)
            if [[ "$ACTION" != "uninstall" ]]; then
                if [[ -z "$DB" || -z "$WEBSERVER" ]]; then
                    log ERROR "Server requires --db and --webserver options"
                    exit 1
                fi
            fi
            ;;
        proxy)
            if [[ "$ACTION" == "install" ]]; then
                if [[ -z "$SERVER_IP" ]]; then
                    log ERROR "Proxy requires --server-ip option"
                    exit 1
                fi
            fi
            ;;
        agent)
            if [[ "$ACTION" == "install" && -z "$SERVER_IP" ]]; then
                log ERROR "Agent requires --server-ip option"
                exit 1
            fi
            ;;
    esac
}

# Delegate to appropriate script
delegate_to_script() {
    case "$COMPONENT" in
        server)
            delegate_server
            ;;
        proxy)
            delegate_proxy
            ;;
        agent)
            delegate_agent
            ;;
    esac
}

# Delegate server operations
delegate_server() {
    local cmd="$SCRIPT_DIR/zabbix-deployer.sh --$ACTION"

    if [[ "$ACTION" != "uninstall" ]]; then
        cmd="$cmd --version $VERSION --db $DB --webserver $WEBSERVER"
        [[ -n "${MODE_FLAG:-}" ]] && cmd="$cmd $MODE_FLAG"
    fi

    [[ "$AUTO_CONFIRM" == "yes" ]] && cmd="$cmd --yes"

    log INFO "Executing: $cmd"
    eval "$cmd"
}

# Delegate proxy operations
delegate_proxy() {
    log INFO "Managing Zabbix Proxy: $ACTION"

    # For now, call a placeholder or implement proxy-specific logic
    # You can create a separate zabbix-proxy-deployer.sh similar to server
    log WARNING "Proxy management is delegated to specialized script (to be implemented)"
    log INFO "Component: $COMPONENT"
    log INFO "Action: $ACTION"
    log INFO "Version: $VERSION"
    log INFO "Database: ${DB:-sqlite}"
    log INFO "Server IP: ${SERVER_IP:-not specified}"
}

# Delegate agent operations
delegate_agent() {
    log INFO "Managing Zabbix Agent: $ACTION"

    # For now, call a placeholder or implement agent-specific logic
    # You can create a separate zabbix-agent-deployer.sh
    log WARNING "Agent management is delegated to specialized script (to be implemented)"
    log INFO "Component: $COMPONENT"
    log INFO "Action: $ACTION"
    log INFO "Version: $VERSION"
    log INFO "Server IP: ${SERVER_IP:-not specified}"
    log INFO "Install Plugins: ${INSTALL_PLUGINS:-no}"
}

# Main execution
main() {
    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    log INFO "========================================"
    log INFO "Zabbix Master Manager Script Started"
    log INFO "========================================"

    # Check prerequisites
    check_jq

    # Parse and validate arguments
    parse_args "$@"
    validate_args

    # Display summary
    log INFO "Component: $COMPONENT"
    log INFO "Action: $ACTION"
    [[ -n "$VERSION" ]] && log INFO "Version: $VERSION"
    [[ -n "$DB" ]] && log INFO "Database: $DB"
    [[ -n "$WEBSERVER" ]] && log INFO "Web Server: $WEBSERVER"
    [[ -n "$SERVER_IP" ]] && log INFO "Server IP: $SERVER_IP"

    # Execute action
    delegate_to_script

    log SUCCESS "Operation completed successfully!"
    log INFO "========================================"
}

# Run main
main "$@"
