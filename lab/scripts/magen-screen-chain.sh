#!/bin/bash
# Magen wiring for the ANDROID_UE_SCREEN chain.
# The sidecar and listener programs live in PR #13. This file only renders
# the filter: TCP 8000 is accepted from the listener address and dropped
# for every other source. It does not publish a host port.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

magen_screen_chain_render() {
  local listener=$1
  if magen_is_placeholder "$listener"; then
    echo "magen: screen listener address is empty or still a placeholder" >&2
    return 1
  fi
  if ! printf '%s\n' "$listener" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "magen: screen listener address must be an IPv4 address" >&2
    return 1
  fi
  cat <<EOF
-N ANDROID_UE_SCREEN
-A ANDROID_UE_SCREEN -p tcp -s ${listener} --dport 8000 -j ACCEPT
-A ANDROID_UE_SCREEN -p tcp --dport 8000 -j DROP
-I INPUT -p tcp --dport 8000 -j ANDROID_UE_SCREEN
EOF
}

# allow only when the source is exactly the listener address.
magen_screen_source_allowed() {
  local listener=$1 source=$2
  [ "$source" = "$listener" ]
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

case "${1:-}" in
  --render)
    magen_screen_chain_render "${2:?listener address}"
    ;;
  *)
    echo "usage: magen-screen-chain.sh --render LISTENER_IPV4" >&2
    exit 2
    ;;
esac
