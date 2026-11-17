#!/bin/bash
# Langkah 2: sambungkan emulator (b0-agen-emu @ magen) ke jalur UE lab5g-dev.
# Jalur: Android 10.0.2.15 -slirp-> 172.26.0.2 -magen(policy route, MASQ docker)-> 172.22.20.1
#        -> guest ens3 (policy route) -> l5gd-ue eth0 10.99.11.21 -> MASQUERADE ke IP UE di tun_srsue
#        -> srsUE -> eNB -> S1-U GTP-U -> SGW-U -> UPF -> SGi -> l5gd-server 10.99.9.20
set -u
. "$(dirname "$0")/common.sh"
echo "### [magen] policy route hanya untuk trafik dari $EMU_BR ke $SERVER"
if ip rule show | grep -q "^$TBL:"; then echo "rule $TBL sudah ada"; ip rule show | grep "^$TBL:"; else
  [ -z "$(ip route show table $TBL)" ] || { echo "ABORT: table $TBL tidak kosong"; exit 1; }
  sudo -n ip route add $SERVER/32 via $GUEST dev virbr-l5gdev table $TBL
  sudo -n ip rule add iif $EMU_BR to $SERVER/32 lookup $TBL priority $TBL
fi
ip rule show | grep "^$TBL:"; ip route show table $TBL

echo "### [guest] siapkan image zeek (dari magen, tanpa internet)"
if $G "sudo -n docker image inspect zeek/zeek:9.0.1 >/dev/null 2>&1"; then echo "image zeek sudah ada di guest"; else
  $D save zeek/zeek:9.0.1 | $G "sudo -n docker load"; fi

$G "sudo -n env SERVER=$SERVER TBL=$TBL bash -s" <<'GEOF'
set -u
pid(){ docker inspect -f '{{.State.Pid}}' $1; }
UU_BR=br-c13aa9d21de3; UE_UU=10.99.11.21
echo "### [guest] policy route ens3 -> l5gd-ue untuk $SERVER"
if ip rule show | grep -q "^$TBL:"; then echo "rule $TBL sudah ada"; else
  [ -z "$(ip route show table $TBL)" ] || { echo "ABORT: table $TBL tidak kosong"; exit 1; }
  ip route add $SERVER/32 via $UE_UU dev $UU_BR table $TBL
  ip rule add iif ens3 from 172.22.20.1 to $SERVER/32 lookup $TBL priority $TBL
fi
ip rule show | grep "^$TBL:"; ip route show table $TBL
echo "### [guest] DOCKER-USER accept (bertanda poc-phase0)"
iptables -C DOCKER-USER -i ens3 -o $UU_BR -s 172.22.20.1 -d $SERVER -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null || \
  iptables -I DOCKER-USER 1 -i ens3 -o $UU_BR -s 172.22.20.1 -d $SERVER -m comment --comment poc-phase0 -j ACCEPT
iptables -C DOCKER-USER -i $UU_BR -o ens3 -s $SERVER -d 172.22.20.1 -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment poc-phase0 -j ACCEPT 2>/dev/null || \
  iptables -I DOCKER-USER 2 -i $UU_BR -o ens3 -s $SERVER -d 172.22.20.1 -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment poc-phase0 -j ACCEPT
iptables -S DOCKER-USER
echo "### [l5gd-ue netns] route balik + MASQUERADE ke IP UE"
P=$(pid l5gd-ue)
nsenter -t $P -n ip route replace 172.22.20.1/32 via 10.99.11.254 dev eth0
nsenter -t $P -n iptables -t nat -C POSTROUTING -s 172.22.20.1/32 -o tun_srsue -m comment --comment poc-phase0 -j MASQUERADE 2>/dev/null || \
  nsenter -t $P -n iptables -t nat -A POSTROUTING -s 172.22.20.1/32 -o tun_srsue -m comment --comment poc-phase0 -j MASQUERADE
bash /home/lab/lab5g-dev/lab-routes.sh
nsenter -t $P -n ip r; nsenter -t $P -n iptables -t nat -S POSTROUTING
echo "### [l5gd-server] listener HTTP :8080 dan UDP echo :9000"
docker exec l5gd-server sh -c 'pgrep -f "http.server 8080" >/dev/null' || docker exec -d l5gd-server sh -c 'mkdir -p /tmp/poc0 && printf "<html><body><h1>lab5g-dev l5gd-server 10.99.9.20</h1><p>PoC phase0: emulator -> UE -> GTP-U -> UPF -> SGi</p></body></html>\n" > /tmp/poc0/index.html && cd /tmp/poc0 && exec python3 -m http.server 8080'
docker exec l5gd-server sh -c 'pgrep -f "UDP4-LISTEN:9000" >/dev/null' || docker exec -d l5gd-server socat UDP4-LISTEN:9000,fork,reuseaddr PIPE
sleep 1; docker exec l5gd-server sh -c 'ss -lntu | grep -E ":8080|:9000"'
GEOF
