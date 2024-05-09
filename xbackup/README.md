```bash
# s3 folder structure
S3:
xbackup/
        /
        /
```

```bash
# Local Folder Structure

Local:
xbackup/
|--- 00/ (full backup)
|--- 01/ (inc)
|--- 02/ (inc)

	|-- 00.tar.gz
	|-- 01.tar.gz
```

```bash
# General Idea of backup.sh

Global:
TARGET_DIR: str     # /xbackup


if time == 00:00
folder_name= full_backup()
else:
folder_name=inc_backup()
push_to_s3(folder_name)


def full_backup():
sudo xtrabackup --backup --user=${MYSQL_USER} --password=${MYSQL_PASSWORD} --target-dir=TARGET_DIR/00 --strict --compress --compress-threads=4
return <folder_name: 00>


def inc_backup(hr: current-hour):
sudo xtrabackup --backup --user=${MYSQL_USER} --password=${MYSQL_PASSWORD} --target-dir=TARGET_DIR/<hr> --strict --compress --compress-threads=4 --incremental-basedir=TARGET_DIR/<hr>
return <folder_name: hr>

def push_to_s3(folder_name):
compress_backup_file_name = <folder_name>.tar.gz
final_dest = /<TARGET_DIR>/<compress_backup_file_name>

# compress target-dir
sudo tar -czvf <final_dest> -C /<TARGET_DIR>/<folder_name> .
# put to s3
sudo s3cmd --config=/root/.s3cfg put <final_dest> s3://<bucket-name><final_dest> --encrypt
```

```bash
# General idea of prepare.sh

s3cmd get --recursive s3://<s3_bucket_name>/<target_dir>/ /<target_dir>/recovery

cd /<target_dir>/recovery/

folder_name = ""
base-folder_name = ""

for file in <target_dir>/recovery
  folder_name = file.split(".")[0]
  sudo tar -xzvf file -C ./<folder_name>
  sudo xtrabackup --decompress --target-dir=./<folder_name> --parallel=4 --remove-original
  if (folder_name == 0):
    base_folder_name = <folder_name>
    sudo xtrabackup --prepare --apply-log-only --target-dir=./<folder_name>
  elif (folder_name != 23)
      sudo xtrabackup --prepare --apply-log-only --target-dir=./<base_folder_name> --incremental-dir=./<folder_name>
  else:
    xtrabackup --prepare --target-dir=./<base_folder_name> --incremental-dir=./<folder_name>
```

```bash
# The Backup script along with necessary dependencies will be in docker container handled by docker Daemon
# docker mainly for easier management, resource cleaning and portability purpose

# the docker container will also have prepare script which will handle the downloading of compressed xbackup and preparing it
# the script can be executed via docker exec xbackup /usr/local/bin/prepare.sh
```

```bash
# To apply backup

# docker exec xbackup /usr/local/bin/apply.sh
```

# Points to Consider
* Privileges Required: RELOAD, LOCK TABLES, PROCESS, REPLICATION_CLIENT, SELECT, BACKUP_ADMIN
* Xtrabackup won't allow DDL changes during backup
* Amount of time for one incremental and full backup
* Amount of data change in one hour
* The xtrabackup requires the mysql data-dir access, so it has to be reside along with the mysql

`After considering the above point we can tweak the cron job parameters to decide the frequency of backup`
