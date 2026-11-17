#!/bin/bash
# Rollback UDP echo :9000 di l5g-server netns.
. ~/poc-latency/phase0/common-vm.sh
$V 'sudo -n bash -s' <<'VEOF'
[ -f /tmp/poc-phase1-udp-echo.pid ] && kill $(cat /tmp/poc-phase1-udp-echo.pid) 2>/dev/null; pkill -f poc-phase1-udp-echo.py
rm -f /tmp/poc-phase1-udp-echo.pid /tmp/poc-phase1-udp-echo.py
P=$(docker inspect -f '{{.State.Pid}}' l5g-server); nsenter -t $P -n ss -lunp | grep 9000 || echo "echo :9000 sudah berhenti"
VEOF
