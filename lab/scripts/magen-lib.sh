#!/bin/bash
# Shared helpers for the magen profile. No host changes.
set -euo pipefail

magen_root() {
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd
}

magen_state_dir() {
  printf '%s\n' "${O5G_STATE_DIR:-${HOME}/o5g-state}"
}

magen_digest_ok() {
  printf '%s\n' "$1" | grep -Eq '@sha256:[0-9A-Fa-f]{64}$'
}

magen_is_placeholder() {
  case "$1" in
    ''|REPLACE_*|*CHANGEME*) return 0 ;;
    *) return 1 ;;
  esac
}

# o5g- names may be removed. b0-agen-emu and every other name may not.
magen_deletable_name() {
  case "$1" in
    b0-agen-emu)
      echo "magen: refusing to delete b0-agen-emu" >&2
      return 1
      ;;
    o5g-*) return 0 ;;
    *)
      echo "magen: refusing to delete ${1}" >&2
      return 1
      ;;
  esac
}

magen_env_get() {
  local file=$1 key=$2
  awk -F= -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ /^[[:space:]]*$/ { next }
    $1 == k {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$file"
}

magen_floor_bytes() {
  echo $((20 * 1024 * 1024 * 1024))
}
