# Sanitized script reference

#!/bin/bash
set -euo pipefail
cd /home/lab/lab5g-dev
COMPOSE=(docker-compose)
# If local bins present, use override
if [ -x bin/open5gs-smfd ] && [ -x bin/open5gs-upfd ]; then
  COMPOSE=(docker-compose -f docker-compose.yml -f docker-compose.override.dev.yml)
  echo "Using LOCAL SMF/UPF binaries from ./bin"
fi
"${COMPOSE[@]}" up -d mongo
for i in $(seq 1 40); do
  docker exec l5gd-mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1 && break
  sleep 2
done
JS="db = db.getSiblingDB('open5gs'); db.subscribers.deleteMany({imsi:/^00101/});"
while IFS=, read imsi k opc; do
  JS="$JS db.subscribers.insertOne({imsi:'$imsi',security:{k:'$k',opc:'$opc',amf:'<REDACTED_AMF>',sqn:NumberLong(0)},ambr:{downlink:{value:1,unit:3},uplink:{value:1,unit:3}},slice:[{sst:1,default_indicator:true,session:[{name:'internet',type:3,qos:{index:9,arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},ambr:{downlink:{value:1,unit:3},uplink:{value:1,unit:3}}}]}],access_restriction_data:32,network_access_mode:0,subscriber_status:0,operator_determined_barring:0,subscribed_rau_tau_timer:12,schema_version:1});"
done < secrets/subs.csv
docker exec l5gd-mongo mongosh --quiet --eval "$JS; print('subscribers=' + db.subscribers.countDocuments({}))"
"${COMPOSE[@]}" up -d hss pcrf mme sgwc sgwu smf upf server
sleep 20
docker-compose -f docker-compose-ran.yml up -d enb
sleep 8
sudo bash ./lab-routes.sh || bash ./lab-routes.sh
docker-compose -f docker-compose-ran.yml up -d ue
sleep 15
sudo bash ./lab-routes.sh || bash ./lab-routes.sh
docker ps --format '{{.Names}} {{.Status}}' | sort

# --- lab5g-dev: ZMQ order (UE binds :2001 before eNB connects) ---
# If RAN was brought up with enb-before-ue, fix with:
#   sudo docker compose -f docker-compose-ran.yml stop enb ue
#   sudo docker compose -f docker-compose-ran.yml up -d ue && sleep 5
#   sudo docker compose -f docker-compose-ran.yml up -d enb

# After the normal LTE bring-up, run "sudo bash endc-up.sh" to enable
# verified dual-carrier EN-DC (only lab5g-dev RAN containers are recreated).
