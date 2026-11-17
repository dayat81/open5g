#!/bin/bash
# poc-inet: buka URL di Chrome emulator (lewati layar first-run "Turn on sync" bila muncul) + screenshot. Pakai: 43-emu-chrome.sh [url]
cd "$(dirname "$0")"; . ~/poc-latency/phase0/common-vm.sh; . ./common-inet.sh
URL=${1:-https://example.com/?poc-inet}; OUT=$RUN/emu-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT
$D exec $EMU sh -c "adb shell input keyevent KEYCODE_WAKEUP; W=\$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1); X=\${W%x*}; Y=\${W#*x}; echo size=\$W; adb shell input tap \$((X*84/576)) \$((Y*933/1024)); sleep 3; adb shell am start -a android.intent.action.VIEW -d '$URL' >/dev/null; sleep 15; adb exec-out screencap -p > /tmp/poc-inet-emu2.png; adb shell dumpsys activity activities | grep -m1 -E 'topResumedActivity|mResumedActivity'"
$D cp $EMU:/tmp/poc-inet-emu2.png $OUT/chrome.png; echo "$OUT/chrome.png $(date -Is)"
