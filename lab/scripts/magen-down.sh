#!/bin/bash
# Remove only project open5g resources whose names start with o5g-.
# b0-agen-emu is never deleted. Volumes stay unless --volumes is set.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

volumes=0
dry=0
names_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --volumes) volumes=1 ;;
    --dry-run) dry=1 ;;
    --names-file)
      shift
      names_file=$1
      ;;
    *)
      echo "usage: magen-down.sh [--volumes] [--dry-run] [--names-file FILE]" >&2
      exit 2
      ;;
  esac
  shift
done

magen_down_check_names() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    magen_deletable_name "$name" || return 1
  done
}

if [ -n "$names_file" ]; then
  magen_down_check_names < "$names_file"
  echo "magen: name check passed"
  echo "changed=0"
  exit 0
fi

if [ "$dry" -eq 1 ]; then
  echo "magen: down would remove only o5g- resources in project open5g"
  echo "changed=0"
  exit 0
fi

root=$(magen_root)
args=(compose -p open5g -f "$root/lab/compose/compose.magen.yml" down --remove-orphans)
if [ "$volumes" -eq 1 ]; then
  args+=(--volumes)
fi
names=$(docker ps -a --filter label=com.docker.compose.project=open5g --format '{{.Names}}')
printf '%s\n' "$names" | magen_down_check_names
docker "${args[@]}"
echo "magen: project open5g is down"
echo "changed=1"
