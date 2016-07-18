FROM couchdb:latest

#####
#
# SSL and Security
#

# http://docs.couchdb.org/en/1.6.1/config/http.html#secure-socket-level-options

# RUN mkdir -p /etc/couchdb/cert


# #WORKDIR .
# #COPY tunnel-neocastnetworks-com.conf /etc/couchdb/cert/tunnel-neocastnetworks-com.conf
# RUN cd /etc/couchdb/cert &&  openssl genrsa > privkey.pem &&  openssl req -batch -new -x509 -key privkey.pem -out couchdb.pem -days 1095 &&  chmod 600 privkey.pem couchdb.pem &&  chown couchdb privkey.pem couchdb.pem

# RUN printf "[daemons]\nhttpsd = {couch_httpd, start_link, [https]}\n" >> /usr/local/etc/couchdb/local.d/docker.ini

# RUN printf "[ssl]\ncert_file = /etc/couchdb/cert/couchdb.pem\nkey_file = /etc/couchdb/cert/privkey.pem\n" >> /usr/local/etc/couchdb/local.d/docker.ini

# RUN printf "[couch_httpd_auth]\nrequire_valid_user = true\n" >> /usr/local/etc/couchdb/local.d/docker.ini

COPY ./docker-entrypoint.sh /
COPY ./ssl.ini /usr/local/etc/couchdb/local.d/
RUN chmod +x /docker-entrypoint.sh

EXPOSE 6984
