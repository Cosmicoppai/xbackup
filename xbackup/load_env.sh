#!/usr/bin/env bash

if [ -f .env ]; then
  echo "Loading environment variables from .env file"
  set -o allexport
  source .env
  set +o allexport
else
  echo ".env file not found!"
  exit 1
fi

required_vars=(DB_HOST DB_DATA_DIR DB_NAME DB_USER DB_PASS CRON_TIME S3_BUCKET S3_REGION S3_ENDPOINT S3_ACCESS_KEY S3_SECRET_KEY S3_ENCRYPTION_KEY S3_UPLOAD_CHUNK_SIZE GPG_PATH ROLLBACK_WINDOW_HR XBACKUP_VOLUME)

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: Environment variable $var is not set!"
    exit 1
  fi
done

get_abs_path() {
  echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
}

if [[ "${DB_DATA_DIR}" != /* ]]; then
  export DB_DATA_DIR=$(get_abs_path "${DB_DATA_DIR}")
fi

if [[ "${XBACKUP_VOLUME}" != /* ]]; then
  export XBACKUP_VOLUME=$(get_abs_path "${XBACKUP_VOLUME}")
fi
