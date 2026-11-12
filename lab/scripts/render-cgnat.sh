#!/bin/sh
# Render the CGNAT nft template to stdout.
# Usage: render-cgnat.sh /path/to/cgnat.nft.template
# Required env: UE_POOL LAB_SUBNET SOCKS_ADDR CT_LIMIT
# SOCKS_ADDR is the tunnel IPv4 only, not a host:port.
set -eu

template=${1:?template path}
: "${UE_POOL:?UE_POOL}"
: "${LAB_SUBNET:?LAB_SUBNET}"
: "${SOCKS_ADDR:?SOCKS_ADDR}"
: "${CT_LIMIT:?CT_LIMIT}"

awk -v pool="$UE_POOL" -v lab="$LAB_SUBNET" -v socks="$SOCKS_ADDR" -v limit="$CT_LIMIT" '
{
  gsub(/__UE_POOL__/, pool)
  gsub(/__LAB_SUBNET__/, lab)
  gsub(/__SOCKS_ADDR__/, socks)
  gsub(/__CT_LIMIT__/, limit)
  print
}
' "$template"
