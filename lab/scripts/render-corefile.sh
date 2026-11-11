#!/bin/sh
# Render the CoreDNS config. Default upstream is 1.1.1.1 over TCP.
set -eu
upstream=${ANDROID_UE_DNS_UPSTREAM:-1.1.1.1}
case "$upstream" in
  *[!A-Za-z0-9.:-]*)
    echo "render-corefile: upstream must be a hostname or IPv4 address" >&2
    exit 1
    ;;
esac
template=${1:-lab/config/cgnat/Corefile.template}
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ ! -f "$template" ]; then
  template="${script_dir}/../config/cgnat/Corefile.template"
fi
awk -v upstream="$upstream" '{ gsub(/__DNS_UPSTREAM__/, upstream); print }' "$template"
