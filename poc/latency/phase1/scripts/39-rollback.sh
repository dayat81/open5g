#!/bin/bash
# Rollback phase 1: stop VPN, uninstall APK, hapus APK sementara di container. (Jalur phase0 TIDAK disentuh.)
. ~/poc-latency/phase0/common-vm.sh 2>/dev/null || . ~/poc-latency/phase0/scripts/common-vm.sh
A="$D exec $EMU adb -s emulator-5554"
$A shell am force-stop id.magnon.poc.examine; sleep 2
$A uninstall id.magnon.poc.examine
$D exec $EMU rm -f /tmp/magnon-poc-examine.apk
$A shell 'pm list packages id.magnon.poc.examine; ip -br a show tun0 2>&1'
