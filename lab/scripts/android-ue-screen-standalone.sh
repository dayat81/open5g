#!/bin/sh
# Start or stop the host-side screen demo. Does not start the emulator.
# The image must already be loaded. This script never builds and never pulls.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
# shellcheck source=android-ue-screen-bind.sh
. "$script_dir/android-ue-screen-bind.sh"

compose_file=$root/lab/compose/compose.screen-standalone.yml
env_file=${SCREEN_STANDALONE_ENV:-$root/lab/compose/screen-standalone.env}
mode=${1:-}

compose_file_ok() {
  if [ ! -f "$compose_file" ]; then
    echo "android-ue-screen-standalone: compose file is missing" >&2
    return 1
  fi
  if grep -Eq '^[[:space:]]*build:' "$compose_file"; then
    echo "android-ue-screen-standalone: compose file must not build an image" >&2
    return 1
  fi
  if grep -q '0.0.0.0' "$compose_file"; then
    echo "android-ue-screen-standalone: compose file names every interface" >&2
    return 1
  fi
  if grep -Eq 'NET_ADMIN|privileged:|/dev/kvm|group_add:' "$compose_file"; then
    echo "android-ue-screen-standalone: compose file adds privileges or kvm" >&2
    return 1
  fi
  if grep -Eq ':(5037|5554|5555|8554|5900|6080)([^0-9]|$)' "$compose_file"; then
    echo "android-ue-screen-standalone: compose file publishes adb, console, or vnc" >&2
    return 1
  fi
  port_keys=$(grep -c '^[[:space:]]*ports:' "$compose_file" || true)
  if [ "$port_keys" -ne 1 ]; then
    echo "android-ue-screen-standalone: expected one published port" >&2
    return 1
  fi
  # Literal compose text. These are not shell expansions.
  # shellcheck disable=SC2016
  grep -q 'container:${ANDROID_EMULATOR_CONTAINER:-b0-agen-emu}' "$compose_file"
  # shellcheck disable=SC2016
  grep -q '127.0.0.1:${SCREEN_HOST_PORT:-3301}:3301' "$compose_file"
  grep -q 'android-ue-screen.sh' "$compose_file"
  grep -q 'ANDROID_UE_SCREEN_MODE: standalone' "$compose_file"
  grep -q '/emulator/ue1' "$compose_file"
  # shellcheck disable=SC2016
  grep -q 'ANDROID_UE_SCREEN_MAX_SIZE: ${ANDROID_UE_SCREEN_MAX_SIZE:-800}' "$compose_file"
  # shellcheck disable=SC2016
  grep -q 'ANDROID_UE_SCREEN_BIT_RATE: ${ANDROID_UE_SCREEN_BIT_RATE:-2000000}' "$compose_file"
  # shellcheck disable=SC2016
  grep -q 'ANDROID_UE_SCREEN_MAX_FPS: ${ANDROID_UE_SCREEN_MAX_FPS:-15}' "$compose_file"
  if grep -q 'android-ue-screen-host.sh' "$compose_file"; then
    echo "android-ue-screen-standalone: compose file duplicates the screen entrypoint" >&2
    return 1
  fi
}

env_value() {
  key=$1
  file=$2
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

require_pin() {
  image=${ANDROID_UE_SCREEN_IMAGE:-}
  network=${ANDROID_EMULATOR_NETWORK:-}
  bind=${ANDROID_UE_SCREEN_BIND:-}
  if [ -f "$env_file" ]; then
    image=$(env_value ANDROID_UE_SCREEN_IMAGE "$env_file")
    network=$(env_value ANDROID_EMULATOR_NETWORK "$env_file")
    bind=$(env_value ANDROID_UE_SCREEN_BIND "$env_file")
  fi
  if ! screen_host_image_ok "$image"; then
    echo "android-ue-screen-standalone: ANDROID_UE_SCREEN_IMAGE must be pinned with @sha256" >&2
    return 1
  fi
  if ! screen_upstream_name_ok "$network"; then
    echo "android-ue-screen-standalone: ANDROID_EMULATOR_NETWORK is missing or still a placeholder" >&2
    return 1
  fi
  if ! screen_bind_ok "$bind"; then
    echo "android-ue-screen-standalone: ANDROID_UE_SCREEN_BIND must be the emulator address, not loopback" >&2
    return 1
  fi
}

compose_bin() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf '%s\n' "docker compose"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    printf '%s\n' "docker-compose"
    return 0
  fi
  echo "android-ue-screen-standalone: docker compose is not installed" >&2
  return 1
}

case "$mode" in
  --check)
    compose_file_ok
    ;;
  --print)
    compose_file_ok
    require_pin
    printf '%s\n' "docker compose -f lab/compose/compose.screen-standalone.yml --env-file lab/compose/screen-standalone.env up -d"
    ;;
  --print-down)
    printf '%s\n' "docker compose -f lab/compose/compose.screen-standalone.yml --env-file lab/compose/screen-standalone.env down"
    ;;
  up)
    compose_file_ok
    if [ ! -f "$env_file" ]; then
      echo "android-ue-screen-standalone: ${env_file} is missing" >&2
      exit 1
    fi
    require_pin
    bin=$(compose_bin)
    # shellcheck disable=SC2086
    exec $bin -f "$compose_file" --env-file "$env_file" up -d
    ;;
  down)
    compose_file_ok
    if [ ! -f "$env_file" ]; then
      echo "android-ue-screen-standalone: ${env_file} is missing" >&2
      exit 1
    fi
    bin=$(compose_bin)
    # shellcheck disable=SC2086
    exec $bin -f "$compose_file" --env-file "$env_file" down
    ;;
  *)
    echo "android-ue-screen-standalone: use --check, --print, --print-down, up, or down" >&2
    exit 1
    ;;
esac
