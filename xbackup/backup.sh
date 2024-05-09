#!/usr/bin/env bash

# It will create the backup and upload it to the cloud
# The generic usage will be one daily full backup and incremental backup every x hour

# It will take backup, compress, encrypt and push it

TARGET_DIR="/xbackup"
FINAL_DIR="$TARGET_DIR/final"
CPUS=$(nproc)
ROLLING_WINDOW_HR=$((10#${ROLLING_WINDOW_HR:-4}))  # default to 4 if not set
COMPRESS_EXT=".tar.zst"
LATEST_BACKUP_TXT="latest_backup.txt"

total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
# 40% of total memory for xtrabackup
mem_for_xtrabackup_kb=$((total_mem_kb * 40 / 100))
# KB to MB for xtrabackup usage
MEM_FOR_XBACKUP=$((mem_for_xtrabackup_kb / 1024))

echo "Starting backup with $CPUS CPU cores and $MEM_FOR_XBACKUP MB of memory allocated."

full_backup() {
    local curr_hr=$1
    echo "Performing full backup... @ $curr_hr"
    mkdir -p "$TARGET_DIR/${curr_hr}"
    xtrabackup --backup --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASS}" --target-dir=${TARGET_DIR}/"${curr_hr}" --strict --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP
    if [ $? -ne 0 ]; then
      echo "Full backup failed."
      return 1
    fi

    echo "Full backup complete."
    return $?
}

inc_backup() {
    local curr_hr=$1
    local prev_hr=$((10#$curr_hr - 1))
    echo "Performing incremental backup for hour $curr_hr..."
    mkdir -p "$TARGET_DIR/${curr_hr}"
    xtrabackup --backup --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASS}" --target-dir=${TARGET_DIR}/"${curr_hr}" --strict --incremental-basedir="${TARGET_DIR}/$(printf "%02d" "$prev_hr")" --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP
    if [ $? -ne 0 ]; then
      echo "Incremental backup failed."
      return 1
    fi

    echo "Incremental backup complete."
    return $?
}

prepare_and_finalize() {
    local curr_hr=$1
    local prev_hr=$((10#$curr_hr - 1))

    if [[ "$curr_hr" != "00" ]]; then
      if [[ "$curr_hr" == "01" ]]; then
        # if it's first inc backup, run the full backup with apply-log-only
        xtrabackup --prepare --apply-log-only --target-dir="${TARGET_DIR}/00" --parallel="$CPUS" --use-memory=$MEM_FOR_XBACKUP --strict
      else
        # apply logs of prev hour
        echo "applying logs of prev hour"
        local prev_inc_dir
        prev_inc_dir="${TARGET_DIR}/$(printf "%02d" "$prev_hr")"
        xtrabackup --prepare --apply-log-only --target-dir="${TARGET_DIR}/00" --incremental-dir="$prev_inc_dir" --parallel="$CPUS" --use-memory=$MEM_FOR_XBACKUP --strict

        if [ $? -eq 0 ]; then
            echo "Applied log of prev hour, deleting incremental dir of prev hour $prev_hr"
#            rm -rf "$prev_inc_dir"
        fi
      fi

      if [ $? -ne 0 ]; then
          echo "Failed to apply logs."
          return 1
      fi
    fi

    _final_dir="$FINAL_DIR/$curr_hr"
    mkdir -p "$_final_dir"

    # copy the data to final dir, so the further logs can be applied on og full backup
    cp -a "$TARGET_DIR/00/." "$_final_dir/"

    # prepare accordingly for 1st and the rest hour
    if [[ "$curr_hr" != "00" ]]; then
      # applying curr incremental backup
      xtrabackup --prepare --target-dir="$_final_dir" --incremental-dir="$TARGET_DIR/$curr_hr" --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP --strict
    else
      xtrabackup --prepare --target-dir="$_final_dir" --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP --strict
    fi
    if [ $? -ne 0 ]; then
        echo "Failed to prepare final backup."
        return 1
    fi

    echo "pushing full backup of $curr_hr"
    push_to_s3 "$curr_hr" "$_final_dir" # "00" /xbackup/final/ (full_backup copy with logs applied)

    if [[ "$curr_hr" != "00" ]]; then
    echo "pushing incremental backup of $curr_hr"
    cp -a "$TARGET_DIR/${curr_hr}/." "$_final_dir/"  # as we'll need this inc backup to apply logs during next hour preparation
    push_to_s3 "${curr_hr}_inc" "$_final_dir"  # curr_hr_inc /xbackup/final/ (inc backup copy)
    fi

    if [ $? -eq 0 ]; then
      clean_old_backups "$curr_hr"
    fi
    return 0
}


push_to_s3() {
    local curr_hr=$1
    local _final_dir=$2
    local compress_backup_file_name="${curr_hr}${COMPRESS_EXT}"  # curr_hr.tar.zst || curr_hr_inc.tar.zst
    local final_dest="${TARGET_DIR}/${compress_backup_file_name}"  # /xbackup/curr_hr.tar.zst || /xbackup/curr_hr_inc.tar.zst

    echo "Compressing backup..."
    tar -cf - -C "${_final_dir}" . | pzstd -o "${final_dest}" -p"${CPUS}" || { echo "Compression failed"; exit 1; }

    echo "Uploading backup to S3 of $curr_hr hr ... with name $compress_backup_file_name"
    s3cmd --config=/root/.s3cfg put "${final_dest}" s3://"${S3_BUCKET}${final_dest}" --encrypt
    if [ $? -eq 0 ]; then
        echo "Upload complete."
        echo "removing compressed and prepared backup"
        rm -rf "$_final_dir"  # remove duplicate backup
        rm "$final_dest"  # remove compressed backup
        echo "$compress_backup_file_name" > "${TARGET_DIR}/${LATEST_BACKUP_TXT}"  # write it to a file, later we'll need it to fetch latest backup
    else
        echo "Upload failed."
        return 1
    fi
    return 0
}

clean_old_backups() {
  curr_hr=$((10#$1))

  if [ $curr_hr -gt $ROLLING_WINDOW_HR ]; then
    local file_name="$((curr_hr - ROLLING_WINDOW_HR))${COMPRESS_EXT}"
    echo "Deleting backup file $file_name..."
    s3cmd --config=/root/.s3cfg del s3://"${S3_BUCKET}${TARGET_DIR}/${file_name}"
  fi
}


perform_backup() {
    case "$1" in
        full)
            full_backup "00" || return
            prepare_and_finalize "00" || return
            ;;
        inc)
            inc_backup "$2" || return
            prepare_and_finalize "$2" || return
            ;;
        *)
            hour=$(date +%H)
              if [ "$hour" -eq "00" ]; then
                  full_backup "$hour" || return
                  folder_name="00"
              else
                  inc_backup "$hour" || return
                  folder_name=$(printf "%02d" "$hour")
              fi
              prepare_and_finalize "$folder_name" || return
            ;;
    esac
}

perform_backup "$1" "$2"
