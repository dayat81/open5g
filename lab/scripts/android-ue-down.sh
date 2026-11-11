#!/bin/bash
# Stop the android-ue profile. Leaves the core, Mongo, and subscriber documents in place.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-lib.sh
. "$script_dir/android-ue-lib.sh"

env_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || exit 2
      env_file=$1
      ;;
    *)
      echo "usage: android-ue-down.sh --env-file FILE" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  echo "usage: android-ue-down.sh --env-file FILE" >&2
  exit 2
fi

root=$(android_ue_root)
state=$(android_ue_state_dir)
get() { android_ue_env_get "$env_file" "$1"; }
export ANDROID_UE_SOCKS_PROFILE=1
rollback_rc=0

if [ -f "$state/tunnel-prepared" ] || [ -f "$state/gatewayports.bak" ]; then
  if ! bash "$script_dir/android-ue-tunnel.sh" rollback --state-dir "$state" --sshd-config "${ANDROID_UE_SSHD_CONFIG:-/etc/ssh/sshd_config}"; then
    echo "android-ue: tunnel rollback failed" >&2
    rollback_rc=1
  fi
fi

shopt -s nullglob
for stale in "$state"/upf-enb-s1u-*.route; do
  rm -f "$stale"
  echo "android-ue: removed stale UPF route state ${stale}. No UPF route was changed."
done
shopt -u nullglob

if [ -f "$state/upf-rule.txt" ]; then
  upf=$(get ANDROID_UE_UPF_CONTAINER)
  rule=$(head -n 1 "$state/upf-rule.txt")
  case "$rule" in
    from\ */32\ lookup\ 1080)
      # shellcheck disable=SC2086
      docker exec "$upf" ip rule del $rule || true
      docker exec "$upf" ip route del default table 1080 || true
      ;;
    *)
      echo "android-ue: saved UPF rule is not a /32 lookup; left the UPF unchanged" >&2
      rollback_rc=1
      ;;
  esac
  rm -f "$state/upf-rule.txt"
  echo "android-ue: removed the UPF policy rule. The main default route was not changed."
fi

# UE before eNB. srsRAN's ZMQ note asks for that order on the way down.
for svc in ue1-screen ue2-screen android1 android2 ue1-route ue2-route ue1 ue2 enb1 enb2 egress-dns egress cgnat; do
  android_ue_compose "$root" "$env_file" stop "$svc" || true
done
android_ue_compose "$root" "$env_file" rm -f \
  ue1-screen ue2-screen android1 android2 ue1-route ue2-route ue1 ue2 enb1 enb2 egress-dns egress cgnat || true
rm -f "$state/cgnat-ues.txt"
echo "android-ue: profile stopped. Core, Mongo, and subscriber documents were not changed."
exit "$rollback_rc"
