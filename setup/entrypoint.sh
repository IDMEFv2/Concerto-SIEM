#!/usr/bin/env bash

set -u
set -o pipefail

state_file=/state/.done
if [[ -e "$state_file" ]]; then
    echo "Setup has already run successfully. Skipping"
    tail -f /dev/null
fi

echo "Running setup"

echo "Waiting for database to be ready ..."
while true; do
    pg_isready -U postgres -h postgres
    if [ $? -eq 0 ]; then
        break
    else
        sleep 2
    fi
done
echo "Database is ready"
echo "Creating users in database ..."

PGPASSWORD=changeme psql -h postgres -U postgres -c "CREATE DATABASE prewikka;" || :
PGPASSWORD=changeme psql -h postgres -U postgres -c "CREATE USER prelude WITH ENCRYPTED PASSWORD 'prelude';" || :
PGPASSWORD=changeme psql -h postgres -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE prewikka TO prelude;" || :
PGPASSWORD=changeme psql -h postgres -U postgres -c "ALTER DATABASE prewikka OWNER TO prelude;" || :
echo "Users created"

echo "Waiting for elasticsearch to be ready ..."
until curl --user elastic:elastic 'http://es01:9200/_cluster/health?wait_for_status=yellow&timeout=30s'; do
    sleep 2
done

curl -u elastic:elastic \
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

curl --user elastic:elastic \
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

printf '<34>1 %s itguxweb2 sshd 24541 - - Failed password for root from 12.34.56.78 port 1806\n' "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" | nc -q 2 localhost 6514

echo "Logstash is ready"

echo "Setup ended"

mkdir -p "${state_file%/*}"
touch "$state_file"

tail -f /dev/null
