#!/bin/sh
# ws-scrcpy beside an emulator that is already running on the Docker host.
# Start this only with network_mode: container:<emulator>. The pinned
# ws-scrcpy 0.8.1 server has no bind address, so it listens on every
# interface of that netns. Do not run this script with host networking.
# The sidecar keeps its own adb server on 5038 and dials 127.0.0.1:5555.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-screen-bind.sh
. "$script_dir/android-ue-screen-bind.sh"

if [ "${1:-}" = "--check-bind" ]; then
  if screen_bind_ok "${ANDROID_UE_SCREEN_BIND:-}"; then
    exit 0
  fi
  echo "android-ue-screen-host: refusing bind ${ANDROID_UE_SCREEN_BIND:-empty}" >&2
  exit 1
fi

if [ "${1:-}" = "--check-path" ]; then
  if screen_path_ok "${ANDROID_UE_SCREEN_PATH:-}"; then
    exit 0
  fi
  echo "android-ue-screen-host: refusing path ${ANDROID_UE_SCREEN_PATH:-empty}" >&2
  exit 1
fi

: "${ANDROID_UE_SCREEN_PORT:?ANDROID_UE_SCREEN_PORT}"
: "${ANDROID_UE_SCREEN_PATH:?ANDROID_UE_SCREEN_PATH}"

if ! screen_port_ok "$ANDROID_UE_SCREEN_PORT"; then
  echo "android-ue-screen-host: refusing port ${ANDROID_UE_SCREEN_PORT}" >&2
  exit 1
fi
if ! screen_path_ok "$ANDROID_UE_SCREEN_PATH"; then
  echo "android-ue-screen-host: path must stay under /emulator/<name>" >&2
  exit 1
fi

if [ -n "${ANDROID_UE_SCREEN_BIND:-}" ]; then
  bind=$ANDROID_UE_SCREEN_BIND
else
  bind=$(screen_discover_bind) || {
    echo "android-ue-screen-host: no emulator address to bind" >&2
    exit 1
  }
fi
if ! screen_bind_ok "$bind"; then
  echo "android-ue-screen-host: refusing bind ${bind}" >&2
  exit 1
fi

if [ ! -f /opt/ws-scrcpy/package.json ]; then
  echo "android-ue-screen-host: /opt/ws-scrcpy/package.json is missing" >&2
  exit 1
fi
if [ ! -f /opt/ws-scrcpy/dist/index.js ]; then
  echo "android-ue-screen-host: dist/index.js is missing; load an image built on a connected machine" >&2
  exit 1
fi
if [ ! -f /opt/ws-scrcpy/dist/vendor/Genymobile/scrcpy/scrcpy-server.jar ]; then
  echo "android-ue-screen-host: scrcpy-server.jar is missing from the image" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "android-ue-screen-host: node is not on PATH" >&2
  exit 1
fi
if ! command -v adb >/dev/null 2>&1; then
  echo "android-ue-screen-host: adb is not on PATH" >&2
  exit 1
fi

config=/tmp/ws-scrcpy.yaml
cat >"$config" <<EOF
runGoogTracker: true
runApplTracker: false
server:
  - secure: false
    port: ${ANDROID_UE_SCREEN_PORT}
    host: ${bind}
EOF
export WS_SCRCPY_CONFIG="$config"
export WS_SCRCPY_PATHNAME="$ANDROID_UE_SCREEN_PATH"

loop_pid=0
stop_children() {
  if [ "$loop_pid" -ne 0 ]; then
    kill "$loop_pid" 2>/dev/null || true
  fi
}
trap stop_children INT TERM

# The emulator adb server stays on its own port inside this netns and is not
# published. This sidecar uses a separate server and dials the daemon on
# 127.0.0.1:5555, then pushes scrcpy-server.jar over that adb connection.
export ANDROID_ADB_SERVER_PORT=5038
adb -P 5038 start-server >/dev/null 2>&1 || true
adb -P 5038 connect 127.0.0.1:5555 >/dev/null 2>&1 || true
(
  while true; do
    sleep 5
    attached=$(adb -P 5038 devices | awk 'NR > 1 && $2 == "device" { print; exit }')
    if [ -z "$attached" ]; then
      adb -P 5038 connect 127.0.0.1:5555 >/dev/null 2>&1 || true
    fi
  done
) &
loop_pid=$!

# The package start script rebuilds the bundle. The Docker host has no
# egress, so run the dist that was produced when the image was built.
cd /opt/ws-scrcpy/dist || exit 1
set +e
node index.js
status=$?
set -e
stop_children
exit "$status"
