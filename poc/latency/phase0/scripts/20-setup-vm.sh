#!/bin/bash
# Sambungkan emulator b0-agen-emu ke jalur UE lab5g-vm. Tidak menyentuh core (enb/sgwu/upf/smf) dan probe.
# Jalur: Android 10.0.2.15 -slirp-> 172.26.0.2 -magen policy-route+MASQ-> 172.22.10.1 -> VM ens3
#   -> policy-route ke l5g-ue eth0 10.99.11.21 -> MASQUERADE ke IP UE (tun_srsue) -> eNB -> S1-U GTP-U -> SGW-U -> UPF -> SGi -> l5g-server
set -u
. "$(dirname "$0")/common-vm.sh"
echo "### [magen] policy route: hanya iif $EMU_BR ke $SERVER/32"
if ip rule show | grep -q "^$TBL:"; then echo "rule $TBL sudah ada"; else
  [ -z "$(ip route show table $TBL 2>/dev/null)" ] || { echo "ABORT table $TBL tidak kosong"; exit 1; }
  sudo -n ip route add $SERVER/32 via $VM dev $VIRBR table $TBL
  sudo -n ip rule add iif $EMU_BR to $SERVER/32 lookup $TBL priority $TBL
fi
ip rule show | grep "^$TBL:"; ip route show table $TBL
$V "sudo -n env SERVER=$SERVER TBL=$TBL bash -s" <<'VEOF'
set -u
UU_BR=br-5bd8dbed8b33; UE_UU=10.99.11.21; SRC=172.22.10.1
echo "### [VM] policy route ens3 -> l5g-ue"
if ip rule show | grep -q "^$TBL:"; then echo "rule $TBL sudah ada"; else
  [ -z "$(ip route show table $TBL 2>/dev/null)" ] || { echo "ABORT table $TBL tidak kosong"; exit 1; }
  ip route add $SERVER/32 via $UE_UU dev $UU_BR table $TBL
  ip rule add iif ens3 from $SRC to $SERVER/32 lookup $TBL priority $TBL
fi
ip rule show | grep "^$TBL:"; ip route show table $TBL
echo "### [VM] DOCKER-USER accept (comment poc-phase0)"
iptables -C DOCKER-USER -i ens3 -o $UU_BR -s $SRC -d $SERVER -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null || \
  iptables -I DOCKER-USER 1 -i ens3 -o $UU_BR -s $SRC -d $SERVER -m comment --comment poc-phase0 -j ACCEPT
iptables -C DOCKER-USER -i $UU_BR -o ens3 -s $SERVER -d $SRC -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null || \
  iptables -I DOCKER-USER 2 -i $UU_BR -o ens3 -s $SERVER -d $SRC -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment poc-phase0 -j ACCEPT
iptables -S DOCKER-USER
echo "### [l5g-ue netns] route balik, MASQUERADE, D5 (rute SGi via tun_srsue, sama dgn lab-routes.sh)"
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue)
nsenter -t $P -n ip route replace $SRC/32 via 10.99.11.254 dev eth0
nsenter -t $P -n iptables -t nat -C POSTROUTING -s $SRC/32 -o tun_srsue -m comment --comment poc-phase0 -j MASQUERADE 2>/dev/null || \
  nsenter -t $P -n iptables -t nat -A POSTROUTING -s $SRC/32 -o tun_srsue -m comment --comment poc-phase0 -j MASQUERADE
nsenter -t $P -n ip route replace 10.99.9.0/24 dev tun_srsue || echo "D5 gagal: tun_srsue belum ada"
nsenter -t $P -n ip -br a show tun_srsue; nsenter -t $P -n ip r; nsenter -t $P -n iptables -t nat -S POSTROUTING
echo "### [l5g-ue] ping server"; docker exec l5g-ue ping -c 3 -W 2 $SERVER | tail -2
VEOF
