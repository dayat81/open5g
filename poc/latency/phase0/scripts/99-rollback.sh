#!/bin/bash
# Rollback semua perubahan phase0 (idempoten).
set -u
. "$(dirname "$0")/common.sh"
echo "### [magen]"; sudo -n ip rule del priority $TBL 2>/dev/null; sudo -n ip route flush table $TBL 2>/dev/null
ip rule show | grep "^$TBL:" || echo "rule $TBL hilang (ok)"
$G "sudo -n env SERVER=$SERVER TBL=$TBL REMOVE_ZEEK_IMAGE=${REMOVE_ZEEK_IMAGE:-0} bash -s" <<'GEOF'
UU_BR=br-c13aa9d21de3
docker rm -f poc0-zeek-s1u poc0-zeek-sgi 2>/dev/null
pkill -f 'tcpdump.*poc0' 2>/dev/null
ip rule del priority $TBL 2>/dev/null; ip route flush table $TBL 2>/dev/null
iptables -D DOCKER-USER -i ens3 -o $UU_BR -s 172.22.20.1 -d $SERVER -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null
iptables -D DOCKER-USER -i $UU_BR -o ens3 -s $SERVER -d 172.22.20.1 -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null
P=$(docker inspect -f '{{.State.Pid}}' l5gd-ue)
nsenter -t $P -n iptables -t nat -D POSTROUTING -s 172.22.20.1/32 -o tun_srsue -m comment --comment poc-phase0 -j MASQUERADE 2>/dev/null
nsenter -t $P -n ip route del 172.22.20.1/32 2>/dev/null
docker exec l5gd-server sh -c 'pkill -f "http.server 8080"; pkill -f "UDP4-LISTEN:9000"' 2>/dev/null
if [ "${REMOVE_ZEEK_IMAGE:-0}" = 1 ]; then docker rmi zeek/zeek:9.0.1; fi
echo "guest rollback selesai"; iptables -S DOCKER-USER; ip rule show | grep "^$TBL:" || true
GEOF
