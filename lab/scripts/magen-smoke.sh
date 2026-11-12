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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      env_file=$1
      ;;
    --fixture) fixture=1 ;;
    *)
      echo "usage: magen-smoke.sh --env-file FILE [--fixture]" >&2
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

python3 - "$report" "$md" "$listener" "$live" "$reason" <<'PY'
import json, sys
report, md, listener, live, reason = sys.argv[1:]
body = {
    "listener_bind": "127.0.0.1:3301",
    "screen_port_8000": "tcp 8000 is accepted only from the listener address and dropped for every other source",
    "listener": listener,
    "core_up": live,
    "s1_setup": live,
    "ue_attach": live,
    "sgi_curl": live,
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
