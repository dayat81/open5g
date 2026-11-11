#!/bin/bash
# Shared helpers for android-ue-up.sh and android-ue-down.sh.
set -euo pipefail

android_ue_root() {
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd
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
