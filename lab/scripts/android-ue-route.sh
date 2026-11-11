#!/bin/bash
# Run in the srsUE network namespace after attach.
# Pin the eNB on the uu interface, point the default route at tun_srsue,
# and drop other new output so the emulator cannot bypass the EPC.
set -euo pipefail

screen_allow_ok() {
  case "$1" in
    ""|REPLACE_*|0.0.0.0|127.*|0.*) return 1 ;;
  esac
  printf '%s\n' "$1" | awk -F. 'NF != 4 { exit 1 } { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i + 0 > 255) exit 1 }'
}

screen_rules_active() {
  case "${ANDROID_UE_SCREEN_IMAGE:-}" in
    ""|REPLACE_*) return 1 ;;
  esac
  return 0
}

screen_iface_for() {
  local want=$1
  local forced=${ANDROID_UE_SCREEN_IFACE:-}
  if [ -n "$forced" ]; then
    printf '%s\n' "$forced"
    return 0
  fi
  ip -4 -o addr show | awk -v addr="$want" '$4 ~ "^" addr "/" { print $2; exit }'
}

screen_rule_line() {
  local iface=$1
  local port=$2
  local allow=$3
  case "$allow" in
    ""|REPLACE_*)
      printf 'iptables -I INPUT 1 -i %s -p tcp -m multiport --dports %s,5555 -j DROP\n' "$iface" "$port"
      ;;
    *)
      printf 'iptables -I INPUT 1 -i %s -p tcp -m multiport --dports %s,5555 ! -s %s -j DROP\n' "$iface" "$port" "$allow"
      ;;
  esac
}

if [ "${1:-}" = "--check-allow" ]; then
  if screen_allow_ok "${ANDROID_UE_SCREEN_ALLOW_FROM:-}"; then
    exit 0
  fi
  echo "android-ue-route: screen allow source must be one non-loopback IPv4 address" >&2
  exit 1
fi

if [ "${1:-}" = "--print-screen-rule" ]; then
  if ! screen_rules_active; then
    printf '%s\n' skipped
    exit 0
  fi
  iface=$(screen_iface_for "${ANDROID_UE_SCREEN_ADDR:-}")
  if [ -z "$iface" ] || [ "$iface" = "lo" ]; then
    echo "android-ue-route: screen interface is missing" >&2
    exit 1
  fi
  screen_rule_line "$iface" "${ANDROID_UE_SCREEN_PORT:-8000}" "${ANDROID_UE_SCREEN_ALLOW_FROM:-}"
  exit 0
fi

tun=${ANDROID_UE_TUN:-tun_srsue}
enb=${ANDROID_UE_ENB_UU:?ANDROID_UE_ENB_UU}
timeout_s=${ANDROID_UE_ATTACH_TIMEOUT:?ANDROID_UE_ATTACH_TIMEOUT}
deadline=$((SECONDS + timeout_s))

while [ "$SECONDS" -lt "$deadline" ]; do
  if ip -4 -o addr show dev "$tun" 2>/dev/null | grep -q ' inet '; then
    break
  fi
  sleep 2
done

if ! ip -4 -o addr show dev "$tun" 2>/dev/null | grep -q ' inet '; then
  echo "android-ue-route: ${tun} has no IPv4 address after ${timeout_s}s" >&2
  exit 1
fi

# The image's socat is rewritten to the uu address by android-ue-adb-bind.sh.
# Do not move interfaces here. Docker's eth0 is not a stable name for uu.

route_line=$(ip -4 route get "$enb")
dev=$(printf '%s\n' "$route_line" | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
if [ -z "$dev" ] || [ "$dev" = "$tun" ]; then
  echo "android-ue-route: no non-tun route to eNB ${enb}" >&2
  exit 1
fi

install_guard() {
  local family=$1
  local bin=$2
  local chain=$3
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "android-ue-route: ${bin} is missing" >&2
    exit 1
  fi
  if ! "$bin" -N "$chain" 2>/dev/null; then
    "$bin" -F "$chain"
  fi
  if ! "$bin" -C OUTPUT -j "$chain" 2>/dev/null; then
    "$bin" -I OUTPUT 1 -j "$chain"
  fi
  "$bin" -A "$chain" -o lo -j ACCEPT
  if [ "$family" = 4 ]; then
    "$bin" -A "$chain" -d "$enb" -p tcp -j ACCEPT
    "$bin" -A "$chain" -o "$tun" -j ACCEPT
    "$bin" -A "$chain" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  fi
  "$bin" -A "$chain" -j DROP
}

install_guard 4 iptables ANDROID_UE_GUARD
# Keep every IPv6 address, including ::1 and fe80. QEMU resolves ::1 with
# AI_ADDRCONFIG, which ignores loopback unless some other IPv6 address exists.
while IFS= read -r v6default; do
  [ -n "$v6default" ] || continue
  # shellcheck disable=SC2086
  ip -6 route del $v6default || true
done <<EOF
$(ip -6 route show default 2>/dev/null || true)
EOF
for knob in accept_ra autoconf; do
  for key in all default; do
    sys="/proc/sys/net/ipv6/conf/${key}/${knob}"
    if [ -w "$sys" ]; then
      printf '0\n' >"$sys"
    fi
  done
done
if command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1; then
  install_guard 6 ip6tables ANDROID_UE_GUARD6
elif command -v ip6tables-nft >/dev/null 2>&1 && ip6tables-nft -L >/dev/null 2>&1; then
  install_guard 6 ip6tables-nft ANDROID_UE_GUARD6
else
  echo "android-ue-route: ip6tables is unavailable. IPv6 addresses stay, and there is no IPv6 default route." >&2
fi
v6_lines=$(ip -6 -o addr show 2>/dev/null || true)
if ! printf '%s\n' "$v6_lines" | grep -q 'inet6 ::1'; then
  echo "android-ue-route: ::1 is missing on lo" >&2
  printf '%s\n' "$v6_lines" >&2
  exit 1
fi
if ! printf '%s\n' "$v6_lines" | grep 'inet6 fe80:' | grep -vq ' lo '; then
  echo "android-ue-route: no non-loopback IPv6 address; QEMU cannot resolve ::1" >&2
  printf '%s\n' "$v6_lines" >&2
  exit 1
fi

for _ in 1 2 3 4 5; do
  ip route replace "${enb}/32" dev "$dev"
  ip route replace default dev "$tun"
  sleep 1
done

default_probe=$(ip -4 route get 1.1.1.1)
case "$default_probe" in
  *"dev ${tun}"*) ;;
  *)
    echo "android-ue-route: 1.1.1.1 is not via ${tun}: ${default_probe}" >&2
    exit 1
    ;;
esac

enb_probe=$(ip -4 route get "$enb")
case "$enb_probe" in
  *"dev ${tun}"*)
    echo "android-ue-route: eNB route points at ${tun}: ${enb_probe}" >&2
    exit 1
    ;;
esac

if screen_rules_active; then
  screen_port=${ANDROID_UE_SCREEN_PORT:-8000}
  case "$screen_port" in
    ''|*[!0-9]*)
      echo "android-ue-route: screen port is not numeric" >&2
      exit 1
      ;;
  esac
  allow=${ANDROID_UE_SCREEN_ALLOW_FROM:-}
  case "$allow" in
    ""|REPLACE_*) ;;
    *)
      if ! screen_allow_ok "$allow"; then
        echo "android-ue-route: screen allow source is not a single IPv4 address" >&2
        exit 1
      fi
      ;;
  esac
  iface=$(screen_iface_for "${ANDROID_UE_SCREEN_ADDR:-}")
  if [ -z "$iface" ] || [ "$iface" = "lo" ]; then
    echo "android-ue-route: screen address has no non-loopback interface" >&2
    exit 1
  fi
  case "$allow" in
    ""|REPLACE_*)
      iptables -I INPUT 1 -i "$iface" -p tcp -m multiport --dports "${screen_port},5555" -j DROP
      ;;
    *)
      iptables -I INPUT 1 -i "$iface" -p tcp -m multiport --dports "${screen_port},5555" ! -s "$allow" -j DROP
      ;;
  esac
  echo "android-ue-route: $(screen_rule_line "$iface" "$screen_port" "$allow")"
fi

ue_addr=$(ip -4 -o addr show dev "$tun" | awk '{ print $4; exit }')
echo "android-ue-route: ${tun} ${ue_addr}; default via ${tun}; eNB ${enb} via ${dev}"
