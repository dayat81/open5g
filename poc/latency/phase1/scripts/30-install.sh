#!/bin/bash
# Phase 1: pasang APK dummy VPN (mode examine) ke emulator b0-agen-emu + izin VPN via appops. Dijalankan di magen.
set -u
. ~/poc-latency/phase0/common-vm.sh 2>/dev/null || . ~/poc-latency/phase0/scripts/common-vm.sh
PKG=id.magnon.poc.examine; APK=~/poc-latency/phase1/magnon-poc-examine.apk
sha256sum $APK
$D cp $APK $EMU:/tmp/magnon-poc-examine.apk
$D exec $EMU adb -s emulator-5554 install -r -g /tmp/magnon-poc-examine.apk
$D exec $EMU adb -s emulator-5554 shell appops set $PKG ACTIVATE_VPN allow
$D exec $EMU adb -s emulator-5554 shell "pm list packages $PKG; appops get $PKG ACTIVATE_VPN; dumpsys package $PKG | grep -E 'versionName|userId' | head -3"
