#!/bin/sh
# Local forward from the guest, or from a laptop, to the Docker host screen.
# ssh -L only. Both ends are 127.0.0.1. No key is read from this repo.
# The guest default local port is 3302 so it does not collide with the
# dashboard screen listener on 3301. A laptop demo sets the local port to 3301.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-screen-bind.sh
. "$script_dir/android-ue-screen-bind.sh"

print_only=0
if [ "${1:-}" = "--print" ]; then
  print_only=1
fi

local_port=${SCREEN_TUNNEL_LOCAL_PORT:-3302}
remote_port=${SCREEN_TUNNEL_REMOTE_PORT:-3301}
target=${ANDROID_EMULATOR_SSH_TARGET:-}

if ! screen_port_ok "$local_port" || ! screen_port_ok "$remote_port"; then
  echo "android-ue-screen-tunnel: refusing port" >&2
  exit 1
fi
case "$target" in
  ""|-*|*[[:space:]]*|REPLACE_*|*CHANGEME*)
    echo "android-ue-screen-tunnel: SSH target is missing or still a placeholder" >&2
    exit 1
    ;;
esac

forward="127.0.0.1:${local_port}:127.0.0.1:${remote_port}"
if [ "$print_only" -eq 1 ]; then
  printf '%s\n' "ssh -N -o ExitOnForwardFailure=yes -o ClearAllForwardings=yes -L ${forward} -- ${target}"
  exit 0
fi

exec ssh -N -o ExitOnForwardFailure=yes -o ClearAllForwardings=yes -L "$forward" -- "$target"
