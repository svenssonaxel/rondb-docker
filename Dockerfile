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

ENV DATA_DIR=$HOPSWORK_DIR/mysql-cluster
ENV MGMD_DATA_DIR=$DATA_DIR/mgmd
ENV NDBD_DATA_DIR=$DATA_DIR/ndb_data
ENV MYSQLD_DATA_DIR=$DATA_DIR/mysql

RUN mkdir -p $MGMD_DATA_DIR
RUN mkdir -p $NDBD_DATA_DIR
RUN mkdir -p $MYSQLD_DATA_DIR

ENV SCRIPTS_DIR=$DATA_DIR/ndb/scripts
RUN mkdir -p $SCRIPTS_DIR

COPY ./resources/rondb_scripts $SCRIPTS_DIR

RUN touch $DATA_DIR/mysql.sock

RUN groupadd mysql && adduser mysql --ingroup mysql

# RUN chmod -R 755 /var/lib/mysql
# ENV MYSQL_UNIX_PORT /var/lib/mysql/mysql.sock

# we expect this image to be used as base image to other
# images with additional entrypoints
COPY ./resources/entrypoints ./docker_entrypoints/rondb_standalone
RUN chmod +x ./docker_entrypoints/rondb_standalone/*

VOLUME $DATA_DIR/config.ini

ENTRYPOINT ["./docker_entrypoints/rondb_standalone/main.sh"]
EXPOSE 3306 33060 11860 1186
CMD ["mysqld"]
