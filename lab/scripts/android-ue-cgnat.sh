#!/bin/sh
# Entrypoint for the cgnat service. Loads the base ruleset and waits.
# Per-UE SNAT is added later by android-ue-add-ue.sh, after attach.
set -eu

template=/etc/cgnat/cgnat.nft.template
rendered=/tmp/cgnat.nft
meta=/tmp/cgnat.if

: "${UE_POOL:?UE_POOL}"
: "${UPF_SGI_ADDR:?UPF_SGI_ADDR}"
: "${CGNAT_SGI_ADDR:?CGNAT_SGI_ADDR}"

sgi_if=$(ip -4 -o addr show | awk -v ip="$CGNAT_SGI_ADDR" 'index($4, ip "/") == 1 { print $2; exit }')
if [ -z "$sgi_if" ]; then
  echo "cgnat: no interface has ${CGNAT_SGI_ADDR}" >&2
  exit 1
fi
egress_if=$(ip -4 -o addr show | awk -v skip="$sgi_if" '$2 != skip && $2 != "lo" { print $2; exit }')
if [ -z "$egress_if" ]; then
  echo "cgnat: no egress interface beside ${sgi_if}" >&2
  exit 1
fi

export UE_POOL SGI_IF="$sgi_if" EGRESS_IF="$egress_if"
/bin/sh /etc/cgnat/render-cgnat.sh base "$template" >"$rendered"

if [ -w /proc/sys/net/ipv4/ip_forward ]; then
  printf '1\n' > /proc/sys/net/ipv4/ip_forward
fi
ip route replace "$UE_POOL" via "$UPF_SGI_ADDR" dev "$sgi_if"
nft delete table ip cgnat 2>/dev/null || true
nft -f "$rendered"

printf 'sgi_if=%s\negress_if=%s\n' "$sgi_if" "$egress_if" >"$meta"
echo "cgnat: base rules loaded on ${sgi_if} -> ${egress_if}; per-UE SNAT is not installed yet"
exec sleep infinity
