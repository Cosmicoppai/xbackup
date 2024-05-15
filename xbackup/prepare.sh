#!/usr/bin/env bash

# It will fetch and decompress the xbackup from the s3

. /etc/environments.sh

S3_TARGET_DIR="xbackup"
TARGET_DIR="/xbackup/recovery"
COMPRESS_EXT=".tar.zst"
LATEST_BACKUP_TXT="latest_backup.txt"


extract_backup() {
    local filename="$1"
    cd "$TARGET_DIR" || { echo "Failed to change directory to $TARGET_DIR"; exit 1; }

    if [ -z "$filename" ]; then  # if filename arg is not there, read from the latest_backup.txt
        if [ ! -f "$LATEST_BACKUP_TXT" ]; then
            echo "Error: File $LATEST_BACKUP_TXT does not exist."
            exit 1
        fi
        filename=$(cat "$LATEST_BACKUP_TXT")
    fi

    if [[ "$filename" != *"$COMPRESS_EXT" ]]; then
        echo "Error: The file name '$filename' does not end with $COMPRESS_EXT."
        exit 1
    fi

    mkdir -p "$TARGET_DIR" || { echo "Failed to create target directory"; exit 1; }

    # download $filename with the same name in $TARGET_DIR
    s3cmd get "s3://$S3_BUCKET/$S3_TARGET_DIR/$filename" "$TARGET_DIR/" || { echo "Failed to download from S3"; exit 1; }

    local final_dest="final"
    mkdir -p "$TARGET_DIR/$final_dest" || { echo "Failed to create folder $final_dest"; exit 1; }

    pzstd -d "$filename" -c -p$(nproc) | tar -xvf - -C "$TARGET_DIR/$final_dest" || { echo "Failed to decompress $filename"; exit 1; }

    echo "Backup extraction completed successfully."
}

extract_backup "$1"
