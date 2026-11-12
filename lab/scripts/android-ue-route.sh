#!/bin/bash
# Run in the srsUE network namespace after attach.
# Pin the eNB on the uu interface, point the default route at tun_srsue,
# and drop other new output so the emulator cannot bypass the EPC.
set -euo pipefail

# IPv4 INPUT. lo and established flows stay open. New packets from tun_srsue
# toward the uemu subnet are dropped. Other input, including uu listeners, stays.
# shellcheck disable=SC2120
android_ue_render_ip4_input() {
  local subnet=${1:-203.0.113.0/29}
  local tun=${2:-tun_srsue}
  cat <<EOF
-A ANDROID_UE_IN4 -i lo -j ACCEPT
-A ANDROID_UE_IN4 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A ANDROID_UE_IN4 -i ${tun} -d ${subnet} -m conntrack --ctstate NEW -j DROP
EOF
}

android_ue_render_forward() {
  local uemu_if=$1
  local uu_if=$2
  local tun=$3
  cat <<EOF
-P FORWARD DROP
-A ANDROID_UE_FWD -o ${tun} -p tcp -j TCPMSS --clamp-mss-to-pmtu
-A ANDROID_UE_FWD -i ${uemu_if} -o ${tun} -j ACCEPT
-A ANDROID_UE_FWD -i ${tun} -o ${uemu_if} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ANDROID_UE_FWD -i ${uu_if} -o ${uemu_if} -j DROP
-A ANDROID_UE_FWD -i ${uemu_if} -o ${uu_if} -j DROP
-A ANDROID_UE_FWD -j DROP
-A ANDROID_UE_NAT -o ${tun} -j MASQUERADE
EOF
}

if [ "${1:-}" = "--render-ip4-input" ]; then
  # shellcheck disable=SC2119
  android_ue_render_ip4_input
  exit 0
fi

if [ "${1:-}" = "--render-forward" ]; then
  android_ue_render_forward "${2:-uemu0}" "${3:-eth0}" "${4:-tun_srsue}"
  exit 0
fi

# Write 0, then read it back. A failed write is acceptable only when the
# value is already 0. Never skip quietly.
android_ue_route_write_zero() {
  local sys=$1
  local got
  if [ ! -e "$sys" ]; then
    echo "android-ue-route: ${sys} does not exist, expected 0" >&2
    exit 1
  fi
  printf '0\n' >"$sys" 2>/dev/null || true
  got=$(cat "$sys" 2>/dev/null || echo missing)
  if [ "$got" != "0" ]; then
    echo "android-ue-route: ${sys} is ${got}, expected 0" >&2
    exit 1
  fi
}

if [ "${1:-}" = "--write-zero-self-test" ]; then
  android_ue_route_write_zero "${2:?sysctl path}"
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
  "$bin" -A "$chain" -i "$tun" -d "${ANDROID_UE_UEMU_SUBNET:?ANDROID_UE_UEMU_SUBNET}" -m conntrack --ctstate NEW -j DROP
}
android_ue_route_install_input4
# disable_ipv6=0 on all, default, lo, and dummy0. Docker may leave eth0 at 1.
# accept_ra, autoconf, and forwarding are 0 on each non-lo interface,
# because all/default do not apply to interfaces that already exist.
android_ue_route_ipv6_lock() {
  local key iface knob sys
  for key in all default lo dummy0; do
    android_ue_route_write_zero "/proc/sys/net/ipv6/conf/${key}/disable_ipv6"
  done
  for iface in $(ip -o link show | awk -F': ' '{ print $2 }' | cut -d@ -f1); do
    if [ "$iface" = "lo" ]; then
      continue
    fi
    for knob in accept_ra autoconf forwarding; do
      android_ue_route_write_zero "/proc/sys/net/ipv6/conf/${iface}/${knob}"
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
  android_ue_route_write_zero /proc/sys/net/ipv6/conf/dummy0/disable_ipv6
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

ue_addr=$(ip -4 -o addr show dev "$tun" | awk '{ print $4; exit }')
uemu_gw=${ANDROID_UE_UEMU_GW:?ANDROID_UE_UEMU_GW}
uu_addr=${ANDROID_UE_UE_UU:?ANDROID_UE_UE_UU}
uemu_if=$(ip -4 -o addr show | awk -v ip="$uemu_gw" 'index($4, ip "/") == 1 { print $2; exit }')
uu_if=$(ip -4 -o addr show | awk -v ip="$uu_addr" 'index($4, ip "/") == 1 { print $2; exit }')
if [ -z "$uemu_if" ] || [ -z "$uu_if" ] || [ "$uemu_if" = "$uu_if" ]; then
  echo "android-ue-route: could not tell the uemu interface from the uu interface" >&2
  exit 1
fi
iptables -P FORWARD DROP
if ! iptables -N ANDROID_UE_FWD 2>/dev/null; then
  iptables -F ANDROID_UE_FWD
fi
if ! iptables -C FORWARD -j ANDROID_UE_FWD 2>/dev/null; then
  iptables -I FORWARD 1 -j ANDROID_UE_FWD
fi
iptables -A ANDROID_UE_FWD -o "$tun" -p tcp -j TCPMSS --clamp-mss-to-pmtu
iptables -A ANDROID_UE_FWD -i "$uemu_if" -o "$tun" -j ACCEPT
iptables -A ANDROID_UE_FWD -i "$tun" -o "$uemu_if" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A ANDROID_UE_FWD -i "$uu_if" -o "$uemu_if" -j DROP
iptables -A ANDROID_UE_FWD -i "$uemu_if" -o "$uu_if" -j DROP
iptables -A ANDROID_UE_FWD -j DROP
if ! iptables -t nat -N ANDROID_UE_NAT 2>/dev/null; then
  iptables -t nat -F ANDROID_UE_NAT
fi
if ! iptables -t nat -C POSTROUTING -j ANDROID_UE_NAT 2>/dev/null; then
  iptables -t nat -A POSTROUTING -j ANDROID_UE_NAT
fi
iptables -t nat -A ANDROID_UE_NAT -o "$tun" -j MASQUERADE
fwd_rules=$(iptables -S ANDROID_UE_FWD)
in4_rules=$(iptables -S ANDROID_UE_IN4)
nat_rules=$(iptables -t nat -S ANDROID_UE_NAT)
policy_rules=$(iptables -S)
if ! grep -F -q -- '--clamp-mss-to-pmtu' <<< "$fwd_rules"; then
  echo "android-ue-route: ANDROID_UE_FWD is missing TCPMSS" >&2
  exit 1
fi
if ! grep -F -q -- "-i ${uemu_if} -o ${tun} -j ACCEPT" <<< "$fwd_rules"; then
  echo "android-ue-route: ANDROID_UE_FWD does not accept ${uemu_if} to ${tun}" >&2
  exit 1
fi
if ! grep -F -q -- "-i ${uu_if} -o ${uemu_if} -j DROP" <<< "$fwd_rules"; then
  echo "android-ue-route: ANDROID_UE_FWD does not drop ${uu_if} to ${uemu_if}" >&2
  exit 1
fi
if ! grep -F -q -- "-i ${uemu_if} -o ${uu_if} -j DROP" <<< "$fwd_rules"; then
  echo "android-ue-route: ANDROID_UE_FWD does not drop ${uemu_if} to ${uu_if}" >&2
  exit 1
fi
if ! grep -F -q -- "-i ${tun} -d ${ANDROID_UE_UEMU_SUBNET} -m conntrack --ctstate NEW -j DROP" <<< "$in4_rules"; then
  echo "android-ue-route: ANDROID_UE_IN4 does not drop new packets from ${tun} to the uemu subnet" >&2
  exit 1
fi
if ! grep -F -q -- "-o ${tun} -j MASQUERADE" <<< "$nat_rules"; then
  echo "android-ue-route: ANDROID_UE_NAT is missing MASQUERADE" >&2
  exit 1
fi
if ! grep -F -q -- '-P FORWARD DROP' <<< "$policy_rules"; then
  echo "android-ue-route: FORWARD policy is not DROP" >&2
  exit 1
fi
echo "android-ue-route: ${tun} ${ue_addr}; default via ${tun}; eNB ${enb} via ${dev}; gateway ${uemu_if} to ${tun}"
