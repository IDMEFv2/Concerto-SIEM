#!/bin/sh

set -e

echo "Start initialisation ..."

cd /opt/sigma_rules

for rule in *; do
    sigma convert -p concerto -t elastalert -f default "$rule" | tail -n +3 > "/opt/elastalert/rules/$rule"
    cat "/opt/elastalert/rules/$rule"
done

echo "Finish initialisation"

/opt/elastalert/run.sh
