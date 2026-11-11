#!/bin/bash
# Bring up one android-ue user. Does not edit Open5GS config and does not
# start the core. Default user is ue1. ue2 stays off unless ANDROID_UE_ALLOW_SECOND=1.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-lib.sh
. "$script_dir/android-ue-lib.sh"

env_file=""
user=ue1
with_cgnat=0
with_socks=0
install_upf_route=0
print_services=0

usage() {
  echo "usage: android-ue-up.sh --env-file FILE [--user ue1|ue2] [--with-cgnat] [--with-socks-egress] [--install-upf-route] [--print-services]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || usage
      env_file=$1
      ;;
    --user)
      shift
      [ "$#" -gt 0 ] || usage
      user=$1
      ;;
    --with-cgnat) with_cgnat=1 ;;
    --with-socks-egress) with_socks=1 ;;
    --install-upf-route) install_upf_route=1 ;;
    --print-services) print_services=1 ;;
    *) usage ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  usage
fi
case "$user" in
  ue1|ue2) ;;
  *)
    echo "android-ue: user must be ue1 or ue2" >&2
    exit 2
    ;;
esac

root=$(android_ue_root)
state=$(android_ue_state_dir)
get() { android_ue_env_get "$env_file" "$1"; }
n=${user#ue}

if [ "$with_socks" -eq 1 ]; then
  with_cgnat=1
fi

if [ "$print_services" -eq 1 ]; then
  printf '%s\n' "ue${n}" "enb${n}" "ue${n}-route" "android${n}"
  if [ "$with_cgnat" -eq 1 ]; then
    echo cgnat
  fi
  if [ "$with_socks" -eq 1 ]; then
    printf '%s\n' egress egress-dns
  fi
  exit 0
fi

mkdir -p "$state"

if [ "$user" = "ue2" ]; then
  allow=$(get ANDROID_UE_ALLOW_SECOND)
  if [ "$allow" != 1 ]; then
    echo "android-ue: ue2 is off until ANDROID_UE_ALLOW_SECOND=1. One emulator is the cap for this guest." >&2
    exit 1
  fi
fi

android_ue_reject_placeholder "UE${n}_IMSI" "$(get "UE${n}_IMSI")"
android_ue_reject_placeholder "UE${n}_KI" "$(get "UE${n}_KI")"
android_ue_reject_placeholder "UE${n}_OPC" "$(get "UE${n}_OPC")"
android_ue_reject_placeholder "UE${n}_IMEI" "$(get "UE${n}_IMEI")"
imsi=$(get "UE${n}_IMSI")
ki=$(get "UE${n}_KI")
opc=$(get "UE${n}_OPC")
imei=$(get "UE${n}_IMEI")
if ! printf '%s\n' "$imsi" | grep -Eq '^[0-9]{15}$'; then
  echo "android-ue: UE${n}_IMSI must be 15 digits" >&2
  exit 1
fi
if ! printf '%s\n' "$ki" | grep -Eq '^[0-9A-Fa-f]{32}$'; then
  echo "android-ue: UE${n}_KI must be 32 hex characters" >&2
  exit 1
fi
if ! printf '%s\n' "$opc" | grep -Eq '^[0-9A-Fa-f]{32}$'; then
  echo "android-ue: UE${n}_OPC must be 32 hex characters" >&2
  exit 1
fi
if ! printf '%s\n' "$imei" | grep -Eq '^[0-9]{15}$'; then
  echo "android-ue: UE${n}_IMEI must be 15 digits" >&2
  exit 1
fi
if [ ! -e /dev/kvm ]; then
  echo "android-ue: /dev/kvm is missing. Nested KVM is a Lab Ops prerequisite." >&2
  exit 1
fi

need_net() {
  local name=$1
  if ! docker network inspect "$name" >/dev/null 2>&1; then
    echo "android-ue: docker network ${name} is missing" >&2
    return 1
  fi
}

need_net "$(get ANDROID_UE_S1MME_NETWORK)"
need_net "$(get ANDROID_UE_S1U_NETWORK)"
need_net "$(get ANDROID_UE_UU_NETWORK)"
need_net "$(get ANDROID_UE_SGI_NETWORK)"
egress=$(get ANDROID_UE_EGRESS_NETWORK)
android_ue_reject_placeholder ANDROID_UE_EGRESS_NETWORK "$egress"
if ! docker network inspect "$egress" >/dev/null 2>&1; then
  echo "android-ue: create the egress network before up. Until Netdrive approves egress, create it internal so it cannot reach the internet:" >&2
  echo "  docker network create --internal ${egress}" >&2
  exit 1
fi

if [ "$with_socks" -eq 1 ]; then
  android_ue_reject_placeholder ANDROID_UE_TUN2SOCKS_IMAGE "$(get ANDROID_UE_TUN2SOCKS_IMAGE)"
  android_ue_reject_placeholder ANDROID_UE_DNS_IMAGE "$(get ANDROID_UE_DNS_IMAGE)"
  android_ue_reject_placeholder ANDROID_UE_SOCKS_ADDR "$(get ANDROID_UE_SOCKS_ADDR)"
  android_ue_reject_placeholder ANDROID_UE_LAB_SUBNET "$(get ANDROID_UE_LAB_SUBNET)"
  socks_addr=$(get ANDROID_UE_SOCKS_ADDR)
  if ! printf '%s\n' "$socks_addr" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:1080$'; then
    echo "android-ue: ANDROID_UE_SOCKS_ADDR must look like an IPv4 address and port 1080" >&2
    exit 1
  fi
  if ! printf '%s\n' "$(get ANDROID_UE_LAB_SUBNET)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
    echo "android-ue: ANDROID_UE_LAB_SUBNET must be an IPv4 prefix" >&2
    exit 1
  fi
  socks_internal=$(docker network inspect -f '{{.Internal}}' "$egress")
  if [ "$socks_internal" != "true" ]; then
    echo "android-ue: the egress network must stay internal for the SOCKS path" >&2
    exit 1
  fi
  export ANDROID_UE_SOCKS_PROFILE=1
  gw=${socks_addr%%:*}
  if ! bash "$script_dir/android-ue-tunnel.sh" check-listen --gw "$gw"; then
    echo "android-ue: port 1080 is not listening only on ${gw}" >&2
    exit 1
  fi
fi

if [ "$install_upf_route" -eq 1 ] && [ "$with_socks" -eq 1 ]; then
  ue_addr=$(get "UE${n}_ADDR")
  android_ue_reject_placeholder "UE${n}_ADDR" "$ue_addr"
  if [ "$(get UE_POOL)" != "${ue_addr}/32" ]; then
    echo "android-ue: UE_POOL must be ${ue_addr}/32 so other UEs are not steered to the laptop" >&2
    exit 1
  fi
fi

echo "android-ue: starting ${user} only. Core config is not modified."
android_ue_compose "$root" "$env_file" up -d \
  "ue${n}" "enb${n}" "ue${n}-route" "android${n}"

if [ "$with_cgnat" -eq 1 ]; then
  android_ue_reject_placeholder ANDROID_UE_CGNAT_IMAGE "$(get ANDROID_UE_CGNAT_IMAGE)"
  android_ue_compose "$root" "$env_file" up -d cgnat
  ready=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    if docker exec l5gd-cgnat test -f /tmp/cgnat.if; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" -ne 1 ]; then
    echo "android-ue: cgnat did not write /tmp/cgnat.if" >&2
    exit 1
  fi
  echo "android-ue: cgnat policy is loaded. No per-UE SNAT rule is added."
fi

if [ "$with_socks" -eq 1 ]; then
  android_ue_compose "$root" "$env_file" up -d egress
  tun_ready=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    if docker exec l5gd-cgnat ip -4 route show default | grep -q 'dev tun0'; then
      tun_ready=1
      break
    fi
    sleep 1
  done
  if [ "$tun_ready" -ne 1 ]; then
    echo "android-ue: tun0 is not the default route in the cgnat netns" >&2
    exit 1
  fi
  dns_upstream=$(get ANDROID_UE_DNS_UPSTREAM)
  if [ -z "$dns_upstream" ]; then
    dns_upstream=1.1.1.1
  fi
  ANDROID_UE_DNS_UPSTREAM="$dns_upstream" \
    bash "$script_dir/render-corefile.sh" >"$state/Corefile"
  android_ue_compose "$root" "$env_file" up -d egress-dns
  echo "android-ue: SOCKS egress is up. The egress docker network stays internal."
fi

if [ "$install_upf_route" -eq 1 ]; then
  flag=$(get ANDROID_UE_INSTALL_UPF_ROUTE)
  if [ "$flag" != 1 ]; then
    echo "android-ue: --install-upf-route also needs ANDROID_UE_INSTALL_UPF_ROUTE=1" >&2
    exit 1
  fi
  if [ "$with_socks" -ne 1 ]; then
    echo "android-ue: the UPF route is only for the SOCKS test window. Pass --with-socks-egress as well." >&2
    exit 1
  fi
  upf=$(get ANDROID_UE_UPF_CONTAINER)
  android_ue_require_set ANDROID_UE_UPF_CONTAINER "$upf"
  cgnat_ip=$(get CGNAT_SGI_ADDR)
  android_ue_reject_placeholder CGNAT_SGI_ADDR "$cgnat_ip"
  ue_addr=$(get "UE${n}_ADDR")
  tun_cidr=$(docker exec "l5gd-ue${n}" ip -4 -o addr show dev tun_srsue | awk '{ print $4; exit }')
  tun_ip=${tun_cidr%%/*}
  if [ "$tun_ip" != "$ue_addr" ]; then
    echo "android-ue: tun_srsue has ${tun_ip:-no address}; the static UE address is ${ue_addr}" >&2
    exit 1
  fi
  rules=$(docker exec "$upf" ip rule show)
  decision=$(android_ue_upf_rule_decide "$rules" "${ue_addr}/32" "$state/upf-rule.txt")
  if [ "$decision" = "skip" ]; then
    echo "android-ue: UPF policy rule for ${ue_addr}/32 is already installed"
  else
    docker exec "$upf" ip route replace default via "$cgnat_ip" table 1080
    docker exec "$upf" ip rule add from "${ue_addr}/32" lookup 1080 priority 100
    printf 'from %s/32 lookup 1080\n' "$ue_addr" >"$state/upf-rule.txt"
    echo "android-ue: UPF steers only ${ue_addr}/32 via table 1080. The main default route was not changed."
  fi
fi

echo "android-ue: ${user} is up. ADB on this guest is 127.0.0.1:$(get "UE${n}_ADB_HOST_PORT"). Core containers were not restarted."
