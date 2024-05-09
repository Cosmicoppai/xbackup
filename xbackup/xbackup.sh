#!/bin/bash

# Usage: ./xbackup.sh backup
#        ./xbackup.sh prepare
#        ./xbackup.sh apply

perform_backup() {
  sudo docker-compose up -d
}

prepare_backup() {
    sudo docker exec xbackup /usr/local/bin/prepare.sh
}

# Function to apply backup
apply_backup() {
    sudo ./apply.sh
}

# Check the argument passed and execute corresponding function
case "$1" in
    "backup")
        perform_backup
        ;;
    "prepare")
        prepare_backup
        ;;
    "apply")
        apply_backup
        ;;
    *)
        echo "Usage: $0 [backup|prepare|apply]"
        exit 1
        ;;
esac

