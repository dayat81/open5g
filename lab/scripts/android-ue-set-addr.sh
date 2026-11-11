#!/bin/bash
# Set ue.addr on an existing test subscriber. Does not insert a document.
# Refuses to upsert. android-ue-seed.sh stays the insert-only path.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-lib.sh
. "$script_dir/android-ue-lib.sh"

env_file=""
user=ue1
mode="set"
print_js=0
print_exec=0

usage() {
  echo "usage: android-ue-set-addr.sh --env-file FILE [--user ue1|ue2] [--rollback] [--print-js] [--print-unset] [--print-exec]" >&2
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
    --rollback) mode="unset" ;;
    --print-js) print_js=1 ;;
    --print-unset) print_js=1; mode="unset" ;;
    --print-exec) print_exec=1 ;;
    *) usage ;;
  esac
  shift
done

set_js() {
  cat <<'JS'
db = db.getSiblingDB('open5gs');
const imsi = process.env.ANDROID_UE_SEED_IMSI;
const apn = process.env.ANDROID_UE_SEED_APN;
const addr = process.env.ANDROID_UE_SEED_ADDR;
const pool = process.env.ANDROID_UE_SEED_POOL;
if (!imsi || !apn || !addr || !pool) {
  print('refusing: address environment is incomplete');
  quit(2);
}
function ipv4ToInt(ip) {
  const parts = ip.split('.');
  if (parts.length !== 4) return null;
  let value = 0;
  for (let i = 0; i < 4; i += 1) {
    if (!/^[0-9]+$/.test(parts[i])) return null;
    const n = Number(parts[i]);
    if (n > 255) return null;
    value = (value * 256) + n;
  }
  return value;
}
function addrInPool(value, cidr) {
  const slash = cidr.indexOf('/');
  if (slash < 0) return false;
  const bits = Number(cidr.slice(slash + 1));
  if (!Number.isInteger(bits) || bits < 0 || bits > 32) return false;
  const left = ipv4ToInt(value);
  const right = ipv4ToInt(cidr.slice(0, slash));
  if (left === null || right === null) return false;
  if (bits === 0) return true;
  const shift = 2 ** (32 - bits);
  return Math.floor(left / shift) === Math.floor(right / shift);
}
if (!addrInPool(addr, pool)) {
  print('refusing: ue.addr is outside the pool');
  quit(2);
}
const used = db.subscribers.countDocuments({imsi: {$ne: imsi}, 'slice.session.ue.addr': addr});
if (used !== 0) {
  print('refusing: ue.addr is already used');
  quit(2);
}
const doc = db.subscribers.findOne({imsi: imsi});
if (!doc) {
  print('refusing: subscriber is missing');
  quit(2);
}
let found = 0;
let current = '';
(doc.slice || []).forEach(function (sl) {
  if (sl.sst !== 1) {
    return;
  }
  (sl.session || []).forEach(function (se) {
    if (se.name !== apn) {
      return;
    }
    found += 1;
    if (se.ue && se.ue.addr) {
      current = se.ue.addr;
    }
  });
});
if (found !== 1) {
  print('refusing: sst 1 session for that APN was not found once');
  quit(2);
}
if (current && current !== addr) {
  print('refusing: ue.addr is already set to a different address');
  quit(2);
}
if (current === addr) {
  print('already set');
  quit(0);
}
const result = db.subscribers.updateOne(
  {imsi: imsi},
  {$set: {'slice.$[sl].session.$[se].ue.addr': addr}},
  {arrayFilters: [{'sl.sst': 1}, {'se.name': apn}], upsert: false}
);
if (!result || result.matchedCount !== 1 || result.modifiedCount !== 1) {
  print('refusing: update did not modify one document');
  quit(2);
}
print('updated');
JS
}

unset_js() {
  cat <<'JS'
db = db.getSiblingDB('open5gs');
const imsi = process.env.ANDROID_UE_SEED_IMSI;
const apn = process.env.ANDROID_UE_SEED_APN;
const oldAddr = process.env.ANDROID_UE_SEED_OLD_ADDR || '';
if (!imsi || !apn) {
  print('refusing: address environment is incomplete');
  quit(2);
}
const update = oldAddr
  ? {$set: {'slice.$[sl].session.$[se].ue.addr': oldAddr}}
  : {$unset: {'slice.$[sl].session.$[se].ue.addr': ''}};
const result = db.subscribers.updateOne(
  {imsi: imsi},
  update,
  {arrayFilters: [{'sl.sst': 1}, {'se.name': apn}], upsert: false}
);
if (!result || result.matchedCount !== 1) {
  print('refusing: rollback did not match one document');
  quit(2);
}
print(oldAddr ? 'restored' : 'unset');
JS
}

backup_js() {
  cat <<'JS'
db = db.getSiblingDB('open5gs');
const imsi = process.env.ANDROID_UE_SEED_IMSI;
if (!imsi) {
  print('refusing: address environment is incomplete');
  quit(2);
}
const doc = db.subscribers.findOne({imsi: imsi});
if (!doc) {
  print('refusing: subscriber is missing');
  quit(2);
}
print(EJSON.stringify(doc));
JS
}

exec_line() {
  printf '%s\n' "docker exec -e ANDROID_UE_SEED_IMSI -e ANDROID_UE_SEED_APN -e ANDROID_UE_SEED_ADDR -e ANDROID_UE_SEED_POOL -e ANDROID_UE_SEED_OLD_ADDR"
}

if [ "$print_exec" -eq 1 ]; then
  exec_line
  exit 0
fi
if [ "$print_js" -eq 1 ]; then
  if [ "$mode" = "unset" ]; then
    unset_js
  else
    set_js
  fi
  exit 0
fi

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  usage
fi
case "$user" in
  ue1|ue2) ;;
  *)
    echo "android-ue-set-addr: user must be ue1 or ue2" >&2
    exit 2
    ;;
esac

get() { android_ue_env_get "$env_file" "$1"; }
n=${user#ue}
imsi=$(get "UE${n}_IMSI")
apn=$(get APN)
addr=$(get "UE${n}_ADDR")
android_ue_reject_placeholder "UE${n}_IMSI" "$imsi"
android_ue_require_set APN "$apn"
android_ue_reject_placeholder "UE${n}_ADDR" "$addr"
pool=$(get UE_POOL)
android_ue_require_set UE_POOL "$pool"
if ! android_ue_addr_in_pool "$addr" "$pool"; then
  echo "android-ue-set-addr: UE${n}_ADDR is outside UE_POOL" >&2
  exit 1
fi
if ! printf '%s\n' "$imsi" | grep -Eq '^[0-9]{15}$'; then
  echo "android-ue-set-addr: UE${n}_IMSI must be 15 digits" >&2
  exit 1
fi
if ! printf '%s\n' "$addr" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "android-ue-set-addr: UE${n}_ADDR must be an IPv4 address" >&2
  exit 1
fi

state=$(android_ue_state_dir)
mkdir -p "$state"
backup="${state}/subscriber-${user}.json"
mongo=${ANDROID_UE_MONGO_CONTAINER:-l5gd-mongo}
export ANDROID_UE_SEED_IMSI="$imsi"
export ANDROID_UE_SEED_APN="$apn"
export ANDROID_UE_SEED_ADDR="$addr"
export ANDROID_UE_SEED_POOL="$pool"
export ANDROID_UE_SEED_OLD_ADDR=""

if [ "$mode" = "set" ]; then
  umask 077
  docker exec \
    -e ANDROID_UE_SEED_IMSI \
    -e ANDROID_UE_SEED_APN \
    -e ANDROID_UE_SEED_ADDR \
    -e ANDROID_UE_SEED_POOL \
    "$mongo" mongosh --quiet open5gs --eval "$(backup_js)" >"$backup"
  chmod 0600 "$backup"
  if ! grep -q '^{' "$backup"; then
    echo "android-ue-set-addr: backup was not a document" >&2
    exit 1
  fi
fi
if [ "$mode" = "unset" ] && [ ! -s "$backup" ]; then
  echo "android-ue-set-addr: ${backup} is missing; refusing to roll back" >&2
  exit 1
fi
if [ "$mode" = "unset" ]; then
  old_addr=$(python3 - "$backup" "$apn" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
apn = sys.argv[2]
found = ""
for sl in doc.get("slice") or []:
    if sl.get("sst") != 1:
        continue
    for se in sl.get("session") or []:
        if se.get("name") != apn:
            continue
        ue = se.get("ue") or {}
        found = ue.get("addr") or ""
print(found)
PY
)
  export ANDROID_UE_SEED_OLD_ADDR="$old_addr"
fi

if [ "$mode" = "unset" ]; then
  program=$(unset_js)
else
  program=$(set_js)
fi
docker exec \
  -e ANDROID_UE_SEED_IMSI \
  -e ANDROID_UE_SEED_APN \
  -e ANDROID_UE_SEED_ADDR \
  -e ANDROID_UE_SEED_POOL \
  -e ANDROID_UE_SEED_OLD_ADDR \
  "$mongo" mongosh --quiet open5gs --eval "$program"
