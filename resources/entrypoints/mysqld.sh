set -e

# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
_get_config() {
	local conf="$1"; shift
	"$@" --verbose --help 2>/dev/null | grep "^$conf" | awk '$1 == "'"$conf"'" { print $2; exit }'
}

# Generate a random password
_mkpw() {
	letter=$(cat /dev/urandom| tr -dc a-zA-Z | dd bs=1 count=16 2> /dev/null )
	number=$(cat /dev/urandom| tr -dc 0-9 | dd bs=1 count=8 2> /dev/null)
	special=$(cat /dev/urandom| tr -dc '=+@#%^&*_.,;:?/' | dd bs=1 count=8 2> /dev/null)

	echo $letter$number$special | fold -w 1 | shuf | tr -d '\n'
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

if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
    echo >&2 '[Entrypoint] No password option specified for new database.'
    echo >&2 '[Entrypoint] A random onetime password will be generated.'
    MYSQL_RANDOM_ROOT_PASSWORD=true
    MYSQL_ONETIME_PASSWORD=true
fi

if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
    MYSQL_ROOT_PASSWORD="$(_mkpw)"
    echo "[Entrypoint] Generated a random MySQL root password"
fi

echo '[Entrypoint] Initializing database...'

"$@" \
    --log-error-verbosity=3 \
    --user=$MYSQLD_USER  \
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
mysql=( mysql --defaults-extra-file="$PASSFILE" --protocol=socket -uroot -hlocalhost --socket="$SOCKET" --init-command="SET @@SESSION.SQL_LOG_BIN=0;")

echo '[Entrypoint] Overwrote the mysql client command for this script'

# TODO: Fix this
echo '[Entrypoint] Running mysql_tzinfo_to_sql /usr/share/zoneinfo | "${mysql[@]}" mysql'
mysql_tzinfo_to_sql /usr/share/zoneinfo | "${mysql[@]}" mysql

if [ -z "$MYSQL_ROOT_HOST" ]; then
    ALTER_ROOT_USER="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
else
    ALTER_ROOT_USER="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; \
    CREATE USER 'root'@'${MYSQL_ROOT_HOST}' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; \
    GRANT ALL ON *.* TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ; \
    GRANT PROXY ON ''@'' TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ;"
fi

echo "[Entrypoint] Deleting unknown users; altering the root user; creating a healthchecker user"
"${mysql[@]}" <<-EOSQL
    DELETE FROM mysql.user WHERE user NOT IN ('mysql.infoschema', 'mysql.session', 'mysql.sys', 'root') OR host NOT IN ('localhost');
    CREATE USER 'healthchecker'@'localhost' IDENTIFIED BY 'healthcheckpass';
    ${ALTER_ROOT_USER}
    FLUSH PRIVILEGES ;
EOSQL

if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "[Entrypoint] Creating temporary config file with password at '$PASSFILE'"
    cat >"$PASSFILE" <<EOF
[client]
password="${MYSQL_ROOT_PASSWORD}"
EOF
    #mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
fi

if [ "$MYSQL_DATABASE" ]; then
    echo "[Entrypoint] Creating MYSQL_DATABASE: $MYSQL_DATABASE"
    echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
    mysql+=( "$MYSQL_DATABASE" )
fi

if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
    echo "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;" | "${mysql[@]}"
    if [ "$MYSQL_DATABASE" ]; then
        echo "GRANT ALL ON \`"$MYSQL_DATABASE"\`.* TO '"$MYSQL_USER"'@'%' ;" | "${mysql[@]}"
    fi
else
    echo '[Entrypoint] Not creating mysql user. MYSQL_USER and MYSQL_PASSWORD must be specified to do so.'
fi

# TODO: Remove this?
for f in /docker-entrypoint-initdb.d/*; do
    case "$f" in
        *.sh)  echo "[Entrypoint] running $f"; . "$f" ;;
        *.sql) echo "[Entrypoint] running $f"; "${mysql[@]}" < "$f" && echo ;;
        *)     echo "[Entrypoint] ignoring $f" ;;
    esac
done

# When using a local socket, mysqladmin shutdown will only complete when the 
# server is actually down.
echo '[Entrypoint] Shutting down MySQLd via mysqladmin...'
mysqladmin --defaults-extra-file="$PASSFILE" shutdown -uroot --socket="$SOCKET"
rm -f "$PASSFILE"
unset PASSFILE
echo "[Entrypoint] Successfully shut down MySQLd"

# This needs to be done outside the normal init, since mysqladmin shutdown will not work after
if [ ! -z "$MYSQL_ONETIME_PASSWORD" ]; then
    if [ -z %%EXPIRE_SUPPORT%% ]; then
        echo "[Entrypoint] User expiration is only supported in MySQL 5.6+"
    else
        echo "[Entrypoint] Setting root user as expired. Password will need to be changed before database can be used."
        SQL=$(mktemp -u $MYSQL_FILES_DIR/XXXXXXXXXX)
        $install_devnull "$SQL"
        if [ ! -z "$MYSQL_ROOT_HOST" ]; then
            cat << EOF > "$SQL"
ALTER USER 'root'@'${MYSQL_ROOT_HOST}' PASSWORD EXPIRE;
ALTER USER 'root'@'localhost' PASSWORD EXPIRE;
EOF
        else
            cat << EOF > "$SQL"
ALTER USER 'root'@'localhost' PASSWORD EXPIRE;
EOF
        fi
        set -- "$@" --init-file="$SQL"
        unset SQL
    fi
fi

echo '[Entrypoint] MySQL init process done. Ready for start up.'

# Used by healthcheck to make sure it doesn't mistakenly report container
# healthy during startup
# Put the password into the temporary config file
touch $MYSQL_FILES_DIR/healthcheck.cnf
cat >"$MYSQL_FILES_DIR/healthcheck.cnf" <<EOF
[client]
user=healthchecker
socket=${SOCKET}
password=healthcheckpass
EOF
touch $MYSQL_FILES_DIR/mysql-init-complete

if [ -n "$MYSQL_INITIALIZE_ONLY" ]; then
    echo "[Entrypoint] MYSQL_INITIALIZE_ONLY is set, exiting without starting MySQL..."
    exit 0
else
    echo "[Entrypoint] Starting RonDB"
fi
echo "[Entrypoint] \$@: $@"
export MYSQLD_PARENT_PID=$$ ; exec "$@" --user=
