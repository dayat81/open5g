#!/bin/bash
# poc-phase2: read-only - asal proxy 172.26.0.1:8080 yang dipakai Chrome
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
ps -o pid,lstart,user,args -p $(pgrep -f 'socat') 2>/dev/null | cut -c1-300
ls -la ~/poc-latency/inet/run/emu-*; tail -n 30 ~/poc-latency/inet/run/emu-*/* 2>/dev/null | cut -c1-300 | tail -60
grep -rn "http_proxy\|8080" ~/poc-latency/inet/*.sh ~/poc-latency/*.sh 2>/dev/null | head
sudo -n ss -tnp | grep -E '172.26.0.1:8080' | head -5
