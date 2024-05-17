#!/usr/bin/env bash

# It will create the backup and upload it to the cloud
# The generic usage will be one daily full backup and incremental backup every x hour

# It will take backup, compress, encrypt and push it

LOCKFILE="/var/run/backup.lock"

if [ -e "$LOCKFILE" ]; then
  echo "Backup script is already running."
  exit 1
fi

touch "$LOCKFILE"

cleanup() {
  rm -f "$LOCKFILE"
}
trap cleanup EXIT

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
      last_successful_backup_hr=$(basename "$last_successful_backup" "${COMPRESS_EXT}")

      if [[ "$last_successful_backup_hr" =~ ^([0-9]{2}) ]]; then
        last_successful_backup_hr="${BASH_REMATCH[1]}"
      else
        echo "Last successful backup hour ($last_successful_backup_hr) is not a valid. Performing full backup instead."
        full_backup "$curr_hr"
        return $?
      fi

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

    echo "Performing incremental backup for hour $curr_hr using inc-base dir as $last_successful_backup_hr ..."

    create_dir "$curr_hr"
    if [ $? -ne 0 ]; then
      echo "Failed to create directories for $curr_hr"
      return 1
    fi

    xtrabackup --backup --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASS}" --target-dir="$TARGET_DIR/$curr_hr" --strict --incremental-basedir="${TARGET_DIR}/${last_successful_backup_hr}" --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP
    if [ $? -ne 0 ]; then
      echo "Incremental backup failed."
      return 1
    fi

    echo "Incremental backup complete."
    return 0
}

prepare_and_finalize() {
    local curr_hr=$1
    local base_backup_dir=""
    local last_successful_inc_hr
    local backup_dirs=()

    while IFS= read -r -d '' dir; do
       dir_basename=$(basename "$dir")
      if [[ "$dir_basename" =~ ^(0[0-9]|1[0-9]|2[0-3])$ ]]; then
        if [[ -z "$base_backup_dir" ]]; then
             base_backup_dir="${dir%/}"
        fi
        if [[ "$(basename "$dir")" -lt "$curr_hr" ]]; then
             last_successful_inc_hr=$(basename "$dir")
        fi
        backup_dirs+=("${dir%/}")
      fi
    done < <(find "${TARGET_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if [[ -z "$base_backup_dir" ]]; then
        echo "No base backup found. Cannot proceed with incremental backup."
        return 1
    fi

    local base_hr=$(basename "$base_backup_dir")

    if [[ "$curr_hr" != "$base_hr" ]]; then
        if [[ "$last_successful_inc_hr" == "$base_hr" ]]; then
            # If it's the first incremental backup, prepare the base backup with --apply-log-only
            echo "Preparing base backup with --apply-log-only"
            xtrabackup --prepare --apply-log-only --target-dir="${base_backup_dir}" --strict --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP
        else
            # Apply logs of the previous hour
            local prev_inc_dir="${TARGET_DIR}/${last_successful_inc_hr}"
            echo "Applying logs of previous hour $last_successful_inc_hr"
            xtrabackup --prepare --apply-log-only --target-dir="${base_backup_dir}" --incremental-dir="${prev_inc_dir}" --strict --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP

            if [ $? -ne 0 ]; then
                echo "Failed to apply logs of $prev_inc_dir."
                return 1
            fi

            echo "Applied logs of $last_successful_inc_hr, deleting incremental dir $prev_inc_dir"
            rm -rf "${prev_inc_dir}"
        fi
    fi

    _final_dir="${FINAL_DIR}/${curr_hr}"
    mkdir -p "${_final_dir}"
    local _inc_final_dir

    # copy the base backup data to final dir, so the further logs can be applied on og full backup
    echo "Copying the base backup data $base_backup_dir to $_final_dir"
    rsync -a -v "${base_backup_dir}/." "${_final_dir}/"

    # prepare accordingly for 1st and the rest hour
    if [[ "$curr_hr" != "$base_hr" ]]; then
      echo "Copying current incremental backup"
      _inc_final_dir="${FINAL_DIR}/${curr_hr}_inc"
      mkdir -p "${_inc_final_dir}"
      rsync -a -v "${TARGET_DIR}/${curr_hr}/." "${_inc_final_dir}/" # as we'll need this inc backup to apply logs during next hour preparation

      # applying curr incremental backup
      echo "Applying current incremental logs"
      xtrabackup --prepare --target-dir="$_final_dir" --incremental-dir="${_inc_final_dir}" --strict --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP
    else
      xtrabackup --prepare --target-dir="$_final_dir" --strict --parallel=$CPUS --use-memory=$MEM_FOR_XBACKUP
    fi
    if [ $? -ne 0 ]; then
        echo "Failed to prepare final backup."
        return 1
    fi

    echo "Pushing full backup of $curr_hr"
    push_to_s3 "$curr_hr" "$_final_dir" # "00" /xbackup/final/ (full_backup copy with logs applied)

    if [[ "$curr_hr" != "$base_hr" ]]; then
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

    echo "Compressing and uploading backup..."
    tar -cf - -C "${_final_dir}" . | pzstd - -p"${CPUS}" | s3cmd --config=/root/.s3cfg put - s3://"${S3_BUCKET}${final_dest}"

    if [ $? -eq 0 ]; then
        echo "Upload complete."
        echo "Removing prepared backup"
        rm -rf "$_final_dir"  # remove duplicate backup
        echo "$compress_backup_file_name" > "${TARGET_DIR}/${LATEST_BACKUP_TXT}"  # write it to a file, later we'll need it to fetch latest backup
    else
        echo "Upload failed."
        return 1
    fi
    return 0
}

clean_old_backups() {
    echo "Removing old backups"

    local s3_backup_list

    s3_backup_list=$(s3cmd --config=/root/.s3cfg ls s3://"${S3_BUCKET}${TARGET_DIR}/" | awk '{print $4}')
    mapfile -t sorted_backup_files < <(echo "$s3_backup_list" | grep -v '_inc' | awk -F'/' '{print $NF, $0}' | sort | awk '{print $2}')

    if [[ ${#sorted_backup_files[@]} -gt $ROLLING_WINDOW_HR ]]; then
        local cutoff_index=$(( ${#sorted_backup_files[@]} - $ROLLING_WINDOW_HR ))
        for ((i=1; i < cutoff_index; i++)); do
            local old_backup_file=${sorted_backup_files[$i]}
            echo "Deleting backup file $old_backup_file..."
            s3cmd --config=/root/.s3cfg del "$old_backup_file"
        done
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
