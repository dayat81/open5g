#!/bin/bash
# Bring up project open5g. SGi egress is off unless --with-sgi-egress.
# The dashboard profile stays closed until #13 digests are pinned and SGi is closed.
# IPv6 sysctls and the screen chain are installed from the host before QEMU.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

env_file=""
images_env=""
with_dashboard=0
with_socks=0
with_sgi=0
boot_only=0
gui_only=1
dry=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      env_file=$1
      ;;
    --images-env)
      shift
      images_env=$1
      ;;
    --with-dashboard) with_dashboard=1 ;;
    --gui-only) gui_only=1 ;;
    --with-epc) gui_only=0 ;;
    --with-socks-egress) with_socks=1 ;;
    --with-sgi-egress) with_sgi=1 ;;
    --boot-only) boot_only=1 ;;
    --dry-run) dry=1 ;;
    *)
      echo "usage: magen-up.sh --env-file FILE [--images-env FILE] [--gui-only | --with-epc] [--boot-only] [--with-dashboard] [--with-sgi-egress] [--with-socks-egress] [--dry-run]" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  echo "usage: magen-up.sh --env-file FILE [--images-env FILE] [--gui-only | --with-epc] [--boot-only] [--with-dashboard] [--with-sgi-egress] [--with-socks-egress] [--dry-run]" >&2
  exit 2
fi

if [ "${MAGEN_CHECK_MODE:-0}" = "1" ]; then
  dry=1
fi

root=$(magen_root)
if [ -z "$images_env" ]; then
  images_env="$root/lab/compose/magen.images.env"
fi
get() { magen_env_get "$env_file" "$1"; }
get_pin() {
  local value pinned
  value=$(get "$1")
  if [ -f "$images_env" ]; then
    pinned=$(magen_env_get "$images_env" "$1")
    if [ -n "$pinned" ]; then
      value=$pinned
    fi
  fi
  printf '%s\n' "$value"
}

image=$(get_pin O5G_ANDROID_IMAGE)
if magen_rejected_b0_image "$image" || ! magen_digest_ok "$image"; then
  echo "magen: O5G_ANDROID_IMAGE must be a #13 image pinned with @sha256. The #12 local tag is rejected." >&2
  exit 1
fi

if [ -n "$(get ANDROID_UE_UU)" ]; then
  echo "magen: ANDROID_UE_UU is not used. Standalone boot does not read it." >&2
  exit 1
fi

if [ "$gui_only" -eq 1 ]; then
  with_dashboard=1
fi

if [ "$with_dashboard" -eq 1 ] && [ "$with_sgi" -eq 1 ]; then
  echo "magen: gui profile stays closed while SGi egress is open." >&2
  exit 1
fi

if [ "$gui_only" -eq 1 ] || [ "$with_dashboard" -eq 1 ]; then
  for key in O5G_DASHBOARD_API_IMAGE O5G_DASHBOARD_WEB_IMAGE O5G_SCREEN_IMAGE O5G_POSTGRES_IMAGE; do
    value=$(get_pin "$key")
    if magen_is_placeholder "$value" || ! magen_digest_ok "$value"; then
      echo "magen: dashboard profile is closed until a digest built from PR #13 at a680f8b is pinned. See docs/deploy/magen.md." >&2
      exit 1
    fi
  done
else
  echo "magen: dashboard profile is off"
fi

if [ "$with_sgi" -eq 1 ]; then
  echo "magen: needs Netdrive approval: egress via host"
fi

if [ "$dry" -eq 1 ]; then
  if [ "$gui_only" -eq 1 ]; then
    echo "magen: dry-run mode=gui services=android1,screen1,dashboard-listener,dashboard-api,dashboard-web,dashboard-postgres"
    echo "magen: gui has no mongo, mme, hss, pcrf, sgwc, sgwu, smf, upf, enb, or ue"
    echo "magen: gui env omits O5G_MONGO_URI"
    echo "magen: ports 127.0.0.1:3300:3300 127.0.0.1:3301:3301"
    echo "magen: listener networks dash,screen bind $(get O5G_LISTENER_DASH)"
  else
    echo "magen: dry-run mode=epc"
  fi
  echo "magen: dry-run project open5g boot_only=${boot_only} dashboard=${with_dashboard} socks=${with_socks} sgi=${with_sgi} gui=${gui_only}"
  echo "changed=0"
  exit 0
fi

pre_args=(--env-file "$env_file")
if [ "$gui_only" -eq 1 ]; then
  pre_args+=(--gui-only)
elif [ "$with_dashboard" -eq 1 ]; then
  pre_args+=(--with-dashboard)
fi
if [ "$gui_only" -eq 0 ]; then
  pre_args+=(--with-epc)
fi
if [ "$with_sgi" -eq 1 ]; then
  pre_args+=(--with-sgi-egress)
fi
bash "$script_dir/magen-preflight.sh" "${pre_args[@]}"
export O5G_STATE_DIR
O5G_STATE_DIR=$(magen_state_dir)
mkdir -p -- "${O5G_STATE_DIR}/conf"
bash "$script_dir/render-magen-config.sh" --env-file "$env_file" --out "${O5G_STATE_DIR}/conf"
compose="$root/lab/compose/compose.magen.yml"
if [ "$with_sgi" -eq 1 ]; then
  bash "$script_dir/magen-socks.sh" --sgi-render "$compose" > "${O5G_STATE_DIR}/compose.sgi.yml"
  compose="${O5G_STATE_DIR}/compose.sgi.yml"
fi
if [ "$with_socks" -eq 1 ]; then
  bash "$script_dir/magen-socks.sh" --render "$compose" > "${O5G_STATE_DIR}/compose.socks.yml"
  compose="${O5G_STATE_DIR}/compose.socks.yml"
fi
args=(compose -p open5g -f "$compose" --env-file "$env_file")
if [ -f "$images_env" ]; then
  args+=(--env-file "$images_env")
fi
log=$(mktemp)
if [ "$gui_only" -eq 1 ]; then
  docker "${args[@]}" up -d android1 screen1 dashboard-listener dashboard-api dashboard-web dashboard-postgres >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
elif [ "$boot_only" -eq 1 ]; then
  docker "${args[@]}" --profile epc up -d android1 android2 >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
else
  docker "${args[@]}" --profile epc up -d >"$log" 2>&1 || { cat "$log" >&2; exit 1; }
fi
cat "$log"

ip6=0
if [ -e /proc/net/if_inet6 ]; then
  all_v6=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)
  if [ "$all_v6" != "1" ]; then
    ip6=1
  fi
fi
listener=$(get O5G_SCREEN_LISTENER)
lock_one() {
  local name=$1 chain=$2
  local pid ipv6_args
  pid=$(docker inspect -f '{{.State.Pid}}' "$name")
  export O5G_ANDROID_IMAGE="$image"
  ipv6_args=(--apply-ipv6 --container "$name" --pid "$pid")
  if [ "$ip6" -eq 1 ]; then
    ipv6_args+=(--ip6tables)
  fi
  bash "$script_dir/magen-netns.sh" "${ipv6_args[@]}"
  if [ "$chain" -eq 1 ]; then
    bash "$script_dir/magen-netns.sh" --apply-screen --container "$name" --pid "$pid" --listener "$listener"
    docker exec "$name" touch /tmp/o5g-host-ready
  fi
}
lock_one o5g-android1 1
if [ "$gui_only" -eq 0 ]; then
  lock_one o5g-android2 1
  if [ "$boot_only" -eq 0 ]; then
    lock_one o5g-ue1 0
    lock_one o5g-ue2 0
  fi
fi
changed=$(magen_compose_changed "$log")
echo "changed=${changed}"
