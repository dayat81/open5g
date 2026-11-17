#!/bin/bash
# Phase 1: start VPN examine -> generator (TCP 5201 x3 + UDP 9000 x5) lewat tun0 -> bukti logcat/dumpsys/screenshot/pcap/Zeek.
set -u
. ~/poc-latency/phase0/common-vm.sh 2>/dev/null || . ~/poc-latency/phase0/scripts/common-vm.sh
PKG=id.magnon.poc.examine
OUT=~/poc-latency/phase1/run-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT; echo "OUT=$OUT"
A="timeout 40 $D exec $EMU adb -s emulator-5554"
$V 'sudo -n bash -s' <<'VEOF'
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue)
nsenter -t $P -n ip route replace 10.99.9.0/24 dev tun_srsue 2>/dev/null
echo "UE_IP=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}')"
VEOF
date -Is > $OUT/magen-date.txt; $A shell 'date +%s.%N' >> $OUT/magen-date.txt; $V 'date -Is; date +%s.%N' >> $OUT/magen-date.txt
sudo -n timeout 120 tcpdump -ni $EMU_BR -s 256 -c 500 -w $OUT/magen-emu-br.pcap host $SERVER >/dev/null 2>&1 &
$A logcat -c
{
echo "### $(date -Is) start VPN"; $A shell am start -n $PKG/.MainActivity; sleep 4
echo "### $(date -Is) tun0 / rules / dumpsys"
$A shell 'ip -4 -br a show tun0; ip route show table all | grep -E "tun0" | head; ip rule | grep -iE "vpn|tun0|uidrange" | head'
$A shell "dumpsys connectivity | grep -iE 'VPN|tun0' | head -15"
$A exec-out screencap -p > $OUT/screen-vpn.png
echo "### $(date -Is) generator (app sama, uid VPN-allowed)"
$A shell am start -n $PKG/.GenActivity --es host $SERVER --ei tcpPort 5201 --ei tcpCount 3 --ei udpPort 9000 --ei udpCount 5
sleep 10
$A exec-out screencap -p > $OUT/screen-gen.png
echo "### $(date -Is) selesai trafik"
} 2>&1 | tee $OUT/android-steps.txt
$A logcat -d -v epoch -s MAGNON_EXAMINE:V MAGNON_GEN:V AndroidRuntime:E > $OUT/logcat-magnon.txt
$A shell am broadcast -n $PKG/.StopReceiver >/dev/null; sleep 2; $A shell ip -4 -br a show tun0 > $OUT/after-stop-broadcast.txt 2>&1; $A shell am force-stop $PKG; sleep 1
$A shell 'ip -4 -br a show tun0 2>&1' > $OUT/after-stop-tun0.txt
sleep 3; sudo -n pkill -f "tcpdump -ni $EMU_BR"; sleep 1; sudo -n chown $(id -u) $OUT/*.pcap 2>/dev/null
sudo -n tcpdump -nr $OUT/magen-emu-br.pcap -A 2>/dev/null | grep -E 'IP |magnonpoc|MAGNON-POC' > $OUT/magen-emu-br.txt
echo "### logcat ringkas"; grep -cE 'dir=' $OUT/logcat-magnon.txt; grep -E 'VPN up|flow open|MAGNON_GEN|FATAL|Exception' $OUT/logcat-magnon.txt | head -30
$V 'sudo -n tail -20 /tmp/poc-phase1-udp-echo.log' > $OUT/udp-echo-server.log 2>&1; echo "### udp echo server"; cat $OUT/udp-echo-server.log
echo "### tunggu rotasi zeek-live"; sleep ${WAIT_ZEEK:-320}
$V 'sudo -n bash -s' > $OUT/zeek-extract.txt 2>&1 <<'VEOF'
L=/dev/shm/netprobe-zeek-live
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); UE=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}' | cut -d/ -f1)
echo "UE_IP=$UE"; ls -la $L | grep -E 'conn|tunnel' | tail -6
for t in conn tunnel; do
  for f in $(ls -t $L/$t*.log 2>/dev/null | head -2); do
    echo "===== $f"; grep -E "\"$UE\"|10\\.99\\.9\\.20" $f | tail -30
  done
done
echo "===== tunnel parents"
for u in $(ls -t $L/conn*.log | head -2 | xargs grep -h "\"$UE\"" | grep -oE '"tunnel_parents":\[[^]]*\]' | grep -oE 'C[A-Za-z0-9]+' | sort -u); do grep -h "\"$u\"" $(ls -t $L/tunnel*.log | head -2) | head -2; done
echo "===== NAT counters"; nsenter -t $P -n iptables -t nat -L POSTROUTING -v -n | grep poc-phase0
VEOF
head -120 $OUT/zeek-extract.txt
cd ~/poc-latency/phase1 && tar czf $(basename $OUT).tgz $(basename $OUT) && ls -la $(basename $OUT).tgz
