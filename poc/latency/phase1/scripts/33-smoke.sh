#!/bin/bash
# Smoke test v0.4 (tanpa butuh UE): start VPN, 1 TCP + 1 UDP, stop VPN, cek tun0 hilang.
. ~/poc-latency/phase0/common-vm.sh
PKG=id.magnon.poc.examine; A="timeout 40 $D exec $EMU adb -s emulator-5554"
OUT=~/poc-latency/phase1/smoke-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT; echo OUT=$OUT
$A logcat -c
$A shell am start -n $PKG/.MainActivity >/dev/null; sleep 3
echo "## up:"; $A shell 'ip -4 -br a show tun0'
$A shell am start -n $PKG/.GenActivity --ei tcpCount 1 --ei udpCount 1 >/dev/null; sleep 10
$A shell am force-stop $PKG; sleep 2
echo "## after stop:"; $A shell 'ip -4 -br a show tun0 2>&1; dumpsys connectivity | grep -c "VPN CONNECTED"'
$A logcat -d -v epoch -s MAGNON_EXAMINE:V MAGNON_GEN:V AndroidRuntime:E > $OUT/logcat.txt; cut -c1-300 $OUT/logcat.txt
