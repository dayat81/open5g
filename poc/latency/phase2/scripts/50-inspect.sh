#!/bin/bash
# poc-phase2: inspeksi read-only (magen). Emulator packages, zeek-live config, versi zeek.
. ~/poc-latency/phase0/common-vm.sh 2>/dev/null || . ~/poc-latency/phase0/scripts/common-vm.sh
date -Is
A="timeout 30 $D exec $EMU adb -s emulator-5554"
echo "### emu"; $A shell 'getprop ro.build.version.sdk; getprop ro.product.cpu.abi; pm list packages | grep -iE "chrome|browser|webview"; dumpsys package com.android.chrome | grep -m2 versionName'
$A shell 'ip -4 -br a; ip route; getprop net.dns1'
$V 'sudo -n bash -s' <<'VEOF'
echo "### VM docker"; docker ps --format '{{.Names}} | {{.Image}} | {{.Status}}'
echo "### zeek-live"
docker inspect netprobe-zeek-live --format '{{json .Config.Cmd}} {{json .Config.Entrypoint}} {{.HostConfig.NetworkMode}} {{json .HostConfig.RestartPolicy}}'
docker inspect netprobe-zeek-live --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Mode}}){{"\n"}}{{end}}'
docker exec netprobe-zeek-live sh -c 'zeek --version; ps -ef | head -20; ls -la /usr/local/zeek/share/zeek/site 2>/dev/null | head; cat /usr/local/zeek/share/zeek/site/local.zeek 2>/dev/null | grep -v "^#" | grep -v "^$" | head -40' 2>&1 | head -80
ls /dev/shm/netprobe-zeek-live | tail -15
echo "### ka"; tail -2 /tmp/poc-phase1-ka.log
P=$(docker inspect -f '{{.State.Pid}}' l5g-ue); nsenter -t $P -n ip -4 -br a show tun_srsue
ip -br link | grep -iE "mirror|vlan" | head
VEOF
