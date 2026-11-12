#!/bin/bash
# Standalone emulator screen on one host. Does not call android-ue-up.sh.
# The lab uu bind, sysctl preset, and write_zero order are not used here.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-lib.sh
. "$script_dir/android-ue-lib.sh"

usage() {
  echo "usage: android-ue-magen.sh --env-file FILE [--check]" >&2
  exit 2
}

env_file=""
check_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || usage
      env_file=$1
      ;;
    --check) check_only=1 ;;
    *) usage ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  usage
fi

root=$(android_ue_root)
get() { android_ue_env_get "$env_file" "$1"; }

ipv4_ok() {
  printf '%s\n' "$1" | awk -F. 'NF != 4 { exit 1 } { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i + 0 > 255) exit 1 }'
}

require_addr() {
  local name=$1
  local value=$2
  android_ue_reject_placeholder "$name" "$value"
  case "$value" in
    ""|0.0.0.0|::|127.*|0.*)
      echo "android-ue-magen: ${name} must be one non-loopback IPv4 address" >&2
      return 1
      ;;
  esac
  ipv4_ok "$value"
}

require_pinned() {
  local name=$1
  local value=$2
  android_ue_reject_placeholder "$name" "$value"
  if ! android_ue_screen_image_ok "$value"; then
    echo "android-ue-magen: ${name} must be pinned with @sha256" >&2
    return 1
  fi
}

android_image=$(get ANDROID_UE_ANDROID_IMAGE)
screen_image=$(get ANDROID_UE_SCREEN_IMAGE)
listener_image=$(get O5G_SCREEN_LISTENER_IMAGE)
emulator_addr=$(get O5G_SCREEN_EMULATOR_ADDR)
listener_addr=$(get O5G_SCREEN_LISTENER_ADDR)
subnet=$(get O5G_SCREEN_SUBNET)
gateway=$(get O5G_SCREEN_GATEWAY)
dashboard_net=$(get O5G_DASHBOARD_NETWORK)
port=$(get ANDROID_UE_SCREEN_PORT)

require_pinned ANDROID_UE_ANDROID_IMAGE "$android_image"
require_pinned ANDROID_UE_SCREEN_IMAGE "$screen_image"
require_pinned O5G_SCREEN_LISTENER_IMAGE "$listener_image"
require_addr O5G_SCREEN_EMULATOR_ADDR "$emulator_addr"
require_addr O5G_SCREEN_LISTENER_ADDR "$listener_addr"
require_addr O5G_SCREEN_GATEWAY "$gateway"
android_ue_reject_placeholder O5G_SCREEN_SUBNET "$subnet"
android_ue_reject_placeholder O5G_DASHBOARD_NETWORK "$dashboard_net"
if ! printf '%s\n' "$subnet" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
  echo "android-ue-magen: O5G_SCREEN_SUBNET must be an IPv4 prefix" >&2
  exit 1
fi
if [ "$emulator_addr" = "$listener_addr" ]; then
  echo "android-ue-magen: the listener address must differ from the emulator address" >&2
  exit 1
fi
case "$port" in
  ''|*[!0-9]*)
    echo "android-ue-magen: ANDROID_UE_SCREEN_PORT is not numeric" >&2
    exit 1
    ;;
esac
if [ -n "$(get ANDROID_UE_UU || true)" ]; then
  echo "android-ue-magen: ANDROID_UE_UU must stay unset. Standalone mode does not loosen the lab uu bind." >&2
  exit 1
fi

compose_file=$root/lab/compose/docker-compose.magen-screen.optional.yml
if grep -q 'ANDROID_UE_UU' "$compose_file"; then
  echo "android-ue-magen: the magen compose file must not pass ANDROID_UE_UU" >&2
  exit 1
fi
if grep -q '0.0.0.0' "$compose_file"; then
  echo "android-ue-magen: the magen compose file binds every address" >&2
  exit 1
fi

if [ "$check_only" -eq 1 ]; then
  echo "android-ue-magen: images are pinned and the screen network is fail-closed"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "android-ue-magen: docker is missing" >&2
  exit 1
fi

compose() {
  local -a bin
  if [ -n "${ANDROID_UE_COMPOSE_BIN:-}" ]; then
    # shellcheck disable=SC2206
    bin=($ANDROID_UE_COMPOSE_BIN)
  elif command -v docker-compose >/dev/null 2>&1; then
    bin=(docker-compose)
  else
    bin=(docker compose)
  fi
  "${bin[@]}" -f "$compose_file" --env-file "$env_file" --profile magen-screen "$@"
}

compose up -d magen-emulator
pid=$(docker inspect -f '{{.State.Pid}}' l5gd-android-magen)
if ! nsenter -t "$pid" -n env \
  ANDROID_UE_SCREEN_IMAGE="$screen_image" \
  ANDROID_UE_SCREEN_ADDR="$emulator_addr" \
  ANDROID_UE_SCREEN_ALLOW_FROM="$listener_addr" \
  ANDROID_UE_SCREEN_PORT="$port" \
  bash "$script_dir/android-ue-route.sh" --install-screen; then
  echo "android-ue-magen: ANDROID_UE_SCREEN was not installed" >&2
  exit 1
fi
compose up -d magen-screen magen-listener
echo "android-ue-magen: sidecar listens on ${emulator_addr}:${port}. The host publish is 127.0.0.1:3301 only."
