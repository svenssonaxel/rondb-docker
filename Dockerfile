# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM ubuntu:latest

ARG BUILDPLATFORM
ARG TARGETPLATFORM

ARG TARGETARCH
ARG TARGETVARIANT

ARG RONDB_VERSION=21.04.6
ARG GLIBC_VERSION=2.31

RUN echo "Running on $BUILDPLATFORM, building for $TARGETPLATFORM"
RUN echo "TARGETARCH: $TARGETARCH; TARGETVARIANT: $TARGETVARIANT"

RUN apt-get update -y \
    && apt-get install -y wget tar gzip

# we need libssl.so.1.1 & libcrypto.so.1.1 for our binaries;
#   /usr/lib/aarch64-linux-gnu only contains libssl.so,
#   which is from openssl-3.x;
#   to get these libraries, we need to download openssl-1.1.1m;
#   we don't need openssl-1.1.1m itself, only its shared libraries;
#   commands are from https://linuxpip.org/install-openssl-linux/
ENV DOWNLOADED_OPENSSL_PATH=/usr/local/ssl
RUN apt-get update -y \
    && apt-get install -y build-essential checkinstall zlib1g-dev \
    && cd /usr/local/src/ \
    && wget https://www.openssl.org/source/openssl-1.1.1m.tar.gz \
    && tar -xf openssl-1.1.1m.tar.gz \
    && cd openssl-1.1.1m \
    && ./config --prefix=$DOWNLOADED_OPENSSL_PATH --openssldir=$DOWNLOADED_OPENSSL_PATH shared zlib \
    && make \
    && make install 
    # Could also run `make test`
    # `make install` places shared libraries into $DOWNLOADED_OPENSSL_PATH

ENV LD_LIBRARY_PATH=$DOWNLOADED_OPENSSL_PATH/lib/:$LD_LIBRARY_PATH

# Copying Hopsworks cloud environment
ENV HOPSWORK_DIR=/srv/hops
WORKDIR $HOPSWORK_DIR
ENV RONDB_BIN_DIR=$HOPSWORK_DIR/mysql-$RONDB_VERSION

# Downloading RonDB via mounted (read-only) file
RUN --mount=type=bind,source=./download_rondb.sh,target=./down.sh ./down.sh -v $RONDB_VERSION -g $GLIBC_VERSION -t $TARGETARCH -o $RONDB_BIN_DIR

# We use symlinks in case we want to exchange binaries
ENV RONDB_BIN_DIR_SYMLINK=$HOPSWORK_DIR/mysql
RUN ln -s $RONDB_BIN_DIR $RONDB_BIN_DIR_SYMLINK

ENV PATH=$RONDB_BIN_DIR_SYMLINK/bin:$PATH

ENV LD_LIBRARY_PATH=$RONDB_BIN_DIR_SYMLINK/lib:$LD_LIBRARY_PATH
RUN ldconfig --verbose

ENV RONDB_DATA_DIR=$HOPSWORK_DIR/mysql-cluster
ENV MGMD_DATA_DIR=$RONDB_DATA_DIR/mgmd
ENV MYSQLD_DATA_DIR=$RONDB_DATA_DIR/mysql
ENV NDBD_DATA_DIR=$RONDB_DATA_DIR/ndb_data

RUN mkdir -p $MGMD_DATA_DIR
RUN mkdir -p $MYSQLD_DATA_DIR
RUN for i in $(seq 64); do mkdir -p $NDBD_DATA_DIR/$i; done

ENV LOG_DIR=$RONDB_DATA_DIR/log
ENV SCRIPTS_DIR=$RONDB_DATA_DIR/ndb/scripts
ENV BACKUP_DATA_DIR=$RONDB_DATA_DIR/ndb/backups
ENV DISK_COLUMNS_DIR=$RONDB_DATA_DIR/ndb_disk_columns
ENV MYSQL_UNIX_PORT=$RONDB_DATA_DIR/mysql.sock

RUN mkdir -p $LOG_DIR
RUN mkdir -p $SCRIPTS_DIR
RUN mkdir -p $BACKUP_DATA_DIR
RUN mkdir -p $DISK_COLUMNS_DIR

COPY ./resources/rondb_scripts $SCRIPTS_DIR
RUN touch $MYSQL_UNIX_PORT

RUN groupadd mysql && adduser mysql --ingroup mysql
RUN chown mysql:mysql -R .

# RUN chmod -R 755 /var/lib/mysql

# we expect this image to be used as base image to other
# images with additional entrypoints
COPY ./resources/entrypoints ./docker_entrypoints/rondb_standalone
RUN chmod +x ./docker_entrypoints/rondb_standalone/*

USER mysql:mysql

ENTRYPOINT ["./docker_entrypoints/rondb_standalone/main.sh"]
EXPOSE 3306 33060 11860 1186
CMD ["mysqld"]
