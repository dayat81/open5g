#!/bin/bash
# Restart HANYA container l5g-ue (srsUE) di lab5g-vm, tunggu attach, jalankan ulang 20-setup-vm.sh,
# lalu keepalive ringan (ping 2 s dari netns l5g-ue ke 10.99.9.20, otomatis berhenti setelah KA_SEC).
. ~/poc-latency/phase0/common-vm.sh
KA_SEC=${KA_SEC:-900}
$V "sudo -n env KA_SEC=$KA_SEC bash -s" <<'VEOF'
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo "restart l5g-ue at $T0"
docker restart -t 10 l5g-ue
for i in $(seq 1 36); do
  L=$(docker logs --since $T0 l5g-ue 2>&1 | grep -E 'Network attach successful|Attach failed' | tail -1)
  [ -n "$L" ] && break; sleep 5
done
docker logs -t --since $T0 l5g-ue 2>&1 | grep -iE 'attach|reject|RRC|IP:' | tail -12
echo "RESULT: $L"
VEOF
