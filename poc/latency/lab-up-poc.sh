#!/bin/bash
# Bring-up all-in-one PoC latency (host lab, idempoten). Pakai: bash ~/poc-latency/lab-up-poc.sh [--no-inet]
#  1) cek UE l5g-ue attach (tun_srsue + ping 10.99.9.20); bila tidak: siklus RAN bersih (stop ue+enb, start enb, 8 s, start ue), maks 2x
#  2) keepalive permanen UE   3) jalur emulator fase 0 (20-setup-vm.sh)   4) UDP echo :9000   5) inet proxy (poc-inet)   6) status
# Tidak menyentuh core Open5GS, probe, lab5g-dev, l5g-syn-*. Rollback: lab-down-poc.sh
set -u
ROOT=~/poc-latency
. "$ROOT/phase0/common-vm.sh" 2>/dev/null || . "$ROOT/phase0/scripts/common-vm.sh"
P1=$ROOT/phase1/scripts; INET=$ROOT/inet
SETUP=$ROOT/phase0/20-setup-vm.sh; [ -f "$SETUP" ] || SETUP=$ROOT/phase0/scripts/20-setup-vm.sh
ue_ok() { $V 'sudo -n bash -s' <<'VEOF'
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue 2>/dev/null); [ -n "$P" ] && [ "$P" != 0 ] || exit 1
nsenter -t $P -n ip -4 -br a show tun_srsue 2>/dev/null | grep -q '10\.45\.' || exit 1
nsenter -t $P -n ip route replace 10.99.9.0/24 dev tun_srsue
nsenter -t $P -n ping -c 2 -W 3 10.99.9.20 >/dev/null
VEOF
}
echo "=== 1. UE attach"; n=0
until ue_ok; do
  n=$((n+1)); [ $n -gt 2 ] && { echo "GAGAL: UE tidak attach setelah 2 siklus RAN. Cek log l5g-ue/l5g-enb/l5g-mme."; exit 1; }
  echo "UE belum attach/tidak ping -> siklus RAN bersih #$n"; bash $P1/37-ran-cycle.sh | grep -E 'RESULT|attach|IP' | tail -4
done; echo "UE OK"
echo "=== 2. keepalive permanen"; bash $P1/35-keepalive.sh start | tail -2
echo "=== 3. jalur emulator (fase 0)"; bash "$SETUP" 2>&1 | tail -3
echo "=== 4. UDP echo :9000"; bash $P1/32-udp-echo-start.sh 2>&1 | tail -2
if [ "${1:-}" != "--no-inet" ]; then
  echo "=== 5. inet proxy"
  ss -ltn | grep -q '127.0.0.1:11080 ' || echo "PERINGATAN: tunnel laptop belum aktif -> di WSL: bash ~/poc-inet/poc-inet-laptop.sh start"
  bash $INET/40-inet-setup.sh 2>&1 | grep -E 'PERINGATAN|pid=|disalin|ERR'
fi
echo "=== 6. status"
$V 'sudo -n bash -s' <<'VEOF'
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); echo "UE: $(nsenter -t $P -n ip -4 -br a show tun_srsue | awk '{print $3}')"
echo "keepalive: $(tail -1 /tmp/poc-phase1-ka.log)"
S=$(docker inspect -f '{{.State.Pid}}' l5g-server); nsenter -t $S -n ss -lun | grep -q ':9000 ' && echo "echo :9000 OK" || echo "echo :9000 MATI"
docker ps --format '{{.Names}} {{.Status}}' | grep -E '^l5g-(ue|enb|mme|sgwc|sgwu|smf|upf|server) '
VEOF
[ "${1:-}" != "--no-inet" ] && bash $INET/41-inet-status.sh 2>&1 | grep -E 'SOCKS|internet|guard|tunnel'
echo "SELESAI $(date -Is)"
