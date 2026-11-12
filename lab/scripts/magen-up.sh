#!/bin/bash
# Bring up project open5g. The dashboard profile stays off unless
# --with-dashboard is set and every dashboard image is pinned with @sha256.
# Standalone boot does not require ANDROID_UE_UU.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

env_file=""
with_dashboard=0
with_socks=0
boot_only=0
dry=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      env_file=$1
      ;;
    --with-dashboard) with_dashboard=1 ;;
    --with-socks-egress) with_socks=1 ;;
    --boot-only) boot_only=1 ;;
    --dry-run) dry=1 ;;
    *)
      echo "usage: magen-up.sh --env-file FILE [--boot-only] [--with-dashboard] [--with-socks-egress] [--dry-run]" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  echo "usage: magen-up.sh --env-file FILE [--boot-only] [--with-dashboard] [--with-socks-egress] [--dry-run]" >&2
  exit 2
fi

if [ "${MAGEN_CHECK_MODE:-0}" = "1" ]; then
  dry=1
fi

root=$(magen_root)
get() { magen_env_get "$env_file" "$1"; }

image=$(get O5G_ANDROID_IMAGE)
if ! magen_digest_ok "$image"; then
  echo "magen: O5G_ANDROID_IMAGE must be pinned with @sha256" >&2
  exit 1
fi

if [ -n "$(get ANDROID_UE_UU)" ]; then
  echo "magen: ANDROID_UE_UU is not used. Standalone boot does not read it." >&2
  exit 1
fi

if [ "$with_dashboard" -eq 1 ]; then
  for key in O5G_DASHBOARD_API_IMAGE O5G_DASHBOARD_WEB_IMAGE O5G_POSTGRES_IMAGE; do
    value=$(get "$key")
    if magen_is_placeholder "$value" || ! magen_digest_ok "$value"; then
      echo "magen: dashboard profile is closed until a digest built from the PR #13 tree is pinned. See docs/deploy/magen.md." >&2
      exit 1
    fi
  done
else
  echo "magen: dashboard profile is off"
fi

if [ "$dry" -eq 1 ]; then
  echo "magen: dry-run project open5g boot_only=${boot_only} dashboard=${with_dashboard} socks=${with_socks}"
  echo "changed=0"
  exit 0
fi

bash "$script_dir/magen-preflight.sh" --env-file "$env_file" ${with_dashboard:+--with-dashboard}
export O5G_STATE_DIR
O5G_STATE_DIR=$(magen_state_dir)
mkdir -p -- "${O5G_STATE_DIR}/conf"
bash "$script_dir/render-magen-config.sh" --env-file "$env_file" --out "${O5G_STATE_DIR}/conf"
compose="$root/lab/compose/compose.magen.yml"
if [ "$with_socks" -eq 1 ]; then
  bash "$script_dir/magen-socks.sh" --render "$compose" > "${O5G_STATE_DIR}/compose.socks.yml"
  compose="${O5G_STATE_DIR}/compose.socks.yml"
fi
args=(compose -p open5g -f "$compose" --env-file "$env_file")
if [ "$with_dashboard" -eq 1 ]; then
  args+=(--profile dashboard)
fi
if [ "$boot_only" -eq 1 ]; then
  docker "${args[@]}" up -d android1 android2
else
  docker "${args[@]}" up -d
fi
echo "changed=1"
