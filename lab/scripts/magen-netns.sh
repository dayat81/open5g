#!/bin/bash
# Enter an o5g emulator or UE netns from the host.
# Root uses nsenter. A docker-group user uses a short-lived helper that
# joins that netns. The helper gets NET_ADMIN only, for iptables-legacy.
# It does not write sysctl. Compose already sets disable_ipv6, and this
# script only reads those values. Privileged is not used, and no raw capability is added.
# The emulator process itself has no NET_ADMIN. all is never written.
# Host iptables are not changed.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

magen_netns_name_ok() {
  case "$1" in
    o5g-android1|o5g-android2|o5g-ue1|o5g-ue2) return 0 ;;
  esac
  echo "magen: refusing to enter ${1}" >&2
  return 1
}

magen_netns_mode() {
  if [ -n "${MAGEN_NETNS_MODE:-}" ]; then
    case "$MAGEN_NETNS_MODE" in
      nsenter|helper) printf '%s\n' "$MAGEN_NETNS_MODE"; return 0 ;;
    esac
    echo "magen: MAGEN_NETNS_MODE must be nsenter or helper" >&2
    return 1
  fi
  if [ "$(id -u)" -eq 0 ] && command -v nsenter >/dev/null 2>&1; then
    echo nsenter
  else
    echo helper
  fi
}

magen_netns_plan() {
  local mode=$1 name=$2
  magen_netns_name_ok "$name"
  if [ "$mode" = "nsenter" ]; then
    printf 'nsenter -t <pid> -n # %s\n' "$name"
    return 0
  fi
  if [ "$mode" = "helper" ]; then
    printf 'docker run --rm --network container:%s --cap-add NET_ADMIN --pull never # iptables-legacy from the pinned emulator image\n' "$name"
    return 0
  fi
  echo "magen: unknown netns mode ${mode}" >&2
  return 1
}

magen_netns_guard() {
  local name=$1 pid=$2
  local id shown have
  magen_netns_name_ok "$name"
  id=$(docker inspect -f '{{.Id}}' "$name")
  shown=$(docker inspect -f '{{.Name}}' "$id")
  have=$(docker inspect -f '{{.State.Pid}}' "$id")
  if [ "$shown" != "/${name}" ]; then
    echo "magen: container id ${id} is ${shown}, not ${name}" >&2
    return 1
  fi
  magen_pid_matches "$name" "$pid" "$have"
}

magen_netns_sh() {
  local name=$1 pid=$2 script=$3
  local mode helper
  magen_netns_guard "$name" "$pid"
  mode=$(magen_netns_mode)
  if [ "$mode" = "nsenter" ]; then
    nsenter -t "$pid" -n bash -c "$script"
    return
  fi
  helper=${O5G_NETNS_HELPER_IMAGE:-${O5G_ANDROID_IMAGE:-}}
  if ! magen_digest_ok "$helper"; then
    echo "magen: the netns helper must be an already pinned image. Refusing to pull." >&2
    return 1
  fi
  docker run --rm --network "container:${name}" \
    --cap-add NET_ADMIN --pull never \
    --entrypoint bash "$helper" -c "$script"
}

magen_ipv6_script() {
  local ip6=$1 ip6t=$2
  cat <<EOF
set -e
read_v6() { cat "/proc/sys/net/ipv6/conf/\$1/disable_ipv6"; }
all_v6=\$(read_v6 all)
lo_v6=\$(read_v6 lo)
if [ "\$all_v6" = 1 ]; then
  echo "magen: disable_ipv6 on all is 1. all was not changed." >&2
  exit 1
fi
if [ "\$lo_v6" != 0 ]; then
  echo "magen: disable_ipv6 on lo is \$lo_v6" >&2
  exit 1
fi
ip -6 addr show dev lo | grep -q 'inet6 ::1'
def_v6=\$(read_v6 default)
if [ "\$def_v6" != 1 ]; then
  echo "magen: disable_ipv6 on default is \$def_v6, expected 1 from compose" >&2
  exit 1
fi
for iface in \$(ip -o link show | awk -F': ' '{ print \$2 }' | cut -d@ -f1); do
  case "\$iface" in lo|all|default) continue ;; esac
  val=\$(read_v6 "\$iface")
  if [ "\$val" != 1 ]; then
    echo "magen: disable_ipv6 on \$iface is \$val, expected 1 from compose" >&2
    exit 1
  fi
done
if [ "$ip6" = 1 ]; then
  ${ip6t} -P INPUT DROP
  ${ip6t} -P OUTPUT DROP
  ${ip6t} -P FORWARD DROP
  ${ip6t} -C INPUT -i lo -j ACCEPT 2>/dev/null || ${ip6t} -A INPUT -i lo -j ACCEPT
  ${ip6t} -C OUTPUT -o lo -j ACCEPT 2>/dev/null || ${ip6t} -A OUTPUT -o lo -j ACCEPT
  ${ip6t} -S | grep -q -- '-P INPUT DROP'
  ${ip6t} -S | grep -q -- '-A INPUT -i lo -j ACCEPT'
else
  echo "magen: host IPv6 is off. Skipping ip6tables. ::1 on lo stays mandatory."
fi
EOF
}

magen_screen_script() {
  local listener=$1 ipt=$2
  case "$listener" in
    ''|*[!0-9.]*) echo "magen: listener address is not an IPv4 address" >&2; return 1 ;;
  esac
  cat <<EOF
set -e
${ipt} -N ANDROID_UE_SCREEN 2>/dev/null || ${ipt} -F ANDROID_UE_SCREEN
${ipt} -A ANDROID_UE_SCREEN -p tcp -s ${listener} --dport 8000 -j ACCEPT
${ipt} -A ANDROID_UE_SCREEN -p tcp --dport 8000 -j DROP
${ipt} -C INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN 2>/dev/null || ${ipt} -I INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN
${ipt} -S ANDROID_UE_SCREEN | grep -q -- '-s ${listener} --dport 8000 -j ACCEPT'
${ipt} -S ANDROID_UE_SCREEN | grep -q -- '--dport 8000 -j DROP'
EOF
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

mode_arg=""
name=""
pid=""
listener=""
ip6=0
action=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan) action=plan; shift; mode_arg=$1 ;;
    --apply-ipv6) action=ipv6 ;;
    --apply-screen) action=screen ;;
    --container) shift; name=$1 ;;
    --pid) shift; pid=$1 ;;
    --listener) shift; listener=$1 ;;
    --ip6tables) ip6=1 ;;
    *) echo "usage: magen-netns.sh --plan nsenter|helper --container NAME | --apply-ipv6|--apply-screen --container NAME --pid PID" >&2; exit 2 ;;
  esac
  shift
done

ipt_bin=iptables
ip6_bin=ip6tables
if [ "$(magen_netns_mode)" = "helper" ]; then
  ipt_bin=iptables-legacy
  ip6_bin=ip6tables-legacy
fi

case "$action" in
  plan) magen_netns_plan "$mode_arg" "$name" ;;
  ipv6) magen_netns_sh "$name" "$pid" "$(magen_ipv6_script "$ip6" "$ip6_bin")" ;;
  screen) magen_netns_sh "$name" "$pid" "$(magen_screen_script "$listener" "$ipt_bin")" ;;
  *) echo "magen: netns action is missing" >&2; exit 2 ;;
esac
