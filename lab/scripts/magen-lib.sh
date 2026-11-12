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
  printf '%s\n' "$1" | grep -Eq '(^sha256:|@sha256:)[0-9A-Fa-f]{64}$'
}

# The #12 local emulator tag is not a #13 image.
magen_rejected_b0_image() {
  case "$1" in
    open5g-android-emulator:local|*:local) return 0 ;;
    *) return 1 ;;
  esac
}

# name must be an o5g android or ue container and pid must be its live pid.
magen_pid_matches() {
  local name=$1 want=$2 have=$3
  case "$name" in
    o5g-android1|o5g-android2|o5g-ue1|o5g-ue2) ;;
    *)
      echo "magen: refusing to enter ${name}" >&2
      return 1
      ;;
  esac
  if [ -z "$want" ] || [ "$want" = "0" ] || [ "$want" != "$have" ]; then
    echo "magen: pid ${want:-missing} is not ${name} (${have:-missing})" >&2
    return 1
  fi
}

magen_compose_changed() {
  local log=$1
  if grep -Eq 'Created|Started|Recreated' "$log"; then
    echo 1
    return 0
  fi
  echo 0
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
