#!/bin/sh
# tun2socks sidecar in the cgnat network namespace.
# The only default route left in place is via tun0. A host route to the
# SOCKS address is the tunnel itself, not a second way out. nft drops any
# other packet that does not leave via tun0.
set -eu

: "${ANDROID_UE_SOCKS_ADDR:?ANDROID_UE_SOCKS_ADDR}"
socks_host=${ANDROID_UE_SOCKS_ADDR%%:*}
socks_port=${ANDROID_UE_SOCKS_ADDR##*:}
if ! printf '%s\n' "$socks_host" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "egress: ANDROID_UE_SOCKS_ADDR must be an IPv4 address and port 1080" >&2
  exit 1
fi
if [ "$socks_port" != "1080" ]; then
  echo "egress: ANDROID_UE_SOCKS_ADDR must use port 1080" >&2
  exit 1
fi
if ! command -v tun2socks >/dev/null 2>&1; then
  echo "egress: tun2socks is not on PATH in the mirrored image" >&2
  exit 1
fi
if ! command -v ip >/dev/null 2>&1; then
  echo "egress: ip is not on PATH in the mirrored image" >&2
  exit 1
fi

route_line=$(ip -4 route get "$socks_host")
dev=$(printf '%s\n' "$route_line" | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
via=$(printf '%s\n' "$route_line" | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')
if [ -z "$dev" ] || [ "$dev" = "tun0" ]; then
  echo "egress: no non-tun route to the SOCKS address" >&2
  exit 1
fi
if [ -n "$via" ]; then
  ip route replace "${socks_host}/32" via "$via" dev "$dev"
else
  ip route replace "${socks_host}/32" dev "$dev"
fi

tun2socks -device tun://tun0 -proxy "socks5://${ANDROID_UE_SOCKS_ADDR}" &
tun_pid=$!
trap 'kill "$tun_pid" 2>/dev/null || true; wait "$tun_pid" 2>/dev/null || true' INT TERM

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if ip link show tun0 >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$tun_pid" 2>/dev/null; then
    echo "egress: tun2socks exited before tun0 appeared" >&2
    wait "$tun_pid" || true
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "egress: tun0 did not appear" >&2
  exit 1
fi

enforce_default() {
  listed=/tmp/cgnat-defaults.txt
  ip route replace default dev tun0
  ip -4 route show default >"$listed"
  while IFS= read -r line; do
    case "$line" in
      ""|*"dev tun0"*) continue ;;
    esac
    case "$line" in
      default\ via\ *\ dev\ *|default\ dev\ *) ;;
      *)
        echo "egress: refusing to delete an unexpected route" >&2
        exit 1
        ;;
    esac
    # The line is the ip-route tokens, already matched above.
    # shellcheck disable=SC2086
    ip route del $line
  done <"$listed"
  count=$(ip -4 route show default | wc -l | tr -d ' ')
  only=$(ip -4 route show default)
  if [ "$count" != "1" ]; then
    echo "egress: expected one default route, saw ${count}" >&2
    exit 1
  fi
  case "$only" in
    *"dev tun0"*) ;;
    *)
      echo "egress: default route is not tun0" >&2
      exit 1
      ;;
  esac
}

i=0
while [ "$i" -lt 3 ]; do
  enforce_default
  i=$((i + 1))
  sleep 1
done
echo "egress: only default route is via tun0; SOCKS host route is ${socks_host}/32 via ${dev}"
wait "$tun_pid"
