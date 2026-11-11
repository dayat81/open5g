#!/bin/sh
# ws-scrcpy sidecar entrypoint. Listens on the UE address in l5gd-screen only.
# No host publish, and no dependency on a host ADB port.
set -eu

screen_bind_ok() {
  screen_bind=$1
  case "$screen_bind" in
    ""|0.0.0.0|127.*|0.*|::|::1|"*")
      return 1
      ;;
  esac
  printf '%s\n' "$screen_bind" | awk -F. 'NF != 4 { exit 1 } { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i + 0 > 255) exit 1 }'
}

if [ "${1:-}" = "--check-bind" ]; then
  if screen_bind_ok "${ANDROID_UE_SCREEN_BIND:-}"; then
    exit 0
  fi
  echo "android-ue-screen: refusing bind ${ANDROID_UE_SCREEN_BIND:-empty}" >&2
  exit 1
fi

: "${ANDROID_UE_SCREEN_BIND:?ANDROID_UE_SCREEN_BIND}"
: "${ANDROID_UE_SCREEN_PORT:?ANDROID_UE_SCREEN_PORT}"
: "${ANDROID_UE_SCREEN_PATH:?ANDROID_UE_SCREEN_PATH}"

if ! screen_bind_ok "$ANDROID_UE_SCREEN_BIND"; then
  echo "android-ue-screen: refusing bind ${ANDROID_UE_SCREEN_BIND}" >&2
  exit 1
fi
case "$ANDROID_UE_SCREEN_PORT" in
  ''|*[!0-9]*)
    echo "android-ue-screen: port is not numeric" >&2
    exit 1
    ;;
esac
if [ "$ANDROID_UE_SCREEN_PORT" -lt 1 ] || [ "$ANDROID_UE_SCREEN_PORT" -gt 65535 ]; then
  echo "android-ue-screen: port is out of range" >&2
  exit 1
fi
case "$ANDROID_UE_SCREEN_PATH" in
  /emulator/ue[0-9]|/emulator/ue[0-9][0-9]) ;;
  *)
    echo "android-ue-screen: path must stay under /emulator/ueN" >&2
    exit 1
    ;;
esac

if [ ! -f /opt/ws-scrcpy/package.json ]; then
  echo "android-ue-screen: /opt/ws-scrcpy/package.json is missing" >&2
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "android-ue-screen: npm is not on PATH" >&2
  exit 1
fi

config=/tmp/ws-scrcpy.yaml
cat >"$config" <<EOF
runGoogTracker: true
runApplTracker: false
server:
  - secure: false
    port: ${ANDROID_UE_SCREEN_PORT}
    host: ${ANDROID_UE_SCREEN_BIND}
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

# The emulator adb server stays on 5037 inside the emulator container.
# This sidecar uses its own adb client and server on 5038, and dials socat at the uu address.
export ANDROID_ADB_SERVER_PORT=5038
: "${ANDROID_UE_UU:?ANDROID_UE_UU}"
if command -v adb >/dev/null 2>&1; then
  adb -P 5038 start-server >/dev/null 2>&1 || true
  adb -P 5038 connect "${ANDROID_UE_UU}:5555" >/dev/null 2>&1 || true
  (
    while true; do
      sleep 5
      attached=$(adb -P 5038 devices | awk 'NR > 1 && $2 == "device" { print; exit }')
      if [ -z "$attached" ]; then
        adb -P 5038 connect "${ANDROID_UE_UU}:5555" >/dev/null 2>&1 || true
      fi
    done
  ) &
  loop_pid=$!
fi

cd /opt/ws-scrcpy || exit 1
set +e
npm start
status=$?
set -e
stop_children
exit "$status"
