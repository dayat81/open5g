#!/bin/bash
# Shared helpers for android-ue-up.sh and android-ue-down.sh.
set -euo pipefail

android_ue_root() {
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd
}

android_ue_state_dir() {
  printf '%s\n' "${ANDROID_UE_STATE_DIR:-/var/lib/open5g-android-ue}"
}

# Prints install or skip. Refuses to overwrite a saved UPF route.
android_ue_upf_decide() {
  local current=$1
  local cgnat_ip=$2
  local state_file=$3
  local via_cgnat=0
  case "$current" in
    "default via ${cgnat_ip} dev "*) via_cgnat=1 ;;
  esac
  if [ -f "$state_file" ]; then
    if [ "$via_cgnat" -eq 1 ]; then
      echo skip
      return 0
    fi
    echo "android-ue: ${state_file} already exists and the UPF default is not via the cgnat address" >&2
    return 1
  fi
  if [ "$via_cgnat" -eq 1 ]; then
    echo "android-ue: UPF default already points at cgnat and no previous route was saved" >&2
    return 1
  fi
  if [ -n "$current" ] && ! printf '%s\n' "$current" | grep -Eq '^default via [0-9.]+ dev [A-Za-z0-9._:-]+$'; then
    echo "android-ue: UPF default route is not a single simple route; not changing it" >&2
    return 1
  fi
  echo install
}

android_ue_env_get() {
  local file=$1
  local key=$2
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

android_ue_require_set() {
  local name=$1
  local value=$2
  if [ -z "$value" ]; then
    echo "android-ue: ${name} is empty in the env file" >&2
    return 1
  fi
}

android_ue_reject_placeholder() {
  local name=$1
  local value=$2
  android_ue_require_set "$name" "$value"
  case "$value" in
    *REPLACE_*|*CHANGEME*)
      echo "android-ue: ${name} still has a placeholder" >&2
      return 1
      ;;
  esac
}

android_ue_compose() {
  local root=$1
  local env_file=$2
  shift 2
  local -a compose
  if [ -n "${ANDROID_UE_COMPOSE_BIN:-}" ]; then
    # shellcheck disable=SC2206
    compose=($ANDROID_UE_COMPOSE_BIN)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose=(docker-compose)
  else
    compose=(docker compose)
  fi
  local -a profiles=(--profile android-ue)
  if [ "${ANDROID_UE_SOCKS_PROFILE:-0}" = 1 ]; then
    profiles+=(--profile socks-egress)
  fi
  "${compose[@]}" \
    -f "$root/lab/compose/docker-compose.android-ue.optional.yml" \
    --env-file "$env_file" \
    "${profiles[@]}" \
    "$@"
}
