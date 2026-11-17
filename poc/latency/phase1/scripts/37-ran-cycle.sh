#!/bin/bash
# Siklus RAN bersih sesuai /home/lab/lab5g/lab-up.sh: stop ue+enb, start enb, sleep 8, start ue; tunggu attach (maks 4 menit).
. ~/poc-latency/phase0/common-vm.sh
$V 'sudo -n bash -s' <<'VEOF'
uptime
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "ran cycle at $T0"
docker stop -t 10 l5g-ue l5g-enb
docker start l5g-enb; sleep 8; docker start l5g-ue
for i in $(seq 1 48); do
  L=$(docker logs --since $T0 l5g-ue 2>&1 | grep -E 'Network attach successful|Attach failed' | tail -1)
  [ -n "$L" ] && break; sleep 5
done
echo "== ue"; docker logs -t --since $T0 l5g-ue 2>&1 | grep -iE 'attach|reject|RRC|IP:|Found|cell' | tail -10
echo "== enb"; docker logs -t --since $T0 l5g-enb 2>&1 | grep -iE 'RACH|S1|error|fail|started' | tail -8
echo "== mme"; docker logs -t --since $T0 l5g-mme 2>&1 | grep -iE 'attach|eNB|error|IMSI' | tail -8
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); nsenter -t $P -n ip -4 -br a
docker stats --no-stream l5g-ue l5g-enb
echo "RESULT: $L"
VEOF
