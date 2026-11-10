#!/bin/bash
# Wait until this user's srsUE is accepting its ZMQ TCP port, then exec srsenb.
# The image entrypoint is /entrypoint.sh and expects the first argument "enb".
set -euo pipefail

target=${UE_ADDRESS:?UE_ADDRESS}
port=2001
wait_s=${ANDROID_UE_ZMQ_WAIT:?ANDROID_UE_ZMQ_WAIT}
deadline=$((SECONDS + wait_s))

while [ "$SECONDS" -lt "$deadline" ]; do
  if timeout 1 bash -c "echo >/dev/tcp/${target}/${port}" 2>/dev/null; then
    exec /entrypoint.sh enb "$@"
  fi
  sleep 1
done

echo "android-ue-enb: ${target}:${port} did not accept within ${wait_s}s" >&2
exit 1
