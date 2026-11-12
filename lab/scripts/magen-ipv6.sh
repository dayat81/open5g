#!/bin/bash
# Per-interface IPv6 lockdown for a magen netns.
# lo stays on (::1 remains). default and every non-lo iface are set to 1.
# all is never written. Host IPv6 off skips ip6tables and does not fail.
set -euo pipefail

magen_ipv6_apply_tree() {
  local root=$1
  local iface path
  path="${root}/default/disable_ipv6"
  if [ ! -e "$path" ]; then
    echo "magen: ${path} is missing" >&2
    return 1
  fi
  printf '1\n' >"$path"
  for iface in "$root"/*; do
    [ -d "$iface" ] || continue
    iface=$(basename -- "$iface")
    case "$iface" in
      all|default|lo) continue ;;
    esac
    printf '1\n' >"${root}/${iface}/disable_ipv6"
  done
  if [ "$(cat "${root}/all/disable_ipv6")" = "1" ]; then
    echo "magen: disable_ipv6 on all is 1. Leave all unset so lo keeps ::1." >&2
    return 1
  fi
  if [ "$(cat "${root}/lo/disable_ipv6")" != "0" ]; then
    echo "magen: disable_ipv6 on lo is not 0" >&2
    return 1
  fi
  if [ "$(cat "${root}/default/disable_ipv6")" != "1" ]; then
    echo "magen: disable_ipv6 on default is not 1" >&2
    return 1
  fi
}

magen_ipv6_ip6tables_needed() {
  local mode=$1
  [ "$mode" != "off" ]
}

magen_ip6tables_render() {
  cat <<'EOF'
-P INPUT DROP
-P OUTPUT DROP
-P FORWARD DROP
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
EOF
}

magen_ip6tables_ok() {
  local rules=$1
  printf '%s\n' "$rules" | grep -q -- '-P INPUT DROP' || return 1
  printf '%s\n' "$rules" | grep -q -- '-P OUTPUT DROP' || return 1
  printf '%s\n' "$rules" | grep -q -- '-P FORWARD DROP' || return 1
  printf '%s\n' "$rules" | grep -q -- '-A INPUT -i lo -j ACCEPT' || return 1
  printf '%s\n' "$rules" | grep -q -- '-A OUTPUT -o lo -j ACCEPT' || return 1
}

magen_ipv6_verify_tree() {
  local root=$1
  local iface val
  if [ "$(cat "${root}/all/disable_ipv6")" = "1" ]; then
    echo "magen: disable_ipv6 on all is 1. all was not supposed to change." >&2
    return 1
  fi
  if [ "$(cat "${root}/lo/disable_ipv6")" != "0" ]; then
    echo "magen: disable_ipv6 on lo is not 0" >&2
    return 1
  fi
  if [ "$(cat "${root}/default/disable_ipv6")" != "1" ]; then
    echo "magen: disable_ipv6 on default is not 1" >&2
    return 1
  fi
  for iface in "$root"/*; do
    [ -d "$iface" ] || continue
    iface=$(basename -- "$iface")
    case "$iface" in
      all|default|lo) continue ;;
    esac
    val=$(cat "${root}/${iface}/disable_ipv6")
    if [ "$val" != "1" ]; then
      echo "magen: disable_ipv6 on ${iface} is ${val}, expected 1" >&2
      return 1
    fi
  done
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

magen_ipv6_apply_netns() {
  local name=$1 pid=$2 have=$3 ip6=$4
  magen_pid_matches "$name" "$pid" "$have"
  local iface val all_v6 lo_v6 def_v6
  # Compose sets disable_ipv6. This path only reads /proc/sys.
  all_v6=$(nsenter -t "$pid" -n cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
  lo_v6=$(nsenter -t "$pid" -n cat /proc/sys/net/ipv6/conf/lo/disable_ipv6)
  def_v6=$(nsenter -t "$pid" -n cat /proc/sys/net/ipv6/conf/default/disable_ipv6)
  if [ "$all_v6" = "1" ]; then
    echo "magen: disable_ipv6 on all is 1 in ${name}. all was not changed by this script." >&2
    return 1
  fi
  if [ "$lo_v6" != "0" ]; then
    echo "magen: disable_ipv6 on lo is ${lo_v6} in ${name}" >&2
    return 1
  fi
  if [ "$def_v6" != "1" ]; then
    echo "magen: disable_ipv6 on default is ${def_v6} in ${name}, expected 1 from compose" >&2
    return 1
  fi
  if ! nsenter -t "$pid" -n ip -6 addr show dev lo | grep -q 'inet6 ::1'; then
    echo "magen: ::1 is missing on lo in ${name}" >&2
    return 1
  fi
  while IFS= read -r iface; do
    [ -n "$iface" ] || continue
    case "$iface" in
      lo|all|default) continue ;;
    esac
    val=$(nsenter -t "$pid" -n cat "/proc/sys/net/ipv6/conf/${iface}/disable_ipv6")
    if [ "$val" != "1" ]; then
      echo "magen: disable_ipv6 on ${iface} is ${val} in ${name}" >&2
      return 1
    fi
  done < <(nsenter -t "$pid" -n ip -o link show | awk -F': ' '{ print $2 }' | cut -d@ -f1)
  if [ "$ip6" != "1" ]; then
    echo "magen: host IPv6 is off. Skipping ip6tables in ${name}. ::1 on lo stays mandatory."
    return 0
  fi
  nsenter -t "$pid" -n ip6tables -P INPUT DROP
  nsenter -t "$pid" -n ip6tables -P OUTPUT DROP
  nsenter -t "$pid" -n ip6tables -P FORWARD DROP
  nsenter -t "$pid" -n ip6tables -C INPUT -i lo -j ACCEPT 2>/dev/null || nsenter -t "$pid" -n ip6tables -A INPUT -i lo -j ACCEPT
  nsenter -t "$pid" -n ip6tables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || nsenter -t "$pid" -n ip6tables -A OUTPUT -o lo -j ACCEPT
  local rules
  rules=$(nsenter -t "$pid" -n ip6tables -S)
  if ! magen_ip6tables_ok "$rules"; then
    echo "magen: ip6tables DROP was not verified in ${name}" >&2
    return 1
  fi
}

case "${1:-}" in
  --apply-tree)
    magen_ipv6_apply_tree "${2:?sysctl tree}"
    magen_ipv6_verify_tree "${2}"
    ;;
  --render-ip6)
    magen_ip6tables_render
    ;;
  --apply)
    shift
    name=""
    pid=""
    have=""
    ip6=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --container) shift; name=$1 ;;
        --pid) shift; pid=$1 ;;
        --have) shift; have=$1 ;;
        --ip6tables) ip6=1 ;;
        *) echo "magen-ipv6: unknown arg $1" >&2; exit 2 ;;
      esac
      shift
    done
    if [ -z "$have" ]; then
      have=$(docker inspect -f '{{.State.Pid}}' "$name")
    fi
    magen_ipv6_apply_netns "$name" "$pid" "$have" "$ip6"
    ;;
  *)
    echo "usage: magen-ipv6.sh --apply-tree DIR | --render-ip6 | --apply --container NAME --pid PID [--ip6tables]" >&2
    exit 2
    ;;
esac
