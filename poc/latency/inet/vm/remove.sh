#!/bin/bash
# poc-inet remove (lab5g-vm, root): kebalikan apply.sh. Tidak menyentuh aturan poc-phase0/keepalive/echo.
D=/home/lab/poc-inet; T=2100; UU_BR=br-5bd8dbed8b33; SRC=172.22.10.1
cpid(){ docker inspect -f '{{.State.Pid}}' $1 2>/dev/null; }
[ -f $D/guard.pid ] && kill $(cat $D/guard.pid) 2>/dev/null; pkill -f "$D/guard.sh"; rm -f $D/guard.pid
bash $D/cgnat.sh remove 2>/dev/null
pkill -f "$D/gost -L"; sleep 1
SP=$(cpid l5g-server); if [ -n "$SP" ] && [ "$SP" != 0 ]; then N="nsenter -t $SP -n"
  while $N iptables -t nat -D PREROUTING -s 10.45.0.0/16 -m comment --comment poc-inet -j POC_INET 2>/dev/null; do :; done
  $N iptables -t nat -F POC_INET 2>/dev/null; $N iptables -t nat -X POC_INET 2>/dev/null; fi
UP=$(cpid l5g-upf); if [ -n "$UP" ] && [ "$UP" != 0 ]; then N="nsenter -t $UP -n"
  while $N ip rule del pref $T 2>/dev/null; do :; done; $N ip route flush table $T 2>/dev/null; fi
UEP=$(cpid l5g-ue); if [ -n "$UEP" ] && [ "$UEP" != 0 ]; then nsenter -t $UEP -n ip route del default dev tun_srsue 2>/dev/null; fi
while ip rule del pref $T 2>/dev/null; do :; done; ip route flush table $T 2>/dev/null
while iptables -D DOCKER-USER -i ens3 -o $UU_BR -s $SRC ! -d 10.0.0.0/8 -m comment --comment poc-inet -j ACCEPT 2>/dev/null; do :; done
while iptables -D DOCKER-USER -i $UU_BR -o ens3 -d $SRC -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment poc-inet -j ACCEPT 2>/dev/null; do :; done
echo "poc-inet VM removed"; pgrep -af "poc-inet" | grep -v remove.sh || true
