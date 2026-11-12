#!/bin/bash
# Open5G preflight. Run in the emulator entrypoint before QEMU starts.
# This container has no NET_ADMIN. The script only reads the netns.
# The route sidecar creates dummy0, brings it up, and adds the ULA.
set -euo pipefail

echo "android-emulator: AI_ADDRCONFIG preflight"

if ! command -v python3 >/dev/null 2>&1; then
  echo "android-emulator: python3 is missing. The image patch must install it." >&2
  exit 1
fi
if ! [ -c /dev/kvm ]; then
  echo "android-emulator: /dev/kvm is not a character device. The emulator needs the host device." >&2
  exit 1
fi

ula=${ANDROID_UE_IPV6_ULA:-fdc2:fd97:24a4::1/128}
python3 - "$ula" <<'PY'
import ipaddress
import sys
text = sys.argv[1]
if "/" not in text:
    sys.exit("android-emulator: ANDROID_UE_IPV6_ULA must be an fc00::/7 address with /128")
addr, prefix = text.split("/", 1)
if prefix != "128":
    sys.exit("android-emulator: ANDROID_UE_IPV6_ULA must use prefix /128")
try:
    ip = ipaddress.IPv6Address(addr)
except ipaddress.AddressValueError as exc:
    sys.exit("android-emulator: ANDROID_UE_IPV6_ULA is not an IPv6 address: %s" % exc)
if ip not in ipaddress.IPv6Network("fc00::/7"):
    sys.exit("android-emulator: ANDROID_UE_IPV6_ULA must be inside fc00::/7")
PY

if ! ip link show dummy0 >/dev/null 2>&1; then
  echo "android-emulator: dummy0 is missing. The route sidecar must create the ULA anchor before the emulator starts." >&2
  exit 1
fi
flags=$(cat /sys/class/net/dummy0/flags)
if [ $((flags & 1)) -ne 1 ]; then
  echo "android-emulator: dummy0 is not UP. The route sidecar must bring it up." >&2
  exit 1
fi
for key in lo dummy0; do
  val=$(cat "/proc/sys/net/ipv6/conf/${key}/disable_ipv6" 2>/dev/null || echo missing)
  if [ "$val" != "0" ]; then
    echo "android-emulator: disable_ipv6 on ${key} is ${val}. The route sidecar must leave it at 0." >&2
    exit 1
  fi
done
if ip -6 route show dev dummy0 | grep -q .; then
  echo "android-emulator: dummy0 still has a main-table route. The route sidecar must remove it." >&2
  ip -6 route show dev dummy0 >&2 || true
  exit 1
fi
if ! ip -6 route show | grep -q 'unreachable default'; then
  echo "android-emulator: the unreachable IPv6 default route is missing. The route sidecar must install it." >&2
  exit 1
fi
if ip -6 route show default | grep -v unreachable | grep -q .; then
  echo "android-emulator: a usable IPv6 default route is present" >&2
  ip -6 route show >&2 || true
  exit 1
fi
if ! ip -6 addr show dev lo | grep -q 'inet6 ::1'; then
  echo "android-emulator: ::1 is missing on lo" >&2
  exit 1
fi

python3 - "$ula" <<'PY'
import ipaddress
import pathlib
import socket
import sys

want = ipaddress.IPv6Address(sys.argv[1].split("/", 1)[0])
text = pathlib.Path("/proc/net/if_inet6").read_text(encoding="utf-8")
found = False
for line in text.splitlines():
    parts = line.split()
    if len(parts) < 6:
        continue
    raw, _idx, plen, _scope, flags, name = parts[:6]
    if name != "dummy0" or plen != "80":
        continue
    addr = ipaddress.IPv6Address(int(raw, 16))
    if addr != want:
        continue
    if int(flags, 16) & 0x48:
        sys.exit("android-emulator: ULA on dummy0 is tentative or dadfailed. The route sidecar must add it with nodad.")
    flagfile = pathlib.Path("/sys/class/net/dummy0/flags")
    if not int(flagfile.read_text(encoding="utf-8").strip(), 16) & 0x1:
        sys.exit("android-emulator: dummy0 is not UP. The route sidecar must bring it up.")
    found = True
    break
if not found:
    sys.exit("android-emulator: dummy0 has no non-tentative %s. The route sidecar must install that ULA before the emulator starts." % want)

try:
    socket.getaddrinfo("::1", 5554, type=socket.SOCK_STREAM, flags=socket.AI_ADDRCONFIG)
except socket.gaierror as exc:
    sys.exit("android-emulator: getaddrinfo ::1 with AI_ADDRCONFIG failed: %s" % exc)
print("android-emulator: ULA %s on dummy0; getaddrinfo ::1 with AI_ADDRCONFIG succeeded" % want)
PY

echo "android-emulator: accel-check"
emulator -accel-check
