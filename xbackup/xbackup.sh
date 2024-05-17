#!/bin/bash

# Usage: ./xbackup.sh start (assuming .env is set correctly)
#        ./xbackup.sh load
#        ./xbackup.sh apply
#        ./xbackup.sh logs
#        ./xbackup.sh stop


perform_backup() {
  sudo chmod +x ./init.sh
  sudo ./init.sh
}

prepare_backup() {
  sudo docker exec xbackup-percona-xtrabackup-1 /usr/local/bin/prepare.sh
}

apply_backup() {
  chmod +x ./load_env.sh && . ./load_env.sh
  sudo systemctl stop mysql && sudo docker exec xbackup-percona-xtrabackup-1 /usr/local/bin/apply.sh && \
  chown -R mysql:mysql "$DB_DATA_DIR" && \
  find "$DB_DATA_DIR" -type d -exec chmod 750 {} \; && \
  sudo systemctl start mysql

  for i in {1..10}; do
    if sudo systemctl is-active --quiet mysql; then
        echo "MySQL is active. Removing old data directory..."
        sudo docker exec xbackup-percona-xtrabackup-1 rm -rf /xbackup/tmp/  # old mysql data
        sudo docker exec xbackup-percona-xtrabackup-1 rm -rf /xbackup/recovery  # data downloaded from s3
        echo "Old data directory removed successfully."
        break
    else
        echo "MySQL not active, sleeping for $i seconds"
        sleep "$i"
    fi
  done

  echo "><"
}

show_logs() {
  sudo docker logs -f xbackup-percona-xtrabackup-1
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
    "stop")
        stop
        ;;
    *)
        echo "Usage: $0 [start|load|apply|logs|stop]"
        exit 1
        ;;
esac
