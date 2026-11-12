#!/bin/sh
# ws-scrcpy sidecar entrypoint. Listens on the UE address in l5gd-screen only.
# No host publish, and no dependency on a host ADB port.
set -eu

screen_bind_ok() {
  screen_bind=$1
  case "$screen_bind" in
    ""|0.0.0.0|::|::1|"*")
      return 1
      ;;
    127.*)
      if [ "${ANDROID_UE_SCREEN_MODE:-}" = "standalone" ]; then
        return 0
      fi
      return 1
      ;;
    0.*)
      return 1
      ;;
  esac
  printf '%s\n' "$screen_bind" | awk -F. 'NF != 4 { exit 1 } { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i + 0 > 255) exit 1 }'
}

screen_socket_matches() {
  python3 - "$1" <<'PY'
import socket
import sys
host = sys.argv[1]
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind((host, 0))
except OSError:
    sys.exit(2)
sock.listen(1)
got = sock.getsockname()[0]
sock.close()
if got != host or got == "0.0.0.0":
    sys.exit(1)
PY
}

screen_socket_in_netns() {
  bind_addr=$1
  ns=o5g-bind-$$
  status=1
  if ! command -v ip >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    echo "android-ue-screen: cannot check the real socket for ${bind_addr}" >&2
    return 1
  fi
  sudo ip netns add "$ns" || return 1
  sudo ip netns exec "$ns" ip link set lo up || { sudo ip netns del "$ns" || true; return 1; }
  sudo ip netns exec "$ns" ip addr add "${bind_addr}/32" dev lo || { sudo ip netns del "$ns" || true; return 1; }
  sudo ip netns exec "$ns" python3 - "$bind_addr" <<'PY'
import socket
import sys
host = sys.argv[1]
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind((host, 0))
sock.listen(1)
got = sock.getsockname()[0]
sock.close()
if got != host or got == "0.0.0.0":
    sys.exit(1)
PY
  status=$?
  sudo ip netns del "$ns" || true
  return "$status"
}

if [ "${1:-}" = "--check-bind" ]; then
  if ! screen_bind_ok "${ANDROID_UE_SCREEN_BIND:-}"; then
    echo "android-ue-screen: refusing bind ${ANDROID_UE_SCREEN_BIND:-empty}" >&2
    exit 1
  fi
  if screen_socket_matches "$ANDROID_UE_SCREEN_BIND"; then
    exit 0
  fi
  if screen_socket_in_netns "$ANDROID_UE_SCREEN_BIND"; then
    exit 0
  fi
  echo "android-ue-screen: socket for ${ANDROID_UE_SCREEN_BIND} is not that address" >&2
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

# The emulator adb server stays on 5037. This sidecar uses its own server on 5038.
export ANDROID_ADB_SERVER_PORT=5038
if [ "${ANDROID_UE_SCREEN_MODE:-}" = "standalone" ]; then
  adb_target=127.0.0.1:5555
else
  : "${ANDROID_UE_UU:?ANDROID_UE_UU}"
  adb_target="${ANDROID_UE_UU}:5555"
fi
if command -v adb >/dev/null 2>&1; then
  adb -P 5038 start-server >/dev/null 2>&1 || true
  adb -P 5038 connect "${adb_target}" >/dev/null 2>&1 || true
  (
    while true; do
      sleep 5
      attached=$(adb -P 5038 devices | awk 'NR > 1 && $2 == "device" { print; exit }')
      if [ -z "$attached" ]; then
        adb -P 5038 connect "${adb_target}" >/dev/null 2>&1 || true
      fi
    done
  ) &
  loop_pid=$!
fi

cd /opt/ws-scrcpy || exit 1
set +e
npm run dist
status=$?
set -e
if [ "$status" -ne 0 ]; then
  stop_children
  exit "$status"
fi
max_size=${ANDROID_UE_SCREEN_MAX_SIZE:-800}
bit_rate=${ANDROID_UE_SCREEN_BIT_RATE:-2000000}
max_fps=${ANDROID_UE_SCREEN_MAX_FPS:-15}
case "$max_size" in
  ''|*[!0-9]*) echo "android-ue-screen: max-size is not numeric" >&2; exit 1 ;;
esac
case "$bit_rate" in
  ''|*[!0-9]*) echo "android-ue-screen: bit-rate is not numeric" >&2; exit 1 ;;
esac
case "$max_fps" in
  ''|*[!0-9]*) echo "android-ue-screen: max-fps is not numeric" >&2; exit 1 ;;
esac
cat > dist/public/open5g-limits.js <<EOF
window.__OPEN5G_LIMITS = { maxSize: ${max_size}, bitRate: ${bit_rate}, maxFps: ${max_fps} };
EOF
cd dist
set +e
npm start
status=$?
set -e
stop_children
exit "$status"
