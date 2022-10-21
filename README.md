
```bash
# Build and run image in docker-compose (for local platform)
./build_run_docker.sh -v 21.04.6 -g 2.31 -m 1 -d 2 -r 2 -my 1

# Build image:
docker buildx build . --platform=linux/arm64 -t rondb:21.04.6

# Explore image:
docker run --rm -it --entrypoint=/bin/bash rondb:21.04.6
```

Important:

Check memory limits for Docker containers here: https://stackoverflow.com/a/44533437/9068781

Goals:

1. Base image with RonDB installed hopsworks/rondb:21.04.9 (x.y.z)
    - Purpose: basic local testing & building stone for other images
    - No building of RonDB
    - Supporting multiple CPU architectures
    - No ndb-agent; no reconfiguration
    - Push image to hopsworks/mronstro registry
    - Has all directories setup for RonDB; setup like in Hopsworks
    - Is the base-image from which other binaries can be copied into
    - Useable for quick-start of RonDB
    - Should this be ubuntu?
    - Need:
        - all RonDB scripts
        - simple dynamic(?) setup of config.ini
        - proper entrypoints
        - available memory calculation
        - Optional: script to create flexible docker-compose setup

2. Reference in ePipe as base image
    - create builder image to build ePipe itself
    - copy over ePipe binary into hopsworks/rondb

3. Reference in ndb-agent as base image
   - add build-arg "with-rondb"
   - install systemctl
