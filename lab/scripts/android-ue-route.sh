#!/bin/bash
# Run in the srsUE network namespace after attach.
# Pin the eNB on the uu interface, point the default route at tun_srsue,
# and drop other new output so the emulator cannot bypass the EPC.
set -euo pipefail

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
if ps -eo comm= 2>/dev/null | awk '$1 == "emulator" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "android-ue-route: emulator is already running; not changing IPv6" >&2
  exit 0
fi
# Keep addresses. disable_ipv6=0 on all, default, lo, and every interface.
# accept_ra, autoconf, and forwarding are 0 on each non-lo interface too,
# because all/default do not apply to interfaces that already exist.
android_ue_route_ipv6_lock() {
  local key iface knob sys
  for key in all default lo; do
    sys="/proc/sys/net/ipv6/conf/${key}/disable_ipv6"
    if [ -w "$sys" ]; then
      printf '0\n' >"$sys"
    fi
  done
  for iface in $(ip -o link show | awk -F': ' '{ print $2 }' | cut -d@ -f1); do
    sys="/proc/sys/net/ipv6/conf/${iface}/disable_ipv6"
    if [ -w "$sys" ]; then
      printf '0\n' >"$sys"
    fi
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
android_ue_route_ipv6_lock
while read -r route; do
  [ -n "$route" ] || continue
  # shellcheck disable=SC2086
  ip -6 route del $route
done < <(ip -6 route show default || true)
ip -6 route replace unreachable default metric 1
if command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1; then
  install_guard 6 ip6tables ANDROID_UE_GUARD6
elif command -v ip6tables-nft >/dev/null 2>&1 && ip6tables-nft -L >/dev/null 2>&1; then
  install_guard 6 ip6tables-nft ANDROID_UE_GUARD6
elif [ "${ANDROID_UE_IPV6_NO_FILTER_OK:-0}" = "1" ]; then
  echo "android-ue-route: ip6tables is missing and ANDROID_UE_IPV6_NO_FILTER_OK=1. The unreachable default route remains." >&2
else
  echo "android-ue-route: ip6tables and ip6tables-nft are missing. Refusing to continue. Set ANDROID_UE_IPV6_NO_FILTER_OK=1 only for a netns check." >&2
  exit 1
fi
if ! ip -6 addr show dev lo | grep -q 'inet6 ::1'; then
  echo "android-ue-route: ::1 is missing on lo" >&2
  exit 1
fi
android_ue_route_fe80_ok() {
  local addr _idx _plen _scope flags name iflag deadline
  deadline=$((SECONDS + 15))
  while [ "$SECONDS" -le "$deadline" ]; do
    while read -r addr _idx _plen _scope flags name; do
      case "$addr" in
        fe80*) ;;
        *) continue ;;
      esac
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
      if [ $((iflag & 1)) -eq 1 ]; then
        return 0
      fi
    done < /proc/net/if_inet6
    sleep 1
  done
  return 1
}
if ! android_ue_route_fe80_ok; then
  echo "android-ue-route: no UP interface has a non-tentative fe80 address" >&2
  ip -6 addr show scope link >&2 || true
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

ue_addr=$(ip -4 -o addr show dev "$tun" | awk '{ print $4; exit }')
echo "android-ue-route: ${tun} ${ue_addr}; default via ${tun}; eNB ${enb} via ${dev}"
