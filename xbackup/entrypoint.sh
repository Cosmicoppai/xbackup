#!/usr/bin/env bash

check_mysql_data_dir() {
  if [ ! -d "$DB_DATA_DIR" ]; then
    echo "Error: MySQL data directory $DB_DATA_DIR does not exist."
    exit 1
  fi

  if [ -z "$(ls -A "$DB_DATA_DIR")" ]; then
    echo "Error: MySQL data directory $DB_DATA_DIR is empty."
    exit 1
  fi

  if [ ! -f "$DB_DATA_DIR/ibdata1" ]; then
    echo "Error: Critical file ibdata1 not found in MySQL data directory $DB_DATA_DIR."
    exit 1
  fi

  if [ ! -f "$DB_DATA_DIR/ib_logfile0" ] && [ ! -f "$DB_DATA_DIR/ib_logfile1" ]; then
      echo "Error: No InnoDB redo log files (ib_logfile0, ib_logfile1) found in MySQL data directory $DB_DATA_DIR."
      exit 1
  fi

  if [ ! -d "$DB_DATA_DIR/mysql" ]; then
      echo "Error: MySQL system database directory not found in MySQL data directory $DB_DATA_DIR."
      exit 1
  fi

  echo "MySQL data directory $DB_DATA_DIR is valid and contains the critical file."
}
check_mysql_data_dir

cat << EOF > /root/.s3cfg
[default]
access_key=$S3_ACCESS_KEY
secret_key=$S3_SECRET_KEY
host_base=$S3_ENDPOINT
host_bucket=%(bucket)s.$S3_ENDPOINT
use_https=True
gpg_command=$GPG_PATH
gpg_encrypt=%(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_decrypt=%(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase=$S3_ENCRYPTION_KEY
enable_multipart=True
multipart_chunk_size_mb=$S3_UPLOAD_CHUNK_SIZE
EOF

mkdir -p /var/log

echo "${CRON_TIME} bash /usr/local/bin/backup.sh >> /var/log/cron.log 2>&1" > /etc/cron.d/backup-cron
chmod 0644 /etc/cron.d/backup-cron
crontab /etc/cron.d/backup-cron

export PATH="/percona-xtrabackup-8.0.35-30-Linux-x86_64.glibc2.17/bin:$PATH"
printenv | awk -F= '{print "export " $1"=\""$2"\""}' >> /etc/environments.sh

exec cron -f
