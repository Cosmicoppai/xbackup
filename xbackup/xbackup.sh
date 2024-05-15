#!/bin/bash

# Usage: ./xbackup.sh start (assuming .env is set correctly)
#        ./xbackup.sh load
#        ./xbackup.sh apply
#        ./xbackup.sh logs
#        ./xbackup.sh down


perform_backup() {
  sudo chmod +x ./init.sh
  sudo ./init.sh
}

prepare_backup() {
    sudo docker exec xbackup /usr/local/bin/prepare.sh
}

apply_backup() {
  sudo chmod _x ./apply.sh
  sudo ./apply.sh
}

show_logs() {
  sudo docker compose logs
}

stop() {
  sudo docker compose down
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
    "logs")
        show_logs
        ;;
    "down")
        stop
        ;;
    *)
        echo "Usage: $0 [start|load|apply|logs|down]"
        exit 1
        ;;
esac

