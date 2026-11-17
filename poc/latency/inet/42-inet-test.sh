#!/bin/bash
# poc-inet test (magen): UE netns (dig/curl/ping), emulator (container curl, Android nc + Chrome), lalu Zeek netprobe-zeek-live.
# Pakai: bash 42-inet-test.sh [WAIT_ZEEK detik, default 330]   Output: run/test-<ts>/
cd "$(dirname "$0")"; . ~/poc-latency/phase0/common-vm.sh; . ./common-inet.sh
OUT=$RUN/test-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT; echo "OUT=$OUT"; date -Is
{
echo "########## [UE netns l5g-ue] $(date -Is)"
$V "sudo -n bash -s" <<'VEOF'
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); N="nsenter -t $P -n"
$N ip -br -4 a show tun_srsue; $N ip r
echo "--- dig @10.99.9.20 example.com (DNS dari SMF -> gost dns -> TCP 1.1.1.1 via SOCKS)"
$N dig +time=5 +tries=2 @10.99.9.20 example.com A | grep -E 'status|^example|Query time|SERVER'
echo "--- dig @8.8.8.8 google.com (DNS publik, di-redirect)"
$N dig +time=5 +tries=2 @8.8.8.8 google.com A +short
IP=$($N dig +short +time=5 @10.99.9.20 example.com A | grep -E '^[0-9.]+$' | head -1); echo "example.com=$IP"
echo "--- curl https://example.com --interface tun_srsue"
$N curl -sS -m 25 --interface tun_srsue --resolve example.com:443:$IP -o /tmp/poc-inet-ue-body.html \
  -w 'http=%{http_code} ip=%{remote_ip} connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s size=%{size_download}\n' https://example.com
grep -o '<title>[^<]*' /tmp/poc-inet-ue-body.html
GIP=$($N dig +short +time=5 @10.99.9.20 www.google.com A | grep -E '^[0-9.]+$' | head -1)
$N curl -sS -m 25 --interface tun_srsue --resolve www.google.com:443:$GIP -o /dev/null -w 'google http=%{http_code} ip=%{remote_ip} total=%{time_total}s\n' https://www.google.com
echo "--- ping 8.8.8.8 (ICMP; diperkirakan GAGAL karena SOCKS hanya TCP)"
$N ping -c 3 -W 2 8.8.8.8 | tail -2
echo "--- ping 10.99.9.20 (kontrol)"; $N ping -c 2 -W 2 10.99.9.20 | tail -1
VEOF
echo "########## [emulator container $EMU, jalur fase 0 -> UE] $(date -Is)"
$D exec $EMU sh -c 'curl -sS -m 25 -o /dev/null -w "container curl example.com http=%{http_code} ip=%{remote_ip} total=%{time_total}s\n" https://example.com; getent hosts example.com'
echo "--- Android (adb shell): DNS + HTTP via toybox nc"
$D exec $EMU sh -c 'adb shell "ping -c1 -W3 example.com 2>&1 | head -1"; adb shell "printf \"HEAD / HTTP/1.0\r\nHost: example.com\r\n\r\n\" | nc -w 10 example.com 80 | head -3"'
echo "--- Android Chrome buka https://example.com"
$D exec $EMU sh -c 'adb shell input keyevent KEYCODE_WAKEUP; adb shell am start -a android.intent.action.VIEW -d https://example.com/?poc-inet >/dev/null; sleep 12; adb exec-out screencap -p > /tmp/poc-inet-emu.png'
$D cp $EMU:/tmp/poc-inet-emu.png $OUT/emulator-chrome.png && ls -la $OUT/emulator-chrome.png
echo "--- counter + log gost"; $V 'sudo -n bash -s' <<'VEOF'
S=$(docker inspect -f '{{.State.Pid}}' l5g-server); nsenter -t $S -n iptables -t nat -L POC_INET -v -n | awk 'NR<=2 || $1>0'
tail -n 300 /home/lab/poc-inet/srv.log | grep -oE '"msg":"[^"]*<>[^"]*"' | sort | uniq -c | sort -rn | head -12
VEOF
} 2>&1 | tee $OUT/test.txt
echo "### tunggu rotasi zeek-live ${1:-330}s"; sleep ${1:-330}
$V 'sudo -n bash -s' <<'VEOF' 2>&1 | tee $OUT/zeek.txt
L=/dev/shm/netprobe-zeek-live
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); UE=$(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}' | cut -d/ -f1); echo "UE_IP=$UE"
for t in conn dns ssl http; do
  for f in $(ls -t $L/$t.*.log 2>/dev/null | head -2); do
    echo "===== $f"; grep -h "\"$UE\"" $f | grep -v '"10.99.9.20","id.resp_p":9000' | grep -vE '"id.resp_h":"10\.99\.9\.20","id.resp_p":(5201)' | grep -v '"proto":"icmp"' | tail -25
  done
done
echo "===== tunnel parents (sampel)"
for u in $(ls -t $L/conn.*.log | head -2 | xargs grep -h "\"$UE\"" | grep -v '10.99.9.20' | grep -oE '"tunnel_parents":\[[^]]*\]' | grep -oE 'C[A-Za-z0-9]+' | sort -u | head -3); do grep -h "\"$u\"" $(ls -t $L/tunnel.*.log | head -2) | head -1; done
VEOF
echo "DONE $OUT"
