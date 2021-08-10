#!/bin/bash
# Copyright (c) 2018, Oracle and/or its affiliates. All rights reserved.
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

# This script will simply use sed to replace placeholder variables in the
# files in template/ with version-specific variants.

set -e
source VERSION

MAJOR_VERSIONS=("${!MYSQL_CLUSTER_VERSIONS[@]}"); [ -n "$1" ] && MAJOR_VERSIONS=("${@:1}")

for MAJOR_VERSION in "${MAJOR_VERSIONS[@]}"; do
    docker run -d -e MYSQL_RANDOM_ROOT_PASSWORD=true --name "mysql-cluster-$MAJOR_VERSION" "mysql/mysql-cluster:$MAJOR_VERSION" --log-error
    inspec exec --no-color $MAJOR_VERSION/inspec/control.rb --controls container
    inspec exec --no-color $MAJOR_VERSION/inspec/control.rb -t "docker://mysql-cluster-$MAJOR_VERSION" --controls packages
    docker stop "mysql-cluster-$MAJOR_VERSION"
    docker rm "mysql-cluster-$MAJOR_VERSION"
done
