#!/usr/bin/env sh
FORCE=0
if [ $# -gt 0 ] ;then
  if [ "$1" = "--force" ] ; then
    FORCE=1
  else 
    echo "Incorrect parameter. Usage: <prog> [--force]"
    exit 1
  fi
fi

ID=49
PID_FILE=/srv/hops/mysql-cluster/log/ndb_${ID}.pid 
/srv/hops/mysql-cluster/ndb/scripts/util/kill-process.sh ndb_mgmd $PID_FILE 0 $FORCE
exit $?
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# 
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# 
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# 
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# 
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# 
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# 
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# 
root@ip-172-31-22-77:/srv/hops/mysql-cluster/ndb/scripts# cat mgm-server-stop.sh
#!/usr/bin/env sh
FORCE=0
if [ $# -gt 0 ] ;then
  if [ "$1" = "--force" ] ; then
    FORCE=1
  else 
    echo "Incorrect parameter. Usage: <prog> [--force]"
    exit 1
  fi
fi

ID=49
PID_FILE=/srv/hops/mysql-cluster/log/ndb_${ID}.pid 
/srv/hops/mysql-cluster/ndb/scripts/util/kill-process.sh ndb_mgmd $PID_FILE 0 $FORCE
exit $?
