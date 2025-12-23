# Zabbix Deployment & Upgrade Scripts

Production-ready bash scripts for automated installation, upgrade, and management of Zabbix Server, Proxy, and Agent components.

## 📋 Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Components](#components)
- [Usage](#usage)
- [Configuration Files](#configuration-files)
- [Supported Platforms](#supported-platforms)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Changelog](#changelog)

## ✨ Features

- ✅ **Automated Installation** - One-command installation of Zabbix Server, Proxy, or Agent
- ✅ **Automated Upgrades** - Zero-downtime upgrades with automatic backups
- ✅ **Multi-Platform Support** - Ubuntu, Debian, RHEL, CentOS, Rocky, Alma, Oracle Linux, SLES
- ✅ **Database Support** - MySQL/MariaDB and PostgreSQL
- ✅ **Web Server Support** - Apache and Nginx
- ✅ **Automatic Backups** - Configuration and database backups before upgrades
- ✅ **Version 7.2+ Support** - Automatic handling of frontend path changes
- ✅ **PHP Auto-Detection** - Automatically detects available PHP-FPM version
- ✅ **Repository Management** - JSON-based repository URL management
- ✅ **Progress Tracking** - Real-time progress bars and detailed logging
- ✅ **Non-Interactive Mode** - Support for automation with --yes flag

## 🔧 Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+, Debian 10+, RHEL/CentOS/Rocky/Alma 8+, SLES 15+
- **Architecture**: AMD64 or ARM64
- **RAM**: Minimum 2GB (4GB+ recommended for server)
- **Disk**: Minimum 10GB free space
- **Root Access**: Required

### Dependencies
- `wget` or `curl`
- `systemctl`
- `dpkg` (Debian/Ubuntu) or `rpm` (RHEL-based)

## 🚀 Quick Start

### Install Zabbix Server (Default Mode)
```bash
sudo ./zabbix-deployer.sh --install --default --version 7.4 --db mysql --webserver apache
```

### Upgrade Zabbix Server (Non-Interactive)
```bash
sudo ./zabbix-deployer.sh --upgrade --version 7.4 --db mysql --webserver apache --yes
```

### Using the Master Manager Script
```bash
# Install server
sudo ./zabbix-manager.sh --component server --action install --version 7.4 --db mysql --webserver apache

# Install agent
sudo ./zabbix-manager.sh --component agent --action install --version 7.4

# Install proxy
sudo ./zabbix-manager.sh --component proxy --action install --version 7.4 --db mysql
```

## 📦 Components

### 1. `zabbix-deployer.sh` - Server Deployment Script
Main script for Zabbix Server installation and upgrade.

**Features:**
- Full server installation with database setup
- Automated upgrades with backups
- Web server configuration
- Database schema import
- Service management

### 2. `zabbix-manager.sh` - Master Management Script
Unified interface for managing all Zabbix components.

**Features:**
- Manages Server, Proxy, and Agent installations
- Uses JSON configuration files for repositories
- Simplified command-line interface
- Consistent behavior across components

### 3. JSON Configuration Files

#### `zabbix-server-repos.json`
Repository URLs for Zabbix Server packages.

#### `zabbix-agent-repos.json`
Repository URLs for Zabbix Agent packages.

#### `zabbix-proxy-repos.json`
Repository URLs for Zabbix Proxy packages.

## 📖 Usage

### Zabbix Server Deployment

#### Installation
```bash
# Interactive installation (manual mode - prompts for password)
sudo ./zabbix-deployer.sh --install --manual --version 7.4 --db mysql --webserver apache

# Non-interactive installation (default mode - uses default password)
sudo ./zabbix-deployer.sh --install --default --version 7.4 --db mysql --webserver nginx
```

#### Upgrade
```bash
# Interactive upgrade
sudo ./zabbix-deployer.sh --upgrade --version 7.4 --db mysql --webserver apache

# Non-interactive upgrade
sudo ./zabbix-deployer.sh --upgrade --version 7.4 --db mysql --webserver apache --yes
```

#### Uninstall
```bash
sudo ./zabbix-deployer.sh --uninstall
```

### Command-Line Options

| Option | Required | Values | Description |
|--------|----------|--------|-------------|
| `--install` | Yes* | - | Install Zabbix |
| `--upgrade` | Yes* | - | Upgrade Zabbix |
| `--uninstall` | Yes* | - | Uninstall Zabbix |
| `--version` | Yes** | 6.0, 7.0, 7.2, 7.4 | Zabbix version |
| `--db` | Yes** | mysql, pgsql | Database type |
| `--webserver` | Yes** | apache, nginx | Web server type |
| `--default` | No | - | Use default password |
| `--manual` | No | - | Prompt for password |
| `--yes`, `-y` | No | - | Auto-confirm prompts |

\* One action required
\*\* Not required for uninstall

## 📝 Configuration Files

### Server Configuration: `zabbix_server_config.conf`
```ini
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=your_password
```

This file is automatically created during installation and used for upgrades.

### Repository Configuration: JSON Files

Example structure for `zabbix-server-repos.json`:
```json
{
  "versions": {
    "7.4": {
      "ubuntu": {
        "22.04": {
          "amd64": "https://repo.zabbix.com/zabbix/7.4/ubuntu/...",
          "arm64": "https://repo.zabbix.com/zabbix/7.4/ubuntu/..."
        }
      }
    }
  }
}
```

## 🖥️ Supported Platforms

| Distribution | Versions | Architecture |
|--------------|----------|--------------|
| Ubuntu | 20.04, 22.04, 24.04 | AMD64, ARM64 |
| Debian | 10, 11, 12 | AMD64, ARM64 |
| RHEL | 8, 9 | AMD64, ARM64 |
| Rocky Linux | 8, 9 | AMD64, ARM64 |
| AlmaLinux | 8, 9 | AMD64, ARM64 |
| Oracle Linux | 8, 9 | AMD64, ARM64 |
| CentOS Stream | 8, 9 | AMD64, ARM64 |
| SLES | 15 | AMD64, ARM64 |

## 💡 Examples

### Example 1: Fresh Server Installation
```bash
# Install Zabbix 7.4 with MySQL and Apache
sudo ./zabbix-deployer.sh --install --default \
  --version 7.4 \
  --db mysql \
  --webserver apache
```

### Example 2: Upgrade from 7.0 to 7.4
```bash
# Non-interactive upgrade
sudo ./zabbix-deployer.sh --upgrade \
  --version 7.4 \
  --db mysql \
  --webserver apache \
  --yes
```

### Example 3: Install with PostgreSQL and Nginx
```bash
# Interactive installation with PostgreSQL
sudo ./zabbix-deployer.sh --install --manual \
  --version 7.4 \
  --db pgsql \
  --webserver nginx
```

### Example 4: Using Master Manager
```bash
# Install Zabbix Agent on multiple hosts
sudo ./zabbix-manager.sh \
  --component agent \
  --action install \
  --version 7.4 \
  --server-ip 192.168.1.100

# Install Zabbix Proxy with MySQL
sudo ./zabbix-manager.sh \
  --component proxy \
  --action install \
  --version 7.4 \
  --db mysql \
  --server-ip 192.168.1.100
```

## 🔍 Troubleshooting

### Check Installation Logs
```bash
tail -f /var/log/zabbix_install.log
```

### Verify Services
```bash
# Check Zabbix Server
systemctl status zabbix-server

# Check Zabbix Agent
systemctl status zabbix-agent2

# Check Web Server
systemctl status apache2  # or nginx
```

### Common Issues

#### Issue: "No Zabbix repository files found after installation"
**Solution**: The script now automatically handles this by purging and reinstalling the repository package.

#### Issue: "Frontend shows path warning after upgrade to 7.2+"
**Solution**: The script automatically updates Apache/Nginx configuration. If you see this, re-run the upgrade.

#### Issue: "Database backup failed"
**Solution**: Check MySQL/PostgreSQL credentials in `/etc/zabbix/zabbix_server.conf`

#### Issue: "PHP-FPM version not found"
**Solution**: Install a supported PHP version (7.4-8.3) or let the script use the default `php-fpm`

### Manual Recovery

If upgrade fails, restore from backup:
```bash
# List backups
ls -lh /opt/zabbix-backup-*

# Restore configuration
sudo cp -r /opt/zabbix-backup-YYYYMMDD_HHMMSS/etc_zabbix/* /etc/zabbix/

# Restore database (MySQL)
mysql -uroot zabbix < /opt/zabbix-backup-YYYYMMDD_HHMMSS/zabbix_db.sql

# Restore database (PostgreSQL)
sudo -u postgres psql zabbix < /opt/zabbix-backup-YYYYMMDD_HHMMSS/zabbix_db.sql
```

## 📊 Upgrade Process Flow

```
1. Pre-Upgrade Checks
   ├── Verify Zabbix is installed
   ├── Check current version
   └── Display upgrade plan

2. Backup Phase
   ├── Stop services
   ├── Backup configuration files
   ├── Backup database
   └── Create restore point

3. Repository Update
   ├── Download new repo package
   ├── Purge old repository
   ├── Install new repository
   └── Update package cache

4. Package Upgrade
   ├── Upgrade Zabbix packages
   └── Handle dependencies

5. Configuration Update (7.2+)
   ├── Update Apache/Nginx config
   └── Fix frontend path

6. Service Restart
   ├── Start Zabbix services
   ├── Start web server
   └── Verify all services running

7. Verification
   ├── Check installed version
   ├── Verify services status
   └── Report results
```

## 🔒 Security Considerations

1. **Database Passwords**:
   - Default mode uses `zabbix_password` - **Change in production!**
   - Manual mode prompts for secure password
   - Passwords stored in `/etc/zabbix/zabbix_server.conf` (mode 640)

2. **Backups**:
   - Backups stored in `/opt/zabbix-backup-*`
   - Contain sensitive data - protect accordingly
   - Retain for disaster recovery

3. **Log Files**:
   - Logs may contain sensitive information
   - Stored in `/var/log/zabbix_install.log`
   - Review and clean periodically

## 📁 File Structure

```
/root/zab-upgrade/
├── zabbix-deployer.sh           # Main server deployment script
├── zabbix-manager.sh             # Master management script
├── zabbix-server-repos.json      # Server repository URLs
├── zabbix-agent-repos.json       # Agent repository URLs
├── zabbix-proxy-repos.json       # Proxy repository URLs
├── zabbix_server_config.conf     # Server configuration
├── check.sh                      # Verification script
├── README.md                     # This file
└── zabbix-release_*.deb          # Repository packages (downloaded)
```

## 🔄 Changelog

### Version 2.0 (Current)
- ✅ Added automatic Apache/Nginx configuration for Zabbix 7.2+
- ✅ Added `--yes` flag for non-interactive mode
- ✅ Improved repository handling with purge before reinstall
- ✅ Added dynamic PHP-FPM version detection
- ✅ Added pre-upgrade version validation
- ✅ Enhanced database backup with multiple auth methods
- ✅ Fixed input redirection for interactive prompts
- ✅ Added support for all major Linux distributions
- ✅ Created JSON-based repository management
- ✅ Added master manager script for all components

### Version 1.0
- Initial release with basic install/upgrade functionality

## 📞 Support

- **Documentation**: See this README
- **Logs**: `/var/log/zabbix_install.log`
- **Zabbix Documentation**: https://www.zabbix.com/documentation/current/

## 📜 License

This script is provided as-is for use with Zabbix installations. Use at your own risk.

## ⚠️ Disclaimer

- Always test in a non-production environment first
- Ensure you have valid backups before upgrading
- Review logs after installation/upgrade
- The script makes system-level changes - use with caution

## 🎯 Best Practices

1. **Before Upgrade**:
   - Read Zabbix upgrade notes
   - Test in staging environment
   - Verify backup integrity
   - Schedule maintenance window

2. **During Upgrade**:
   - Monitor logs in real-time
   - Keep terminal session active
   - Don't interrupt the process

3. **After Upgrade**:
   - Verify all services running
   - Test web interface
   - Check monitoring is working
   - Clear browser cache
   - Review logs for errors

## 🤝 Contributing

To improve these scripts:
1. Test thoroughly in your environment
2. Document any issues found
3. Suggest improvements
4. Share your use cases

---

**Last Updated**: December 2025
**Script Version**: 2.0
**Tested Zabbix Versions**: 6.0, 7.0, 7.2, 7.4
