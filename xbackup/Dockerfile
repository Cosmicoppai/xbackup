FROM ubuntu:22.04

USER root

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y wget lsb-release curl cron s3cmd perl libdbd-mysql-perl gnupg zstd && \
    wget https://downloads.percona.com/downloads/Percona-XtraBackup-8.0/Percona-XtraBackup-8.0.35-30/binary/tarball/percona-xtrabackup-8.0.35-30-Linux-x86_64.glibc2.17.tar.gz && \
    tar -xvf percona-xtrabackup-8.0.35-30-Linux-x86_64.glibc2.17.tar.gz && \
    chmod +x /percona-xtrabackup-8.0.35-30-Linux-x86_64.glibc2.17/bin/xtrabackup && \
    echo 'export PATH="/percona-xtrabackup-8.0.35-30-Linux-x86_64.glibc2.17/bin:$PATH"' >> ~/.bashrc && \
    source ~/.bashrc && \
    echo xtrabackup --version && \
    rm -rf /var/lib/apt/lists/* && rm percona-xtrabackup-8.0.35-30-Linux-x86_64.glibc2.17.tar.gz

COPY entrypoint.sh /entrypoint.sh
COPY backup.sh /usr/local/bin/backup.sh
COPY prepare.sh /usr/local/bin/prepare.sh

RUN mkdir -p /xbackup/ /etc/cron.d /var/log && \
    chmod +x /usr/local/bin/backup.sh /usr/local/bin/prepare.sh /entrypoint.sh

ENV PATH="/percona-xtrabackup-8.0.35-30-Linux-x86_64.glibc2.17/bin:$PATH"

ENTRYPOINT ["/entrypoint.sh"]