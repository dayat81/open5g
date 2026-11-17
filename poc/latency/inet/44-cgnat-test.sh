#!/bin/bash
# poc-inet CGNAT test (magen): dari netns l5g-ue (tanpa gost dns): dig UDP @8.8.8.8, QUIC UDP 443 (version negotiation) ke google,
# lalu log mapping CGNAT, counter SNAT/TPROXY, log gost redu, dan Zeek conn.log UDP 443/53 UE (netprobe-zeek-live READ-ONLY + poc-phase2-zeek).
# Pakai: bash 44-cgnat-test.sh [WAIT_ZEEK detik, default 0]  -> run/cgnat-<ts>/
. ~/poc-latency/phase0/common-vm.sh; cd ~/poc-latency/inet && . ./common-inet.sh
OUT=$RUN/cgnat-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT; echo "OUT=$OUT"
{ echo "### magen $(date -Is)"; ss -ltn | grep -E "127.0.0.1:1108[01] "
$V "sudo -n bash -s" <<'VEOF'
D=/home/lab/poc-inet; P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); N="nsenter -t $P -n"
echo "### UE $(date -Is)"; $N ip -br -4 a show tun_srsue
echo "--- dig @8.8.8.8 www.google.com (UDP, CGNAT; bukan gost dns)"; $N dig +time=5 +tries=2 @8.8.8.8 www.google.com A | grep -E 'status|^www|Query time|SERVER'
echo "--- dig @9.9.9.9 example.com (UDP 53 non-8.8.8.8 -> tetap gost dns)"; $N dig +time=5 +tries=1 @9.9.9.9 example.com A +short
echo "--- QUIC UDP 443 + DNS UDP (python, socket UDP biasa)"; $N python3 $D/udp-check.py
echo "--- curl --http3"; $N curl -sS -m 15 --http3 -o /dev/null -w 'h3 http=%{http_code} ver=%{http_version}\n' https://www.google.com 2>&1 | tail -1
sleep 2; echo "### CGNAT"; bash $D/cgnat.sh status
echo "--- cgnat-map.log (tail)"; tail -20 $D/cgnat-map.log
echo "--- gost redu log (tail)"; tail -n 400 $D/cgnat-udp.log | grep -oE '"msg":"[^"]*"' | sort | uniq -c | sort -rn | head -10
VEOF
} 2>&1 | tee $OUT/test.txt
[ "${1:-0}" -gt 0 ] && { echo "### tunggu zeek ${1}s"; sleep $1; }
$V 'sudo -n bash -s' <<'VEOF' 2>&1 | tee $OUT/zeek.txt
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); UE=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}' | cut -d/ -f1); echo "UE_IP=$UE"
for L in /dev/shm/netprobe-zeek-live /dev/shm/poc-phase2-zeek; do
  for f in $(ls -t $L/conn*.log 2>/dev/null | head -3); do
    echo "===== $f"; grep -h "\"proto\":\"udp\"" $f | grep -E "\"($UE|100\.64\.0\.[12])\"" | grep -E '"id.resp_p":(443|53)[,}]' | grep -v '"10.99.9.20"' | tail -12
  done
done
VEOF
echo "DONE $OUT"
