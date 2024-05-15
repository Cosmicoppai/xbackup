#!/usr/bin/env bash

# It will create the backup and upload it to the cloud
# The generic usage will be one daily full backup and incremental backup every x hour

# It will take backup, compress, encrypt and push it

. /etc/environments.sh

TARGET_DIR="/xbackup"
FINAL_DIR="$TARGET_DIR/final"
CPUS=$(nproc)
ROLLING_WINDOW_HR=$((10#${ROLLING_WINDOW_HR:-4}))  # default to 4 if not set
COMPRESS_EXT=".tar.zst"
LATEST_BACKUP_TXT="latest_backup.txt"

total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
# 40% of total memory for xtrabackup
mem_for_xtrabackup_kb=$((total_mem_kb * 30 / 100))
# KB to bytes for xtrabackup usage
MEM_FOR_XBACKUP=$((mem_for_xtrabackup_kb * 1024))

echo "Starting backup with $CPUS CPU cores and $MEM_FOR_XBACKUP KB of memory allocated."


create_dir() {
  local curr_hr=$1

  local backup_dir="$TARGET_DIR/${curr_hr}"
  if [ -d "$backup_dir" ]; then
    echo "Removing old backup of $curr_hr ($backup_dir)"
    rm -rf "${backup_dir:?}/"* || { echo "Failed to remove old backup directory $backup_dir"; return 1; }
  else
    echo "Creating temp dir for $curr_hr"
    mkdir -p "$backup_dir"
  fi

}

full_backup() {
    local curr_hr=$1

    create_dir "$curr_hr"
    if [ $? -ne 0 ]; then
      echo "Failed to create directories for $curr_hr"
      return 1
    fi

    xtrabackup --backup --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASS}" --target-dir=${TARGET_DIR}/"${curr_hr}" --strict --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP
    if [ $? -ne 0 ]; then
      echo "Full backup failed."
      return 1
    fi

    echo "Full backup complete."
    return 0
}

inc_backup() {
    local curr_hr=$1
    local last_successful_backup

    if [ -f "${TARGET_DIR}/${LATEST_BACKUP_TXT}" ]; then
      last_successful_backup=$(cat "${TARGET_DIR}/${LATEST_BACKUP_TXT}")
      last_successful_backup_hr=${last_successful_backup%%_*}

      if [ "$last_successful_backup_hr" -ge "$curr_hr" ]; then
        echo "Last successful backup is ahead of or equal to the current hour. Performing full backup instead."
        full_backup "$curr_hr"
        return $?
      fi
    else
      echo "No last successful backup found. Performing full backup instead."
      full_backup "$curr_hr"
      return $?
    fi

    echo "Performing incremental backup for hour $curr_hr..."

    create_dir "$curr_hr"
    if [ $? -ne 0 ]; then
      echo "Failed to create directories for $curr_hr"
      return 1
    fi

    xtrabackup --backup --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASS}" --target-dir="$backup_dir" --strict --incremental-basedir="${TARGET_DIR}/${last_successful_backup}" --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP

    if [ $? -ne 0 ]; then
      echo "Incremental backup failed."
      return 1
    fi

    echo "Incremental backup complete."
    return 0
}

prepare_and_finalize() {
    local curr_hr=$1
    local prev_hr=$((10#$curr_hr - 1))

    if [[ "$curr_hr" != "00" ]]; then
      if [[ "$curr_hr" == "01" ]]; then
        # if it's first inc backup, run the full backup with apply-log-only
        echo "Preparing base backup with --apply-log-only"
        xtrabackup --prepare --apply-log-only --target-dir="${TARGET_DIR}/00" --strict
      else
        # apply logs of prev hour
        echo "Applying logs of prev hour"
        local prev_inc_dir
        prev_inc_dir="${TARGET_DIR}/$(printf "%02d" "$prev_hr")"
        xtrabackup --prepare --apply-log-only --target-dir="${TARGET_DIR}/00" --incremental-dir="$prev_inc_dir" --parallel="$CPUS" --use-memory=$MEM_FOR_XBACKUP --strict

        if [ $? -eq 0 ]; then
            echo "Applied log of prev hour, deleting incremental dir of prev hour $prev_hr"
            rm -rf "$prev_inc_dir"
        fi
      fi

      if [ $? -ne 0 ]; then
          echo "Failed to apply logs."
          return 1
      fi
    fi

    _final_dir="${FINAL_DIR}/${curr_hr}"
    mkdir -p "${_final_dir}"
    local _inc_final_dir

    # copy the base backup data to final dir, so the further logs can be applied on og full backup
    echo "Copying the base backup data to $_final_dir"
    cp -a "${TARGET_DIR}/00/." "${_final_dir}/"

    # prepare accordingly for 1st and the rest hour
    if [[ "$curr_hr" != "00" ]]; then
      echo "Copying current incremental backup"
      _inc_final_dir="${FINAL_DIR}/${curr_hr}_inc"
      mkdir -p "${_inc_final_dir}"
      cp -a "${TARGET_DIR}/${curr_hr}/." "${_inc_final_dir}/" # as we'll need this inc backup to apply logs during next hour preparation

      # applying curr incremental backup
      echo "Applying current incremental logs"
      xtrabackup --prepare --target-dir="$_final_dir" --incremental-dir="${_inc_final_dir}" --strict
    else
      xtrabackup --prepare --target-dir="$_final_dir" --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP --strict
    fi
    if [ $? -ne 0 ]; then
        echo "Failed to prepare final backup."
        return 1
    fi

    echo "Pushing full backup of $curr_hr"
    push_to_s3 "$curr_hr" "$_final_dir" # "00" /xbackup/final/ (full_backup copy with logs applied)

    if [[ "$curr_hr" != "00" ]]; then
      echo "Pushing incremental backup of $curr_hr"
      push_to_s3 "${curr_hr}_inc" "${_inc_final_dir}"  # curr_hr_inc /xbackup/final/ (inc backup copy)
    fi

    if [ $? -eq 0 ]; then
      clean_old_backups "$curr_hr"

      if [ $? -ne 0 ]; then
        echo "Failed to delete backup of $curr_hr."
        return 1
      fi

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
        echo "Removing compressed and prepared backup"
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
  curr_hr="$1"

  if [ $((10#$curr_hr)) -gt $ROLLING_WINDOW_HR ]; then
    local old_hr
    old_hr=$(printf "%02d" $((10#$curr_hr - $ROLLING_WINDOW_HR)))
    local file_name="${old_hr}${COMPRESS_EXT}"
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
