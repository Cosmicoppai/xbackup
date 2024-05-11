#!/usr/bin/env bash

# $1 -> volume_name
# $2 -> volume_path

sudo apt update && sudo apt install -y apt-transport-https ca-certificates curl software-properties-common lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-cache policy docker-ce
sudo apt install docker-ce -y
sudo systemctl status docker

docker volume create "$1" --opt type=none --opt device="$2" --opt o=bind

export XBACKUP_VOLUME="$2"

docker-compose up -d
