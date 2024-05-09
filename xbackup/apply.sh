#!/usr/bin/env bash
# It will copy/move the prepared backup in data dir of mysql
##❣️ Don't forget to run ./prepare.sh prior running this file

sudo systemctl stop mysql && sudo mv /var/lib/mysql/ /tmp/

sudo mkdir /var/lib/mysql && sudo xtrabackup --copy-back --target-dir=/xbackup/recovery/final

sudo chown -R mysql:mysql /var/lib/mysql
sudo find /var/lib/mysql -type d -exec chmod 750 {} \;

if sudo systemctl is-active --quiet mysql; then
    echo "MySQL is active. Removing old data directory..."
    sudo rm -rf /tmp/mysql/
    sudo rm -rf /xbackup/recovery
    echo "Old data directory removed successfully."
else
    echo "Failed to start MySQL. Old data directory not removed."
fi

echo "><"