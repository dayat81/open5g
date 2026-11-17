#!/bin/bash
# poc-phase2 test (magen): VPN examine v0.7 (app + Chrome, route 0/0) -> Chrome buka 2 situs lewat tun0 -> UE 10.45.0.x -> internet (poc-inet)
# Bukti: logcat (flow Chrome uid/pkg, mglt tx/echo RTT), pcap marker di bridge emulator magen, mglt.log (instance Zeek poc-phase2),
#        conn/ssl netprobe-zeek-live (flow Chrome dari UE dalam tunnel GTP), screenshot Chrome, skew sebelum/sesudah.
# Pakai: bash 56-test.sh [URL1] [URL2]     (WAIT_ZEEK=detik tunggu rotasi zeek-live, default sampai batas 5 mnt berikut + 40 s)
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
U1=${1:-https://example.com/?poc-phase2}; U2=${2:-https://www.wikipedia.org/}
OUT=$P2/results/run-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT; echo "OUT=$OUT"
A="timeout 60 $D exec $EMU adb -s emulator-5554"
CH=com.android.chrome
{
echo "### $(date -Is) precheck (read-only): UE, keepalive, poc-inet, zeek mglt"
$V 'sudo -n bash -s' <<'VEOF'
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); echo "UE: $(nsenter -t $P -n ip -4 -br a show tun_srsue)"
tail -1 /tmp/poc-phase1-ka.log; ss -ltn | grep -c ':11080 ' | sed 's/^/socks listen count=/'
docker ps --filter name=poc-phase2-zeek-mglt --format '{{.Names}} {{.Status}}'
VEOF
echo "### skew sebelum"; bash $P2/scripts/55-skew.sh
} 2>&1 | tee $OUT/precheck.txt
sudo -n timeout 300 tcpdump -ni $EMU_BR -s 200 -w $OUT/magen-emu-br-marker.pcap udp port 9000 >/dev/null 2>&1 &
sudo -n timeout 300 tcpdump -ni $EMU_BR -s 96 -c 20000 -w $OUT/magen-emu-br-tcp443.pcap 'tcp port 443 and tcp[tcpflags] & (tcp-syn|tcp-fin) != 0' >/dev/null 2>&1 &
sleep 1
$A logcat -G 16M >/dev/null 2>&1; $A logcat -c
{
echo "### $(date -Is) force-stop Chrome (flow bersih), start VPN v0.7 (allowed app+Chrome)"
$A shell am force-stop $CH
$A shell input keyevent KEYCODE_WAKEUP
$A shell am start -n $PKG/.MainActivity --es apps $CH; sleep 5
$A shell 'ip -4 -br a show tun0; ip rule | grep -iE "uidrange" | head -5; echo "global http_proxy (read-only, tidak diubah): $(settings get global http_proxy)"'
$A shell "dumpsys connectivity | grep -iE 'VPN.*(CONNECTED|tun0)|Underlying|allowed' | head -8"
$A exec-out screencap -p > $OUT/screen-vpn.png
$A shell input keyevent KEYCODE_HOME; sleep 1
$A shell "dumpsys package $CH | grep -m1 userId" | sed 's/^/Chrome /'
echo "### $(date -Is) Chrome -> $U1"
$A shell am start -W -a android.intent.action.VIEW -d "$U1" $CH; sleep 15
$A exec-out screencap -p > $OUT/screen-chrome-1.png
echo "### $(date -Is) Chrome -> $U2"
$A shell am start -a android.intent.action.VIEW -d "$U2" $CH; sleep 25
$A exec-out screencap -p > $OUT/screen-chrome-2.png
echo "### $(date -Is) selesai browsing"
} 2>&1 | tee $OUT/android-steps.txt
$A logcat -d -v epoch -s MAGNON_EXAMINE:V AndroidRuntime:E > $OUT/logcat-magnon.txt
$A shell am broadcast -n $PKG/.StopReceiver >/dev/null; sleep 2; $A shell am force-stop $PKG; sleep 1
$A shell 'ip -4 -br a show tun0 2>&1' > $OUT/after-stop-tun0.txt
echo "### skew sesudah" | tee -a $OUT/precheck.txt; bash $P2/scripts/55-skew.sh 2>&1 | tee -a $OUT/precheck.txt
sudo -n pkill -f "tcpdump -ni $EMU_BR" ; sleep 1; sudo -n chown $(id -u) $OUT/*.pcap 2>/dev/null
echo "### ringkas logcat"
grep -cE ' dir=' $OUT/logcat-magnon.txt | sed 's/^/pkt log lines=/'
grep -E 'VPN up|mglt ready|tcp flow open|udp flow open|drop quic|FATAL' $OUT/logcat-magnon.txt | head -40
grep -c 'mglt tx' $OUT/logcat-magnon.txt | sed 's/^/mglt tx=/'; grep -c 'mglt echo' $OUT/logcat-magnon.txt | sed 's/^/mglt echo=/'
grep 'mglt echo' $OUT/logcat-magnon.txt | head -5
echo "### mglt.log (instance poc-phase2) + conn marker"
$V "sudo -n bash -c 'cat $ZLOG/mglt*.log'" > $OUT/mglt.log 2>&1; wc -l < $OUT/mglt.log; head -4 $OUT/mglt.log
$V "sudo -n bash -c 'cat $ZLOG/conn*.log'" > $OUT/zeek-p2-conn.log 2>&1
# tunggu rotasi zeek-live (batas 5 menit + 40 s)
now=$(date +%s); W=${WAIT_ZEEK:-$(( (300 - now % 300) + 40 ))}; echo "### tunggu rotasi zeek-live ${W}s"; sleep $W
$V 'sudo -n bash -s' > $OUT/zeek-live-extract.txt 2>&1 <<'VEOF'
L=/dev/shm/netprobe-zeek-live
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); UE=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}' | cut -d/ -f1)
echo "UE_IP=$UE"
for t in conn ssl dns; do
  for f in $(ls -t $L/$t.*.log 2>/dev/null | head -2); do
    echo "===== $f"; grep -h "\"$UE\"" $f | grep -v '"proto":"icmp"' | grep -vE '"id.resp_h":"10\.99\.9\.20","id.resp_p":(9000|5201)' | tail -60
  done
done
echo "===== tunnel parents (sampel)"
for u in $(ls -t $L/conn.*.log | head -2 | xargs grep -h "\"$UE\"" | grep '"id.resp_p":443' | grep -oE '"tunnel_parents":\[[^]]*\]' | grep -oE 'C[A-Za-z0-9]+' | sort -u | head -3); do grep -h "\"$u\"" $(ls -t $L/tunnel.*.log | head -2) | head -1; done
VEOF
grep -c '"id.resp_p":443' $OUT/zeek-live-extract.txt | sed 's/^/zeek-live conn+ssl baris :443=/'
grep '"server_name"' $OUT/zeek-live-extract.txt | grep -oE '"server_name":"[^"]*"' | sort | uniq -c | head
cd $P2/results && tar czf $(basename $OUT).tgz $(basename $OUT) && ls -la $(basename $OUT).tgz
echo "DONE $OUT"
