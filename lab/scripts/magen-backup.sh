#!/bin/bash
# Read-only mongodump and pg_dump from the guest.
# Dumps land in $HOME/o5g-state/backup/<timestamp> mode 0700, with sha256 files.
# Dump bytes are never printed and never written inside the repo.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

from_dir=""
dry=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --from-dir)
      shift
      from_dir=$1
      ;;
    --dry-run) dry=1 ;;
    *)
      echo "usage: magen-backup.sh [--from-dir DIR | --dry-run]" >&2
      exit 2
      ;;
  esac
  shift
done

root=$(magen_root)
state=$(magen_state_dir)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
dest="${state}/backup/${stamp}"

if [ "$dry" -eq 1 ]; then
  echo "magen: backup would write ${dest}"
  echo "changed=0"
  exit 0
fi

case "$dest" in
  "$root"|"$root"/*)
    echo "magen: backup directory is inside the repo" >&2
    exit 1
    ;;
esac

guest=${MAGEN_GUEST_HOST:-}
key=${MAGEN_GUEST_KEY:-}
if [ -z "$from_dir" ]; then
  if magen_is_placeholder "$guest" || magen_is_placeholder "$key"; then
    echo "magen: guest address and key come from the gitignored inventory. Refusing the placeholder." >&2
    exit 1
  fi
fi

mkdir -p -- "$dest"
chmod 0700 "$dest"

copy_one() {
  local src=$1 name
  name=$(basename -- "$src")
  cp -- "$src" "${dest}/${name}"
  chmod 0600 "${dest}/${name}"
  (cd -- "$dest" && sha256sum "$name" > "${name}.sha256")
  chmod 0600 "${dest}/${name}.sha256"
}

if [ -n "$from_dir" ]; then
  found=0
  for src in "$from_dir"/*; do
    [ -f "$src" ] || continue
    copy_one "$src"
    found=1
  done
  if [ "$found" -eq 0 ]; then
    echo "magen: backup source directory has no files" >&2
    exit 1
  fi
else
  ssh -i "$key" -o BatchMode=yes "$guest" 'mongodump --archive --gzip' > "${dest}/mongo.archive.gz"
  ssh -i "$key" -o BatchMode=yes "$guest" 'pg_dump -Fc --no-owner --no-acl open5g' > "${dest}/postgres.dump"
  chmod 0600 "${dest}/mongo.archive.gz" "${dest}/postgres.dump"
  (cd -- "$dest" && sha256sum mongo.archive.gz postgres.dump > SHA256SUMS)
  chmod 0600 "${dest}/SHA256SUMS"
fi

echo "magen: backup stored ${dest}"
echo "changed=1"
