# RonDB with Docker

This repository creates the possibility of:
- building cross-platform RonDB images
- running local (non-production) RonDB clusters with docker-compose

To learn more about RonDB, have a look [here](rondb.com).

## Quickstart

Dependencies:
- Docker, docker-compose, Docker Buildx

Important:
- The ndbds require a considerable amount of memory; currently it is set as 7GB per data node. To make sure that this amount is actually allocated for the respective containers, run `docker stats` after having started a docker-compose instance. To adjust the allowed memory limits for Docker containers, do as described [here](https://stackoverflow.com/a/44533437/9068781).
- The Docker image downloads the RonDB tarballs from [repo.hops.works](repo.hops.works). These builds specify both the CPU architecture and the **glibc version**, which is why both the script `./build_run_docker.sh` and the Dockerfile require the glibc version as an argument. Simply look at [repo.hops.works](repo.hops.works) to see which RonDB version was built with which glibc version for which CPU architecture.

Commands to run:
```bash
# Build and run image in docker-compose (for local platform)
./build_run_docker.sh -v 21.04.6 -g 2.31 -m 1 -d 2 -r 2 -my 1

# Build cross-platform image:
docker buildx build . --platform=linux/arm64 -t rondb:21.04.6 \
  --build-arg RONDB_VERSION=21.04.6
  --build-arg GLIBC_VERSION=2.31

# Explore image:
docker run --rm -it --entrypoint=/bin/bash rondb:21.04.6
```

Exemplatory commands to run with running docker-compose cluster:
```bash
# Open shell inside a running container
docker exec -it <container-id> /bin/bash

# If inside mgmd container; check the live cluster configuration:
ndb_mgm -e show

# If inside mysqld container; open mysql client:
mysql -uroot
```

## Goals of this repository

1. Create an image with RonDB installed hopsworks/rondb:21.04.9 (x.y.z)
   - Purpose: basic local testing & building stone for other images
   - No building of RonDB itself
   - Supporting multiple CPU architectures
   - No ndb-agent; no reconfiguration / online software upgrades / backups, etc.
   - Push image to hopsworks/mronstro registry
   - Has all directories setup for RonDB; setup like in Hopsworks
   - Is the base-image from which other binaries can be copied into
   - Useable for quick-start of RonDB
   - Need:
     - all RonDB scripts
     - dynamic setup of config.ini/my.cnf
     - dynamic setup of docker-compose file
     - standalone entrypoints

2. Use this image as base image in further private repositories e.g. ndb-agent
   - use this for testing managed RonDB to avoid the necessity of a Hopsworks cluster
   - add build-arg "with-rondb"
   - install other required software there such as systemctl

3. Reference in ePipe as base image
    - create builder image to build ePipe itself
    - copy over ePipe binary into hopsworks/rondb

## TODO

- Add dynamic Docker memory allocation; the more ndbds we have, the more memory each ndbd container requires
- Avoid running everything twice with 2 mysqlds
- Are env files even needed in this image?
  - Add ndb-cluster-connection-pool-nodeids as env to Dockerfile
- Check out whether/how ndb_waiter can be used
  - ndb_waiter --ndb-connectstring=mgm_1:1186
