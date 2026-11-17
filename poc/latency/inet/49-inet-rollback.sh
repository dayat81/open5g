#!/bin/bash
# poc-inet rollback (magen): hapus semua perubahan poc-inet di VM + magen. Tunnel laptop: poc-inet-laptop.sh stop (di WSL).
cd "$(dirname "$0")"; . ~/poc-latency/phase0/common-vm.sh; . ./common-inet.sh
$V "sudo -n bash /home/lab/poc-inet/remove.sh" || echo "remove.sh VM gagal/tidak ada"
[ -f $RUN/vm-tunnel.pid ] && kill $(cat $RUN/vm-tunnel.pid) 2>/dev/null; pkill -f "$RUN/vm-tunnel.sh"
pkill -f -- "-R 127.0.0.1:$SOCKS_PORT:127.0.0.1:$SOCKS_PORT lab@$VM"; rm -f $RUN/vm-tunnel.pid
while sudo -n ip rule del priority $TBL_INET 2>/dev/null; do :; done; sudo -n ip route flush table $TBL_INET 2>/dev/null
echo "magen poc-inet removed"; ip rule show | grep -E "^$TBL_INET:" || true
