#!/usr/bin/env bash

# It will fetch and decompress the xbackup from the S3

. /etc/environments.sh

S3_TARGET_DIR="xbackup"
DEST_DIR="/xbackup"
TARGET_DIR="/xbackup/recovery"
COMPRESS_EXT=".tar.zst"
LATEST_BACKUP_TXT="latest_backup.txt"

extract_backup() {
    local filename="$1"

    cd "$DEST_DIR" || { echo "Failed to change directory to $DEST_DIR"; exit 1; }

    if [ -z "$filename" ]; then  # if filename arg is not there, read from the latest_backup.txt
        if [ ! -f "$LATEST_BACKUP_TXT" ]; then
            echo "Error: File $LATEST_BACKUP_TXT does not exist."
            exit 1
        fi

        last_successful_backup=$(cat "${DEST_DIR}/${LATEST_BACKUP_TXT}")
        filename=$(basename "$last_successful_backup" "${COMPRESS_EXT}")
        if [[ "$filename" =~ ^([0-9]{2}) ]]; then
            filename="${BASH_REMATCH[1]}"
        else
            echo "Last successful backup hour ($filename) is not valid"
            return 1
        fi
        filename="${filename}${COMPRESS_EXT}"
    fi

    mkdir -p "$TARGET_DIR" || { echo "Failed to create target directory"; exit 1; }

    s3cmd get "s3://$S3_BUCKET/$S3_TARGET_DIR/$filename" "$TARGET_DIR/" || { echo "Failed to download from S3"; exit 1; }

    local downloaded_file="$TARGET_DIR/$filename"
    if [ ! -f "$downloaded_file" ]; then
        echo "Error: The file $downloaded_file does not exist after download."
        exit 1
    fi

    if [ ! -s "$downloaded_file" ]; then
        echo "Error: The downloaded file $downloaded_file is empty."
        exit 1
    fi

    local final_dest="final"
    mkdir -p "$TARGET_DIR/$final_dest" || { echo "Failed to create folder $final_dest"; exit 1; }

    pzstd -d "$downloaded_file" -c -p$(nproc) | tar -xvf - -C "$TARGET_DIR/$final_dest" || { echo "Failed to decompress $filename"; exit 1; }

    echo "Backup extraction completed successfully."
}

extract_backup "$1"
