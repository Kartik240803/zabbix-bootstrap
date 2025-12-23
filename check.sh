#!/bin/bash

echo "=== Checking Zabbix Repository Status ==="
echo ""

echo "1. Current Zabbix version:"
zabbix_server -V 2>&1 | head -n1
echo ""

echo "2. Installed Zabbix packages:"
dpkg -l | grep zabbix | awk '{print $2, $3}'
echo ""

echo "3. Zabbix repository files:"
ls -la /etc/apt/sources.list.d/ | grep zabbix
echo ""

echo "4. Zabbix repository content:"
cat /etc/apt/sources.list.d/zabbix.list 2>/dev/null || echo "No zabbix.list file found"
echo ""

echo "5. Available Zabbix server versions in repository:"
apt-cache policy zabbix-server-mysql
echo ""

echo "6. Check if 7.4 packages are available:"
apt-cache madison zabbix-server-mysql | head -5
echo ""

echo "7. Repository priorities:"
apt-cache policy | grep -A2 "zabbix"
