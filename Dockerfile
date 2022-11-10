# syntax=docker/dockerfile:1

# Explaining order of ARGS in Dockerfiles: https://stackoverflow.com/a/53683625/9068781

ARG RONDB_TARBALL_LOCAL_REMOTE

# Download all required Ubuntu dependencies
FROM --platform=$TARGETPLATFORM ubuntu:latest as rondb_runtime_dependencies

ARG BUILDPLATFORM
ARG TARGETPLATFORM

ARG TARGETARCH
ARG TARGETVARIANT

ARG OPEN_SSL_VERSION=1.1.1m

RUN echo "Running on $BUILDPLATFORM, building for $TARGETPLATFORM"
RUN echo "TARGETARCH: $TARGETARCH; TARGETVARIANT: $TARGETVARIANT"

RUN --mount=type=cache,target=/var/cache/apt,id=ubuntu22-apt \
    --mount=type=cache,target=/var/lib/apt/lists,id=ubuntu22-apt-lists \
    apt-get update -y \
    && apt-get install -y wget tar gzip \
    libncurses5 libnuma-dev
    # the last two libraries are required for x86 only

# Creating a cache dir for downloads to avoid redownloading
ENV DOWNLOADS_CACHE_DIR=/tmp/downloads
RUN mkdir $DOWNLOADS_CACHE_DIR

# we need libssl.so.1.1 & libcrypto.so.1.1 for our binaries;
#   /usr/lib/aarch64-linux-gnu only contains libssl.so,
#   which is from openssl-3.x;
#   to get these libraries, we need to download openssl-1.1.1m;
#   we don't need openssl-1.1.1m itself, only its shared libraries;
#   commands are from https://linuxpip.org/install-openssl-linux/
ENV OPENSSL_ROOT=/usr/local/ssl
RUN --mount=type=cache,target=$DOWNLOADS_CACHE_DIR \
    --mount=type=cache,target=/var/cache/apt,id=ubuntu22-apt \
    --mount=type=cache,target=/var/lib/apt/lists,id=ubuntu22-apt-lists \
    apt-get update -y \
    && apt-get install -y build-essential checkinstall zlib1g-dev \
    && wget -N --progress=bar:force -P $DOWNLOADS_CACHE_DIR \
        https://www.openssl.org/source/openssl-$OPEN_SSL_VERSION.tar.gz \
    && tar -xf $DOWNLOADS_CACHE_DIR/openssl-$OPEN_SSL_VERSION.tar.gz -C . \
    && cd openssl-$OPEN_SSL_VERSION \
    && ./config --prefix=$OPENSSL_ROOT --openssldir=$OPENSSL_ROOT shared zlib \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -r openssl-$OPEN_SSL_VERSION
    # Could also run `make test`
    # `make install` places shared libraries into $OPENSSL_ROOT

ENV LD_LIBRARY_PATH=$OPENSSL_ROOT/lib/:$LD_LIBRARY_PATH
RUN ldconfig --verbose

# Get RonDB tarball from local path
FROM rondb_runtime_dependencies as local_tarball
ARG RONDB_TARBALL_URI
COPY $RONDB_TARBALL_URI ./temp_tarball.tar.gz

# Get RonDB tarball from remote url
FROM rondb_runtime_dependencies as remote_tarball
ARG RONDB_TARBALL_URI
RUN wget $RONDB_TARBALL_URI -O ./temp_tarball.tar.gz

FROM ${RONDB_TARBALL_LOCAL_REMOTE}_tarball

ARG RONDB_VERSION=21.04.6

# Copying Hopsworks cloud environment
ENV HOPSWORK_DIR=/srv/hops
ENV RONDB_BIN_DIR=$HOPSWORK_DIR/mysql-$RONDB_VERSION

# Processing tarballs from previous build stage
RUN mkdir -p $RONDB_BIN_DIR
RUN tar xfz ./temp_tarball.tar.gz -C $RONDB_BIN_DIR --strip-components=1
RUN rm ./temp_tarball.tar.gz

WORKDIR $HOPSWORK_DIR

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

ENV MYSQL_FILES_DIR=$RONDB_DATA_DIR/mysql-files
RUN mkdir -p $MYSQL_FILES_DIR

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
