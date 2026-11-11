#!/bin/bash
# Open5G preflight. Run in the emulator entrypoint before QEMU starts.
# Upstream docker-android does not ship this file.
set -euo pipefail

echo "android-emulator: AI_ADDRCONFIG preflight"

anchor=${ANDROID_UE_IPV6_ANCHOR:-1}
if [ "$anchor" = "1" ]; then
  ip link add dummy0 type dummy >/dev/null 2>&1 || true
  if ip link show dummy0 >/dev/null 2>&1; then
    ip link set dummy0 up
    if ! ip -6 addr show dev dummy0 | grep -q 'inet6 fd00::1/128'; then
      ip -6 addr add fd00::1/128 dev dummy0 nodad
    fi
    ip -6 route del fd00::1/128 dev dummy0 >/dev/null 2>&1 || true
  else
    echo "android-emulator: dummy0 ULA anchor is unavailable; relying on fe80" >&2
  fi
  if ip -6 route show default | grep -q .; then
    echo "android-emulator: IPv6 anchor must not add a default route" >&2
    ip -6 route show >&2 || true
    exit 1
  fi
fi

python3 -c 'import socket, sys
try:
    socket.getaddrinfo("::1", 5554, type=socket.SOCK_STREAM, flags=socket.AI_ADDRCONFIG)
except socket.gaierror as exc:
    print("android-emulator: getaddrinfo ::1 with AI_ADDRCONFIG failed: %s" % exc, file=sys.stderr)
    sys.exit(1)
print("android-emulator: getaddrinfo ::1 with AI_ADDRCONFIG succeeded")
'

if ! ip -6 addr show dev lo | grep -q 'inet6 ::1'; then
  echo "android-emulator: ::1 is missing on lo" >&2
  exit 1
fi

python3 - <<'PY'
import pathlib
import sys
text = pathlib.Path("/proc/net/if_inet6").read_text(encoding="utf-8")
ok = False
for line in text.splitlines():
    parts = line.split()
    if len(parts) < 6:
        continue
    addr, _idx, _plen, scope, flags, name = parts[:6]
    if not addr.startswith("fe80") or name == "lo":
        continue
    flags_i = int(flags, 16)
    if flags_i & 0x40 or flags_i & 0x08:
        continue
    flagfile = pathlib.Path("/sys/class/net") / name / "flags"
    if not flagfile.exists():
        continue
    if int(flagfile.read_text(encoding="utf-8").strip(), 16) & 0x1:
        print("android-emulator: usable fe80 on %s" % name)
        ok = True
        break
if not ok:
    print("android-emulator: no UP interface has a non-tentative fe80 address", file=sys.stderr)
    sys.exit(1)
PY

echo "android-emulator: accel-check"
emulator -accel-check
