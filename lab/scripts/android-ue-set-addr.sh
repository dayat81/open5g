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
if (!imsi || !apn || !addr) {
  print('refusing: address environment is incomplete');
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
if (!result || result.matchedCount !== 1) {
  print('refusing: update did not match one document');
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
if (!imsi || !apn) {
  print('refusing: address environment is incomplete');
  quit(2);
}
const result = db.subscribers.updateOne(
  {imsi: imsi},
  {$unset: {'slice.$[sl].session.$[se].ue.addr': ''}},
  {arrayFilters: [{'sl.sst': 1}, {'se.name': apn}], upsert: false}
);
if (!result || result.matchedCount !== 1) {
  print('refusing: unset did not match one document');
  quit(2);
}
print('unset');
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
  printf '%s\n' "docker exec -e ANDROID_UE_SEED_IMSI -e ANDROID_UE_SEED_APN -e ANDROID_UE_SEED_ADDR"
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

if [ "$mode" = "set" ]; then
  umask 077
  docker exec \
    -e ANDROID_UE_SEED_IMSI \
    -e ANDROID_UE_SEED_APN \
    -e ANDROID_UE_SEED_ADDR \
    "$mongo" mongosh --quiet open5gs --eval "$(backup_js)" >"$backup"
  chmod 0600 "$backup"
  if ! grep -q '^{' "$backup"; then
    echo "android-ue-set-addr: backup was not a document" >&2
    exit 1
  fi
fi
if [ "$mode" = "unset" ] && [ ! -s "$backup" ]; then
  echo "android-ue-set-addr: ${backup} is missing; refusing to unset" >&2
  exit 1
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
  "$mongo" mongosh --quiet open5gs --eval "$program"
