#!/bin/bash
# Copyright (c) 2017, 2021, Oracle and/or its affiliates.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

set -e

# This script will simply use sed to replace placeholder variables in the
# files in template/ with version-specific variants.

source ./VERSION

REPO=https://repo.mysql.com; [ -n "$1" ] && REPO=$1
REPO_NAME=mysql; [ -n "$2" ] && REPO_NAME=$2

declare -A PASSWORDSET
PASSWORDSET["7.5"]="ALTER USER 'root'@'localhost' IDENTIFIED BY '\${MYSQL_ROOT_PASSWORD}';"
PASSWORDSET["7.6"]=${PASSWORDSET["7.5"]}
PASSWORDSET["8.0"]=${PASSWORDSET["7.6"]}

declare -A DATABASE_INIT
DATABASE_INIT["7.5"]="\"\$@\" --user=\$MYSQLD_USER --initialize-insecure"
DATABASE_INIT["7.6"]="\"\$@\" --user=\$MYSQLD_USER --initialize-insecure"
DATABASE_INIT["8.0"]="\"\$@\" --user=\$MYSQLD_USER --initialize-insecure"

# 5.7+ has the --daemonize flag, which makes the process fork and then exit when
# the server is ready, removing the need for a fragile wait loop
declare -A INIT_STARTUP
INIT_STARTUP["7.5"]="\"\$@\" --user=\$MYSQLD_USER --daemonize --skip-networking --socket=\"\$SOCKET\""
INIT_STARTUP["7.6"]="\"\$@\" --user=\$MYSQLD_USER --daemonize --skip-networking --socket=\"\$SOCKET\""
INIT_STARTUP["8.0"]="\"\$@\" --user=\$MYSQLD_USER --daemonize --skip-networking --socket=\"\$SOCKET\""

declare -A STARTUP
STARTUP["7.5"]="exec \"\$@\" --user=\$MYSQLD_USER"
STARTUP["7.6"]="exec \"\$@\" --user=\$MYSQLD_USER"
STARTUP["8.0"]="export MYSQLD_PARENT_PID=\$\$ ; exec \"\$@\" --user=$MYSQLD_USER"

declare -A STARTUP_WAIT
STARTUP_WAIT["7.5"]="\"\""
STARTUP_WAIT["7.6"]="\"\""


# MySQL 8.0 supports a call to validate the config, while older versions have it as a side
# effect of running --verbose --help
declare -A VALIDATE_CONFIG
VALIDATE_CONFIG["7.5"]="output=\$(\"\$@\" --verbose --help 2>\&1 > /dev/null) || result=\$?"
VALIDATE_CONFIG["7.6"]="output=\$(\"\$@\" --verbose --help 2>\&1 > /dev/null) || result=\$?"
VALIDATE_CONFIG["8.0"]="output=\$(\"\$@\" --validate-config) || result=\$?"

# Data directories that must be created with special ownership and permissions when the image is built
declare -A PRECREATE_DIRS
PRECREATE_DIRS["7.5"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"
PRECREATE_DIRS["7.6"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"
PRECREATE_DIRS["8.0"]="/var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/run/mysqld"

for VERSION in "${!MYSQL_CLUSTER_VERSIONS[@]}"
do
  # Dockerfiles
  MYSQL_CLUSTER_REPOPATH=yum/mysql-$VERSION-community/docker/x86_64
  DOCKERFILE_TEMPLATE=template/Dockerfile
  if [ "${VERSION}" != "8.0" ]; then
    DOCKERFILE_TEMPLATE=template/Dockerfile-pre8
  fi
  sed 's#%%MYSQL_CLUSTER_PACKAGE%%#'"mysql-cluster-community-server-minimal-${MYSQL_CLUSTER_VERSIONS[${VERSION}]}"'#g' $DOCKERFILE_TEMPLATE > tmpfile
  sed -i 's#%%REPO%%#'"${REPO}"'#g' tmpfile
  sed -i 's#%%REPO_NAME%%#'"${REPO_NAME}"'#g' tmpfile
  REPO_VERSION=${VERSION//\./}
  sed -i 's#%%REPO_VERSION%%#'"${REPO_VERSION}"'#g' tmpfile

  if [[ ! -z ${MYSQL_SHELL_VERSIONS[${VERSION}]} ]]; then
    sed -i 's#%%MYSQL_SHELL_PACKAGE%%#'"mysql-shell-${MYSQL_SHELL_VERSIONS[${VERSION}]}"'#g' tmpfile
  else
    sed -i 's#%%MYSQL_SHELL_PACKAGE%%#'""'#g' tmpfile
  fi

  mv tmpfile ${VERSION}/Dockerfile

  # Dockerfile_spec.rb
  if [ ! -d "${VERSION}/inspec" ]; then
    mkdir "${VERSION}/inspec"
  fi
  sed 's#%%MYSQL_CLUSTER_VERSION%%#'"${MYSQL_CLUSTER_VERSIONS[${VERSION}]}"'#g' template/control.rb > tmpFile
  sed -i 's#%%MYSQL_SHELL_VERSION%%#'"${MYSQL_SHELL_VERSIONS[${VERSION}]}"'#g' tmpFile
  sed -i 's#%%MAJOR_VERSION%%#'"${VERSION}"'#g' tmpFile
  mv tmpFile "${VERSION}/inspec/control.rb"

  # Entrypoint
  sed 's#%%PASSWORDSET%%#'"${PASSWORDSET[${VERSION}]}"'#g' template/docker-entrypoint.sh > tmpfile
  sed -i 's#%%DATABASE_INIT%%#'"${DATABASE_INIT[${VERSION}]}"'#g' tmpfile
  sed -i 's#%%INIT_STARTUP%%#'"${INIT_STARTUP[${VERSION}]}"'#g' tmpfile
  sed -i 's#%%STARTUP%%#'"${STARTUP[${VERSION}]}"'#g' tmpfile
  sed -i 's#%%STARTUP_WAIT%%#'"${STARTUP_WAIT[${VERSION}]}"'#g' tmpfile
  sed -i 's#%%FULL_SERVER_VERSION%%#'"${FULL_SERVER_VERSIONS[${VERSION}]}"'#g' tmpfile
  sed -i 's#%%VALIDATE_CONFIG%%#'"${VALIDATE_CONFIG[${VERSION}]}"'#g' tmpfile
  mv tmpfile ${VERSION}/docker-entrypoint.sh
  chmod +x ${VERSION}/docker-entrypoint.sh

  # Healthcheck
  cp template/healthcheck.sh ${VERSION}/
  chmod +x ${VERSION}/healthcheck.sh

  # Build-time preparation script
  sed 's#%%PRECREATE_DIRS%%#'"${PRECREATE_DIRS[${VERSION}]}"'#g' template/prepare-image.sh > tmpfile
  mv tmpfile ${VERSION}/prepare-image.sh
  chmod +x ${VERSION}/prepare-image.sh
done
