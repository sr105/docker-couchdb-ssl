FROM couchdb:1.6.1

RUN apt-get update && apt-get install -y \
    netcat

COPY docker-entrypoint.sh /
COPY ssl.ini /usr/local/etc/couchdb/local.d/
RUN chmod +x /docker-entrypoint.sh

ENV COUCHDB_USER='admin'
ENV COUCHDB_PASSWORD='admin'
ENV ACRALYZER_USER='reporter'
ENV ACRALYZER_PASSWORD='reporter'
ENV APP_NAME='myapp'

EXPOSE 6984
