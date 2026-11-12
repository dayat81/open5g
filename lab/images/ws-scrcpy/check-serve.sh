#!/bin/bash
# Build the pinned ws-scrcpy tree with the Open5G patches and request the real server.
# This is not a stub. GET / must not be the page the dashboard uses.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
dockerfile=$script_dir/Dockerfile
commit=$(awk -F= '$1 == "ARG WS_SCRCPY_COMMIT" { print $2; exit }' "$dockerfile")
sha=$(awk -F= '$1 == "ARG WS_SCRCPY_TARBALL_SHA256" { print $2; exit }' "$dockerfile")
if [ -z "$commit" ] || [ -z "$sha" ]; then
  echo "ws-scrcpy: Dockerfile is missing the commit or tarball pin" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/src.tar.gz" "https://github.com/NetrisTV/ws-scrcpy/archive/${commit}.tar.gz"
echo "${sha}  $work/src.tar.gz" | sha256sum -c
mkdir "$work/src"
tar -xzf "$work/src.tar.gz" -C "$work/src" --strip-components=1
patch -p1 -d "$work/src" <"$script_dir/patches/0001-pathname.patch"
patch -p1 -d "$work/src" <"$script_dir/patches/0002-open5g-bind.patch"
cp "$script_dir/build.config.override.json" "$work/src/build.config.override.json"
(
  cd "$work/src"
  npm ci
  npm run dist
)
cat >"$work/src/dist/public/open5g-limits.js" <<'EOF'
window.__OPEN5G_LIMITS = { maxSize: 800, bitRate: 2000000, maxFps: 15 };
EOF

port=$(python3 - <<'PY'
import socket
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
)
cat >"$work/config.yaml" <<EOF
runGoogTracker: false
runApplTracker: false
server:
  - secure: false
    port: ${port}
    host: 127.0.0.1
EOF

export WS_SCRCPY_CONFIG=$work/config.yaml
export WS_SCRCPY_PATHNAME=/emulator/ue1
pid=0
stop_server() {
  if [ "$pid" -ne 0 ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}
trap 'stop_server; rm -rf "$work"' EXIT
(
  cd "$work/src/dist"
  node ./index.js
) &
pid=$!

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if python3 - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
try:
    sock = socket.create_connection(("127.0.0.1", port), 0.2)
except OSError:
    sys.exit(1)
sock.close()
PY
  then
    ready=1
    break
  fi
  sleep 0.25
done
if [ "$ready" -ne 1 ]; then
  echo "ws-scrcpy: server did not listen on 127.0.0.1:${port}" >&2
  exit 1
fi

python3 - "$port" <<'PY'
import pathlib
import socket
import sys
import urllib.error
import urllib.request
port = int(sys.argv[1])
listeners = []
with open("/proc/net/tcp", encoding="ascii") as handle:
    next(handle)
    for line in handle:
        local, _remote, state = line.split()[1:4]
        ip_hex, port_hex = local.split(":")
        if int(port_hex, 16) == port and state == "0A":
            listeners.append(socket.inet_ntoa(bytes.fromhex(ip_hex)[::-1]))
if listeners != ["127.0.0.1"]:
    sys.exit(f"listener addresses were {listeners}, expected 127.0.0.1")
v6 = pathlib.Path("/proc/net/tcp6")
if v6.exists():
    for line in v6.read_text(encoding="ascii").splitlines()[1:]:
        local, _remote, state = line.split()[1:4]
        _ip_hex, port_hex = local.split(":")
        if int(port_hex, 16) == port and state == "0A":
            sys.exit("the screen server is also listening on IPv6")

def fetch(path):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=5) as response:
        return response.status, response.read()

status, body = fetch("/emulator/ue1/")
if status != 200 or b"bundle" not in body:
    sys.exit(f"/emulator/ue1/ was {status}")
assets = []
for token in body.decode("utf-8", "replace").split('src="')[1:]:
    src = token.split('"', 1)[0]
    if src.startswith("/") or "://" in src:
        sys.exit(f"asset is not under the pathname: {src}")
    assets.append(src)
if not assets:
    sys.exit("the page has no local asset")
for src in assets:
    asset_status, _payload = fetch("/emulator/ue1/" + src)
    if asset_status != 200:
        sys.exit(f"/emulator/ue1/{src} was {asset_status}")
    try:
        fetch("/" + src)
    except urllib.error.HTTPError as exc:
        if exc.code == 200:
            sys.exit(f"/{src} was served from the server root")
    else:
        sys.exit(f"/{src} was served from the server root")
try:
    root_status, _root = fetch("/")
except urllib.error.HTTPError as exc:
    root_status = exc.code
if root_status == 200:
    sys.exit("GET / is still the screen page")
limits_status, limits = fetch("/emulator/ue1/open5g-limits.js")
if limits_status != 200 or b"2000000" not in limits or b"maxFps: 15" not in limits:
    sys.exit("video limits were not served under the pathname")
print("ws-scrcpy: /emulator/ue1/ is 200 and assets stay under that prefix")
PY

stop_server
pid=0
bad_port=$(python3 - <<'PY'
import socket
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
)
cat >"$work/bad.yaml" <<EOF
runGoogTracker: false
runApplTracker: false
server:
  - secure: false
    port: ${bad_port}
    host: 0.0.0.0
EOF
if timeout 15s env WS_SCRCPY_CONFIG="$work/bad.yaml" WS_SCRCPY_PATHNAME=/emulator/ue1 \
  node "$work/src/dist/index.js" >"$work/bad.log" 2>&1; then
  echo "ws-scrcpy: server accepted host 0.0.0.0" >&2
  exit 1
fi
if ! grep -q 'Refusing to listen on an unspecified host' "$work/bad.log"; then
  echo "ws-scrcpy: 0.0.0.0 did not fail closed" >&2
  cat "$work/bad.log" >&2
  exit 1
fi
echo "ws-scrcpy: 0.0.0.0 was refused"
