#!/usr/bin/env bash

# $1 -> volume_path

run_cmd() {
  echo "+ $*"
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

export XBACKUP_VOLUME="$1"

run_cmd sudo docker compose up -d
