#!/bin/bash

## This file does the following
## i. Builds the Docker image of RonDB
## i. Generates a config.ini & my.cnf file
## i. Creates docker-compose file
## i. Runs docker-compose
## i. Optionally runs a benchmark

set -e

function print_usage() {
    cat <<EOF
Usage:
  $0    
        [-v         --rondb-version             <string>]
        [-ruri      --rondb-tarball-uri         <string>]
        [-m         --num-mgm-nodes             <int>   ]
        [-d         --num-data-nodes            <int>   ]
        [-r         --replication-factor        <int>   ]
        [-my        --num-mysql-nodes           <int>   ]
        [-a         --num-api-nodes             <int>   ]
        [-b         --run-benchmark             <string>
                        Options: <sysbench_single, sysbench_multi, dbt2_single, dbt2_multi>
                                                        ]
        [-rtarl     --rondb-tarball-is-local            ]
EOF
}

if [ -z "$1" ]; then
    print_usage
    exit 0
fi

#######################
#### CLI Arguments ####
#######################

# Defaults
RONDB_TARBALL_LOCAL_REMOTE=remote
NUM_MGM_NODES=1
NUM_DATA_NODES=1
NUM_MYSQL_NODES=0
NUM_API_NODES=0
REPLICATION_FACTOR=1
RUN_BENCHMARK=

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -v | --rondb-version)
        RONDB_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
    -ruri | --rondb-tarball-uri)
        RONDB_TARBALL_URI="$2"
        shift # past argument
        shift # past value
        ;;
    -m | --num-mgm-nodes)
        NUM_MGM_NODES="$2"
        shift # past argument
        shift # past value
        ;;
    -d | --num-data-nodes)
        NUM_DATA_NODES="$2"
        shift # past argument
        shift # past value
        ;;
    -r | --replication-factor)
        REPLICATION_FACTOR="$2"
        shift # past argument
        shift # past value
        ;;
    -my | --num-mysql-nodes)
        NUM_MYSQL_NODES="$2"
        shift # past argument
        shift # past value
        ;;
    -a | --num-api-nodes)
        NUM_API_NODES="$2"
        shift # past argument
        shift # past value
        ;;

    -b | --run-benchmark)
        RUN_BENCHMARK="$2"
        shift # past argument
        shift # past value
        ;;

    -rtarl | --rondb-tarball-is-local)
        RONDB_TARBALL_LOCAL_REMOTE=local
        shift # past argument
        ;;

    *)                     # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift              # past argument
        ;;
    esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

echo "RonDB version                             = ${RONDB_VERSION}"
echo "RonDB tarball local/remote                = ${RONDB_TARBALL_LOCAL_REMOTE}"
echo "RonDB tarball URI                         = ${RONDB_TARBALL_URI}"
echo "Number of management nodes                = ${NUM_MGM_NODES}"
echo "Number of data nodes                      = ${NUM_DATA_NODES}"
echo "Replication factor                        = ${REPLICATION_FACTOR}"
echo "Number of mysql nodes                     = ${NUM_MYSQL_NODES}"
echo "Number of api nodes                       = ${NUM_API_NODES}"
echo "Run benchmark                             = ${RUN_BENCHMARK}"

if [[ -n $1 ]]; then
    echo "Last line of file specified as non-opt/last argument:"
    tail -1 "$1"
fi

if [ $NUM_MGM_NODES -lt 1 ]; then
    echo "At least 1 mgmd is required"
    exit 1
elif [ $REPLICATION_FACTOR -lt 1 -o $REPLICATION_FACTOR -gt 4 ]; then
    echo "The replication factor has to be >=1 and <5; It is currently $REPLICATION_FACTOR"
    exit 1
elif [ $NUM_DATA_NODES -lt 1 ]; then
    echo "At least 1 ndbd is required"
    exit 1
elif [ -z $RONDB_TARBALL_URI ]; then
    echo "The parameter --rondb-tarball-uri is not optional"
    exit 1
fi

MOD_NDBDS=$(($NUM_DATA_NODES % $REPLICATION_FACTOR))
if [ $MOD_NDBDS -ne 0 ]; then
    echo "The number of data nodes needs to be a multiple of the replication factor"
    exit 1
fi

if [ ! -z $RUN_BENCHMARK ]; then
    if [ "$RUN_BENCHMARK" != "sysbench_single" -a \
        "$RUN_BENCHMARK" != "sysbench_multi" -a \
        "$RUN_BENCHMARK" != "dbt2_single" -a \
        "$RUN_BENCHMARK" != "dbt2_multi" ]; then
        echo "Benchmark has to be one of <sysbench_single, sysbench_multi, dbt2_single, dbt2_multi>"
        exit 1
    elif [ $NUM_API_NODES -lt 1 ]; then
        echo "At least one api is required to run benchmarks"
        exit 1
    elif [ $NUM_MYSQL_NODES -lt 1 ]; then
        echo "At least one mysqld is required to run benchmarks"
        exit 1
    fi

    # This is not a hard requirement, but is better for benchmarking
    # One api container can however also run multiple Sysbench instances against multiple mysqld containers
    if [ "$RUN_BENCHMARK" == "sysbench_multi" ]; then
        if [ $NUM_MYSQL_NODES -lt $NUM_API_NODES ]; then
            echo "For sysbench_multi, there should be at least as many mysqld as api containers"
            exit 1
        fi
    fi

    if [ "$RUN_BENCHMARK" == "sysbench_multi" -o "$RUN_BENCHMARK" == "dbt2_multi" ]; then
        if [ $NUM_MYSQL_NODES -lt 2 ]; then
            echo "At least two mysqlds are required to run the multi-benchmarks"
            exit 1
        fi
    fi

    if [ "$RUN_BENCHMARK" == "dbt2_single" -o "$RUN_BENCHMARK" == "dbt2_multi" ]; then
        if [ $NUM_API_NODES -gt 1 ]; then
            echo "Can only run dbt2 benchmarks with one api container"
            exit 1
        fi
    fi

    # TODO: Make this work with BENCHMARK_SERVERS in sysbench_multi
    if [ $NUM_API_NODES -gt 1 ]; then
        echo "Running more than one api container for Sysbench benchmarks is currently not supported"
        exit 1
    fi
fi

FILE_SUFFIX="v${RONDB_VERSION}_m${NUM_MGM_NODES}_d${NUM_DATA_NODES}_r${REPLICATION_FACTOR}_my${NUM_MYSQL_NODES}_api${NUM_API_NODES}"

# https://stackoverflow.com/a/246128/9068781
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
AUTOGENERATED_FILES_DIR="$SCRIPT_DIR/autogenerated_files/$FILE_SUFFIX"
mkdir -p $AUTOGENERATED_FILES_DIR

DOCKER_COMPOSE_FILEPATH="$AUTOGENERATED_FILES_DIR/docker_compose.yml"
CONFIG_INI_FILEPATH="$AUTOGENERATED_FILES_DIR/config.ini"
MY_CNF_FILEPATH="$AUTOGENERATED_FILES_DIR/my.cnf"

# These directories will be mounted into the api containers
SYSBENCH_SINGLE_DIR="$AUTOGENERATED_FILES_DIR/sysbench_single"
SYSBENCH_MULTI_DIR="$AUTOGENERATED_FILES_DIR/sysbench_multi"
DBT2_SINGLE_DIR="$AUTOGENERATED_FILES_DIR/dbt2_single"
DBT2_MULTI_DIR="$AUTOGENERATED_FILES_DIR/dbt2_multi"

# Otherwise the results will be mounted into a new cluster
rm -rf $SYSBENCH_SINGLE_DIR $DBT2_SINGLE_DIR \
    $SYSBENCH_MULTI_DIR $DBT2_MULTI_DIR

mkdir -p $SYSBENCH_SINGLE_DIR $DBT2_SINGLE_DIR
if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
    mkdir -p $SYSBENCH_MULTI_DIR $DBT2_MULTI_DIR
fi

AUTOBENCH_SYS_SINGLE_FILEPATH="$SYSBENCH_SINGLE_DIR/autobench.conf"
AUTOBENCH_SYS_MULTI_FILEPATH="$SYSBENCH_MULTI_DIR/autobench.conf"
AUTOBENCH_DBT2_SINGLE_FILEPATH="$DBT2_SINGLE_DIR/autobench.conf"
AUTOBENCH_DBT2_MULTI_FILEPATH="$DBT2_MULTI_DIR/autobench.conf"

#######################
#######################
#######################

echo "Building RonDB Docker image for local platform"

RONDB_IMAGE_NAME="rondb-standalone:$RONDB_VERSION"
docker buildx build . \
    --tag $RONDB_IMAGE_NAME \
    --build-arg RONDB_VERSION=$RONDB_VERSION \
    --build-arg RONDB_TARBALL_LOCAL_REMOTE=$RONDB_TARBALL_LOCAL_REMOTE \
    --build-arg RONDB_TARBALL_URI=$RONDB_TARBALL_URI

#######################
#######################
#######################

echo "Loading templates"

CONFIG_INI_TEMPLATE=$(cat ./resources/config_templates/config.ini)
CONFIG_INI_MGMD_TEMPLATE=$(cat ./resources/config_templates/config_mgmd.ini)
CONFIG_INI_NDBD_TEMPLATE=$(cat ./resources/config_templates/config_ndbd.ini)
CONFIG_INI_MYSQLD_TEMPLATE=$(cat ./resources/config_templates/config_mysqld.ini)
CONFIG_INI_API_TEMPLATE=$(cat ./resources/config_templates/config_api.ini)

MY_CNF_TEMPLATE=$(cat ./resources/config_templates/my.cnf)

AUTOBENCH_DBT2_TEMPLATE=$(cat ./resources/config_templates/autobench_dbt2.conf)
AUTOBENCH_SYSBENCH_TEMPLATE=$(cat ./resources/config_templates/autobench_sysbench.conf)

# Doing restart on-failure for the agent upgrade; we return a failure there
RONDB_DOCKER_COMPOSE_TEMPLATE="

    <insert-service-name>:
      image: $RONDB_IMAGE_NAME
      container_name: <insert-service-name>
"

VOLUMES_FIELD="
      volumes:"

ENV_FIELD="
      environment:"

# We add volumes to the data dir for debugging purposes
ENV_VAR_TEMPLATE="
      - %s=%s"

# Bind config.ini to mgmd containers
BIND_CONFIG_INI_TEMPLATE="
      - type: bind
        source: $CONFIG_INI_FILEPATH
        target: /srv/hops/mysql-cluster/config.ini"

# Bind my.cnf to mysqld containers
BIND_MY_CNF_TEMPLATE="
      - type: bind
        source: $MY_CNF_FILEPATH
        target: /srv/hops/mysql-cluster/my.cnf"

### Bind benchmarking directories to api containers ###

BIND_SYS_SINGLE_DIR="
      - type: bind
        source: $SYSBENCH_SINGLE_DIR
        target: /home/mysql/benchmarks/sysbench_single"

BIND_SYS_MULTI_DIR="
      - type: bind
        source: $SYSBENCH_MULTI_DIR
        target: /home/mysql/benchmarks/sysbench_multi"

BIND_DBT2_SINGLE_DIR="
      - type: bind
        source: $DBT2_SINGLE_DIR
        target: /home/mysql/benchmarks/dbt2_single"

BIND_DBT2_MULTI_DIR="
      - type: bind
        source: $DBT2_MULTI_DIR
        target: /home/mysql/benchmarks/dbt2_multi"

# We add volumes to the data dir for debugging purposes
VOLUME_DATA_DIR_TEMPLATE="
      - %s:/srv/hops/mysql-cluster/%s"

VOLUME_BENCHMARKING_TEMPLATE="
      - %s:/home/mysql/benchmarks/%s"

COMMAND_TEMPLATE="
      command: %s"

#######################
#######################
#######################

echo "Filling out templates"

source $SCRIPT_DIR/docker.env
source $SCRIPT_DIR/misc_configs.env
CONFIG_INI=$(printf "$CONFIG_INI_TEMPLATE" "$REPLICATION_FACTOR")
MGM_CONNECTION_STRING=''
SINGLE_MYSQLD_IP=''
MULTI_MYSQLD_IPS=''

# TODO: Use this for BENCHMARK_SERVERS in Sysbench
SINGLE_API_IP=''
MULTI_API_IPS=''

VOLUMES=()
BASE_DOCKER_COMPOSE_FILE="version: '3.8'

services:"

for CONTAINER_NUM in $(seq $NUM_MGM_NODES); do
    NODE_ID=$((65 + $(($CONTAINER_NUM - 1))))

    template="$RONDB_DOCKER_COMPOSE_TEMPLATE"
    SERVICE_NAME="mgmd_$CONTAINER_NUM"
    template=$(echo "$template" | sed "s/<insert-service-name>/$SERVICE_NAME/g")
    command=$(printf "$COMMAND_TEMPLATE" "[\"ndb_mgmd\", \"--ndb-nodeid=$NODE_ID\", \"--initial\"]")
    template+="$command"

    template+="
      deploy:
        resources:
          limits:
            cpus: '$MGMD_CPU_LIMIT'
            memory: $MGMD_MEMORY_LIMIT
          reservations:
            memory: $MGMD_MEMORY_RESERVATION"

    template+="$VOLUMES_FIELD"
    template+="$BIND_CONFIG_INI_TEMPLATE"

    VOLUME_NAME="dataDir_$SERVICE_NAME"
    volume=$(printf "$VOLUME_DATA_DIR_TEMPLATE" "$VOLUME_NAME" "mgmd")
    template+="$volume"
    VOLUMES+=("$VOLUME_NAME")

    VOLUME_NAME="logDir_$SERVICE_NAME"
    volume=$(printf "$VOLUME_DATA_DIR_TEMPLATE" "$VOLUME_NAME" "log")
    template+="$volume"
    VOLUMES+=("$VOLUME_NAME")

    BASE_DOCKER_COMPOSE_FILE+="$template"

    # NodeId, HostName, PortNumber, NodeActive, ArbitrationRank
    SLOT=$(printf "$CONFIG_INI_MGMD_TEMPLATE" "$NODE_ID" "$SERVICE_NAME" "1186" "1" "2")
    CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")

    MGM_CONNECTION_STRING+="$SERVICE_NAME:1186,"
done
# Remove last comma from MGM_CONNECTION_STRING
MGM_CONNECTION_STRING=${MGM_CONNECTION_STRING%?}

# We're not bothering with inactive ndbds here
NUM_NODE_GROUPS=$(($NUM_DATA_NODES / $REPLICATION_FACTOR))
for CONTAINER_NUM in $(seq $NUM_DATA_NODES); do
    NODE_ID=$CONTAINER_NUM

    template="$RONDB_DOCKER_COMPOSE_TEMPLATE"
    SERVICE_NAME="ndbd_$CONTAINER_NUM"
    template=$(echo "$template" | sed "s/<insert-service-name>/$SERVICE_NAME/g")
    command=$(printf "$COMMAND_TEMPLATE" "[\"ndbmtd\", \"--ndb-nodeid=$NODE_ID\", \"--initial\", \"--ndb-connectstring=$MGM_CONNECTION_STRING\"]")
    template+="$command"

    template+="
      deploy:
        resources:
          limits:
            cpus: '$NDBD_CPU_LIMIT'
            memory: $NDBD_MEMORY_LIMIT
          reservations:
            memory: $NDBD_MEMORY_RESERVATION"

    template+="$VOLUMES_FIELD"

    VOLUME_NAME="dataDir_$SERVICE_NAME"
    volume=$(printf "$VOLUME_DATA_DIR_TEMPLATE" "$VOLUME_NAME" "ndb_data")
    template+="$volume"
    VOLUMES+=("$VOLUME_NAME")

    VOLUME_NAME="logDir_$SERVICE_NAME"
    volume=$(printf "$VOLUME_DATA_DIR_TEMPLATE" "$VOLUME_NAME" "log")
    template+="$volume"
    VOLUMES+=("$VOLUME_NAME")

    BASE_DOCKER_COMPOSE_FILE+="$template"

    NODE_GROUP=$(($CONTAINER_NUM % $NUM_NODE_GROUPS))
    # NodeId, NodeGroup, NodeActive, HostName, ServerPort, FileSystemPath (NodeId)
    SLOT=$(printf "$CONFIG_INI_NDBD_TEMPLATE" "$NODE_ID" "$NODE_GROUP" "1" "$SERVICE_NAME" "11860" "$NODE_ID")
    CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")
done

if [ $NUM_MYSQL_NODES -gt 0 ]; then
    for CONTAINER_NUM in $(seq $NUM_MYSQL_NODES); do
        template="$RONDB_DOCKER_COMPOSE_TEMPLATE"
        SERVICE_NAME="mysqld_$CONTAINER_NUM"
        template=$(echo "$template" | sed "s/<insert-service-name>/$SERVICE_NAME/g")
        command=$(printf "$COMMAND_TEMPLATE" "[\"mysqld\"]")
        template+="$command"

        # Make sure these memory boundaries are allowed in Docker settings!
        # To check whether they are being used use `docker stats`
        template+="
      deploy:
        resources:
          limits:
            cpus: '$MYSQLD_CPU_LIMIT'
            memory: $MYSQLD_MEMORY_LIMIT
          reservations:
            memory: $MYSQLD_MEMORY_RESERVATION"

        template+="$VOLUMES_FIELD"
        template+="$BIND_MY_CNF_TEMPLATE"

        VOLUME_NAME="dataDir_$SERVICE_NAME"
        volume=$(printf "$VOLUME_DATA_DIR_TEMPLATE" "$VOLUME_NAME" "mysql")
        template+="$volume"
        VOLUMES+=("$VOLUME_NAME")

        # This is for debugging
        VOLUME_NAME="mysqlFilesDir_$SERVICE_NAME"
        volume=$(printf "$VOLUME_DATA_DIR_TEMPLATE" "$VOLUME_NAME" "mysql-files")
        template+="$volume"
        VOLUMES+=("$VOLUME_NAME")

        # Can add the following env vars to the mysqld containers:
        # MYSQL_ROOT_PASSWORD
        # MYSQL_DATABASE

        template+="$ENV_FIELD"
        env_var=$(printf "$ENV_VAR_TEMPLATE" "MYSQL_ALLOW_EMPTY_PASSWORD" "true")
        template+="$env_var"
        env_var=$(printf "$ENV_VAR_TEMPLATE" "MYSQL_USER" "$MYSQL_USER")
        template+="$env_var"
        env_var=$(printf "$ENV_VAR_TEMPLATE" "MYSQL_PASSWORD" "$MYSQL_PASSWORD")
        template+="$env_var"
        if [ $CONTAINER_NUM -eq 1 ]; then
            # Only need one mysqld to setup databases, users, etc.
            env_var=$(printf "$ENV_VAR_TEMPLATE" "MYSQL_SETUP_APP" "1")
            template+="$env_var"
        fi

        BASE_DOCKER_COMPOSE_FILE+="$template"

        NODE_ID_OFFSET=$(($((CONTAINER_NUM - 1)) * $MYSQLD_SLOTS_PER_CONTAINER))
        for SLOT_NUM in $(seq $MYSQLD_SLOTS_PER_CONTAINER); do
            NODE_ID=$((67 + $NODE_ID_OFFSET + $(($SLOT_NUM - 1))))
            # NodeId, NodeActive, ArbitrationRank, HostName
            SLOT=$(printf "$CONFIG_INI_MYSQLD_TEMPLATE" "$NODE_ID" "1" "1" "$SERVICE_NAME")
            CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")
        done

        MULTI_MYSQLD_IPS+="$SERVICE_NAME;"
        if [ $CONTAINER_NUM -eq 1 ]; then
            SINGLE_MYSQLD_IP+="$SERVICE_NAME"
        fi
    done
fi
# Remove last semi-colon from MULTI_MYSQLD_IPS
MULTI_MYSQLD_IPS=${MULTI_MYSQLD_IPS%?}

if [ $NUM_API_NODES -gt 0 ]; then
    for CONTAINER_NUM in $(seq $NUM_API_NODES); do
        template="$RONDB_DOCKER_COMPOSE_TEMPLATE"
        SERVICE_NAME="api_$CONTAINER_NUM"
        template=$(echo "$template" | sed "s/<insert-service-name>/$SERVICE_NAME/g")

        if [ -z $RUN_BENCHMARK ]; then
            # Simply keep the API container running, so we can run benchmarks manually
            command=$(printf "$COMMAND_TEMPLATE" "bash -c \"tail -F anything\"")
        else
            # Use the ndb_waiter to wait until RonDB has started before running benchmark
            # Added extra sleep for mysqlds; may have to increase this
            command=$(printf "$COMMAND_TEMPLATE" ">
          bash -c \"ndb_waiter --ndb-connectstring=$MGM_CONNECTION_STRING &&
                    sleep 25 &&
                    bench_run.sh --verbose --default-directory /home/mysql/benchmarks/$RUN_BENCHMARK\"")
        fi

        template+="$command"

        # Make sure these memory boundaries are allowed in Docker settings!
        # To check whether they are being used use `docker stats`
        template+="
      deploy:
        resources:
          limits:
            cpus: '$API_CPU_LIMIT'
            memory: $API_MEMORY_LIMIT
          reservations:
            memory: $API_MEMORY_RESERVATION"

        template+="$VOLUMES_FIELD"
        if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
            template+="$BIND_SYS_SINGLE_DIR"
            template+="$BIND_DBT2_SINGLE_DIR"
            if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
                template+="$BIND_SYS_MULTI_DIR"
                template+="$BIND_DBT2_MULTI_DIR"
            fi
        fi

        template+="$ENV_FIELD"
        env_var=$(printf "$ENV_VAR_TEMPLATE" "MYSQL_PASSWORD" "$MYSQL_PASSWORD")
        template+="$env_var"

        BASE_DOCKER_COMPOSE_FILE+="$template"

        NODE_ID_OFFSET=$(($((CONTAINER_NUM - 1)) * $API_SLOTS_PER_CONTAINER))
        for SLOT_NUM in $(seq $API_SLOTS_PER_CONTAINER); do
            NODE_ID=$((195 + $NODE_ID_OFFSET + $(($SLOT_NUM - 1))))
            # NodeId, NodeActive, ArbitrationRank, HostName
            SLOT=$(printf "$CONFIG_INI_API_TEMPLATE" "$NODE_ID" "1" "1" "$SERVICE_NAME")
            CONFIG_INI=$(printf "%s\n\n%s" "$CONFIG_INI" "$SLOT")
        done

        MULTI_API_IPS+="$SERVICE_NAME;"
        if [ $CONTAINER_NUM -eq 1 ]; then
            SINGLE_API_IP+="$SERVICE_NAME"
        fi
    done
fi
# Remove last semi-colon from MULTI_API_IPS
MULTI_API_IPS=${MULTI_API_IPS%?}

# Append volumes to end of file
BASE_DOCKER_COMPOSE_FILE+="

volumes:"

for VOLUME in "${VOLUMES[@]}"; do
    BASE_DOCKER_COMPOSE_FILE+="
    $VOLUME:"
done

BASE_DOCKER_COMPOSE_FILE+="
"

#######################
#######################
#######################

echo "Writing data to files"

if [ "$NUM_MYSQL_NODES" -gt 0 ]; then
    echo "Writing my.cnf"
    MY_CNF=$(printf "$MY_CNF_TEMPLATE" "$MYSQLD_SLOTS_PER_CONTAINER" "$MGM_CONNECTION_STRING")
    echo "$MY_CNF" >$MY_CNF_FILEPATH

    if [ "$NUM_API_NODES" -gt 0 ]; then
        echo "Writing benchmarking files for single mysqlds"

        # This will always have 1 api and 1 mysqld container, and 1 Sysbench instance
        AUTOBENCH_SYSBENCH_SINGLE=$(printf "$AUTOBENCH_SYSBENCH_TEMPLATE" \
            "$SINGLE_MYSQLD_IP" "$MYSQL_USER" "$MYSQL_PASSWORD" \
            "$MYSQLD_SLOTS_PER_CONTAINER" "$MGM_CONNECTION_STRING" \
            "1")
        echo "$AUTOBENCH_SYSBENCH_SINGLE" >$AUTOBENCH_SYS_SINGLE_FILEPATH

        AUTOBENCH_DBT2_SINGLE=$(printf "$AUTOBENCH_DBT2_TEMPLATE" \
            "$SINGLE_MYSQLD_IP" "$MYSQL_USER" "$MYSQL_PASSWORD" \
            "$MYSQLD_SLOTS_PER_CONTAINER" "$MGM_CONNECTION_STRING")
        echo "$AUTOBENCH_DBT2_SINGLE" >$AUTOBENCH_DBT2_SINGLE_FILEPATH

        if [ "$NUM_MYSQL_NODES" -gt 1 ]; then
            echo "Writing benchmarking files for multiple mysqlds"

            AUTOBENCH_SYSBENCH_MULTI=$(printf "$AUTOBENCH_SYSBENCH_TEMPLATE" \
                "$MULTI_MYSQLD_IPS" "$MYSQL_USER" "$MYSQL_PASSWORD" \
                "$MYSQLD_SLOTS_PER_CONTAINER" "$MGM_CONNECTION_STRING" \
                "$NUM_MYSQL_NODES")
            echo "$AUTOBENCH_SYSBENCH_MULTI" >$AUTOBENCH_SYS_MULTI_FILEPATH

            AUTOBENCH_DBT2_MULTI=$(printf "$AUTOBENCH_DBT2_TEMPLATE" \
                "$MULTI_MYSQLD_IPS" "$MYSQL_USER" "$MYSQL_PASSWORD" \
                "$MYSQLD_SLOTS_PER_CONTAINER" "$MGM_CONNECTION_STRING")
            echo "$AUTOBENCH_DBT2_MULTI" >$AUTOBENCH_DBT2_MULTI_FILEPATH
        fi
    fi
fi

echo "$BASE_DOCKER_COMPOSE_FILE" >$DOCKER_COMPOSE_FILEPATH
echo "$CONFIG_INI" >$CONFIG_INI_FILEPATH

# Remove previous volumes
docker-compose -f $DOCKER_COMPOSE_FILEPATH -p "rondb_$FILE_SUFFIX" down -v
# Run fresh setup
docker-compose -f $DOCKER_COMPOSE_FILEPATH -p "rondb_$FILE_SUFFIX" up
