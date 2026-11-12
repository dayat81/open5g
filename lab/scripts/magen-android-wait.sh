#!/bin/bash
# Hold the emulator until the host has locked this netns.
# magen-up writes /tmp/o5g-host-ready with nsenter after IPv6 sysctls and the
# ANDROID_UE_SCREEN chain. Preflight and QEMU run only after that.
set -euo pipefail

deadline=$((SECONDS + ${MAGEN_NETNS_WAIT:-120}))
while [ ! -f /tmp/o5g-host-ready ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "magen: host netns lock did not arrive before QEMU" >&2
    exit 1
  fi
  sleep 0.2
done
exec /opt/start-emulator.sh "$@"
