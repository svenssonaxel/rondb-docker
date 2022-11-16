#!/bin/bash
# Copyright (c) 2017, 2021, Oracle and/or its affiliates.
# Copyright (c) 2021, 2022, Hopsworks AB and/or its affiliates.
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

# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
_get_config() {
    local conf="$1"
    shift
    "$@" --verbose --help 2>/dev/null | grep "^$conf" | awk '$1 == "'"$conf"'" { print $2; exit }'
}

# Make sure that "--defaults-file" is always run as second argument
# Otherwise there is a risk that it might not be read
shift
set -- mysqld --defaults-file=$RONDB_DATA_DIR/my.cnf "$@"
echo "[Entrypoint] \$@: $@"

# Check if entrypoint (and the container) is running as root
if [ $(id --user) = "0" ]; then
    echo "[Entrypoint] We are running as root; setting MYSQLD_USER to 'mysql'"
    is_root=1
    install_devnull="install /dev/null -m0600 -omysql -gmysql"
    MYSQLD_USER=mysql
else
    echo "[Entrypoint] Setting MYSQLD_USER to current non-root user"
    install_devnull="install /dev/null -m0600"
    MYSQLD_USER=$(id --user --name)
fi

# Test that the server can start. We redirect stdout to /dev/null so
# only the error messages are left.
result=0
output=$("$@" --validate-config) || result=$?
if [ ! "$result" = "0" ]; then
    echo >&2 '[Entrypoint] ERROR: Unable to start MySQL. Please check your configuration.'
    echo >&2 "[Entrypoint] $output"
    exit 1
fi
echo "[Entrypoint] The MySQL configuration has been validated"

# Get config
SOCKET="$(_get_config 'socket' "$@")"
echo "SOCKET: $SOCKET"

# If the password variable is a filename we use the contents of the file. We
# read this first to make sure that a proper error is generated for empty files.
if [ -f "$MYSQL_ROOT_PASSWORD" ]; then
    MYSQL_ROOT_PASSWORD="$(cat $MYSQL_ROOT_PASSWORD)"
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        echo >&2 '[Entrypoint] Empty MYSQL_ROOT_PASSWORD file specified.'
        exit 1
    fi
fi

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo >&2 '[Entrypoint] No password option specified for root user.'
fi

echo '[Entrypoint] Initializing database...'

# Technically, specifying the user here is unnecessary since that is
# the default user according to the Dockerfile
"$@" \
    --log-error-verbosity=3 \
    --user=$MYSQLD_USER \
    --initialize-insecure

echo '[Entrypoint] Database initialized'
echo '[Entrypoint] Executing mysqld as daemon with no networking allowed...'

"$@" \
    --user=$MYSQLD_USER \
    --daemonize \
    --skip-networking

echo '[Entrypoint] Successfully executed daemonized mysqld'

echo "[Entrypoint] Pinging mysqld..."
for ping_attempt in {1..30}; do
    if mysqladmin --socket="$SOCKET" ping &>/dev/null; then
        echo "[Entrypoint] Successfully pinged mysqld on attempt $ping_attempt"
        break
    fi
    echo "[Entrypoint] Failed pinging mysqld on attempt $ping_attempt"
    sleep 1
done
if [ "$ping_attempt" = 30 ]; then
    echo >&2 '[Entrypoint] Timeout during MySQL init.'
    exit 1
fi

# To avoid using password on commandline, put it in a temporary file.
# The file is only populated when and if the root password is set.
PASSFILE=$(mktemp -u $MYSQL_FILES_DIR/XXXXXXXXXX)
$install_devnull "$PASSFILE"

# Define the client command used throughout the script
# "SET @@SESSION.SQL_LOG_BIN=0;" is required for products like group replication to work properly
mysql=(mysql --defaults-extra-file="$PASSFILE" --protocol=socket -uroot -hlocalhost --socket="$SOCKET" --init-command="SET @@SESSION.SQL_LOG_BIN=0;")

echo '[Entrypoint] Overwrote the mysql client command for this script'

# TODO: Fix this
echo '[Entrypoint] Running mysql_tzinfo_to_sql /usr/share/zoneinfo | "${mysql[@]}" mysql'
mysql_tzinfo_to_sql /usr/share/zoneinfo | "${mysql[@]}" mysql


echo "[Entrypoint] Deleting unknown users; altering the root user"
"${mysql[@]}" <<-EOSQL
    DELETE FROM mysql.user WHERE user NOT IN ('mysql.infoschema', 'mysql.session', 'mysql.sys', 'root') OR host NOT IN ('localhost');
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
    FLUSH PRIVILEGES;
EOSQL

if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "[Entrypoint] Creating temporary config file with password at '$PASSFILE'"
    cat >"$PASSFILE" <<EOF
[client]
password="${MYSQL_ROOT_PASSWORD}"
EOF
    #mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
fi

# TODO: Consider placing into docker-entrypoint-initdb.d
# Benchmarking table; all other tables will be created by the benchmakrs themselves
echo "CREATE DATABASE IF NOT EXISTS \`dbt2\` ;" | "${mysql[@]}"

if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
    echo "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;" | "${mysql[@]}"

    # TODO: Consider placing into docker-entrypoint-initdb.d
    # Grant MYSQL_USER rights to all benchmarking databases
    echo "GRANT NDB_STORED_USER ON *.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
    echo "GRANT ALL PRIVILEGES ON \`sysbench%\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
    echo "GRANT ALL PRIVILEGES ON \`dbt%\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
    echo "GRANT ALL PRIVILEGES ON \`sbtest%\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"

else
    echo '[Entrypoint] Not creating mysql user. MYSQL_USER and MYSQL_PASSWORD must be specified to do so.'
fi

# TODO: Remove this?
for f in /docker-entrypoint-initdb.d/*; do
    case "$f" in
    *.sh)
        echo "[Entrypoint] running $f"
        . "$f"
        ;;
    *.sql)
        echo "[Entrypoint] running $f"
        "${mysql[@]}" <"$f" && echo
        ;;
    *) echo "[Entrypoint] ignoring $f" ;;
    esac
done

# When using a local socket, mysqladmin shutdown will only complete when the
# server is actually down.
echo '[Entrypoint] Shutting down MySQLd via mysqladmin...'
mysqladmin --defaults-extra-file="$PASSFILE" shutdown -uroot --socket="$SOCKET"
echo "[Entrypoint] Successfully shut down MySQLd"

echo "[Entrypoint] Removing PASSFILE '$PASSFILE'"
rm -f "$PASSFILE"
unset PASSFILE

echo '[Entrypoint] MySQL init process done. Ready for start up.'

echo "[Entrypoint] \$@: $@"
export MYSQLD_PARENT_PID=$$
exec "$@"
