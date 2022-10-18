#!/bin/bash

set -e

# This script helps us download and install RonDB from repo.hops.works 
# depending on the build platform we are targeting in the Docker image.

function print_usage() {
    cat <<EOF
Usage:
  $0 [-v RONDB_VERSION] [-g GLIBC_VERSION] [-t TARGET_ARCH] [-o OUTPUT_DIR]
EOF
}

NUM_PARAMETERS="$#"
if [ $NUM_PARAMETERS -ne 8 ]; then
    echo "Illegal number of parameters: $NUM_PARAMETERS"
    print_usage
    exit 1
fi

#######################
#### CLI Arguments ####
#######################

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -v | --rondb-version)
        RONDB_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
    -g | --glibc-version)
        GLIBC_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
    -t | --target_arch)
        TARGET_ARCH="$2"
        shift # past argument
        shift # past value
        ;;
    -o | --output-dir)
        OUTPUT_DIR="$2"
        shift # past argument
        shift # past value
        ;;
    *)                     # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift              # past argument
        ;;
    esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

echo "RonDB version                             = ${RONDB_VERSION}"
echo "Glibc version                             = ${GLIBC_VERSION}"
echo "Target architecture                       = ${TARGET_ARCH}"
echo "Output directory                          = ${OUTPUT_DIR}"

echo "PWD                                       = $PWD"

if [[ -n $1 ]]; then
    echo "Last line of file specified as non-opt/last argument:"
    tail -1 "$1"
    exit 1
fi

# Convert this into notation used in URL; ignoring TARGETVARIANT, e.g. arm/v7
if [ "$TARGET_ARCH" = "amd64" ]; then
    TARGETARCH_DOWNLOAD=x86_64
elif [ "$TARGET_ARCH" = "arm64" ]; then
    TARGETARCH_DOWNLOAD=arm64_v8
else
    echo "unsupported target architecture '$TARGET_ARCH'" && exit 1
fi

TARBALL_NAME=rondb-$RONDB_VERSION-linux-glibc$GLIBC_VERSION-$TARGETARCH_DOWNLOAD
echo "Downloading $TARBALL_NAME.tar.gz"

# Install RonDB
wget -q http://repo.hops.works/master/$TARBALL_NAME.tar.gz
tar xfz $TARBALL_NAME.tar.gz
rm $TARBALL_NAME.tar.gz
mv $TARBALL_NAME $OUTPUT_DIR
