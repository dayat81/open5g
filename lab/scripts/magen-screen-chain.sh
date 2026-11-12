#!/bin/bash
# Magen wiring for the ANDROID_UE_SCREEN chain.
# The sidecar and listener programs live in PR #13. This file only renders
# the filter: TCP 8000 is accepted from the listener address and dropped
# for every other source. It does not publish a host port.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

magen_screen_chain_render() {
  local listener=$1
  if magen_is_placeholder "$listener"; then
    echo "magen: screen listener address is empty or still a placeholder" >&2
    return 1
  fi
  if ! printf '%s\n' "$listener" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "magen: screen listener address must be an IPv4 address" >&2
    return 1
  fi
  cat <<EOF
-N ANDROID_UE_SCREEN
-A ANDROID_UE_SCREEN -p tcp -s ${listener} --dport 8000 -j ACCEPT
-A ANDROID_UE_SCREEN -p tcp --dport 8000 -j DROP
-I INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN
EOF
}

# allow only when the source is exactly the listener address.
magen_screen_source_allowed() {
  local listener=$1 source=$2
  [ "$source" = "$listener" ]
}

magen_screen_rules_ok() {
  local listener=$1 rules=$2
  printf '%s\n' "$rules" | grep -q -- "-s ${listener} --dport 8000 -j ACCEPT" || return 1
  printf '%s\n' "$rules" | grep -q -- '--dport 8000 -j DROP' || return 1
  if printf '%s\n' "$rules" | grep -E -- '-j ACCEPT' | grep -v -- "-s ${listener} "; then
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

magen_screen_chain_apply() {
  local name=$1 pid=$2 have=$3 listener=$4
  case "$name" in
    o5g-android1|o5g-android2) ;;
    *)
      echo "magen: the screen chain is only installed in o5g-androidN" >&2
      return 1
      ;;
  esac
  magen_pid_matches "$name" "$pid" "$have"
  nsenter -t "$pid" -n iptables -N ANDROID_UE_SCREEN 2>/dev/null || nsenter -t "$pid" -n iptables -F ANDROID_UE_SCREEN
  nsenter -t "$pid" -n iptables -A ANDROID_UE_SCREEN -p tcp -s "$listener" --dport 8000 -j ACCEPT
  nsenter -t "$pid" -n iptables -A ANDROID_UE_SCREEN -p tcp --dport 8000 -j DROP
  if ! nsenter -t "$pid" -n iptables -C INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN 2>/dev/null; then
    nsenter -t "$pid" -n iptables -I INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN
  fi
  local rules
  rules=$(nsenter -t "$pid" -n iptables -S ANDROID_UE_SCREEN)
  if ! magen_screen_rules_ok "$listener" "$rules"; then
    echo "magen: ANDROID_UE_SCREEN was not verified in ${name}. Port 8000 stays fail-closed." >&2
    return 1
  fi
}

case "${1:-}" in
  --render)
    magen_screen_chain_render "${2:?listener address}"
    ;;
  --apply)
    shift
    name=""
    pid=""
    have=""
    listener=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --container) shift; name=$1 ;;
        --pid) shift; pid=$1 ;;
        --have) shift; have=$1 ;;
        --listener) shift; listener=$1 ;;
        *) echo "magen-screen-chain: unknown arg $1" >&2; exit 2 ;;
      esac
      shift
    done
    if [ -z "$have" ]; then
      have=$(docker inspect -f '{{.State.Pid}}' "$name")
    fi
    magen_screen_chain_apply "$name" "$pid" "$have" "$listener"
    ;;
  *)
    echo "usage: magen-screen-chain.sh --render ADDR | --apply --container o5g-androidN --pid PID --listener ADDR" >&2
    exit 2
    ;;
esac
