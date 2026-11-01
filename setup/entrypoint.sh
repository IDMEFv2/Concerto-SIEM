#!/usr/bin/env bash

set -u
set -o pipefail

echo "Running setup"

echo "Waiting for database to be ready ..."
while true; do
    pg_isready -U $POSTGRES_USER -h postgres
    if [ $? -eq 0 ]; then
        break
    else
        sleep 2
    fi
done
echo "Database is ready"

USER_EXISTS=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -tAc "SELECT 1 FROM pg_roles WHERE rolname='$POSTGRES_CONCERTO_USER';")

if [ "$USER_EXISTS" = "1" ]; then
	echo "User $POSTGRES_CONCERTO_USER already exists, skipping creation."
else
	echo "Creating user in database ..."
	PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -c "CREATE DATABASE $POSTGRES_CONCERTO_DB;" || :
	PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -c "CREATE USER $POSTGRES_CONCERTO_USER WITH ENCRYPTED PASSWORD '$POSTGRES_CONCERTO_PASSWORD';" || :
	PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_CONCERTO_DB TO $POSTGRES_CONCERTO_USER;" || :
	PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U $POSTGRES_USER -c "ALTER DATABASE $POSTGRES_CONCERTO_DB OWNER TO $POSTGRES_CONCERTO_USER;" || :
	echo "User created"
fi

echo "Waiting for elasticsearch to be ready ..."
until curl --user elastic:$ELASTIC_PASSWORD 'http://es01:9200/_cluster/health?wait_for_status=yellow&timeout=30s'; do
    sleep 2
done

curl -u elastic:$ELASTIC_PASSWORD \
-X PUT localhost:9200/_index_template/proto-default \
-H 'Content-Type: application/json' \
-d '{
  "index_patterns": [
    "logs*",
    "alerts*",
    "elastalert*"
  ],
  "priority": 1001,
  "template": {
    "settings": {
      "number_of_replicas": 0
    }
  }
}'

curl --user elastic:$ELASTIC_PASSWORD \
-XPUT 'http://localhost:9200/_cluster/settings' \
-H 'Content-Type: application/json' \
-d '{
  "persistent": {
    "cluster.routing.allocation.disk.watermark.low": "97%",
    "cluster.routing.allocation.disk.watermark.high": "98%",
    "cluster.routing.allocation.disk.watermark.flood_stage": "99%"
  }
}'

echo "Elasticsearch is ready"

echo "Logstash: Send first log and first IDMEFv2 ..."

until `curl --user elastic:$ELASTIC_PASSWORD -fs 'http://es01:9200/_cat/indices?h=index' | grep -q alerts`; do
       printf '<34>1 %s itguxweb2 sshd 24541 - - Failed password for root from 12.34.56.78 port 1806\n' "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" | nc -q 5 logstash 6514
done

echo "Logstash is ready"

echo "Setup ended"
