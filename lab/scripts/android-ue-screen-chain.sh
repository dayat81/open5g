#!/bin/sh
# ANDROID_UE_SCREEN for the manual emulator netns.
# Accept TCP 8000 only from the screen-publish address. Drop every other source.
# The chain is applied with nsenter from the host. The emulator container
# does not gain NET_ADMIN. This file does not stop or remove that container.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-screen-bind.sh
. "$script_dir/android-ue-screen-bind.sh"

screen_pid_ok() {
  screen_name=$1
  screen_want=$2
  screen_have=$3
  case "$screen_name" in
    b0-agen-emu) ;;
    *)
      echo "android-ue-screen-chain: refusing to enter ${screen_name:-empty}" >&2
      return 1
      ;;
  esac
  case "$screen_want" in
    ""|0|*[!0-9]*)
      echo "android-ue-screen-chain: pid is missing" >&2
      return 1
      ;;
  esac
  if [ "$screen_want" != "$screen_have" ]; then
    echo "android-ue-screen-chain: pid ${screen_want} is not ${screen_name}" >&2
    return 1
  fi
}

screen_chain_render() {
  screen_allow=$1
  if ! screen_bind_ok "$screen_allow"; then
    echo "android-ue-screen-chain: publisher address is not one unicast address" >&2
    return 1
  fi
  printf '%s\n' "-N ANDROID_UE_SCREEN"
  printf '%s\n' "-A ANDROID_UE_SCREEN -p tcp -s ${screen_allow} --dport 8000 -j ACCEPT"
  printf '%s\n' "-A ANDROID_UE_SCREEN -p tcp --dport 8000 -j DROP"
  printf '%s\n' "-I INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN"
}

screen_rules_ok() {
  screen_allow=$1
  screen_rules=$2
  printf '%s\n' "$screen_rules" | grep -q -- "-s ${screen_allow} --dport 8000 -j ACCEPT" || return 1
  printf '%s\n' "$screen_rules" | grep -q -- '--dport 8000 -j DROP' || return 1
  if printf '%s\n' "$screen_rules" | grep -E -- '-j ACCEPT' | grep -v -- "-s ${screen_allow} "; then
    return 1
  fi
}

screen_bind_matches() {
  screen_expected=$1
  screen_inspected=$2
  if ! screen_bind_ok "$screen_expected"; then
    echo "android-ue-screen-chain: bind address is not usable" >&2
    return 1
  fi
  if [ "$screen_expected" != "$screen_inspected" ]; then
    echo "android-ue-screen-chain: bind does not match docker inspect" >&2
    return 1
  fi
}

screen_smoke_judge() {
  screen_emu_rc=$1
  screen_loop_rc=$2
  case "$screen_emu_rc" in
    0)
      echo "android-ue-screen-chain: host reached the emulator screen port" >&2
      return 1
      ;;
  esac
  case "$screen_loop_rc" in
    0) return 0 ;;
  esac
  echo "android-ue-screen-chain: 127.0.0.1 did not answer" >&2
  return 1
}

screen_chain_install() {
  screen_name=$1
  screen_want=$2
  screen_have=$3
  screen_allow=$4
  screen_pid_ok "$screen_name" "$screen_want" "$screen_have"
  screen_chain_render "$screen_allow" >/dev/null
  nsenter -t "$screen_want" -n iptables -N ANDROID_UE_SCREEN 2>/dev/null \
    || nsenter -t "$screen_want" -n iptables -F ANDROID_UE_SCREEN
  nsenter -t "$screen_want" -n iptables -A ANDROID_UE_SCREEN -p tcp -s "$screen_allow" --dport 8000 -j ACCEPT
  nsenter -t "$screen_want" -n iptables -A ANDROID_UE_SCREEN -p tcp --dport 8000 -j DROP
  if ! nsenter -t "$screen_want" -n iptables -C INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN 2>/dev/null; then
    nsenter -t "$screen_want" -n iptables -I INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN
  fi
  screen_rules=$(nsenter -t "$screen_want" -n iptables -S ANDROID_UE_SCREEN)
  if ! screen_rules_ok "$screen_allow" "$screen_rules"; then
    echo "android-ue-screen-chain: ANDROID_UE_SCREEN did not verify. Port 8000 stays fail-closed." >&2
    screen_chain_remove "$screen_name" "$screen_want" "$screen_have" || true
    return 1
  fi
}

screen_chain_remove() {
  screen_name=$1
  screen_want=$2
  screen_have=$3
  screen_pid_ok "$screen_name" "$screen_want" "$screen_have"
  nsenter -t "$screen_want" -n iptables -D INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN 2>/dev/null || true
  nsenter -t "$screen_want" -n iptables -F ANDROID_UE_SCREEN 2>/dev/null || true
  nsenter -t "$screen_want" -n iptables -X ANDROID_UE_SCREEN 2>/dev/null || true
}

run_chain_cli() {
  case "${1:-}" in
    --render)
      screen_chain_render "${2:?publisher address}"
      ;;
    --pid-ok)
      screen_pid_ok "${2:?container}" "${3:?pid}" "${4:?inspect pid}"
      ;;
    --bind-match)
      screen_bind_matches "${2:?expected}" "${3:?inspected}"
      ;;
    --smoke-judge)
      screen_smoke_judge "${2:?emulator curl status}" "${3:?loopback curl status}"
      ;;
    --install)
      screen_chain_install "${2:?container}" "${3:?pid}" "${4:?inspect pid}" "${5:?publisher address}"
      ;;
    --remove)
      screen_chain_remove "${2:?container}" "${3:?pid}" "${4:?inspect pid}"
      ;;
    *)
      echo "usage: android-ue-screen-chain.sh --render ADDR | --pid-ok NAME WANT HAVE | --bind-match EXPECTED INSPECTED | --smoke-judge EMU_RC LOOP_RC" >&2
      exit 2
      ;;
  esac
}

if [ "${0##*/}" = "android-ue-screen-chain.sh" ]; then
  run_chain_cli "$@"
fi
