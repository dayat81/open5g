#!/bin/bash
# Trafik dari emulator ke l5g-server (tanpa listener baru: ICMP + TCP ke iperf3 :5201 yang sudah ada),
# lalu ambil log Zeek dari probe yang SUDAH ADA (netprobe-zeek-live, /dev/shm/netprobe-zeek-live) - read-only.
set -u
. "$(dirname "$0")/common-vm.sh"
OUT=~/poc-latency/phase0/vm-run-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT; echo "OUT=$OUT"
$V 'sudo -n bash -s' <<'VEOF'
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue)
nsenter -t $P -n ip route replace 10.99.9.0/24 dev tun_srsue 2>/dev/null
echo "UE_IP=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}')"
VEOF
sudo -n timeout 90 tcpdump -ni $EMU_BR -s 128 -c 300 -w $OUT/magen-emu-br.pcap host $SERVER >/dev/null 2>&1 &
sleep 2
A="timeout 40 $D exec $EMU adb shell"
{
echo "### $(date -Is) android ip/route"; $A 'ip -4 -br a show eth0; ip route get 10.99.9.20'
echo "### $(date -Is) android ping"; $A 'ping -c 5 -W 2 10.99.9.20' 2>&1
echo "### $(date -Is) android TCP ke l5g-server:5201 (iperf3 yg sudah ada), 3x"
for i in 1 2 3; do $A "echo magnon-phase0-tcp-$i | timeout 4 nc 10.99.9.20 5201 >/dev/null 2>&1; echo rc=\$?" 2>&1; sleep 1; done
echo "### $(date -Is) android UDP ke :9000 (tanpa listener; cukup terlihat di conn.log)"
$A "echo magnon-phase0-udp | timeout 3 nc -u 10.99.9.20 9000 >/dev/null 2>&1; echo rc=\$?" 2>&1
echo "### $(date -Is) selesai"
} 2>&1 | tee $OUT/android-traffic.txt
sleep 3; sudo -n pkill -f "tcpdump -ni $EMU_BR"; sleep 1; sudo -n chown $(id -u) $OUT/*.pcap 2>/dev/null
$D exec $EMU adb exec-out screencap -p > $OUT/emulator-screen.png 2>/dev/null
echo "### tunggu flush/rotasi zeek-live (rotasi 300 s)"; sleep ${WAIT_ZEEK:-320}
$V 'sudo -n bash -s' > $OUT/zeek-extract.txt 2>&1 <<'VEOF'
L=/dev/shm/netprobe-zeek-live
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); UE=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}' | cut -d/ -f1)
echo "UE_IP=$UE"; ls -la $L | grep -E 'conn|tunnel|gtp' | tail -20
for t in conn tunnel gtpv1 icmp; do
  for f in $(ls -t $L/$t*.log 2>/dev/null | head -3); do
    echo "===== $f (header + baris yang memuat $UE / 10.99.9.20 / 10.99.2.)"
    grep -E '^#(fields|types)' $f | head -2
    grep -P "$UE|10\\.99\\.9\\.20|\\t5201\\t|\\t9000\\t" $f | tail -40
  done
done
echo "===== VM tcpdump-free: counters UE NAT"; nsenter -t $P -n iptables -t nat -L POSTROUTING -v -n
iptables -L DOCKER-USER -v -n
VEOF
cat $OUT/zeek-extract.txt | head -150
cd ~/poc-latency/phase0 && tar czf $(basename $OUT).tgz $(basename $OUT) && ls -la $(basename $OUT).tgz
