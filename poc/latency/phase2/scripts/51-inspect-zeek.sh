#!/bin/bash
# poc-phase2: inspeksi read-only image/entrypoint netprobe-zeek-live (magen -> VM)
. ~/poc-latency/phase0/common-vm.sh 2>/dev/null || . ~/poc-latency/phase0/scripts/common-vm.sh
$V 'sudo -n bash -s' <<'VEOF'
free -m; nproc; uptime
docker exec netprobe-zeek-live sh -c 'cat /opt/netprobe/entrypoint.sh; ls -la /opt/netprobe /opt/netprobe/* 2>/dev/null | head -60'
cat /home/lab/lab5g/zeek-live/tap-map.csv
for p in /proc/[0-9]*; do c=$(tr '\0' ' ' < $p/cmdline 2>/dev/null); case "$c" in *zeek*) echo "$(basename $p): $c";; esac; done | grep -v probe | head
docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}' netprobe-zeek-live l5g-probe-zeek-s1u
head -c 600 $(ls -t /dev/shm/netprobe-zeek-live/conn.*.log | head -1); echo
VEOF
