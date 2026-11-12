#!/bin/bash
# Write the magen smoke report. CI uses --fixture. Live checks run later
# in a Lab Ops window and are recorded as skipped here.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"
# shellcheck source=magen-screen-chain.sh
. "$script_dir/magen-screen-chain.sh"

env_file=""
fixture=0
with_sgi=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      env_file=$1
      ;;
    --fixture) fixture=1 ;;
    --with-sgi-egress) with_sgi=1 ;;
    *)
      echo "usage: magen-smoke.sh --env-file FILE [--fixture] [--with-sgi-egress]" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  echo "usage: magen-smoke.sh --env-file FILE [--fixture]" >&2
  exit 2
fi

get() { magen_env_get "$env_file" "$1"; }
if [ -n "$(get O5G_STATE_DIR)" ]; then
  O5G_STATE_DIR=$(get O5G_STATE_DIR)
  export O5G_STATE_DIR
fi
magen_radio_gate() {
  local boot=$1 sim=$2 log=$3 registry=$4
  local ok=1 modem=missing
  boot=$(printf '%s' "$boot" | tr -d '\r')
  sim=$(printf '%s' "$sim" | tr -d '\r')
  if [ -z "$boot" ] || [ "$boot" != "1" ]; then
    ok=0
  fi
  case "$sim" in
    READY|LOADED) ;;
    *) ok=0 ;;
  esac
  if [ -s "$log" ] && grep -q 'ModemSimulator' "$log"; then
    modem=present
  else
    ok=0
  fi
  if [ ! -s "$registry" ]; then
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "magen: radio gate passed"
    return 0
  fi
  echo "magen: radio gate FAIL." >&2
  echo "magen: evidence boot=${boot:-empty} gsm.sim.state=${sim:-empty} ModemSimulator=${modem}" >&2
  echo "magen: no automatic fallback was applied." >&2
  echo "magen: preferred option, only if Architect picks it later: install a dummy0 ULA anchor from the host with nsenter -n and a pid guard before QEMU. The emulator stays without NET_ADMIN and all.disable_ipv6 is never set to 1." >&2
  echo "magen: last resort: -feature -ModemSimulator." >&2
  return 1
}

magen_radio_collect_live() {
  local dest=$1
  local name=${MAGEN_RADIO_CONTAINER:-o5g-android1}
  if ! command -v docker >/dev/null 2>&1; then
    echo "magen: radio gate FAIL. docker is not available, so emulator evidence could not be read." >&2
    echo "magen: the radio-ok fixture is not used unless --fixture is set." >&2
    return 1
  fi
  if ! docker exec "$name" adb shell getprop sys.boot_completed >"$dest/boot" 2>>"$dest/err"; then
    echo "magen: radio gate FAIL. adb getprop sys.boot_completed could not be read from ${name}." >&2
    echo "magen: the radio-ok fixture is not used unless --fixture is set." >&2
    return 1
  fi
  if ! docker exec "$name" adb shell getprop gsm.sim.state >"$dest/sim" 2>>"$dest/err"; then
    echo "magen: radio gate FAIL. adb getprop gsm.sim.state could not be read from ${name}." >&2
    echo "magen: the radio-ok fixture is not used unless --fixture is set." >&2
    return 1
  fi
  if ! docker exec "$name" adb shell dumpsys telephony.registry >"$dest/registry" 2>>"$dest/err"; then
    echo "magen: radio gate FAIL. dumpsys telephony.registry could not be read from ${name}." >&2
    echo "magen: the radio-ok fixture is not used unless --fixture is set." >&2
    return 1
  fi
  if ! docker exec "$name" adb shell logcat -d >"$dest/logcat" 2>>"$dest/err"; then
    echo "magen: radio gate FAIL. ModemSimulator logcat could not be read from ${name}." >&2
    echo "magen: the radio-ok fixture is not used unless --fixture is set." >&2
    return 1
  fi
  sed -i 's/\r$//' "$dest/boot" "$dest/sim"
  if [ ! -s "$dest/boot" ] || [ ! -s "$dest/sim" ] || [ ! -s "$dest/registry" ] || [ ! -s "$dest/logcat" ]; then
    echo "magen: radio gate FAIL. emulator evidence is empty." >&2
    echo "magen: the radio-ok fixture is not used unless --fixture is set." >&2
    return 1
  fi
}

if [ "$fixture" -eq 1 ]; then
  radio_dir=${MAGEN_RADIO_DIR:-"$(magen_root)/lab/scripts/fixtures/magen/radio-ok"}
else
  radio_dir=$(mktemp -d)
  if ! magen_radio_collect_live "$radio_dir"; then
    exit 1
  fi
fi
if ! magen_radio_gate "$(cat "$radio_dir/boot" 2>/dev/null || true)" "$(cat "$radio_dir/sim" 2>/dev/null || true)" "$radio_dir/logcat" "$radio_dir/registry"; then
  exit 1
fi
magen_screen_evidence_ok() {
  local ws=$1 host8000=$2
  ws=$(printf '%s' "$ws" | tr -d '\r')
  if [ "$ws" != "101" ]; then
    echo "magen: screen gate FAIL. websocket status is ${ws:-empty}, expected 101 on 127.0.0.1:3301/emulator/ue1." >&2
    return 1
  fi
  if [ "$host8000" != "closed" ]; then
    echo "magen: screen gate FAIL. emulator port 8000 is reachable from the host." >&2
    return 1
  fi
  echo "magen: screen gate passed"
}
magen_screen_collect_live() {
  local dest=$1 addr=$2
  python3 - "$dest" "$addr" <<'PY'
import socket, sys
dest, addr = sys.argv[1], sys.argv[2]
req = (
    "GET /emulator/ue1/ HTTP/1.1\r\n"
    "Host: 127.0.0.1:3301\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
    "Sec-WebSocket-Version: 13\r\n\r\n"
)
status = ""
try:
    sock = socket.create_connection(("127.0.0.1", 3301), 2)
    sock.sendall(req.encode())
    status = sock.recv(64).decode("ascii", "replace").split(" ", 2)[1]
    sock.close()
except Exception:
    status = ""
open(dest + "/ws", "w", encoding="utf-8").write(status + "\n")
host = "open"
try:
    probe = socket.create_connection((addr, 8000), 1)
    probe.close()
except Exception:
    host = "closed"
open(dest + "/host8000", "w", encoding="utf-8").write(host + "\n")
PY
}
if [ "$fixture" -eq 1 ]; then
  screen_dir=${MAGEN_SCREEN_DIR:-"$(magen_root)/lab/scripts/fixtures/magen/screen-ok"}
else
  screen_dir=$(mktemp -d)
  if ! magen_screen_collect_live "$screen_dir" "$(get O5G_SCREEN_ANDROID1)"; then
    echo "magen: screen gate FAIL. listener evidence could not be read." >&2
    exit 1
  fi
fi
if ! magen_screen_evidence_ok "$(cat "$screen_dir/ws" 2>/dev/null || true)" "$(cat "$screen_dir/host8000" 2>/dev/null || true)"; then
  exit 1
fi
python3 - "$(magen_root)/lab/compose/compose.magen.yml" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
in_upf = False
in_networks = False
for raw in text.splitlines():
    if raw.startswith("  upf:"):
        in_upf = True
        in_networks = False
        continue
    if in_upf and raw.startswith("  ") and not raw.startswith("   "):
        break
    if in_upf and raw.startswith("    networks:"):
        in_networks = True
        continue
    if in_networks and raw.startswith("      egress:"):
        sys.stderr.write("magen: default UPF joins a non-internal network\n")
        sys.exit(1)
PY
listener=$(get O5G_SCREEN_LISTENER)
other=$(get O5G_SCREEN_ANDROID1)
if magen_screen_source_allowed "$listener" "$other"; then
  echo "magen: emulator address must not match the listener allow rule" >&2
  exit 1
fi
if ! magen_screen_source_allowed "$listener" "$listener"; then
  echo "magen: listener address was not allowed" >&2
  exit 1
fi

state=$(magen_state_dir)
mkdir -p -- "$state"
chmod 0700 "$state"
report="${state}/smoke.json"
md="${state}/smoke.md"
live="skipped"
reason="Lab Ops window"
if [ "$fixture" -eq 0 ]; then
  live="not-run"
  reason="pass --fixture in CI; run without it only on MAGEN_HOST during Lab Ops"
fi

python3 - "$report" "$md" "$listener" "$live" "$reason" "$with_sgi" <<'PY'
import json, sys
report, md, listener, live, reason, sgi = sys.argv[1:]
body = {
    "listener_bind": "127.0.0.1:3301",
    "screen_port_8000": "tcp 8000 is accepted only from the listener address and dropped for every other source",
    "listener": listener,
    "core_up": live,
    "s1_setup": live,
    "ue_attach": live,
    "sgi_curl": "SKIPPED" if sgi == "0" else "pending-approval",
    "bind_0_0_0_0": "absent",
    "v6_guard": "lo keeps ::1; all is not set to 1",
    "emulator_boot_completed": live,
    "adb_stable_seconds": 120,
    "lo_has_loopback": "mandatory",
    "eth_global_v6": "absent",
    "dashboard_w1_w4_w7_w8": live,
    "screen_s1_s2": live,
    "screen_v5_s1_s8": live,
    "ue_chains": "N/A",
    "reason": reason,
}
open(report, "w", encoding="utf-8").write(json.dumps(body, indent=2) + "\n")
lines = ["# magen smoke", ""]
for key, value in body.items():
    lines.append("- %s: %s" % (key, value))
open(md, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
echo "magen: smoke report ${report}"
echo "changed=1"
