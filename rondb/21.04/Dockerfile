# Copyright (c) 2017, 2021, Oracle and/or its affiliates.
# Copyright (c) 2021, 2021, Logical Clocks AB and/or its affiliates.
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

FROM oraclelinux:8-slim

ARG RONDB_VERSION=rondb-21.04.1

RUN microdnf install wget tar gzip ncurses-compat-libs

# Install RonDB 21.04.1
RUN wget http://repo.hops.works/master/$RONDB_VERSION-linux-glibc2.17-x86_64.tar.gz \
    && tar xfz $RONDB_VERSION-linux-glibc2.17-x86_64.tar.gz \
    && rm $RONDB_VERSION-linux-glibc2.17-x86_64.tar.gz \
    && mv $RONDB_VERSION-linux-glibc2.17-x86_64 /usr/local/$RONDB_VERSION \
    && mkdir /docker-entrypoint-initdb.d \
    mkdir -p /var/lib/mysql \
    mkdir -p /var/lib/rondb \
    adduser mysql \
    && chown mysql:mysql -R /var/lib/mysql \
    && chmod -R 755 /var/lib/mysql

COPY prepare-image.sh /
RUN /prepare-image.sh && rm -f /prepare-image.sh

ENV MYSQL_UNIX_PORT /var/lib/mysql/mysql.sock
ENV PATH=/usr/local/$RONDB_VERSION/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/$RONDB_VERSION/lib:$LD_LIBRARY_PATH

COPY docker-entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
COPY cnf/my.cnf /etc/
COPY cnf/rondb.cnf /etc/

ENTRYPOINT ["/entrypoint.sh"]
HEALTHCHECK CMD /healthcheck.sh
EXPOSE 3306 33060 11860 1186
CMD ["mysqld"]

