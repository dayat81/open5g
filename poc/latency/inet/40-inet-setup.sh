#!/bin/bash
# poc-inet setup (host lab, idempoten). Prasyarat: tunnel laptop aktif (laptop/poc-inet-laptop.sh start) -> magen 127.0.0.1:11080.
# Jalur: UE/emulator -> GTP-U -> UPF (rule 2100) -> l5g-server netns: gost red/dns -> 10.99.9.254:11080 (gost fwd VM)
#   -> VM 127.0.0.1:11080 (ssh -R dari magen, loop) -> magen 127.0.0.1:11080 (ssh -R dinamis dari laptop) -> internet via laptop.
set -u
cd "$(dirname "$0")"; . ~/poc-latency/phase0/common-vm.sh; . ./common-inet.sh
echo "### [magen] cek SOCKS laptop 127.0.0.1:$SOCKS_PORT"
ss -ltn | grep -q "127.0.0.1:$SOCKS_PORT " && echo "OK listen" || echo "PERINGATAN: SOCKS laptop belum aktif (jalankan poc-inet-laptop.sh start di WSL)"
echo "### [magen] rule/table $TBL_INET: emulator (iif $EMU_BR) ke non-privat -> VM"
sudo -n ip route replace default via $VM dev $VIRBR table $TBL_INET
for p in $PRIV; do sudo -n ip route replace throw $p table $TBL_INET; done
ip rule show | grep -q "^$TBL_INET:" || sudo -n ip rule add iif $EMU_BR lookup $TBL_INET priority $TBL_INET
ip rule show | grep -E "^(2099|$TBL_INET):"
echo "### [VM] salin gost + script"
if [ ! -x bin/gost ]; then
  echo "ERR: inet/bin/gost tidak ada. Unduh gost 3.3.3 linux/amd64 (lihat inet/README.md) dan taruh di inet/bin/gost." >&2
  exit 1
fi
$V "mkdir -p $VM_DIR"
L=$(sha256sum bin/gost | cut -c1-64); R=$($V "sha256sum $VM_DIR/gost 2>/dev/null | cut -c1-64")
[ "$L" = "$R" ] || { scp -q $SSHVM_OPTS bin/gost lab@$VM:$VM_DIR/gost && echo "gost disalin"; }
scp -q $SSHVM_OPTS vm/apply.sh vm/remove.sh vm/guard.sh lab@$VM:$VM_DIR/ && $V "chmod +x $VM_DIR/gost $VM_DIR/*.sh"
[ -n "${DNS_UP:-}" ] && $V "echo $DNS_UP > $VM_DIR/dns_up"
echo "### [magen] tunnel magen->VM (ssh -R 127.0.0.1:$SOCKS_PORT), loop"
cat > $RUN/vm-tunnel.sh <<TEOF
#!/bin/bash
# poc-inet: tunnel magen -> lab5g-vm (VM 127.0.0.1:$SOCKS_PORT -> magen 127.0.0.1:$SOCKS_PORT). Stop: 49-inet-rollback.sh
while true; do
  ssh $SSHVM_OPTS -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -R 127.0.0.1:$SOCKS_PORT:127.0.0.1:$SOCKS_PORT lab@$VM
  echo "\$(date -Is) vm-tunnel exit \$?, retry 5 s"; sleep 5
done
TEOF
chmod +x $RUN/vm-tunnel.sh
if [ -f $RUN/vm-tunnel.pid ] && kill -0 $(cat $RUN/vm-tunnel.pid) 2>/dev/null; then echo "vm-tunnel sudah jalan pid=$(cat $RUN/vm-tunnel.pid)"; else
  setsid nohup $RUN/vm-tunnel.sh >> $RUN/vm-tunnel.log 2>&1 < /dev/null & echo $! > $RUN/vm-tunnel.pid; sleep 3; echo "vm-tunnel pid=$(cat $RUN/vm-tunnel.pid)"; fi
echo "### [VM] apply + guard"
$V "sudo -n bash -s" <<VEOF
$VM_DIR/apply.sh
if [ -f $VM_DIR/guard.pid ] && kill -0 \$(cat $VM_DIR/guard.pid) 2>/dev/null; then echo "guard sudah jalan pid=\$(cat $VM_DIR/guard.pid)"; else
  setsid nohup $VM_DIR/guard.sh >> $VM_DIR/guard.log 2>&1 < /dev/null & echo \$! > $VM_DIR/guard.pid; echo "guard pid=\$(cat $VM_DIR/guard.pid)"; fi
sleep 2; ss -ltnp | grep -E ':11080 '
VEOF
