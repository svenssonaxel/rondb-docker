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

# Binding current directory to /tmp (read-only)
RUN --mount=type=bind,target=/tmp /tmp/download_rondb.sh -v $RONDB_VERSION -g $GLIBC_VERSION -t $TARGETARCH -o $RONDB_BIN_DIR

# We use symlinks in case we want to exchange binaries
ENV RONDB_BIN_DIR_SYMLINK=$HOPSWORK_DIR/mysql
RUN ln -s $RONDB_BIN_DIR $RONDB_BIN_DIR_SYMLINK
ENV PATH=$RONDB_BIN_DIR_SYMLINK/bin:$PATH
ENV LD_LIBRARY_PATH=$RONDB_BIN_DIR_SYMLINK/lib:$LD_LIBRARY_PATH

RUN groupadd mysql && adduser mysql --ingroup mysql

# RUN chmod -R 755 /var/lib/mysql
# ENV MYSQL_UNIX_PORT /var/lib/mysql/mysql.sock

COPY entrypoints /tmp/entrypoints

ENTRYPOINT ["/tmp/entrypoints/entrypoint.sh"]
HEALTHCHECK CMD /healthcheck.sh
EXPOSE 3306 33060 11860 1186
CMD ["mysqld"]
