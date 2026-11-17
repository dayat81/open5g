#!/bin/bash
# Restart l5g-enb (UE sudah listen ZMQ :2001), tunggu attach UE (maks 3 menit).
. ~/poc-latency/phase0/common-vm.sh
$V 'sudo -n bash -s' <<'VEOF'
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "restart l5g-enb at $T0"
docker restart -t 10 l5g-enb
for i in $(seq 1 36); do
  L=$(docker logs --since $T0 l5g-ue 2>&1 | grep -E 'Network attach successful|Attach failed' | tail -1)
  [ -n "$L" ] && break; sleep 5
done
echo "== ue"; docker logs -t --since $T0 l5g-ue 2>&1 | grep -iE 'attach|reject|RRC|IP:|Found' | tail -10
echo "== enb"; docker logs -t --since $T0 l5g-enb 2>&1 | grep -iE 'S1|MME|RACH|error|fail' | tail -10
echo "== mme"; docker logs -t --since $T0 l5g-mme 2>&1 | tail -8
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); nsenter -t $P -n ip -4 -br a
echo "RESULT: $L"
VEOF
