#!/bin/bash
# poc-inet CGNAT (lab5g-vm, root). Pakai: cgnat.sh apply|remove   (apply dipanggil apply.sh/guard tiap 10 s, idempoten)
# Fungsi CGNAT (NAT44, RFC 6598) untuk UDP UE 10.45.0.0/16 ke tujuan non-privat:
#  l5g-server netns : ip rule 2101 from 10.45/16 -> table 2101 (default via 10.99.9.254 + throw privat);
#                     nat POSTROUTING POC_CGNAT: SNAT UDP 10.45.0.N -> 100.64.0.1:port-block 240 port/UE (N=1..254),
#                     sisa 10.45/16 -> 100.64.0.2; filter FORWARD POC_CGNAT_FWD: hanya UDP non-privat yg diteruskan;
#                     log mapping (cgnat-map.py, baca /proc/net/nf_conntrack netns) -> $D/cgnat-map.log (rotasi 5 MB x3)
#  host VM          : mangle PREROUTING TPROXY UDP dari 100.64.0.0/29 (bridge SGi) -> gost redu :12346 -> relay://127.0.0.1:11081
#                     (ssh -R magen -> laptop gost relay, UDP-over-TCP) ; ip rule 2101 to 100.64.0.0/29 -> l5g-server ;
#                     ip rule 2102 fwmark 0x2101 -> local ; DOCKER-USER drop sisa 100.64.0.0/29 (tidak bocor ke ens3)
#  DNS UDP ke 8.8.8.8 (CGNAT_DNS di $D/cgnat_dns) dikecualikan dari redirect gost dns HANYA saat relay 127.0.0.1:11081 hidup.
D=/home/lab/poc-inet; G=$D/gost; T=2101; TM=2102; MARK=0x2101; BR=br-250e9b29a2ee; GW=10.99.9.254; SRV=10.99.9.20
POOL=100.64.0.0/29; PUB1=100.64.0.1; PUB2=100.64.0.2; RPORT=12346; RELAY=127.0.0.1:11081; BLK=240; BASE=1024
PRIV="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4"
CGNAT_DNS=$(cat $D/cgnat_dns 2>/dev/null || echo 8.8.8.8)
C="-m comment --comment poc-inet"
log(){ echo "$(date -Is) cgnat $*"; }
cpid(){ docker inspect -f '{{.State.Pid}}' $1 2>/dev/null; }
SP=$(cpid l5g-server); N="nsenter -t $SP -n"
relay_up(){ ss -ltn | grep -q " $RELAY "; }
dedupe() { # dedupe <iptables-prefix> <table> <chain> <pattern> : hapus duplikat aturan identik (sisa race guard)
  local n; n=$($1 iptables -t $2 -S $3 2>/dev/null | grep -c -- "$4")
  while [ "$n" -gt 1 ]; do $1 iptables -t $2 -D $3 $(echo "$($1 iptables -t $2 -S $3 | grep -- "$4" | head -1)" | cut -d' ' -f3-) || break; n=$((n-1)); log "dedupe $3"; done
}
apply() {
  [ -n "$SP" ] && [ "$SP" != 0 ] || return 0
  exec 9>/run/poc-inet-cgnat.lock; flock -w 20 9 || return 0
  # --- l5g-server: routing UDP UE -> host
  $N ip route show table $T 2>/dev/null | grep -q "default via $GW" || {
    $N ip route replace default via $GW dev eth0 table $T; for p in $PRIV; do $N ip route replace throw $p table $T; done; log "srv table $T"; }
  $N ip rule show | grep -q "^$T:" || { $N ip rule add from 10.45.0.0/16 lookup $T pref $T; log "srv rule $T"; }
  # --- l5g-server: SNAT port-block per UE
  if ! $N iptables -t nat -S POC_CGNAT 2>/dev/null | grep -q "$PUB2"; then
    $N iptables -t nat -N POC_CGNAT 2>/dev/null; $N iptables -t nat -F POC_CGNAT
    { echo "*nat"; for i in $(seq 1 254); do lo=$((BASE + (i-1)*BLK)); hi=$((lo + BLK - 1))
        echo "-A POC_CGNAT -s 10.45.0.$i/32 -p udp $C -j SNAT --to-source $PUB1:$lo-$hi"; done
      echo "-A POC_CGNAT -s 10.45.0.0/16 -p udp $C -j SNAT --to-source $PUB2"; echo COMMIT; } | $N iptables-restore --noflush
    log "srv POC_CGNAT (254 port-block x $BLK)"
  fi
  $N iptables -t nat -C POSTROUTING -o eth0 -s 10.45.0.0/16 $C -j POC_CGNAT 2>/dev/null || \
    $N iptables -t nat -I POSTROUTING 1 -o eth0 -s 10.45.0.0/16 $C -j POC_CGNAT
  if ! $N iptables -S POC_CGNAT_FWD 2>/dev/null | grep -q DROP; then
    $N iptables -N POC_CGNAT_FWD 2>/dev/null; $N iptables -F POC_CGNAT_FWD
    for p in $PRIV; do $N iptables -A POC_CGNAT_FWD -d $p $C -j RETURN; done
    $N iptables -A POC_CGNAT_FWD -p udp $C -j ACCEPT; $N iptables -A POC_CGNAT_FWD $C -j DROP; log "srv POC_CGNAT_FWD"
  fi
  $N iptables -C FORWARD -s 10.45.0.0/16 $C -j POC_CGNAT_FWD 2>/dev/null || $N iptables -I FORWARD 1 -s 10.45.0.0/16 $C -j POC_CGNAT_FWD
  # --- DNS publik lewat CGNAT (bukan gost dns) bila relay hidup
  for ip in $CGNAT_DNS; do
    R="-d $ip/32 -p udp --dport 53 $C -j RETURN"
    if relay_up; then $N iptables -t nat -C POC_INET $R 2>/dev/null || { $N iptables -t nat -I POC_INET 1 $R && log "dns $ip via CGNAT"; }
    else while $N iptables -t nat -D POC_INET $R 2>/dev/null; do log "dns $ip kembali ke gost dns (relay mati)"; done; fi
  done
  # --- log mapping
  NS=$(readlink /proc/$SP/ns/net); ok=0
  for mp in $(pgrep -f "$D/cgnat-map.py"); do [ "$(readlink /proc/$mp/ns/net)" = "$NS" ] && ok=1 || kill $mp; done
  [ $ok = 1 ] || { setsid nohup $N python3 $D/cgnat-map.py $D/cgnat-map.log >> $D/cgnat-map.err 2>&1 < /dev/null & log "start cgnat-map"; }
  # --- host: TPROXY -> gost redu -> relay
  pgrep -f "gost -L redu://:$RPORT" >/dev/null || { setsid nohup $G -L "redu://:$RPORT?ttl=60s" -F "relay://$RELAY" >> $D/cgnat-udp.log 2>&1 < /dev/null & log "start gost redu :$RPORT -> relay $RELAY"; }
  iptables -t mangle -C PREROUTING -i $BR -s $POOL -p udp $C -j TPROXY --on-port $RPORT --tproxy-mark $MARK/0xffffffff 2>/dev/null || \
    { iptables -t mangle -A PREROUTING -i $BR -s $POOL -p udp $C -j TPROXY --on-port $RPORT --tproxy-mark $MARK/0xffffffff; log "host TPROXY"; }
  ip rule show | grep -q "^$TM:" || ip rule add fwmark $MARK lookup $TM pref $TM
  ip route show table $TM 2>/dev/null | grep -q local || ip route replace local 0.0.0.0/0 dev lo table $TM
  ip rule show | grep -q "^$T:" || ip rule add to $POOL lookup $T pref $T
  ip route show table $T 2>/dev/null | grep -q "$SRV" || ip route replace $POOL via $SRV dev $BR table $T
  iptables -C DOCKER-USER -i $BR -s $POOL $C -j DROP 2>/dev/null || iptables -I DOCKER-USER 1 -i $BR -s $POOL $C -j DROP
  dedupe "" mangle PREROUTING "TPROXY"; dedupe "" filter DOCKER-USER "$POOL"
  dedupe "$N" nat POC_INET "dport 53 -m comment --comment poc-inet -j RETURN"; dedupe "$N" nat POSTROUTING "POC_CGNAT"; dedupe "$N" filter FORWARD "POC_CGNAT_FWD"
  return 0
}
remove() {
  pkill -f "gost -L redu://:$RPORT"; pkill -f "$D/cgnat-map.py"
  while iptables -t mangle -D PREROUTING -i $BR -s $POOL -p udp $C -j TPROXY --on-port $RPORT --tproxy-mark $MARK/0xffffffff 2>/dev/null; do :; done
  while iptables -D DOCKER-USER -i $BR -s $POOL $C -j DROP 2>/dev/null; do :; done
  while ip rule del pref $TM 2>/dev/null; do :; done; ip route flush table $TM 2>/dev/null
  while ip rule del pref $T 2>/dev/null; do :; done; ip route flush table $T 2>/dev/null
  if [ -n "$SP" ] && [ "$SP" != 0 ]; then
    for ip in $CGNAT_DNS; do while $N iptables -t nat -D POC_INET -d $ip/32 -p udp --dport 53 $C -j RETURN 2>/dev/null; do :; done; done
    while $N iptables -t nat -D POSTROUTING -o eth0 -s 10.45.0.0/16 $C -j POC_CGNAT 2>/dev/null; do :; done
    $N iptables -t nat -F POC_CGNAT 2>/dev/null; $N iptables -t nat -X POC_CGNAT 2>/dev/null
    while $N iptables -D FORWARD -s 10.45.0.0/16 $C -j POC_CGNAT_FWD 2>/dev/null; do :; done
    $N iptables -F POC_CGNAT_FWD 2>/dev/null; $N iptables -X POC_CGNAT_FWD 2>/dev/null
    while $N ip rule del pref $T 2>/dev/null; do :; done; $N ip route flush table $T 2>/dev/null
  fi
  echo "cgnat removed"
}
status() {
  echo "relay $RELAY: $(relay_up && echo listen || echo MATI)"; pgrep -af "gost -L redu|cgnat-map" | cut -c1-140
  [ -n "$SP" ] && { $N ip rule show | grep "^$T:"; $N iptables -t nat -L POC_CGNAT -v -n 2>/dev/null | awk 'NR>2 && $1>0'; $N iptables -L POC_CGNAT_FWD -v -n 2>/dev/null | awk 'NR>2 && $1>0'
    $N iptables -t nat -L POC_INET -v -n | grep 'dpt:53' ; }
  iptables -t mangle -L PREROUTING -v -n | grep TPROXY; ip rule | grep -E "^($T|$TM):"
  tail -5 $D/cgnat-map.log 2>/dev/null
}
case "$1" in apply) apply ;; remove) remove ;; status) status ;; *) echo "cgnat.sh apply|remove|status"; exit 2 ;; esac
