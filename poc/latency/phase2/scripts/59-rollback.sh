#!/bin/bash
# poc-phase2 rollback (magen). TIDAK menyentuh: keepalive UE, jalur poc-phase0, poc-inet, echo UDP :9000, netprobe-zeek-live.
#  1) stop VPN v0.7 + kembalikan app ke v0.6 (phase1) + appops VPN   (KEEP_APP=1 untuk tetap v0.7)
#  2) hapus container Zeek poc-phase2-zeek-mglt (+ log tmpfs bila PURGE=1)
#  3) logcat buffer kembali 256K
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
A="timeout 60 $D exec $EMU adb -s emulator-5554"
echo "### [emu] stop VPN"; $A shell am broadcast -n $PKG/.StopReceiver >/dev/null 2>&1; $A shell am force-stop $PKG
if [ "${KEEP_APP:-0}" != 1 ] && [ -f ~/poc-latency/phase1/magnon-poc-examine.apk ]; then
  echo "### [emu] kembali ke v0.6 (uninstall v0.7, install phase1 apk)"
  $D cp ~/poc-latency/phase1/magnon-poc-examine.apk $EMU:/tmp/magnon-poc-examine.apk
  $A uninstall $PKG; $A install -r -g /tmp/magnon-poc-examine.apk; $A shell appops set $PKG ACTIVATE_VPN allow
  $A shell "dumpsys package $PKG | grep -m1 versionName"
fi
$A logcat -G 256K >/dev/null 2>&1
$A shell 'ip -4 -br a show tun0 2>&1'
echo "### [VM] hapus container $ZCT"
$V "sudo -n bash -c 'docker rm -f $ZCT 2>&1; [ \"${PURGE:-0}\" = 1 ] && rm -rf $ZLOG $VM_P2 && echo purged; docker ps -a --filter label=poc-phase2=1 --format \"{{.Names}}\"'"
echo "rollback poc-phase2 selesai (keepalive/poc-phase0/poc-inet/echo tidak diubah)"
