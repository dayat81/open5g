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

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

case "${1:-}" in
  --apply-tree)
    magen_ipv6_apply_tree "${2:?sysctl tree}"
    ;;
  *)
    echo "usage: magen-ipv6.sh --apply-tree DIR" >&2
    exit 2
    ;;
esac
