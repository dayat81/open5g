#!/bin/bash
# Bersihkan proses toybox nc -u yang menggantung di emulator (nc -u tidak keluar setelah -w).
for i in $(seq 1 ${1:-8}); do
  sudo -n docker exec b0-agen-emu adb shell 'for p in $(pidof nc); do kill $p; echo killed $p; done' 2>&1
  sleep 3
done
