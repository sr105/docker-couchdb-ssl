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
		echo "USER USER USER" >&2
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

if [ "$1" = 'couchdb' ]; then
	check_for_admin_user
	fix_permissions
	# do this after fix_permissions because it uses tighter permissions
	fix_ssl_certificates
	exec gosu couchdb "$@"
fi

exec "$@"
