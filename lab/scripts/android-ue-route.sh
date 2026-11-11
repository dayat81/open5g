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

iface_for_addr() {
  local want=$1
  local forced=$2
  if [ -n "$forced" ]; then
    printf '%s\n' "$forced"
    return 0
  fi
  ip -4 -o addr show | awk -v addr="$want" '$4 ~ "^" addr "/" { print $2; exit }'
}

screen_iface_for() {
  iface_for_addr "$1" "${ANDROID_UE_SCREEN_IFACE:-}"
}

screen_rule_line() {
  local iface=$1
  local port=$2
  local allow=$3
  case "$allow" in
    ""|REPLACE_*)
      printf 'iptables -A INPUT -i %s -p tcp --dport %s -j DROP\n' "$iface" "$port"
      ;;
    *)
      printf 'iptables -A INPUT -i %s -p tcp --dport %s ! -s %s -j DROP\n' "$iface" "$port" "$allow"
      ;;
  esac
}

android_ue_render_adb_allow() {
  local iface=$1
  printf '%s\n' "-A ANDROID_UE_ADB -i ${iface} -p tcp -m multiport --dports 5554,5555 -j ACCEPT"
  printf '%s\n' "-A ANDROID_UE_ADB -p tcp -m multiport --dports 5554,5555 -j DROP"
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

if [ "${1:-}" = "--print-adb-allow" ]; then
  iface=${ANDROID_UE_ADB_IFACE:-}
  if [ -z "$iface" ] || [ "$iface" = "lo" ]; then
    echo "android-ue-route: uu interface is missing" >&2
    exit 1
  fi
  android_ue_render_adb_allow "$iface"
  exit 0
fi

# IPv4 INPUT. lo and established flows stay open. New packets from tun_srsue
# are dropped. uu (5554/5555) is not named here, so those listeners stay reachable.
# The screen rule, when the image is set, is appended after ANDROID_UE_IN4.
# 5554/5555 are not in that rule. They have their own chain.
android_ue_render_ip4_input() {
  cat <<'EOF'
-A ANDROID_UE_IN4 -i lo -j ACCEPT
-A ANDROID_UE_IN4 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A ANDROID_UE_IN4 -i tun_srsue -j DROP
EOF
}

if [ "${1:-}" = "--render-ip4-input" ]; then
  android_ue_render_ip4_input
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

# The vendored image binds socat to ANDROID_UE_UU. Do not rename interfaces here.

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
android_ue_route_install_input4() {
  local bin=iptables
  local chain=ANDROID_UE_IN4
  if ! "$bin" -N "$chain" 2>/dev/null; then
    "$bin" -F "$chain"
  fi
  if ! "$bin" -C INPUT -j "$chain" 2>/dev/null; then
    "$bin" -I INPUT 1 -j "$chain"
  fi
  "$bin" -A "$chain" -i lo -j ACCEPT
  "$bin" -A "$chain" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  "$bin" -A "$chain" -i "$tun" -j DROP
}
android_ue_route_install_input4
android_ue_route_install_adb() {
  local bin=iptables
  local chain=ANDROID_UE_ADB
  local iface
  iface=$(iface_for_addr "${ANDROID_UE_UU:?ANDROID_UE_UU}" "")
  if [ -z "$iface" ] || [ "$iface" = "lo" ]; then
    echo "android-ue-route: uu address has no non-loopback interface" >&2
    exit 1
  fi
  if ! "$bin" -N "$chain" 2>/dev/null; then
    "$bin" -F "$chain"
  fi
  # Append. ANDROID_UE_IN4 was inserted at INPUT 1, so this jump stays after it.
  # Do not set the INPUT policy.
  if ! "$bin" -C INPUT -j "$chain" 2>/dev/null; then
    "$bin" -A INPUT -j "$chain"
  fi
  "$bin" -A "$chain" -i "$iface" -p tcp -m multiport --dports 5554,5555 -j ACCEPT
  "$bin" -A "$chain" -p tcp -m multiport --dports 5554,5555 -j DROP
  echo "android-ue-route: $(android_ue_render_adb_allow "$iface" | tr '\n' ' ')"
}
android_ue_route_install_adb
# disable_ipv6=0 on all, default, lo, and dummy0. Docker may leave eth0 at 1.
# accept_ra, autoconf, and forwarding are 0 on each non-lo interface,
# because all/default do not apply to interfaces that already exist.
android_ue_route_ipv6_lock() {
  local key iface knob sys
  for key in all default lo dummy0; do
    sys="/proc/sys/net/ipv6/conf/${key}/disable_ipv6"
    if [ -w "$sys" ]; then
      printf '0\n' >"$sys"
    fi
  done
  for iface in $(ip -o link show | awk -F': ' '{ print $2 }' | cut -d@ -f1); do
    if [ "$iface" = "lo" ]; then
      continue
    fi
    for knob in accept_ra autoconf forwarding; do
      sys="/proc/sys/net/ipv6/conf/${iface}/${knob}"
      if [ -w "$sys" ]; then
        printf '0\n' >"$sys"
      fi
    done
  done
}
android_ue_route_ula_ok() {
  local ula=$1
  local addr head
  case "$ula" in
    *REPLACE*|*CHANGEME*)
      echo "android-ue-route: ANDROID_UE_IPV6_ULA is still a placeholder" >&2
      return 1
      ;;
  esac
  case "$ula" in
    */128) ;;
    *)
      echo "android-ue-route: ANDROID_UE_IPV6_ULA must use prefix /128" >&2
      return 1
      ;;
  esac
  addr=${ula%/*}
  case "$addr" in
    ::*)
      echo "android-ue-route: ANDROID_UE_IPV6_ULA must be inside fc00::/7" >&2
      return 1
      ;;
    *:*) ;;
    *)
      echo "android-ue-route: ANDROID_UE_IPV6_ULA must be an IPv6 address" >&2
      return 1
      ;;
  esac
  head=$(printf '%s' "${addr%%:*}" | tr '[:upper:]' '[:lower:]')
  if ! printf '%s\n' "$head" | grep -Eq '^(fc|fd)[0-9a-f]{0,2}$'; then
    echo "android-ue-route: ANDROID_UE_IPV6_ULA must be inside fc00::/7" >&2
    return 1
  fi
  if ! printf '%s\n' "$addr" | grep -Eq '^[0-9A-Fa-f:]+$'; then
    echo "android-ue-route: ANDROID_UE_IPV6_ULA has illegal characters" >&2
    return 1
  fi
  case "$addr" in
    *:::*)
      echo "android-ue-route: ANDROID_UE_IPV6_ULA is not a valid IPv6 address" >&2
      return 1
      ;;
  esac
}
android_ue_route_anchor() {
  local ula addr sys route
  ula=${ANDROID_UE_IPV6_ULA:-fdc2:fd97:24a4::1/128}
  android_ue_route_ula_ok "$ula"
  addr=${ula%/*}
  ip link add dummy0 type dummy >/dev/null 2>&1 || true
  if ! ip link show dummy0 >/dev/null 2>&1; then
    echo "android-ue-route: cannot create dummy0. The ULA anchor is required." >&2
    exit 1
  fi
  ip link set dummy0 addrgenmode none
  ip link set dummy0 up
  sys=/proc/sys/net/ipv6/conf/dummy0/disable_ipv6
  if [ -w "$sys" ]; then
    printf '0\n' >"$sys"
  fi
  if ! ip -6 addr show dev dummy0 | grep -q "inet6 ${addr}/128"; then
    ip -6 addr add "$ula" dev dummy0 nodad
  fi
  ip -6 route del "${addr}/128" dev dummy0 || true
  while read -r route; do
    [ -n "$route" ] || continue
    # shellcheck disable=SC2086
    ip -6 route del $route dev dummy0 || true
  done < <(ip -6 route show dev dummy0 || true)
}
android_ue_route_anchor
android_ue_route_ipv6_lock
while read -r route; do
  [ -n "$route" ] || continue
  # shellcheck disable=SC2086
  ip -6 route del $route
done < <(ip -6 route show default || true)
ip -6 route replace unreachable default metric 1
if ! ip -6 addr show dev lo | grep -q 'inet6 ::1'; then
  echo "android-ue-route: ::1 is missing on lo" >&2
  exit 1
fi
android_ue_route_nonloop_ok() {
  local addr _idx _plen _scope flags name iflag prefix
  while read -r addr _idx _plen _scope flags name; do
    [ -n "${name:-}" ] || continue
    if [ "$name" = "lo" ]; then
      continue
    fi
    flags=$((16#$flags))
    # IFA_F_TENTATIVE 0x40 and IFA_F_DADFAILED 0x08.
    if [ $((flags & 16#48)) -ne 0 ]; then
      continue
    fi
    iflag=$(cat "/sys/class/net/${name}/flags" 2>/dev/null || echo 0)
    iflag=$((iflag))
    if [ $((iflag & 1)) -ne 1 ]; then
      continue
    fi
    prefix=$(printf '%s' "$addr" | cut -c1-2 | tr 'A-F' 'a-f')
    if [ "$name" = "dummy0" ] && { [ "$prefix" = "fd" ] || [ "$prefix" = "fc" ]; }; then
      return 0
    fi
  done < /proc/net/if_inet6
  return 1
}
deadline=$((SECONDS + 15))
while [ "$SECONDS" -le "$deadline" ]; do
  if android_ue_route_nonloop_ok; then
    break
  fi
  sleep 1
done
if ! android_ue_route_nonloop_ok; then
  echo "android-ue-route: dummy0 has no UP non-tentative ULA. fe80 does not replace it." >&2
  ip -6 addr show >&2 || true
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
      iptables -A INPUT -i "$iface" -p tcp --dport "$screen_port" -j DROP
      ;;
    *)
      iptables -A INPUT -i "$iface" -p tcp --dport "$screen_port" ! -s "$allow" -j DROP
      ;;
  esac
  echo "android-ue-route: $(screen_rule_line "$iface" "$screen_port" "$allow")"
fi

ue_addr=$(ip -4 -o addr show dev "$tun" | awk '{ print $4; exit }')
echo "android-ue-route: ${tun} ${ue_addr}; default via ${tun}; eNB ${enb} via ${dev}"
