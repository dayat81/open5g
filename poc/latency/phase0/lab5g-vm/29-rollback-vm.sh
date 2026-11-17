#!/bin/bash
# Rollback perubahan lab5g-vm + magen (idempoten). Rute D5 di l5g-ue dibiarkan (bagian runbook lab-routes.sh).
set -u
. "$(dirname "$0")/common-vm.sh"
sudo -n ip rule del priority $TBL 2>/dev/null; sudo -n ip route flush table $TBL 2>/dev/null
ip rule show | grep "^$TBL:" || echo "[magen] rule $TBL hilang (ok)"
$V "sudo -n env SERVER=$SERVER TBL=$TBL bash -s" <<'VEOF'
UU_BR=br-5bd8dbed8b33; SRC=172.22.10.1
ip rule del priority $TBL 2>/dev/null; ip route flush table $TBL 2>/dev/null
iptables -D DOCKER-USER -i ens3 -o $UU_BR -s $SRC -d $SERVER -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null
iptables -D DOCKER-USER -i $UU_BR -o ens3 -s $SERVER -d $SRC -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue)
nsenter -t $P -n iptables -t nat -D POSTROUTING -s $SRC/32 -o tun_srsue -m comment --comment poc-phase0 -j MASQUERADE 2>/dev/null
nsenter -t $P -n ip route del $SRC/32 2>/dev/null
echo "[VM] rollback selesai"; iptables -S DOCKER-USER; ip rule show | grep "^$TBL:" || true; nsenter -t $P -n iptables -t nat -S POSTROUTING
VEOF
