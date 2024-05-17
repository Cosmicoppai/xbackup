#!/usr/bin/env bash
# It will copy/move the prepared backup in data dir of mysql
##❣️ Don't forget to run ./prepare.sh prior running this file

. /etc/environments.sh

mv "$DB_DATA_DIR" /xbackup/tmp

mkdir -p "$DB_DATA_DIR" && xtrabackup --copy-back --target-dir=/xbackup/recovery/final --datadir="$DB_DATA_DIR"