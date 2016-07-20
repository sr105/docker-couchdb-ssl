#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -e

check_for_admin_user() {
	# if we don't find an [admins] section followed by a non-comment, display a warning
	if grep -Pzoqr '\[admins\]\n[^;]\w+' /usr/local/etc/couchdb; then
		return
	fi

	if [ "$COUCHDB_USER" ] && [ "$COUCHDB_PASSWORD" ]; then
		# Create admin
		DOCKER_INI=/usr/local/etc/couchdb/local.d/docker.ini
		printf "[admins]\n$COUCHDB_USER = $COUCHDB_PASSWORD\n" >> ${DOCKER_INI}
		return
	fi

	# The - option suppresses leading tabs but *not* spaces. :)
	cat >&2 <<-'EOWARN'
		****************************************************
		WARNING: CouchDB is running in Admin Party mode.
		         This will allow anyone with access to the
		         CouchDB port to access your database. In
		         Docker's default configuration, this is
		         effectively any other container on the same
		         system.
		         Use "-e COUCHDB_USER=admin -e COUCHDB_PASSWORD=password"
		         to set it in "docker run".
		****************************************************
	EOWARN
}

fix_permissions() {
	# we need to set the permissions here because docker mounts volumes as root
	chown -R couchdb:couchdb \
		/usr/local/var/lib/couchdb \
		/usr/local/var/log/couchdb \
		/usr/local/var/run/couchdb \
		/usr/local/etc/couchdb

	chmod -R 0770 \
		/usr/local/var/lib/couchdb \
		/usr/local/var/log/couchdb \
		/usr/local/var/run/couchdb \
		/usr/local/etc/couchdb

	chmod 664 /usr/local/etc/couchdb/*.ini
	chmod 775 /usr/local/etc/couchdb/*.d
}

fix_ssl_certificates() {
	local CERT_PATH=/usr/local/etc/couchdb/cert
	mkdir -p ${CERT_PATH}
	cd ${CERT_PATH}

	# Generate them if missing
	if ! [ -e couchdb.pem ]; then
		openssl genrsa > privkey.pem
		openssl req -batch -new -x509 -key privkey.pem -out couchdb.pem -days 30
		# mark them as self-signed in a way that is easy for us to test
		echo "# self-signed" >> couchdb.pem
	fi
	chmod 600 privkey.pem couchdb.pem
	chown couchdb:couchdb privkey.pem couchdb.pem

	# Tell the user how to install their own certificate and private key
	if grep -q 'self-signed' couchdb.pem; then
		# Unless the user has changed the hostname, this works
		local CONTAINER=${HOSTNAME}
		# The - option suppresses leading tabs but *not* spaces. :)
		# Note: No quotes around EOWARN to get variable expansion
		cat >&2 <<-EOWARN
			****************************************************
			WARNING: CouchDB is using a generated self-signed
			         SSL certificate and private key. Copy your
			         own files into the container and then
			         restart. The certificate and private key
			         files must be named couchdb.pem and
			         privkey.pem respectively.
			         docker cp couchdb.pem ${CONTAINER}:${CERT_PATH}/couchdb.pem
			         docker cp privkey.pem ${CONTAINER}:${CERT_PATH}/privkey.pem
			         docker restart ${CONTAINER}
			****************************************************
		EOWARN
	fi

	cd -
}

couchdb_start() {
	couchdb &
	# use a global here because "set -e" will consider
	# "return $couchdb_pid" as a script error
	couchdb_pid=$!
	while ! nc -z localhost 5984; do
	    echo "Waiting for couchdb to start..." >&2
	    sleep 1
	done
}

couchdb_stop() {
	kill $couchdb_pid
	while [ -d /proc/$couchdb_pid ]; do
		echo "Waiting for couchdb to stop..." >&2
		sleep 1
	done
}

# https://wiki.apache.org/couchdb/Replication
couchdb_replicate() {
	local AUTH="${COUCHDB_USER}:${COUCHDB_PASSWORD}"
	local JSON_TYPE="Content-Type: application/json"
	local URL=localhost:5984/_replicate

	local SOURCE="$1"
	local DESTINATION="$2"
	cat <<-EOF | curl -sX POST -u "${AUTH}" -H "${JSON_TYPE}" -d @- $URL
		{
		    "source":"http://get.acralyzer.com/${SOURCE}",
		    "target":"${DESTINATION}",
		    "create_target":true
		}
		EOF
}

# https://github.com/ACRA/acralyzer/wiki/Create-users-before-CouchDB-1.2
acralyzer_create_reporter() {
	local SALT=$(openssl rand 16 | openssl md5)
	local PASSWORD_SHA=$(echo -n "${ACRALYZER_PASSWORD}${SALT}" | openssl sha1)

	local AUTH="${COUCHDB_USER}:${COUCHDB_PASSWORD}"
	local JSON_TYPE="Content-Type: application/json"
	local URL=localhost:5984/_users
	cat <<-EOF | curl -sX POST -u "${AUTH}" -H "${JSON_TYPE}" -d @- "$URL"
		{
		    "_id": "org.couchdb.user:${ACRALYZER_USER}",
		    "name": "${ACRALYZER_USER}",
		    "type": "user",
		    "roles": ["reporter", "reader"],
		    "password_sha": "${PASSWORD_SHA}",
		    "salt": "${SALT}"
		}
		EOF
}

acralyzer_install() {
	if [ -e /.acralyzer_installed ]; then
		return
	fi

	couchdb_start
	couchdb_replicate distrib-acra-storage acra-${APP_NAME}
	couchdb_replicate distrib-acralyzer acralyzer
	acralyzer_create_reporter
	couchdb_stop
	touch /.acralyzer_installed
}

if [ "$1" = 'couchdb' ]; then
	check_for_admin_user
	# this must be after check_for_admin_user because of
	# "require_valid_user = true" but before fix_permissions
	# because of how we run couchdb
	acralyzer_install
	fix_permissions
	# do this after fix_permissions because it uses tighter permissions
	fix_ssl_certificates

	exec gosu couchdb "$@"
fi

exec "$@"
