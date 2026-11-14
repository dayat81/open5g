#!/bin/sh
# Host screen demo for the emulator that is already running.
# Does not build, pull, stop, or remove that container.
# Access to the published port is ssh -L only. 127.0.0.1:3301 has no RBAC.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
# shellcheck source=android-ue-screen-bind.sh
. "$script_dir/android-ue-screen-bind.sh"
# shellcheck source=android-ue-screen-chain.sh
. "$script_dir/android-ue-screen-chain.sh"

compose_file=$root/lab/compose/compose.screen-standalone.yml
env_file=${SCREEN_STANDALONE_ENV:-$root/lab/compose/screen-standalone.env}
mode=${1:-}
network_name=b0-screen
emulator_name=b0-agen-emu

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
  grep -q 'name: b0-screen' "$compose_file"
  grep -q 'internal: true' "$compose_file"
  grep -q 'enable_ipv6: false' "$compose_file"
  # shellcheck disable=SC2016
  grep -q 'ANDROID_UE_SCREEN_MAX_SIZE: ${ANDROID_UE_SCREEN_MAX_SIZE:-800}' "$compose_file"
  # shellcheck disable=SC2016
  grep -q 'ANDROID_UE_SCREEN_BIT_RATE: ${ANDROID_UE_SCREEN_BIT_RATE:-2000000}' "$compose_file"
  # shellcheck disable=SC2016
  grep -q 'ANDROID_UE_SCREEN_MAX_FPS: ${ANDROID_UE_SCREEN_MAX_FPS:-15}' "$compose_file"
  if grep -q 'ANDROID_EMULATOR_NETWORK' "$compose_file"; then
    echo "android-ue-screen-standalone: compose file still joins the emulator bridge" >&2
    return 1
  fi
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

load_runtime() {
  image=${ANDROID_UE_SCREEN_IMAGE:-}
  bind=${ANDROID_UE_SCREEN_BIND:-}
  publish_addr=${SCREEN_PUBLISH_ADDR:-}
  host_port=${SCREEN_HOST_PORT:-3301}
  container=${ANDROID_EMULATOR_CONTAINER:-b0-agen-emu}
  if [ -f "$env_file" ]; then
    image=$(env_value ANDROID_UE_SCREEN_IMAGE "$env_file")
    bind=$(env_value ANDROID_UE_SCREEN_BIND "$env_file")
    publish_addr=$(env_value SCREEN_PUBLISH_ADDR "$env_file")
    found_port=$(env_value SCREEN_HOST_PORT "$env_file")
    found_name=$(env_value ANDROID_EMULATOR_CONTAINER "$env_file")
    if [ -n "$found_port" ]; then
      host_port=$found_port
    fi
    if [ -n "$found_name" ]; then
      container=$found_name
    fi
  fi
}

require_pin() {
  load_runtime
  if [ "$container" != "$emulator_name" ]; then
    echo "android-ue-screen-standalone: the emulator container must stay ${emulator_name}" >&2
    return 1
  fi
  if ! screen_host_image_ok "$image"; then
    echo "android-ue-screen-standalone: ANDROID_UE_SCREEN_IMAGE must be pinned with @sha256" >&2
    return 1
  fi
  if ! screen_bind_ok "$bind" || ! screen_bind_ok "$publish_addr"; then
    echo "android-ue-screen-standalone: screen addresses must be unicast and not loopback" >&2
    return 1
  fi
  if [ "$bind" = "$publish_addr" ]; then
    echo "android-ue-screen-standalone: the publisher address must differ from the emulator address" >&2
    return 1
  fi
  if ! screen_port_ok "$host_port"; then
    echo "android-ue-screen-standalone: host port is not usable" >&2
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

run_compose() {
  bin=$(compose_bin)
  # shellcheck disable=SC2086
  $bin -f "$compose_file" --env-file "$env_file" "$@"
}

inspect_network_ip() {
  target=$1
  docker inspect -f "{{with index .NetworkSettings.Networks \"${network_name}\"}}{{.IPAddress}}{{end}}" "$target"
}

emulator_pid() {
  docker inspect -f '{{.State.Pid}}' "$emulator_name"
}

attach_emulator() {
  if [ "$(inspect_network_ip "$emulator_name")" = "$bind" ]; then
    return 0
  fi
  docker network connect --ip "$bind" "$network_name" "$emulator_name"
  seen=$(inspect_network_ip "$emulator_name")
  screen_bind_matches "$bind" "$seen"
}

detach_emulator() {
  docker network disconnect "$network_name" "$emulator_name" 2>/dev/null || true
}

remove_chain_if_running() {
  pid=$(emulator_pid 2>/dev/null || true)
  if [ -z "$pid" ] || [ "$pid" = "0" ]; then
    return 0
  fi
  screen_chain_remove "$emulator_name" "$pid" "$pid" || true
}

stop_screen_containers() {
  docker rm -f open5g-screen open5g-screen-publish >/dev/null 2>&1 || true
}

smoke_live() {
  emu_rc=0
  if curl -fsS --max-time 3 "http://${bind}:8000/emulator/ue1/" >/dev/null 2>&1; then
    emu_rc=0
  else
    emu_rc=1
  fi
  loop_rc=0
  if curl -fsS --max-time 5 "http://127.0.0.1:${host_port}/emulator/ue1/" >/dev/null 2>&1; then
    loop_rc=0
  else
    loop_rc=1
  fi
  screen_smoke_judge "$emu_rc" "$loop_rc"
}

bring_up() {
  require_pin
  if [ ! -f "$env_file" ]; then
    echo "android-ue-screen-standalone: ${env_file} is missing" >&2
    return 1
  fi
  if ! command -v nsenter >/dev/null 2>&1 || ! command -v iptables >/dev/null 2>&1; then
    echo "android-ue-screen-standalone: nsenter and iptables are required on the host" >&2
    return 1
  fi
  run_compose up -d screen-publish
  attach_emulator
  seen=$(inspect_network_ip "$emulator_name")
  screen_bind_matches "$bind" "$seen"
  publish_seen=$(inspect_network_ip open5g-screen-publish)
  screen_bind_matches "$publish_addr" "$publish_seen"
  pid=$(emulator_pid)
  if ! screen_chain_install "$emulator_name" "$pid" "$(emulator_pid)" "$publish_addr"; then
    stop_screen_containers
    detach_emulator
    return 1
  fi
  run_compose up -d screen
  if ! smoke_live; then
    stop_screen_containers
    remove_chain_if_running
    echo "android-ue-screen-standalone: smoke failed. The emulator was left running." >&2
    return 1
  fi
}

bring_down() {
  load_runtime
  if [ "$container" != "$emulator_name" ]; then
    echo "android-ue-screen-standalone: refusing to touch ${container}" >&2
    return 1
  fi
  stop_screen_containers
  remove_chain_if_running
  detach_emulator
  docker network rm "$network_name" >/dev/null 2>&1 || true
}

case "$mode" in
  --check)
    compose_file_ok
    ;;
  --print)
    compose_file_ok
    require_pin
    printf '%s\n' "docker compose -f lab/compose/compose.screen-standalone.yml --env-file lab/compose/screen-standalone.env up -d screen-publish"
    printf '%s\n' "docker network connect --ip <bind> b0-screen b0-agen-emu"
    printf '%s\n' "nsenter -t <pid> -n iptables ANDROID_UE_SCREEN"
    printf '%s\n' "docker compose -f lab/compose/compose.screen-standalone.yml --env-file lab/compose/screen-standalone.env up -d screen"
    ;;
  --print-down)
    printf '%s\n' "docker rm -f open5g-screen open5g-screen-publish"
    printf '%s\n' "nsenter -t <pid> -n iptables -D INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN"
    printf '%s\n' "docker network disconnect b0-screen b0-agen-emu"
    printf '%s\n' "docker network rm b0-screen"
    ;;
  up)
    compose_file_ok
    bring_up
    ;;
  down)
    compose_file_ok
    bring_down
    ;;
  *)
    echo "android-ue-screen-standalone: use --check, --print, --print-down, up, or down" >&2
    exit 1
    ;;
esac
