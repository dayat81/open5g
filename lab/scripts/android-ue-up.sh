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
install_upf_route=0

usage() {
  echo "usage: android-ue-up.sh --env-file FILE [--user ue1|ue2] [--with-cgnat] [--install-upf-route]" >&2
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
    --install-upf-route) install_upf_route=1 ;;
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
state=${ANDROID_UE_STATE_DIR:-/tmp/open5g-android-ue-state}
mkdir -p "$state"

get() { android_ue_env_get "$env_file" "$1"; }

n=${user#ue}
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
block=$(get "UE${n}_PORT_BLOCK")
if ! printf '%s\n' "$block" | grep -Eq '^[0-9]+-[0-9]+$'; then
  echo "android-ue: UE${n}_PORT_BLOCK must look like 15000-19999" >&2
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
  ue_cidr=$(docker exec "l5gd-ue${n}" ip -4 -o addr show dev tun_srsue | awk '{ print $4; exit }')
  ue_ip=${ue_cidr%%/*}
  if [ -z "$ue_ip" ]; then
    echo "android-ue: tun_srsue has no address to SNAT" >&2
    exit 1
  fi
  pairs_file=$state/cgnat-ues.txt
  touch "$pairs_file"
  tmp_pairs=$(mktemp)
  awk -v u="$user" '$1 != u { print }' "$pairs_file" >"$tmp_pairs"
  printf '%s %s %s\n' "$user" "$ue_ip" "$block" >>"$tmp_pairs"
  mv "$tmp_pairs" "$pairs_file"
  # shellcheck disable=SC2046
  docker exec l5gd-cgnat /bin/sh /etc/cgnat/android-ue-add-ue.sh $(awk '{ printf "%s %s ", $2, $3 }' "$pairs_file")
  echo "android-ue: CGNAT SNAT installed for ${user} (${ue_ip}, ports ${block})"
fi

if [ "$install_upf_route" -eq 1 ]; then
  flag=$(get ANDROID_UE_INSTALL_UPF_ROUTE)
  if [ "$flag" != 1 ]; then
    echo "android-ue: --install-upf-route also needs ANDROID_UE_INSTALL_UPF_ROUTE=1" >&2
    exit 1
  fi
  internal=$(docker network inspect -f '{{.Internal}}' "$egress")
  if [ "$internal" = "true" ]; then
    echo "android-ue: egress network ${egress} is internal. Refusing to point the UPF default route at it." >&2
    exit 1
  fi
  upf=$(get ANDROID_UE_UPF_CONTAINER)
  android_ue_require_set ANDROID_UE_UPF_CONTAINER "$upf"
  cgnat_ip=$(get CGNAT_SGI_ADDR)
  android_ue_reject_placeholder CGNAT_SGI_ADDR "$cgnat_ip"
  prev=$(docker exec "$upf" ip -4 route show default)
  if [ -n "$prev" ] && ! printf '%s\n' "$prev" | grep -Eq '^default via [0-9.]+ dev [A-Za-z0-9._:-]+$'; then
    echo "android-ue: UPF default route is not a single simple route; not changing it" >&2
    exit 1
  fi
  printf '%s\n' "$prev" >"$state/upf-default.txt"
  docker exec "$upf" ip route replace default via "$cgnat_ip"
  echo "android-ue: UPF ${upf} default route now via ${cgnat_ip}. Rollback restores the saved route."
fi

echo "android-ue: ${user} is up. ADB on this guest is 127.0.0.1:$(get "UE${n}_ADB_HOST_PORT"). Core containers were not restarted."
