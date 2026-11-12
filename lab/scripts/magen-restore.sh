#!/bin/bash
# Restore mongorestore and pg_restore from dump paths outside the repo.
# Fail closed when the target already has documents or rows, unless
# --force-nonempty is set. Dump bytes are not printed.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

mongo_dump=""
pg_dump=""
force=0
mongo_count=""
pg_count=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mongo-dump)
      shift
      mongo_dump=$1
      ;;
    --pg-dump)
      shift
      pg_dump=$1
      ;;
    --force-nonempty) force=1 ;;
    --mongo-count)
      shift
      mongo_count=$1
      ;;
    --pg-count)
      shift
      pg_count=$1
      ;;
    *)
      echo "usage: magen-restore.sh --mongo-dump FILE --pg-dump FILE [--force-nonempty]" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$mongo_dump" ] || [ -z "$pg_dump" ]; then
  echo "usage: magen-restore.sh --mongo-dump FILE --pg-dump FILE [--force-nonempty]" >&2
  exit 2
fi

root=$(magen_root)
magen_restore_path_ok() {
  local path=$1
  case "$path" in
    "$root"|"$root"/*)
      echo "magen: dump path is inside the repo" >&2
      return 1
      ;;
    /*) ;;
    *)
      echo "magen: dump path must be absolute and outside the repo" >&2
      return 1
      ;;
  esac
  [ -f "$path" ] || {
    echo "magen: dump file is missing" >&2
    return 1
  }
}

magen_restore_path_ok "$mongo_dump"
magen_restore_path_ok "$pg_dump"

magen_restore_allow() {
  local count=$1
  if [ "$count" != "0" ] && [ "$force" -ne 1 ]; then
    echo "magen: target is not empty. Refusing restore without --force-nonempty." >&2
    return 1
  fi
}

if [ -n "$mongo_count" ] || [ -n "$pg_count" ]; then
  magen_restore_allow "${mongo_count:-0}"
  magen_restore_allow "${pg_count:-0}"
  echo "magen: restore counts accepted"
  echo "changed=0"
  exit 0
fi

mongo_count=$(docker exec o5g-mongo mongosh --quiet --eval 'db.getSiblingDB("open5gs").subscribers.countDocuments()')
pg_count=$(docker exec o5g-dashboard-postgres psql -U "${O5G_POSTGRES_USER:?O5G_POSTGRES_USER}" -d "${O5G_POSTGRES_DB:?O5G_POSTGRES_DB}" -tAc 'select count(*) from information_schema.tables where table_schema = '"'"'public'"'"'')
magen_restore_allow "$mongo_count"
if [ "${pg_count:-0}" != "0" ] && [ "$force" -ne 1 ]; then
  echo "magen: target is not empty. Refusing restore without --force-nonempty." >&2
  exit 1
fi
docker exec -i o5g-mongo mongorestore --archive < "$mongo_dump"
docker exec -i o5g-dashboard-postgres pg_restore -U "${O5G_POSTGRES_USER}" -d "${O5G_POSTGRES_DB}" < "$pg_dump"
echo "changed=1"
