#!/bin/bash
# Copyright (c) 2017, 2021, Oracle and/or its affiliates.
# Copyright (c) 2021, 2021, Hopsworks AB and/or its affiliates.
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

# Let group members access files created by us. This is to allow the host user
# (outside the container) to access mounted volumes. The umask will be inherited
# by child processes, so this is the only place we need to set it.
umask 0002

# https://stackoverflow.com/a/246128/9068781
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ "$1" = 'mysqld' ]; then

	# In order to make use of the umask, we need to set the environment
	# variables that controls the creation file mode for mysqld. These
	# variables are confusingly named UMASK and UMASK_DIR - despite their
	# names, they are used as modes, not masks. The default UMASK and
	# UMASK_DIR values are 0640 and 0750, respectively. We want an effect
	# similar to `chmod g=u`, so we'll set them to 0660 and 0770. The
	# prefixed 0 causes mysqld to interpret these as octal numbers. Note
	# that this configuration does not affect the file creation mode mysqld
	# uses for files containing cryptographic key (*.pem). This only means
	# the host user cannot read private keys, which is not a problem. Since
	# the host user has write permission to all directories, everything can
	# still be deleted.
	export UMASK=0660
	export UMASK_DIR=0770

	"$SCRIPT_DIR/mysqld.sh" "$@"
else
	if [ -n "$MYSQL_INITIALIZE_ONLY" ]; then
		echo "[entrypoints/main.sh] MySQL already initialized and MYSQL_INITIALIZE_ONLY is set, exiting without starting MySQL..."
		exit 0
	fi

	# "set" lets us set the arguments to the current script.
	# the command also has its own commands (see set --help).
	# to avoid accidentally using one of the set-commands,
	# we use "set --" to make clear that everything following
	# this is an argument to the script itself and not the set
	# command.

	set -- "$@" --nodaemon
	if [ "$1" == "ndb_mgmd" ]; then
		echo "[entrypoints/main.sh] Starting ndb_mgmd"
		set -- "$@" -f "$RONDB_DATA_DIR/config.ini" --configdir="$RONDB_DATA_DIR/log"
	elif [ "$1" == "ndbmtd" ]; then

            exit 77

		# ndbmtd has several hard-coded file creation modes that cannot
		# be configured. Permissions can be removed from such hard-coded
		# modes using umask, but there is no way to add permissions to
		# them. As a workaround, this is a very hacky background process
		# that every 5 seconds makes sure that the group's permissions
		# equal the owner's.
		while true; do
			# Find all files owned by the current user, print their
			# modestring and path, null-terminated.
			find /srv/hops/mysql-cluster -user "$USER" -printf '%m %p\0' |
			# Remove all null-terminated items that begin with two
			# equal characters (where the group's permissions
			# already equals the user's) and then remove the
			# modestring.
			sed -zr '/^(.)\1/d; s/^... //;' |
			# xargs: Run chmod with an efficient number of file
			# arguments to correct the group's permissions.
			xargs -r0 chmod -cf g=u ||
			# Make sure the process does not exit due to some
			# failure.
			true
			sleep 5
		done &

		echo "[entrypoints/main.sh] Starting ndbmtd"
		# Command for more verbosity with ndbmtds: `set -- "$@" --verbose=TRUE`
	elif [ "$1" == "ndb_mgm" ]; then
		echo "[entrypoints/main.sh] Starting ndb_mgm"
	fi
	sleep 3600
        exit 0
fi
