
---

# Xbackup

`Xbackup` is a Docker-based backup solution for MySQL databases, utilizing `xtrabackup` for creating backups and `s3cmd` for pushing these backups to Amazon S3. The setup includes incremental and full backups, managed by cron jobs, with configurable parameters for database credentials, S3 credentials, and backup schedules.

## Features

- Full and incremental MySQL backups using `xtrabackup`
- Secure backup storage in Amazon S3
- Configurable backup schedules via cron jobs
- Easy deployment using Docker and Docker Compose

## Prerequisites

- Docker
- Docker Compose
- AWS S3 bucket and credentials

## Installation

1. **Clone the repository:**

    ```bash
    git clone https://github.com/Cosmicoppai/xbackup.git
    cd xbackup
    ```

2. **Configure Environment Variables:**

    Create a `.env` file in the project root and add your configuration:

    ```env
    DB_HOST=your_database_host
    DB_USER=your_database_user
    DB_PASSWORD=your_database_password
    DB_NAME=your_database_name
    S3_ACCESS_KEY=your_s3_access_key
    S3_SECRET_KEY=your_s3_secret_key
    S3_BUCKET=your_s3_bucket_name
    S3_REGION=your_s3_region
    ```

3. **Build and Run the Docker Container:**

    ```bash
    sudo ./init.sh /path/to/backup/volume
    ```

## Usage

The `init.sh` script sets up Docker, installs necessary packages, and configures the backup environment. It will:

1. Install Docker if it's not already installed.
2. Configure the Docker repository and install Docker CE.
3. Start and enable the Docker service.
4. Launch the Docker Compose setup for `xbackup`.

### Backup Scheduling

Backups are managed using cron jobs defined in the `docker-compose.yml` file. Modify the cron job schedule as needed:

Edit the `cron job` time in `.env` file to set your backup schedules:

```cron
CRON_TIME="0 */3 * * *"
```

### Restoring Backups

To restore a backup, download the backup files from S3 and use `xtrabackup` to apply logs and restore the database:

```bash
    sudo docker exec xbackup /usr/local/bin/prepare.sh
```

## Contributing

Feel free to fork this repository and submit pull requests. Contributions are welcome!

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

For any questions or suggestions, feel free to open an issue or contact the repository owner.

---