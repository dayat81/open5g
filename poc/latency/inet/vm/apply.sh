#!/bin/bash
# poc-inet apply (lab5g-vm, root). Idempoten; dipanggil guard.sh tiap 10 s.
# Memasang: gost fwd host 10.99.9.254:11080 -> 127.0.0.1:11080 (ssh -R dari magen);
#   gost red+dns di netns l5g-server; iptables nat POC_INET (l5g-server); ip rule 2100 di UPF, VM host; default route UE; DOCKER-USER poc-inet.
D=/home/lab/poc-inet; G=$D/gost; BR_SGI=10.99.9.254; SRV=10.99.9.20; T=2100
UU_BR=br-5bd8dbed8b33; UE_UU=10.99.11.21; SRC=172.22.10.1
DNS_UP=${DNS_UP:-$(cat $D/dns_up 2>/dev/null || echo tcp://1.1.1.1:53)}
PRIV="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4"
log(){ echo "$(date -Is) $*"; }
cpid(){ docker inspect -f '{{.State.Pid}}' $1 2>/dev/null; }
tbl(){ # tbl <nsenter-prefix> <gw-args>  : table T = default + throw private
  local pre="$1"; shift
  $pre ip route replace default "$@" table $T
  for p in $PRIV; do $pre ip route replace throw $p table $T; done
}
for f in $D/*.log; do [ -f "$f" ] && [ $(stat -c %s "$f") -gt 20000000 ] && : > "$f"; done
# 1) forward SOCKS ke bridge SGi (hanya terjangkau container di lab5g_sgi)
if ! pgrep -f "gost -L tcp://$BR_SGI:11080" >/dev/null; then
  setsid nohup $G -L tcp://$BR_SGI:11080/127.0.0.1:11080 >> $D/fwd.log 2>&1 < /dev/null & log "start gost fwd"
fi
# 2) gost red+dns di netns l5g-server
SP=$(cpid l5g-server)
if [ -n "$SP" ] && [ "$SP" != 0 ]; then
  NS=$(readlink /proc/$SP/ns/net); ok=0
  for gp in $(pgrep -f "gost -L red://:12345"); do
    if [ "$(readlink /proc/$gp/ns/net)" = "$NS" ]; then ok=1; else kill $gp; log "kill gost srv netns lama $gp"; fi
  done
  if [ $ok = 0 ]; then
    setsid nohup nsenter -t $SP -n $G -L "red://:12345" -L "dns://:10053/$DNS_UP" -L "dns://:10053/$DNS_UP?mode=tcp" \
      -F socks5://$BR_SGI:11080 >> $D/srv.log 2>&1 < /dev/null & log "start gost srv (red :12345, dns :10053 -> $DNS_UP)"
  fi
  N="nsenter -t $SP -n"
  if ! $N iptables -t nat -C PREROUTING -s 10.45.0.0/16 -m comment --comment poc-inet -j POC_INET 2>/dev/null \
     || ! $N iptables -t nat -S POC_INET 2>/dev/null | grep -q 'REDIRECT --to-ports 12345'; then
    $N iptables -t nat -N POC_INET 2>/dev/null; $N iptables -t nat -F POC_INET
    $N iptables -t nat -A POC_INET -p udp --dport 53 -m comment --comment poc-inet -j REDIRECT --to-ports 10053
    $N iptables -t nat -A POC_INET -p tcp --dport 53 -m comment --comment poc-inet -j REDIRECT --to-ports 10053
    for p in $PRIV; do $N iptables -t nat -A POC_INET -d $p -m comment --comment poc-inet -j RETURN; done
    $N iptables -t nat -A POC_INET -p tcp -m comment --comment poc-inet -j REDIRECT --to-ports 12345
    $N iptables -t nat -C PREROUTING -s 10.45.0.0/16 -m comment --comment poc-inet -j POC_INET 2>/dev/null || \
      $N iptables -t nat -I PREROUTING 1 -s 10.45.0.0/16 -m comment --comment poc-inet -j POC_INET
    log "iptables POC_INET l5g-server dipasang"
  fi
fi
# 3) UPF: trafik UE ke non-privat -> l5g-server (policy rule, table main UPF tidak diubah)
UP=$(cpid l5g-upf)
if [ -n "$UP" ] && [ "$UP" != 0 ]; then
  N="nsenter -t $UP -n"
  $N ip route show table $T 2>/dev/null | grep -q "default via $SRV" || { tbl "$N" via $SRV dev eth2; log "UPF table $T"; }
  $N ip rule show | grep -q "^$T:" || { $N ip rule add from 10.45.0.0/16 iif ogstun lookup $T pref $T; log "UPF rule $T"; }
fi
# 4) UE: default route lewat tun_srsue (MASQUERADE poc-phase0 sudah mencakup semua tujuan)
UEP=$(cpid l5g-ue)
if [ -n "$UEP" ] && [ "$UEP" != 0 ] && nsenter -t $UEP -n ip link show tun_srsue >/dev/null 2>&1; then
  nsenter -t $UEP -n ip route show default | grep -q tun_srsue || { nsenter -t $UEP -n ip route replace default dev tun_srsue; log "UE default dev tun_srsue"; }
fi
# 5) VM host: emulator (dari magen, SNAT 172.22.10.1) ke non-privat -> l5g-ue
ip route show table $T 2>/dev/null | grep -q "default via $UE_UU" || { tbl "" via $UE_UU dev $UU_BR; log "VM table $T"; }
ip rule show | grep -q "^$T:" || { ip rule add iif ens3 from $SRC lookup $T pref $T; log "VM rule $T"; }
iptables -C DOCKER-USER -i ens3 -o $UU_BR -s $SRC ! -d 10.0.0.0/8 -m comment --comment poc-inet -j ACCEPT 2>/dev/null || \
  { iptables -I DOCKER-USER 1 -i ens3 -o $UU_BR -s $SRC ! -d 10.0.0.0/8 -m comment --comment poc-inet -j ACCEPT; log "DOCKER-USER fwd"; }
iptables -C DOCKER-USER -i $UU_BR -o ens3 -d $SRC -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment poc-inet -j ACCEPT 2>/dev/null || \
  { iptables -I DOCKER-USER 2 -i $UU_BR -o ens3 -d $SRC -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment poc-inet -j ACCEPT; log "DOCKER-USER ret"; }
exit 0
