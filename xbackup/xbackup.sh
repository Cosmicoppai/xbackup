#!/bin/bash

# Usage: ./xbackup.sh start (assuming .env is set correctly)
#        ./xbackup.sh load
#        ./xbackup.sh apply

perform_backup() {
  sudo ./init.sh
}

prepare_backup() {
    sudo docker exec xbackup /usr/local/bin/prepare.sh
}

apply_backup() {
    sudo ./apply.sh
}

case "$1" in
    "start")
        perform_backup
        ;;
    "load")
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

