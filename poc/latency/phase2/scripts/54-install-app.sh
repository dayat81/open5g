#!/bin/bash
# poc-phase2: pasang app v0.7 (allowed: app + com.android.chrome, route 0/0, DNS via forwarder, marker MGLT) + appops VPN.
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
APK=$P2/magnon-poc-examine-v0.7.apk
if [ ! -f "$APK" ]; then
  echo "ERR: $APK tidak ada. Bangun dulu: bash $P2/app/build.sh (APK tidak dilampirkan di git)." >&2
  exit 1
fi
sha256sum $APK
A="timeout 60 $D exec $EMU adb -s emulator-5554"
$D cp $APK $EMU:/tmp/magnon-poc-examine-v0.7.apk
$A shell am broadcast -n $PKG/.StopReceiver >/dev/null 2>&1; $A shell am force-stop $PKG
$A install -r -g /tmp/magnon-poc-examine-v0.7.apk
$A shell appops set $PKG ACTIVATE_VPN allow
$A shell "dumpsys package $PKG | grep -m2 -E 'versionName|userId'; appops get $PKG ACTIVATE_VPN; pm list packages com.android.chrome"
