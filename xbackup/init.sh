#!/usr/bin/env bash

run_cmd() {
  echo "[+] $*"
  "$@"
}

if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Proceeding with installation."

  run_cmd sudo apt update
  run_cmd sudo apt install -y apt-transport-https ca-certificates curl software-properties-common lsb-release gnupg

  run_cmd curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  run_cmd sudo tee /etc/apt/sources.list.d/docker.list > /dev/null <<EOF
deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable
EOF

  run_cmd sudo apt update
  run_cmd sudo apt install docker-ce -y

  run_cmd sudo systemctl start docker
  run_cmd sudo systemctl enable docker
else
  echo "Docker is already installed. Skipping installation."
fi

run_cmd sudo systemctl is-active --quiet docker && echo "Docker is running" || echo "Docker is not running :("


if [ -f .env ]; then
  echo "Loading environment variables from .env file"
  set -o allexport
  source .env
  set -o allexport
else
  echo ".env file not found!"
  exit 1
fi

required_vars=(DB_HOST DB_DATA_DIR DB_NAME DB_USER DB_PASS CRON_TIME S3_BUCKET S3_REGION S3_ENDPOINT S3_ACCESS_KEY S3_SECRET_KEY S3_ENCRYPTION_KEY S3_UPLOAD_CHUNK_SIZE GPG_PATH ROLLBACK_WINDOW_HR XBACKUP_VOLUME)

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo $var
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

run_cmd sudo docker compose up -d --build
