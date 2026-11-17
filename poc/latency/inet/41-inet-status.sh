#!/bin/bash
# poc-inet status (magen, read-only)
cd "$(dirname "$0")"; . ~/poc-latency/phase0/common-vm.sh; . ./common-inet.sh
echo "### magen"; ss -ltn | grep -q "127.0.0.1:$SOCKS_PORT " && echo "SOCKS laptop: listen" || echo "SOCKS laptop: TIDAK aktif"
curl -sS -m 15 -x socks5h://127.0.0.1:$SOCKS_PORT -o /dev/null -w 'magen->socks->internet: http=%{http_code} t=%{time_total}s\n' https://example.com 2>&1 | tail -1
[ -f $RUN/vm-tunnel.pid ] && kill -0 $(cat $RUN/vm-tunnel.pid) 2>/dev/null && echo "vm-tunnel pid=$(cat $RUN/vm-tunnel.pid)" || echo "vm-tunnel TIDAK jalan"
ss -ltn | grep -q "127.0.0.1:$UDP_PORT " && echo "relay UDP laptop :$UDP_PORT listen" || echo "relay UDP laptop :$UDP_PORT TIDAK aktif"
[ -f $RUN/vm-tunnel-udp.pid ] && kill -0 $(cat $RUN/vm-tunnel-udp.pid) 2>/dev/null && echo "vm-tunnel-udp pid=$(cat $RUN/vm-tunnel-udp.pid)" || echo "vm-tunnel-udp TIDAK jalan"
ip rule show | grep -E "^(2099|$TBL_INET):"
$V "sudo -n bash -s" <<'VEOF'
D=/home/lab/poc-inet; echo "### VM"; ss -ltn | grep -E ':11080 ' | awk '{print "listen",$4}'
[ -f $D/guard.pid ] && kill -0 $(cat $D/guard.pid) 2>/dev/null && echo "guard pid=$(cat $D/guard.pid)" || echo "guard TIDAK jalan"
pgrep -af "$D/gost" | cut -c1-160; ip rule show | grep '^2100:'
U=$(docker inspect -f '{{.State.Pid}}' l5g-upf); nsenter -t $U -n ip rule show | grep '^2100:' | sed 's/^/UPF /'
S=$(docker inspect -f '{{.State.Pid}}' l5g-server); nsenter -t $S -n iptables -t nat -L POC_INET -v -n 2>/dev/null | awk 'NR>2 && $1>0 {print "POC_INET",$1"pkt",$3,$NF,$(NF-1)}'
E=$(docker inspect -f '{{.State.Pid}}' l5g-ue); nsenter -t $E -n ip -br -4 a show tun_srsue; nsenter -t $E -n ip r show default
echo "### CGNAT"; bash $D/cgnat.sh status 2>&1 | tail -15
tail -3 $D/guard.log 2>/dev/null; tail -1 /tmp/poc-phase1-ka.log
VEOF
