#!/bin/sh
# Entrypoint for the cgnat service. Loads the SOCKS policy and waits.
# Does not change Open5GS. The UPF route is a separate, restored step.
set -eu

# Continue when the value is already 1, even if /proc/sys is read-only.
# Compose sets these sysctls. Fail only when the value is not 1 and the
# write is rejected or does not stick.
cgnat_ensure_sysctl() {
  _file=$1
  _name=$2
  _current=$(cat "$_file" 2>/dev/null || echo missing)
  if [ "$_current" = "1" ]; then
    return 0
  fi
  if ! printf '1\n' >"$_file" 2>/dev/null; then
    echo "cgnat: ${_name} is ${_current} and /proc/sys rejected the write. The compose service must set sysctls ${_name}: \"1\"." >&2
    return 1
  fi
  _current=$(cat "$_file" 2>/dev/null || echo missing)
  if [ "$_current" != "1" ]; then
    echo "cgnat: ${_name} is ${_current} after the write. The compose service must set sysctls ${_name}: \"1\"." >&2
    return 1
  fi
}

if [ "${1:-}" = "--sysctl-self-test" ]; then
  root=$(mktemp -d)
  trap 'rm -rf "$root"' EXIT
  printf '1\n' >"$root/already"
  cgnat_ensure_sysctl "$root/already" net.ipv4.ip_forward
  if ! grep -qx 1 "$root/already"; then
    echo "cgnat: self-test changed a sysctl that was already 1" >&2
    exit 1
  fi
  printf '0\n' >"$root/writable"
  cgnat_ensure_sysctl "$root/writable" net.ipv4.ip_forward
  if ! grep -qx 1 "$root/writable"; then
    echo "cgnat: self-test did not set a writable sysctl to 1" >&2
    exit 1
  fi
  mkdir "$root/rejected"
  if cgnat_ensure_sysctl "$root/rejected" net.ipv4.ip_forward 2>"$root/err"; then
    echo "cgnat: self-test ignored a rejected write" >&2
    exit 1
  fi
  if ! grep -q 'compose service must set sysctls net.ipv4.ip_forward' "$root/err"; then
    echo "cgnat: self-test failure did not name the compose sysctl" >&2
    cat "$root/err" >&2
    exit 1
  fi
  echo "cgnat sysctl self-test passed"
  exit 0
fi

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
/bin/sh /opt/cgnat/render-cgnat.sh "$template" >"$rendered"

cgnat_ensure_sysctl /proc/sys/net/ipv4/ip_forward net.ipv4.ip_forward
cgnat_ensure_sysctl /proc/sys/net/ipv4/conf/all/route_localnet net.ipv4.conf.all.route_localnet
ip route replace "$UE_POOL" via "$UPF_SGI_ADDR" dev "$sgi_if"
nft delete table ip cgnat 2>/dev/null || true
nft delete table ip6 cgnat 2>/dev/null || true
nft -f "$rendered"

printf 'sgi_if=%s\nsocks_host=%s\n' "$sgi_if" "$socks_host" >"$meta"
echo "cgnat: policy loaded; internet is dropped until tun0 exists"
exec sleep infinity
