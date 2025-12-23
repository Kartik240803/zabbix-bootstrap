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

- ✅ **Fully Automated Installation** - Zero manual steps, complete hands-off deployment
- ✅ **Automatic Frontend Configuration** - Creates web config automatically (no installation wizard)
- ✅ **Locale Auto-Configuration** - Generates required locales to prevent frontend errors
- ✅ **Web Server Auto-Configuration** - Automatically configures Nginx/Apache, handles port conflicts
- ✅ **Smart Service Management** - Proper startup order (no premature service failures)
- ✅ **Automated Upgrades** - Zero-downtime upgrades with automatic backups
- ✅ **Multi-Platform Support** - Ubuntu, Debian, RHEL, CentOS, Rocky, Alma, Oracle Linux, SLES
- ✅ **Database Support** - MySQL/MariaDB and PostgreSQL with automatic schema import
- ✅ **Web Server Support** - Apache and Nginx with intelligent conflict resolution
- ✅ **Dual Password Modes** - `--default` for dev/test, `--manual` for production
- ✅ **Automatic Backups** - Configuration and database backups before upgrades
- ✅ **Version 6.0-7.4 Support** - All current Zabbix LTS and stable versions
- ✅ **PHP Auto-Detection** - Automatically detects available PHP-FPM version (7.4-8.3)
- ✅ **Repository Management** - JSON-based repository URL management
- ✅ **Progress Tracking** - Real-time progress bars and detailed logging
- ✅ **Non-Interactive Mode** - Full automation support with `--yes` flag

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

### Development/Testing Installation (Recommended for First-Time Users)
```bash
# Fully automated - no prompts, ready in minutes
sudo ./zabbix-deployer.sh --install --default --version 6.0 --db mysql --webserver nginx --yes
```
**Access**: `http://your-server-ip/` (nginx) or `http://your-server-ip/zabbix` (apache)
**Login**: Username: `Admin` | Password: `zabbix`
**Database Password**: `zabbix_password` (change for production!)

### Production Installation (Secure)
```bash
# Interactive - prompts for secure database password
sudo ./zabbix-manager.sh --component server --action install \
  --version 7.4 --db mysql --webserver apache --manual
```

### Upgrade Zabbix Server
```bash
# Fully automated upgrade with automatic backups
sudo ./zabbix-deployer.sh --upgrade --version 7.4 --db mysql --webserver nginx --yes
```

### Using the Master Manager Script
```bash
# Install server (development)
sudo ./zabbix-manager.sh --component server --action install \
  --version 7.4 --db mysql --webserver apache --default --yes

# Install agent
sudo ./zabbix-manager.sh --component agent --action install \
  --version 7.4 --server-ip 192.168.1.100 --yes

# Install proxy
sudo ./zabbix-manager.sh --component proxy --action install \
  --version 7.4 --db mysql --server-ip 192.168.1.100 --yes
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

### Password Modes: `--default` vs `--manual`

**When to use `--default` mode:**
- ✅ **Testing/Development environments** - Quick setup for testing
- ✅ **POC/Demo installations** - Temporary installations for demonstrations
- ✅ **Lab environments** - Internal testing and learning
- ✅ **Automated deployments** - CI/CD pipelines where passwords are changed later
- ✅ **Docker/Containers** - Containerized deployments with secrets management
- ⚠️ **Default password**: `zabbix_password` - **MUST be changed for production!**

**When to use `--manual` mode:**
- ✅ **Production environments** - Secure installations with custom passwords
- ✅ **Security-compliant deployments** - Meets security policy requirements
- ✅ **Multi-tenant environments** - Different passwords for different installations
- ✅ **Compliance requirements** - Audit trails require custom passwords
- 🔒 **Interactive prompt**: Asks for password during installation (not compatible with `--yes` flag)

**Example Decision Flow:**
```
Are you installing in production?
  └─ YES → Use --manual (secure custom password)
  └─ NO → Is this temporary/testing?
      └─ YES → Use --default (quick setup, change later if needed)
      └─ NO → Use --manual (better safe than sorry)
```

### Zabbix Server Deployment

#### Installation
```bash
# Production installation (manual mode - secure password)
sudo ./zabbix-deployer.sh --install --manual --version 7.4 --db mysql --webserver apache

# Development/Testing installation (default mode - uses 'zabbix_password')
sudo ./zabbix-deployer.sh --install --default --version 7.4 --db mysql --webserver nginx --yes
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
| `--version` | Yes** | 6.0, 7.0, 7.2, 7.4 | Zabbix version to install/upgrade |
| `--db` | Yes** | mysql, pgsql | Database type (MySQL/MariaDB or PostgreSQL) |
| `--webserver` | Yes** | apache, nginx | Web server type |
| `--default` | Yes*** | - | **Dev/Test Mode**: Uses default password `zabbix_password` |
| `--manual` | Yes*** | - | **Production Mode**: Prompts for secure custom password |
| `--yes`, `-y` | No | - | Auto-confirm all prompts (non-interactive mode) |

\* One action required (install, upgrade, or uninstall)
\*\* Required for install/upgrade, not required for uninstall
\*\*\* Either `--default` or `--manual` required for install action only

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

### Example 1: Production Server Installation (Secure)
```bash
# Install Zabbix 7.4 for production with custom password
# Interactive - will prompt for database password
sudo ./zabbix-deployer.sh --install --manual \
  --version 7.4 \
  --db mysql \
  --webserver apache
```

### Example 2: Development/Testing Installation (Quick Setup)
```bash
# Install Zabbix 6.0 for development with default password
# Fully automated - no prompts
sudo ./zabbix-deployer.sh --install --default \
  --version 6.0 \
  --db mysql \
  --webserver nginx \
  --yes
```

### Example 3: Upgrade from 7.0 to 7.4
```bash
# Non-interactive upgrade (uses existing database password)
sudo ./zabbix-deployer.sh --upgrade \
  --version 7.4 \
  --db mysql \
  --webserver apache \
  --yes
```

### Example 4: Install with PostgreSQL (Production)
```bash
# Production installation with PostgreSQL and Nginx
# Interactive - prompts for password
sudo ./zabbix-deployer.sh --install --manual \
  --version 7.4 \
  --db pgsql \
  --webserver nginx
```

### Example 5: Docker/Container Deployment (Default Password, Changed Later)
```bash
# Quick deployment for containerized environment
# Password will be changed via secrets management
sudo ./zabbix-deployer.sh --install --default \
  --version 7.4 \
  --db mysql \
  --webserver apache \
  --yes

# Later, change password using secrets management or manual update
```

### Example 6: Using Master Manager
```bash
# Install Zabbix Agent on multiple hosts
sudo ./zabbix-manager.sh \
  --component agent \
  --action install \
  --version 7.4 \
  --server-ip 192.168.1.100 \
  --yes

# Install Zabbix Proxy with MySQL
sudo ./zabbix-manager.sh \
  --component proxy \
  --action install \
  --version 7.4 \
  --db mysql \
  --server-ip 192.168.1.100 \
  --yes
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

#### Issue: "Locale for language 'en_US' is not found on the web server"
**Solution**: The script (v2.1+) automatically generates locales. For manual fix:
```bash
sudo apt install -y locales
sudo sed -i '/en_US.UTF-8 UTF-8/s/^# //g' /etc/locale.gen
sudo locale-gen en_US.UTF-8
sudo systemctl restart zabbix-server apache2  # or nginx php8.3-fpm
```

#### Issue: "Zabbix server won't start - database connection failed"
**Solution**: Check database password matches in both:
- `/etc/zabbix/zabbix_server.conf` (DBPassword=)
- `/etc/zabbix/web/zabbix.conf.php` ($DB['PASSWORD'])

#### Issue: "Installation shows wizard instead of login page"
**Solution**: The script (v2.1+) creates frontend config automatically. For manual fix:
```bash
# Frontend config is missing, check if it exists
ls -la /etc/zabbix/web/zabbix.conf.php
# If missing, re-run: configure_zabbix_frontend function
```

#### Issue: "Nginx won't start - port 80 already in use"
**Solution**: The script (v2.1+) automatically stops Apache. For manual fix:
```bash
sudo systemctl stop apache2
sudo systemctl disable apache2
sudo systemctl start nginx
```

#### Issue: "No Zabbix repository files found after installation"
**Solution**: The script automatically handles this by purging and reinstalling the repository package.

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

### 1. Database Password Management

**Default Mode (`--default`)**:
- Uses password: `zabbix_password`
- ⚠️ **CRITICAL**: Change this password immediately in production!
- Suitable only for: Development, Testing, POC, Lab environments
- Password is stored in:
  - `/etc/zabbix/zabbix_server.conf` (Server config)
  - `/etc/zabbix/web/zabbix.conf.php` (Frontend config)

**Manual Mode (`--manual`)**:
- Prompts for password during installation
- Password entered securely (not displayed on screen)
- Recommended for: Production, Security-compliant, Multi-tenant environments
- Cannot be used with `--yes` flag (requires interactive input)

**How to Change Database Password After Installation**:
```bash
# 1. Change MySQL password
mysql -uroot -e "ALTER USER 'zabbix'@'localhost' IDENTIFIED BY 'your_new_secure_password';"

# 2. Update Zabbix server configuration
sudo sed -i 's/^DBPassword=.*/DBPassword=your_new_secure_password/' /etc/zabbix/zabbix_server.conf

# 3. Update frontend configuration
sudo sed -i "s/\$DB\['PASSWORD'\].*/\$DB['PASSWORD'] = 'your_new_secure_password';/" /etc/zabbix/web/zabbix.conf.php

# 4. Restart Zabbix server
sudo systemctl restart zabbix-server
```

**Password Storage Security**:
- Server config: `/etc/zabbix/zabbix_server.conf` (mode 640, owner: zabbix:zabbix)
- Frontend config: `/etc/zabbix/web/zabbix.conf.php` (mode 640, owner: www-data:www-data)
- Both files are protected from unauthorized access

### 2. Backups

- **Location**: `/opt/zabbix-backup-YYYYMMDD_HHMMSS/`
- **Contents**: Configuration files + Database dumps
- ⚠️ **Contain sensitive data** - Protect with appropriate permissions
- **Retention**: Keep for disaster recovery, rotate regularly
- **Encryption**: Consider encrypting backups for additional security

### 3. Log Files

- **Location**: `/var/log/zabbix_install.log`
- ⚠️ **May contain**: Database passwords, configuration details
- **Recommendation**: Review and clean periodically
- **Permissions**: Ensure only root can read (mode 600)

### 4. Network Security

- **Frontend Access**: Configure firewall rules for port 80/443
- **Database Access**: MySQL/PostgreSQL should only listen on localhost
- **Agent Communication**: Use encryption for agent-server communication
- **API Access**: Enable API authentication and use tokens

### 5. SSL/TLS Configuration

After installation, consider enabling HTTPS:
```bash
# For Apache
sudo a2enmod ssl
sudo systemctl restart apache2

# For Nginx
# Configure SSL in /etc/nginx/sites-available/zabbix
```

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

### Version 2.1 (Current - December 2025)
- ✅ **Locale Configuration**: Automatic generation of `en_US.UTF-8` locale to prevent frontend errors
- ✅ **Frontend Auto-Configuration**: Creates `/etc/zabbix/web/zabbix.conf.php` automatically (no installation wizard)
- ✅ **Web Server Auto-Configuration**:
  - Nginx: Automatically uncomments `listen 80`, removes default site, stops Apache conflicts
  - Apache: Automatically stops Nginx conflicts
- ✅ **Service Restart Fix**: Services now restart AFTER configuration (fixes startup failures)
- ✅ **Complete Automation**: Zero manual steps required - fully hands-off installation
- ✅ **Enhanced Security Documentation**: Clear guidance on `--default` vs `--manual` modes
- ✅ **Password Management**: Added instructions for changing default passwords post-installation

### Version 2.0
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

**Last Updated**: December 23, 2025
**Script Version**: 2.1
**Tested Zabbix Versions**: 6.0, 7.0, 7.2, 7.4
**Tested Platforms**: Ubuntu 20.04/22.04/24.04, Debian 11/12, RHEL 8/9, Rocky 8/9
