#!/bin/bash
# Insert one test subscriber. Refuses when that IMSI is already present.
# Does not update or replace an existing document. Do not run this during
# the dashboard PR #7 test window.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-lib.sh
. "$script_dir/android-ue-lib.sh"

env_file=""
user=ue1
print_js=0
print_exec=0

usage() {
  echo "usage: android-ue-seed.sh --env-file FILE [--user ue1|ue2] [--print-js]" >&2
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
    --print-js) print_js=1 ;;
    --print-exec) print_exec=1 ;;
    *) usage ;;
  esac
  shift
done

seed_js() {
  cat <<'JS'
db = db.getSiblingDB('open5gs');
const imsi = process.env.ANDROID_UE_SEED_IMSI;
const k = process.env.ANDROID_UE_SEED_KI;
const opc = process.env.ANDROID_UE_SEED_OPC;
const apn = process.env.ANDROID_UE_SEED_APN;
const addr = process.env.ANDROID_UE_SEED_ADDR;
if (!imsi || !k || !opc || !apn || !addr) {
  print('refusing: seed environment is incomplete');
  quit(2);
}
const found = db.subscribers.countDocuments({imsi: imsi});
if (found !== 0) {
  print('refusing: subscriber already exists');
  quit(2);
}
db.subscribers.insertOne({
  imsi: imsi,
  security: {k: k, opc: opc, amf: '8000', sqn: NumberLong(0)},
  ambr: {downlink: {value: 1, unit: 3}, uplink: {value: 1, unit: 3}},
  slice: [{sst: 1, default_indicator: true, session: [{name: apn, type: 3,
    ue: {addr: addr},
    qos: {index: 9, arp: {priority_level: 8, pre_emption_capability: 1, pre_emption_vulnerability: 1}},
    ambr: {downlink: {value: 1, unit: 3}, uplink: {value: 1, unit: 3}}}]}],
  access_restriction_data: 32, network_access_mode: 0, subscriber_status: 0,
  operator_determined_barring: 0, subscribed_rau_tau_timer: 12, schema_version: 1
});
print('inserted');
JS
}

seed_exec_args() {
  printf '%s\n' "docker exec -e ANDROID_UE_SEED_IMSI -e ANDROID_UE_SEED_KI -e ANDROID_UE_SEED_OPC -e ANDROID_UE_SEED_APN -e ANDROID_UE_SEED_ADDR"
}

if [ "$print_js" -eq 1 ]; then
  seed_js
  exit 0
fi
if [ "$print_exec" -eq 1 ]; then
  seed_exec_args
  exit 0
fi

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  usage
fi
case "$user" in
  ue1|ue2) ;;
  *)
    echo "android-ue-seed: user must be ue1 or ue2" >&2
    exit 2
    ;;
esac

get() { android_ue_env_get "$env_file" "$1"; }
n=${user#ue}
imsi=$(get "UE${n}_IMSI")
ki=$(get "UE${n}_KI")
opc=$(get "UE${n}_OPC")
apn=$(get APN)
android_ue_reject_placeholder "UE${n}_IMSI" "$imsi"
android_ue_reject_placeholder "UE${n}_KI" "$ki"
android_ue_reject_placeholder "UE${n}_OPC" "$opc"
android_ue_require_set APN "$apn"
addr=$(get "UE${n}_ADDR")
android_ue_reject_placeholder "UE${n}_ADDR" "$addr"
if ! printf '%s\n' "$addr" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "android-ue-seed: UE${n}_ADDR must be an IPv4 address" >&2
  exit 1
fi
if ! printf '%s\n' "$imsi" | grep -Eq '^[0-9]{15}$'; then
  echo "android-ue-seed: UE${n}_IMSI must be 15 digits" >&2
  exit 1
fi
mongo=${ANDROID_UE_MONGO_CONTAINER:-l5gd-mongo}
export ANDROID_UE_SEED_IMSI="$imsi"
export ANDROID_UE_SEED_KI="$ki"
export ANDROID_UE_SEED_OPC="$opc"
export ANDROID_UE_SEED_APN="$apn"
export ANDROID_UE_SEED_ADDR="$addr"
# Inherit the values. Do not put Ki or OPc after -e, where ps can see them.
docker exec \
  -e ANDROID_UE_SEED_IMSI \
  -e ANDROID_UE_SEED_KI \
  -e ANDROID_UE_SEED_OPC \
  -e ANDROID_UE_SEED_APN \
  -e ANDROID_UE_SEED_ADDR \
  "$mongo" mongosh --quiet open5gs --eval "$(seed_js)"
