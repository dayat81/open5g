#!/bin/bash
# poc-phase2 status (read-only): zeek mglt container, log terbaru, keepalive, VPN emulator
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
$V "sudo -n bash -c 'docker ps --filter name=$ZCT --format \"{{.Names}} {{.Status}}\"; docker logs --tail 3 $ZCT 2>&1; ls -la $ZLOG; docker stats --no-stream --format \"{{.Name}} {{.CPUPerc}} {{.MemUsage}}\" $ZCT; tail -1 /tmp/poc-phase1-ka.log'"
$D exec $EMU adb -s emulator-5554 shell 'ip -4 -br a show tun0 2>&1; dumpsys package id.magnon.poc.examine | grep -m1 versionName'
