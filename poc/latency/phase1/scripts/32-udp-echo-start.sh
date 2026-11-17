#!/bin/bash
# UDP echo SEMENTARA di netns container l5g-server (lab5g-vm) port 9000. Proses python3 di host VM via nsenter
# (image/container l5g-server tidak diubah). Rollback: 38-udp-echo-stop.sh
. ~/poc-latency/phase0/common-vm.sh
$V 'sudo -n bash -s' <<'VEOF'
P=$(docker inspect -f '{{.State.Pid}}' l5g-server); echo "l5g-server pid=$P"
which python3 socat 2>/dev/null
if [ -f /tmp/poc-phase1-udp-echo.pid ] && kill -0 $(cat /tmp/poc-phase1-udp-echo.pid) 2>/dev/null; then echo "sudah jalan pid=$(cat /tmp/poc-phase1-udp-echo.pid)"; else
cat > /tmp/poc-phase1-udp-echo.py <<'PY'
# poc-phase1 UDP echo :9000 (magnon examine PoC)
import socket, time, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("0.0.0.0", 9000))
while True:
    d, a = s.recvfrom(65535)
    s.sendto(d, a)
    print("%.6f echo %s:%d len=%d" % (time.time(), a[0], a[1], len(d)), flush=True)
PY
nohup nsenter -t $P -n python3 -u /tmp/poc-phase1-udp-echo.py >> /tmp/poc-phase1-udp-echo.log 2>&1 &
echo $! > /tmp/poc-phase1-udp-echo.pid; sleep 1
fi
echo "pid=$(cat /tmp/poc-phase1-udp-echo.pid)"; nsenter -t $P -n ss -lunp | grep 9000
VEOF
