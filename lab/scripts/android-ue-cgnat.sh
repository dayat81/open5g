#!/bin/sh
# Entrypoint for the cgnat service. Loads the SOCKS policy and waits.
# Does not change Open5GS. The UPF route is a separate, restored step.
set -eu

template=/etc/cgnat/cgnat.nft.template
rendered=/tmp/cgnat.nft
meta=/tmp/cgnat.if

: "${UE_POOL:?UE_POOL}"
: "${UPF_SGI_ADDR:?UPF_SGI_ADDR}"
: "${CGNAT_SGI_ADDR:?CGNAT_SGI_ADDR}"
: "${ANDROID_UE_LAB_SUBNET:?ANDROID_UE_LAB_SUBNET}"
: "${ANDROID_UE_SOCKS_ADDR:?ANDROID_UE_SOCKS_ADDR}"
: "${CGNAT_CT_LIMIT:?CGNAT_CT_LIMIT}"

case "$ANDROID_UE_LAB_SUBNET" in
  REPLACE_*|*CHANGEME*)
    echo "cgnat: ANDROID_UE_LAB_SUBNET is still a placeholder" >&2
    exit 1
    ;;
esac
socks_host=${ANDROID_UE_SOCKS_ADDR%%:*}
socks_port=${ANDROID_UE_SOCKS_ADDR##*:}
case "$socks_host" in
  REPLACE_*|*CHANGEME*)
    echo "cgnat: ANDROID_UE_SOCKS_ADDR is still a placeholder" >&2
    exit 1
    ;;
esac
if ! printf '%s\n' "$socks_host" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "cgnat: ANDROID_UE_SOCKS_ADDR must be an IPv4 address and port 1080" >&2
  exit 1
fi
if [ "$socks_port" != "1080" ]; then
  echo "cgnat: ANDROID_UE_SOCKS_ADDR must use port 1080" >&2
  exit 1
fi
if ! printf '%s\n' "$ANDROID_UE_LAB_SUBNET" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
  echo "cgnat: ANDROID_UE_LAB_SUBNET must be an IPv4 prefix" >&2
  exit 1
fi

sgi_if=$(ip -4 -o addr show | awk -v ip="$CGNAT_SGI_ADDR" 'index($4, ip "/") == 1 { print $2; exit }')
if [ -z "$sgi_if" ]; then
  echo "cgnat: no interface has ${CGNAT_SGI_ADDR}" >&2
  exit 1
fi

export UE_POOL="$UE_POOL"
export LAB_SUBNET="$ANDROID_UE_LAB_SUBNET"
export SOCKS_ADDR="$socks_host"
export CT_LIMIT="$CGNAT_CT_LIMIT"
/bin/sh /etc/cgnat/render-cgnat.sh "$template" >"$rendered"

if [ -w /proc/sys/net/ipv4/ip_forward ]; then
  printf '1\n' > /proc/sys/net/ipv4/ip_forward
fi
if [ -w /proc/sys/net/ipv4/conf/all/route_localnet ]; then
  printf '1\n' > /proc/sys/net/ipv4/conf/all/route_localnet
fi
ip route replace "$UE_POOL" via "$UPF_SGI_ADDR" dev "$sgi_if"
nft delete table ip cgnat 2>/dev/null || true
nft delete table ip6 cgnat 2>/dev/null || true
nft -f "$rendered"

printf 'sgi_if=%s\nsocks_host=%s\n' "$sgi_if" "$socks_host" >"$meta"
echo "cgnat: policy loaded; internet is dropped until tun0 exists"
exec sleep infinity
