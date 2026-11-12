#!/bin/sh
# Forward one container address to the emulator container's screen port.
# Compose publishes that listen port on 127.0.0.1 only. This process does
# not bind every interface and does not publish a port by itself.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-screen-bind.sh
. "$script_dir/android-ue-screen-bind.sh"

if [ "${1:-}" = "--check-bind" ]; then
  if screen_bind_ok "${SCREEN_PUBLISH_BIND:-}"; then
    exit 0
  fi
  echo "android-ue-screen-publish: refusing bind ${SCREEN_PUBLISH_BIND:-empty}" >&2
  exit 1
fi

if [ "${1:-}" = "--check-upstream" ]; then
  if screen_upstream_name_ok "${ANDROID_EMULATOR_CONTAINER:-}"; then
    exit 0
  fi
  echo "android-ue-screen-publish: refusing upstream name" >&2
  exit 1
fi

: "${ANDROID_EMULATOR_CONTAINER:?ANDROID_EMULATOR_CONTAINER}"
: "${SCREEN_UPSTREAM_PORT:?SCREEN_UPSTREAM_PORT}"
: "${SCREEN_PUBLISH_PORT:?SCREEN_PUBLISH_PORT}"

if ! screen_upstream_name_ok "$ANDROID_EMULATOR_CONTAINER"; then
  echo "android-ue-screen-publish: refusing upstream name" >&2
  exit 1
fi
if ! screen_port_ok "$SCREEN_UPSTREAM_PORT" || ! screen_port_ok "$SCREEN_PUBLISH_PORT"; then
  echo "android-ue-screen-publish: refusing port" >&2
  exit 1
fi

if [ -n "${SCREEN_PUBLISH_BIND:-}" ]; then
  bind=$SCREEN_PUBLISH_BIND
else
  bind=$(screen_discover_bind) || {
    echo "android-ue-screen-publish: no container address to bind" >&2
    exit 1
  }
fi
if ! screen_bind_ok "$bind"; then
  echo "android-ue-screen-publish: refusing bind ${bind}" >&2
  exit 1
fi

exec python3 - "$bind" "$SCREEN_PUBLISH_PORT" "$ANDROID_EMULATOR_CONTAINER" "$SCREEN_UPSTREAM_PORT" <<'PY'
import socket
import sys
import threading

listen_host, listen_port, upstream_host, upstream_port = sys.argv[1:5]
listen_port = int(listen_port)
upstream_port = int(upstream_port)


def pipe(source, sink):
    try:
        while True:
            data = source.recv(65536)
            if not data:
                break
            sink.sendall(data)
    except OSError:
        pass
    finally:
        for item in (source, sink):
            try:
                item.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(client):
    try:
        remote = socket.create_connection((upstream_host, upstream_port), timeout=5)
    except OSError:
        client.close()
        return
    left = threading.Thread(target=pipe, args=(client, remote), daemon=True)
    right = threading.Thread(target=pipe, args=(remote, client), daemon=True)
    left.start()
    right.start()
    left.join()
    right.join()
    client.close()
    remote.close()


server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((listen_host, listen_port))
server.listen(32)
while True:
    client, _addr = server.accept()
    threading.Thread(target=handle, args=(client,), daemon=True).start()
PY
