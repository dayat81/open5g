#!/bin/bash
# S1 checklist. A machine without KVM cannot produce the websocket 101 line.
# When the listener is absent this exits 0 and says the evidence is pending.
set -euo pipefail

pending() {
  cat <<'EOF'
S1 evidence is pending. Do not treat this run as a pass.

Lab Ops window, after the image digest is filled in:
1. Build lab/images/android-emulator/build.sh from this tree and mirror it. The B0/B2 image from PR #12 binds a different socat address and must not be reused. Record name@sha256 with 64 hex digits.
2. Build lab/images/ws-scrcpy and mirror that image the same way. android-ue-magen.sh and android-ue-up.sh refuse a tag without @sha256.
3. On the lab UE path, set ANDROID_UE_SCREEN_IMAGE before the first android-ue-up.sh, or, if androidN is already running, use android-ue-up.sh --screen-only. That installs ANDROID_UE_SCREEN and does not start the route sidecar again.
4. From the laptop: ssh -L 3300:127.0.0.1:3300 -L 3301:127.0.0.1:3301 <guest>
5. Open the dashboard as the assigned student. The listener log must contain "101 Switching Protocols" for /emulator/ue1/.
6. Confirm the frame shows the api-33 swiftshader screen and that a touch arrives. max-size 800, bit-rate 2M, and max-fps 15 are the defaults.
7. On the guest, ss must show the sidecar bound to the screen address, not 0.0.0.0, and port 8000 closed on the uu interface.
8. Rollback is OPEN5G_EMULATOR_ENABLED=0 and stopping the screen container. Do not run this from the PR #12 tree.
EOF
}

if [ ! -e /dev/kvm ]; then
  pending
  echo "android-ue-screen-smoke: /dev/kvm is missing"
  exit 0
fi

listener=${OPEN5G_S1_LISTENER:-http://127.0.0.1:3301/emulator/ue1/}
if ! python3 - "$listener" <<'PY'
import socket, sys
from urllib.parse import urlparse
parsed = urlparse(sys.argv[1])
sock = socket.socket()
sock.settimeout(2)
try:
    sock.connect((parsed.hostname or "127.0.0.1", parsed.port or 80))
except OSError:
    sys.exit(1)
PY
then
  pending
  echo "android-ue-screen-smoke: the screen listener is not accepting connections"
  exit 0
fi

echo "android-ue-screen-smoke: listener is up. Capture the 101 line from its log before calling S1 passed." >&2
exit 1
