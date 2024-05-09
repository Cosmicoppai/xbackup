#!/usr/bin/env bash

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

echo "${CRON_TIME} /usr/local/bin/backup.sh >> /var/log/cron.log 2>&1" > /etc/cron.d/backup-cron
chmod 0644 /etc/cron.d/backup-cron
crontab /etc/cron.d/backup-cron

exec cron -f
