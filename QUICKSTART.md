# Zabbix Deployment - Quick Start Guide

This guide will get you started with Zabbix installation and upgrades in minutes.

## 📋 Prerequisites

- Root or sudo access
- Ubuntu/Debian/RHEL/CentOS system
- Minimum 2GB RAM
- 10GB free disk space

## 🚀 Quick Installation

### Option 1: Install Zabbix Server (Fastest)

```bash
cd /root/zab-upgrade
sudo ./zabbix-deployer.sh --install --default --version 7.4 --db mysql --webserver apache
```

This will:
- ✅ Install Zabbix 7.4 Server
- ✅ Install MySQL database
- ✅ Install Apache web server
- ✅ Use default password: `zabbix_password`
- ✅ Configure everything automatically

**Access your Zabbix:**
- URL: `http://YOUR_SERVER_IP/zabbix`
- Username: `Admin`
- Password: `zabbix`

### Option 2: Install with Custom Password

```bash
sudo ./zabbix-deployer.sh --install --manual --version 7.4 --db mysql --webserver apache
```

You'll be prompted to enter a secure database password.

### Option 3: Install with Nginx

```bash
sudo ./zabbix-deployer.sh --install --default --version 7.4 --db mysql --webserver nginx
```

### Option 4: Install with PostgreSQL

```bash
sudo ./zabbix-deployer.sh --install --default --version 7.4 --db pgsql --webserver apache
```

## 🔄 Quick Upgrade

### Upgrade to Latest Version (Non-Interactive)

```bash
sudo ./zabbix-deployer.sh --upgrade --version 7.4 --db mysql --webserver apache --yes
```

The `--yes` flag skips confirmation prompts (perfect for automation).

### Upgrade (Interactive)

```bash
sudo ./zabbix-deployer.sh --upgrade --version 7.4 --db mysql --webserver apache
```

You'll be asked to confirm before proceeding.

## 🔍 Verify Installation

### Check Services

```bash
# Check all services
systemctl status zabbix-server zabbix-agent2 apache2

# Or individually
systemctl status zabbix-server
systemctl status zabbix-agent2
systemctl status apache2  # or nginx
```

### Check Version

```bash
zabbix_server -V
```

### View Logs

```bash
# Installation log
tail -f /var/log/zabbix_install.log

# Zabbix server log
tail -f /var/log/zabbix/zabbix_server.log
```

## 🛠️ Using the Master Manager

The master manager provides a unified interface for all components:

### Install Agent on Remote Host

```bash
sudo ./zabbix-manager.sh \
  --component agent \
  --action install \
  --version 7.4 \
  --server-ip 192.168.1.100
```

### Install Proxy

```bash
sudo ./zabbix-manager.sh \
  --component proxy \
  --action install \
  --version 7.4 \
  --db mysql \
  --server-ip 192.168.1.100
```

### Install Server via Manager

```bash
sudo ./zabbix-manager.sh \
  --component server \
  --action install \
  --version 7.4 \
  --db mysql \
  --webserver apache \
  --default
```

## 🔐 Security Recommendations

### After Installation:

1. **Change Default Password**
   ```bash
   # Login to web interface
   # Go to: Administration → Users → Admin
   # Change password immediately!
   ```

2. **Update Database Password**
   ```bash
   # Edit configuration
   sudo nano /root/zab-upgrade/zabbix_server_config.conf

   # Change DBPassword value
   DBPassword=your_secure_password

   # Update Zabbix server config
   sudo nano /etc/zabbix/zabbix_server.conf

   # Update DBPassword line
   DBPassword=your_secure_password

   # Restart service
   sudo systemctl restart zabbix-server
   ```

3. **Secure MySQL**
   ```bash
   sudo mysql_secure_installation
   ```

4. **Configure Firewall**
   ```bash
   # For Ubuntu/Debian
   sudo ufw allow 80/tcp    # HTTP
   sudo ufw allow 443/tcp   # HTTPS (if using SSL)
   sudo ufw allow 10051/tcp # Zabbix server

   # For RHEL/CentOS
   sudo firewall-cmd --permanent --add-service=http
   sudo firewall-cmd --permanent --add-service=https
   sudo firewall-cmd --permanent --add-port=10051/tcp
   sudo firewall-cmd --reload
   ```

## 📊 Post-Installation Steps

### 1. Complete Web Setup

Visit `http://YOUR_SERVER_IP/zabbix` and:
- Login with Admin/zabbix
- Change admin password
- Configure email notifications
- Add your hosts

### 2. Verify Database Connection

```bash
# Check Zabbix can connect to database
sudo tail -f /var/log/zabbix/zabbix_server.log | grep -i database
```

### 3. Enable SSL (Recommended)

```bash
# Install certbot
sudo apt install certbot python3-certbot-apache

# Get certificate
sudo certbot --apache -d your-domain.com

# Auto-renewal
sudo certbot renew --dry-run
```

## 🐛 Troubleshooting

### Problem: Web interface shows blank page

**Solution:**
```bash
# Clear browser cache (Ctrl+Shift+Delete)
# Restart Apache
sudo systemctl restart apache2
```

### Problem: Cannot connect to database

**Solution:**
```bash
# Check database is running
sudo systemctl status mysql

# Check credentials in config
sudo grep DBPassword /etc/zabbix/zabbix_server.conf

# Test connection manually
mysql -uzabbix -p zabbix
```

### Problem: Services not starting

**Solution:**
```bash
# Check logs
sudo journalctl -u zabbix-server -n 50

# Check configuration
sudo zabbix_server -t

# Restart services
sudo systemctl restart zabbix-server zabbix-agent2
```

### Problem: SELinux blocking (RHEL/CentOS)

**Solution:**
```bash
# Temporarily disable
sudo setenforce 0

# Or configure properly
sudo setsebool -P httpd_can_connect_zabbix on
sudo setsebool -P httpd_can_network_connect_db on
```

## 📈 Performance Tuning

### For Production Systems:

1. **Increase PHP limits:**
   ```bash
   sudo nano /etc/php/8.1/apache2/php.ini

   # Update these values:
   max_execution_time = 300
   memory_limit = 256M
   post_max_size = 32M
   upload_max_filesize = 16M
   max_input_time = 300

   sudo systemctl restart apache2
   ```

2. **Optimize MySQL:**
   ```bash
   sudo nano /etc/mysql/my.cnf

   # Add under [mysqld]:
   innodb_buffer_pool_size = 1G
   innodb_log_file_size = 256M
   max_connections = 200

   sudo systemctl restart mysql
   ```

3. **Adjust Zabbix Cache:**
   ```bash
   sudo nano /etc/zabbix/zabbix_server.conf

   # Increase cache sizes:
   CacheSize=128M
   HistoryCacheSize=64M
   TrendCacheSize=32M
   ValueCacheSize=128M

   sudo systemctl restart zabbix-server
   ```

## 📚 Next Steps

1. ✅ [Add your first host](https://www.zabbix.com/documentation/current/manual/quickstart/host)
2. ✅ [Configure monitoring](https://www.zabbix.com/documentation/current/manual/config/items)
3. ✅ [Set up triggers and alerts](https://www.zabbix.com/documentation/current/manual/config/triggers)
4. ✅ [Create dashboards](https://www.zabbix.com/documentation/current/manual/web_interface/frontend_sections/monitoring/dashboard)
5. ✅ [Configure email notifications](https://www.zabbix.com/documentation/current/manual/config/notifications)

## 🎯 Common Use Cases

### Monitor Linux Server
1. Install agent on target server
2. Add host in Zabbix web interface
3. Link "Linux by Zabbix agent" template
4. Wait for data to appear

### Monitor Website
1. Go to Configuration → Hosts → Create host
2. Add "Website" template
3. Configure URL to monitor
4. Set up SSL certificate monitoring

### Monitor Database
1. Install appropriate agent plugin
2. Configure database credentials
3. Link database template
4. Set up performance triggers

## 📞 Getting Help

- **Logs**: `/var/log/zabbix_install.log`
- **Documentation**: See [README.md](README.md)
- **Official Docs**: https://www.zabbix.com/documentation/current/
- **Community**: https://www.zabbix.com/forum/

## ⚡ Quick Reference

| Task | Command |
|------|---------|
| Install Server | `./zabbix-deployer.sh --install --default --version 7.4 --db mysql --webserver apache` |
| Upgrade Server | `./zabbix-deployer.sh --upgrade --version 7.4 --db mysql --webserver apache --yes` |
| Check Status | `systemctl status zabbix-server` |
| View Logs | `tail -f /var/log/zabbix_install.log` |
| Restart Services | `systemctl restart zabbix-server zabbix-agent2 apache2` |
| Check Version | `zabbix_server -V` |
| Test Config | `zabbix_server -t` |
| List Backups | `ls -lh /opt/zabbix-backup-*` |

---

**🎉 You're all set! Happy monitoring!**

For detailed documentation, see [README.md](README.md)
