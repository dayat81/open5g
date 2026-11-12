#!/bin/sh
# Dashboard screen mode check. Prints the mode only. Does not print the URL,
# open a socket, or start the API. guest is the default and ignores the URL.
set -eu

mode=${OPEN5G_EMULATOR_SCREEN_MODE:-guest}
case "$mode" in
  guest)
    printf '%s\n' "mode=guest"
    exit 0
    ;;
  host-agen) ;;
  *)
    echo "android-ue-screen-mode: mode must be guest or host-agen" >&2
    exit 1
    ;;
esac

url=${SCREEN_UPSTREAM_URL:-}
case "$url" in
  "")
    echo "android-ue-screen-mode: host-agen is off until SCREEN_UPSTREAM_URL is loopback" >&2
    exit 1
    ;;
  http://127.0.0.1:*|ws://127.0.0.1:*) ;;
  *)
    echo "android-ue-screen-mode: SCREEN_UPSTREAM_URL must use 127.0.0.1" >&2
    exit 1
    ;;
esac

rest=${url#http://127.0.0.1:}
rest=${rest#ws://127.0.0.1:}
case "$rest" in
  */) rest=${rest%/} ;;
esac
case "$rest" in
  ""|*[!0-9]*|0*)
    echo "android-ue-screen-mode: SCREEN_UPSTREAM_URL must be host and port only" >&2
    exit 1
    ;;
esac
if [ "$rest" -lt 1 ] || [ "$rest" -gt 65535 ]; then
  echo "android-ue-screen-mode: port is out of range" >&2
  exit 1
fi
case "$rest" in
  3000|3001)
    echo "android-ue-screen-mode: port 3000 is Grafana and 3001 is Next" >&2
    exit 1
    ;;
esac
printf '%s\n' "mode=host-agen upstream=loopback"
