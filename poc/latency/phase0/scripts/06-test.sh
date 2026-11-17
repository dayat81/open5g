#!/bin/bash
# Path kunci SSH di host lab. Set LAB_USER (atau LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS)
# ke akun lab; placeholder LAB_USER menggantikan username personal (repo public).
# Langkah 3-5: Zeek live di guest (S1-U + SGi), trafik app dari emulator, kumpulkan bukti.
set -u
. "$(dirname "$0")/common.sh"
OUT=~/poc-latency/phase0/run-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT
echo "OUT=$OUT"
$G "sudo -n bash -s" <<'GEOF'
set -u
W=/home/lab/poc-phase0; rm -rf $W; mkdir -p $W/zeek-s1u $W/zeek-sgi $W/pcap; chown -R lab $W
bash /home/lab/lab5g-dev/lab-routes.sh >/dev/null
docker rm -f poc0-zeek-s1u poc0-zeek-sgi >/dev/null 2>&1
docker run -d --name poc0-zeek-s1u --net host --cap-add NET_RAW --cap-add NET_ADMIN -v $W/zeek-s1u:/logs -w /logs zeek/zeek:9.0.1 zeek -C -i br-4724ba3f624c -f 'udp port 2152' local >/dev/null
docker run -d --name poc0-zeek-sgi --net host --cap-add NET_RAW --cap-add NET_ADMIN -v $W/zeek-sgi:/logs -w /logs zeek/zeek:9.0.1 zeek -C -i br-ba8f283d800b -f 'host 10.99.9.20' local >/dev/null
nohup timeout 300 tcpdump -ni br-4724ba3f624c -s 256 -c 3000 -w $W/pcap/poc0-s1u.pcap udp port 2152 >/dev/null 2>&1 &
nohup timeout 300 tcpdump -ni br-ba8f283d800b -s 256 -c 3000 -w $W/pcap/poc0-sgi.pcap host 10.99.9.20 >/dev/null 2>&1 &
sleep 6; docker ps --filter name=poc0-zeek --format '{{.Names}} {{.Status}}'
P=$(docker inspect -f '{{.State.Pid}}' l5gd-ue); echo "UE_IP=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}')"
GEOF
# capture korelasi di magen (sisi emulator, sebelum MASQUERADE)
sudo -n timeout 120 tcpdump -ni $EMU_BR -s 256 -c 500 -w $OUT/magen-emu-br.pcap host $SERVER >/dev/null 2>&1 &
sleep 2
A="$D exec $EMU adb shell"
{
echo "### $(date -Is) android: ip"; $A 'ip -4 -br a show eth0; ip route get 10.99.9.20'
echo "### $(date -Is) android: ping"; $A 'ping -c 5 -W 2 10.99.9.20' 2>&1
echo "### $(date -Is) android: HTTP via nc (toybox)"; $A "printf 'GET /?src=android-nc HTTP/1.0\r\nHost: 10.99.9.20\r\nUser-Agent: magnon-phase0-nc/emulator-5554\r\n\r\n' | nc -w 5 10.99.9.20 8080" 2>&1
echo "### $(date -Is) android: UDP echo"; $A "echo magnon-phase0-udp-\$(date +%s) | nc -u -w 3 10.99.9.20 9000" 2>&1
for i in 1 2 3; do $A "echo magnon-phase0-udp-seq$i | nc -u -w 1 10.99.9.20 9000" >/dev/null 2>&1; done
echo "### $(date -Is) android: Chrome app -> http://10.99.9.20:8080/"; $A 'am start -a android.intent.action.VIEW -d "http://10.99.9.20:8080/?src=android-chrome" com.android.chrome' 2>&1
sleep 15
$D exec $EMU adb exec-out screencap -p > $OUT/emulator-chrome.png
echo "screencap bytes: $(stat -c %s $OUT/emulator-chrome.png)"
echo "### $(date -Is) android: HTTP via nc kedua"; $A "printf 'GET /?src=android-nc-2 HTTP/1.0\r\nHost: 10.99.9.20\r\nUser-Agent: magnon-phase0-nc/emulator-5554\r\n\r\n' | nc -w 5 10.99.9.20 8080" 2>&1 | head -3
} 2>&1 | tee $OUT/android-traffic.txt
sleep 5
sudo -n pkill -f "tcpdump -ni $EMU_BR" ; sleep 1
sudo -n chown $(id -u) $OUT/*.pcap 2>/dev/null
$G "sudo -n bash -s" <<'GEOF'
W=/home/lab/poc-phase0
docker stop -t 20 poc0-zeek-s1u poc0-zeek-sgi >/dev/null
pkill -f "tcpdump -ni br-4724ba3f624c -s 256" ; pkill -f "tcpdump -ni br-ba8f283d800b -s 256"; sleep 1
docker logs poc0-zeek-s1u > $W/zeek-s1u/zeek-stdout.txt 2>&1; docker logs poc0-zeek-sgi > $W/zeek-sgi/zeek-stdout.txt 2>&1
docker rm poc0-zeek-s1u poc0-zeek-sgi >/dev/null
P=$(docker inspect -f '{{.State.Pid}}' l5gd-ue); nsenter -t $P -n iptables -t nat -L POSTROUTING -v -n > $W/ue-nat-counters.txt
iptables -L DOCKER-USER -v -n > $W/guest-docker-user-counters.txt
docker logs --since 10m l5gd-ue > $W/l5gd-ue-log.txt 2>&1
chown -R lab $W; ls -la $W $W/*; cd /home/lab && tar czf /tmp/poc0-guest.tgz poc-phase0
GEOF
scp -q -i /ftpdata/${LAB_USER:-LAB_USER}/lab5g-dev/vm/lab_id_ed25519 -o BatchMode=yes -o LogLevel=ERROR lab@$GUEST:/tmp/poc0-guest.tgz $OUT/
cd $OUT && tar xzf poc0-guest.tgz && rm poc0-guest.tgz
cd ~/poc-latency/phase0 && tar czf $(basename $OUT).tgz $(basename $OUT) && ls -la $(basename $OUT).tgz
