#!/bin/sh
# Shared bind checks for the host-side screen demo.
# Sourced by the streamer and the loopback publisher. No network calls.
# shellcheck shell=sh

screen_bind_ok() {
  screen_bind=$1
  case "$screen_bind" in
    ""|0.0.0.0|127.*|0.*|::|::1|"*")
      return 1
      ;;
  esac
  printf '%s\n' "$screen_bind" | awk -F. 'NF != 4 { exit 1 } { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i + 0 > 255) exit 1 }'
}

screen_discover_bind() {
  python3 -c 'import fcntl, socket, struct, sys
path = "/proc/net/route"
iface = ""
with open(path, encoding="ascii", errors="replace") as handle:
    next(handle, None)
    for line in handle:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "00000000" and parts[0] != "lo":
            iface = parts[0]
            break
if not iface:
    sys.exit(1)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    info = fcntl.ioctl(sock.fileno(), 0x8915, struct.pack("256s", iface.encode("ascii")[:15]))
except OSError:
    sys.exit(1)
address = socket.inet_ntoa(info[20:24])
if address.startswith("127.") or address == "0.0.0.0" or address.startswith("0."):
    sys.exit(1)
sys.stdout.write(address + "\n")'
}

screen_path_ok() {
  screen_path=$1
  case "$screen_path" in
    /emulator/*) ;;
    *) return 1 ;;
  esac
  screen_name=${screen_path#/emulator/}
  case "$screen_name" in
    *[!a-z0-9-]*) return 1 ;;
    [a-z]*) ;;
    *) return 1 ;;
  esac
  if [ "${#screen_name}" -lt 1 ] || [ "${#screen_name}" -gt 32 ]; then
    return 1
  fi
}

screen_port_ok() {
  screen_port=$1
  case "$screen_port" in
    ""|*[!0-9]*|0*) return 1 ;;
  esac
  if [ "$screen_port" -lt 1 ] || [ "$screen_port" -gt 65535 ]; then
    return 1
  fi
  case "$screen_port" in
    3000|3001) return 1 ;;
  esac
}

screen_upstream_name_ok() {
  screen_name=$1
  case "$screen_name" in
    ""|-*|.*|*.|*[!A-Za-z0-9._-]*|REPLACE_*|*CHANGEME*) return 1 ;;
  esac
  if [ "${#screen_name}" -lt 1 ] || [ "${#screen_name}" -gt 63 ]; then
    return 1
  fi
  if printf '%s\n' "$screen_name" | awk -F. 'NF == 4 { ok = 1; for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i + 0 > 255) ok = 0; if (ok) exit 0; exit 1 } { exit 1 }'; then
    return 1
  fi
}

# Same pin as the lab screen image: name@sha256 and 64 hex digits. A bare image id is refused.
screen_host_image_ok() {
  screen_image=$1
  case "$screen_image" in
    ""|*[[:space:]]*|REPLACE_*|*CHANGEME*) return 1 ;;
  esac
  printf '%s\n' "$screen_image" | grep -Eq '@sha256:[0-9A-Fa-f]{64}([^0-9A-Fa-f]|$)'
}
