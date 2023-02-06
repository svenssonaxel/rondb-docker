#!/bin/bash

set -e

echo "[Entrypoint] RonDB Docker Image"

echo "\$@: $@"

# In the case we're running on Linux and the user executing build_run_docker.sh
# is not 1000:1000, we will fail writing files to the host file system. We thereby
# add the mysql user to the group of host user.

# We need to be in the same group as the host to be able to create files
whoami
if [ $(getent group $HOST_GROUP_ID) ]; then
	echo "group $HOST_GROUP_ID exists."
else
	echo "group $HOST_GROUP_ID does not exist."
	groupadd -g $HOST_GROUP_ID host_group_dummy
fi

usermod -g $HOST_GROUP_ID mysql  # Overwrite primary group
usermod -a -G mysql mysql  # Append secondary group
echo "groups mysql: $(groups mysql)"

ls -la ./docker_entrypoints/rondb_standalone
chmod +x ./docker_entrypoints/rondb_standalone/main.sh
echo "PATH: $PATH"
sudo -E -u mysql "$(pwd)/docker_entrypoints/rondb_standalone/main.sh" "$@"
