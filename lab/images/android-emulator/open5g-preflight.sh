#!/bin/bash
# Open5G preflight. Run in the emulator entrypoint before QEMU starts.
# Upstream docker-android does not ship this file.
set -euo pipefail

echo "android-emulator: AI_ADDRCONFIG preflight"

ula=${ANDROID_UE_IPV6_ULA:-fd00::1/128}
case "$ula" in
  *:*/128) ;;
  *)
    echo "android-emulator: ANDROID_UE_IPV6_ULA must be an IPv6 address with /128" >&2
    exit 1
    ;;
esac
case "$ula" in
  *REPLACE*|*CHANGEME*)
    echo "android-emulator: ANDROID_UE_IPV6_ULA is still a placeholder" >&2
    exit 1
    ;;
esac
addr=${ula%/*}
ip link add dummy0 type dummy >/dev/null 2>&1 || true
if ! ip link show dummy0 >/dev/null 2>&1; then
  echo "android-emulator: cannot create dummy0. The ULA anchor is required for getaddrinfo AI_ADDRCONFIG." >&2
  exit 1
fi
ip link set dummy0 up
sys=/proc/sys/net/ipv6/conf/dummy0/disable_ipv6
if [ -w "$sys" ]; then
  printf '0\n' >"$sys"
fi
if ! ip -6 addr show dev dummy0 | grep -q "inet6 ${addr}/128"; then
  ip -6 addr add "$ula" dev dummy0 nodad
fi
while read -r route; do
  [ -n "$route" ] || continue
  # shellcheck disable=SC2086
  ip -6 route del $route
done < <(ip -6 route show dev dummy0 || true)
if ip -6 route show default | grep -v unreachable | grep -q .; then
  echo "android-emulator: IPv6 anchor must not add a usable default route" >&2
  ip -6 route show >&2 || true
  exit 1
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

def usable(flags, name):
    flags_i = int(flags, 16)
    if flags_i & 0x40 or flags_i & 0x08:
        return False
    flagfile = pathlib.Path("/sys/class/net") / name / "flags"
    if not flagfile.exists():
        return False
    return bool(int(flagfile.read_text(encoding="utf-8").strip(), 16) & 0x1)

text = pathlib.Path("/proc/net/if_inet6").read_text(encoding="utf-8")
ok = False
for line in text.splitlines():
    parts = line.split()
    if len(parts) < 6:
        continue
    addr, _idx, _plen, _scope, flags, name = parts[:6]
    if name == "lo":
        continue
    prefix = addr[:2].lower()
    if prefix in ("fd", "fc") and name == "dummy0" and usable(flags, name):
        print("android-emulator: ULA anchor on dummy0")
        ok = True
        break
    if addr.lower().startswith("fe80") and usable(flags, name):
        print("android-emulator: usable fe80 on %s" % name)
        ok = True
        break
if not ok:
    print("android-emulator: no ULA on dummy0 and no UP non-tentative fe80", file=sys.stderr)
    sys.exit(1)
PY

echo "android-emulator: accel-check"
emulator -accel-check
