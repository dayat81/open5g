#!/bin/bash
# Prepare and roll back the guest side of the ssh -R SOCKS tunnel.
# prepare backs up GatewayPorts before changing it. rollback kills the
# listener on port 1080, deletes the INPUT rules, and restores the backup.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-lib.sh
. "$script_dir/android-ue-lib.sh"

android_ue_backup_gatewayports() {
  local src=$1
  local dest=$2
  local line
  line=$(grep -E '^[[:space:]]*GatewayPorts[[:space:]]+' "$src" | head -n 1 || true)
  if [ -z "$line" ]; then
    printf 'absent\n' >"$dest"
  else
    printf '%s\n' "$line" >"$dest"
  fi
}

android_ue_set_gatewayports() {
  local file=$1
  local tmp
  tmp=$(mktemp)
  if grep -Eq '^[[:space:]]*GatewayPorts[[:space:]]+' "$file"; then
    awk '
      BEGIN { done = 0 }
      /^[[:space:]]*GatewayPorts[[:space:]]+/ {
        if (!done) {
          print "GatewayPorts clientspecified"
          done = 1
        }
        next
      }
      { print }
    ' "$file" >"$tmp"
  else
    cat "$file" >"$tmp"
    printf '\nGatewayPorts clientspecified\n' >>"$tmp"
  fi
  mv "$tmp" "$file"
}

android_ue_restore_gatewayports() {
  local file=$1
  local backup=$2
  local saved tmp
  saved=$(head -n 1 "$backup")
  tmp=$(mktemp)
  if [ "$saved" = "absent" ]; then
    grep -Ev '^[[:space:]]*GatewayPorts[[:space:]]+' "$file" >"$tmp" || true
  else
    awk -v saved="$saved" '
      BEGIN { done = 0 }
      /^[[:space:]]*GatewayPorts[[:space:]]+/ {
        if (!done) {
          print saved
          done = 1
        }
        next
      }
      { print }
      END {
        if (!done) {
          print saved
        }
      }
    ' "$file" >"$tmp"
  fi
  mv "$tmp" "$file"
}

android_ue_listener_pids() {
  sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | awk '!seen[$0]++'
}

android_ue_input_rules() {
  local gw=$1
  local cgnat_ip=$2
  printf '%s\n' "-p tcp -d ${gw} --dport 1080 -s ${cgnat_ip} -j ACCEPT"
  printf '%s\n' "-p tcp -d ${gw} --dport 1080 -j DROP"
}

android_ue_tunnel_self_test() {
  local dir sshd backup
  dir=$(mktemp -d)
  sshd=$dir/sshd_config
  backup=$dir/gatewayports.bak
  printf 'Port 22\n' >"$sshd"
  android_ue_backup_gatewayports "$sshd" "$backup"
  if [ "$(cat "$backup")" != "absent" ]; then
    echo "tunnel self-test: missing GatewayPorts was not recorded as absent" >&2
    exit 1
  fi
  android_ue_set_gatewayports "$sshd"
  if ! grep -qx 'GatewayPorts clientspecified' "$sshd"; then
    echo "tunnel self-test: clientspecified was not written" >&2
    exit 1
  fi
  android_ue_restore_gatewayports "$sshd" "$backup"
  if grep -Eq '^[[:space:]]*GatewayPorts[[:space:]]+' "$sshd"; then
    echo "tunnel self-test: absent GatewayPorts was not removed" >&2
    exit 1
  fi

  printf 'GatewayPorts no\n' >"$sshd"
  android_ue_backup_gatewayports "$sshd" "$backup"
  if [ "$(cat "$backup")" != "GatewayPorts no" ]; then
    echo "tunnel self-test: previous GatewayPorts line was not saved" >&2
    exit 1
  fi
  android_ue_set_gatewayports "$sshd"
  android_ue_restore_gatewayports "$sshd" "$backup"
  if ! grep -qx 'GatewayPorts no' "$sshd"; then
    echo "tunnel self-test: GatewayPorts was not restored" >&2
    exit 1
  fi

  local rules pid
  rules=$(android_ue_input_rules 192.0.2.10 192.0.2.20)
  printf '%s\n' "$rules" | grep -q -- '-p tcp -d 192.0.2.10 --dport 1080 -s 192.0.2.20 -j ACCEPT'
  printf '%s\n' "$rules" | grep -q -- '-p tcp -d 192.0.2.10 --dport 1080 -j DROP'
  pid=$(printf '%s\n' 'users:(("sshd",pid=4242,fd=3))' | android_ue_listener_pids)
  if [ "$pid" != "4242" ]; then
    echo "tunnel self-test: listener pid was not parsed" >&2
    exit 1
  fi
  rm -rf "$dir"
  echo "tunnel self-test passed"
}

usage() {
  echo "usage: android-ue-tunnel.sh prepare|rollback|self-test [--env-file FILE] [--state-dir DIR] [--sshd-config PATH] [--dry-run]" >&2
  exit 2
}

cmd=${1:-}
if [ "$cmd" = "self-test" ]; then
  android_ue_tunnel_self_test
  exit 0
fi
shift || usage
case "$cmd" in
  prepare|rollback) ;;
  *) usage ;;
esac

env_file=""
state=$(android_ue_state_dir)
sshd_config=${ANDROID_UE_SSHD_CONFIG:-/etc/ssh/sshd_config}
dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || usage
      env_file=$1
      ;;
    --state-dir)
      shift
      [ "$#" -gt 0 ] || usage
      state=$1
      ;;
    --sshd-config)
      shift
      [ "$#" -gt 0 ] || usage
      sshd_config=$1
      ;;
    --dry-run) dry_run=1 ;;
    *) usage ;;
  esac
  shift
done

run_cmd() {
  if [ "$dry_run" -eq 1 ]; then
    printf '%s\n' "$*"
    return 0
  fi
  "$@"
}

reload_sshd() {
  if [ "$dry_run" -eq 1 ]; then
    echo "reload sshd"
    return 0
  fi
  sshd -t -f "$sshd_config"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload ssh
  else
    service ssh reload
  fi
}

kill_listeners() {
  local pids pid
  if [ "$dry_run" -eq 1 ]; then
    echo "kill listeners on port 1080"
    return 0
  fi
  if ! command -v ss >/dev/null 2>&1; then
    echo "android-ue-tunnel: ss is missing; listener on 1080 was not killed" >&2
    return 1
  fi
  pids=$(ss -H -ltnp 'sport = :1080' | android_ue_listener_pids || true)
  if [ -z "$pids" ]; then
    echo "android-ue-tunnel: no listener on port 1080"
    return 0
  fi
  printf '%s\n' "$pids" | while IFS= read -r pid; do
    if [ -z "$pid" ] || [ "$pid" = "1" ]; then
      continue
    fi
    kill "$pid"
    echo "android-ue-tunnel: killed pid ${pid} listening on 1080"
  done
}

if [ "$cmd" = "prepare" ]; then
  if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
    usage
  fi
  get() { android_ue_env_get "$env_file" "$1"; }
  socks=$(get ANDROID_UE_SOCKS_ADDR)
  cgnat_ip=$(get CGNAT_SGI_ADDR)
  android_ue_reject_placeholder ANDROID_UE_SOCKS_ADDR "$socks"
  android_ue_reject_placeholder CGNAT_SGI_ADDR "$cgnat_ip"
  gw=${socks%%:*}
  if ! printf '%s\n' "$gw" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "android-ue-tunnel: ANDROID_UE_SOCKS_ADDR must start with an IPv4 address" >&2
    exit 1
  fi
  if ! printf '%s\n' "$cgnat_ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "android-ue-tunnel: CGNAT_SGI_ADDR must be an IPv4 address" >&2
    exit 1
  fi
  mkdir -p "$state"
  if [ -f "$state/gatewayports.bak" ]; then
    echo "android-ue-tunnel: ${state}/gatewayports.bak already exists; not backing up over it" >&2
    exit 1
  fi
  android_ue_backup_gatewayports "$sshd_config" "$state/gatewayports.bak"
  android_ue_set_gatewayports "$sshd_config"
  android_ue_input_rules "$gw" "$cgnat_ip" >"$state/input-1080.rules"
  if [ "$dry_run" -eq 0 ]; then
    pos=1
    while IFS= read -r spec; do
      # shellcheck disable=SC2086
      iptables -C INPUT $spec 2>/dev/null || iptables -I INPUT "$pos" $spec
      pos=$((pos + 1))
    done <"$state/input-1080.rules"
  fi
  : >"$state/tunnel-prepared"
  reload_sshd
  echo "android-ue-tunnel: GatewayPorts clientspecified, previous value saved, INPUT 1080 limited to the cgnat address"
  exit 0
fi

if [ ! -f "$state/tunnel-prepared" ] && [ ! -f "$state/gatewayports.bak" ]; then
  echo "android-ue-tunnel: no tunnel state in ${state}"
  exit 0
fi
kill_listeners || true
if [ -f "$state/input-1080.rules" ]; then
  while IFS= read -r spec; do
    if [ "$dry_run" -eq 1 ]; then
      echo "iptables -D INPUT ${spec}"
    else
      # shellcheck disable=SC2086
      iptables -D INPUT $spec || true
    fi
  done <"$state/input-1080.rules"
  rm -f "$state/input-1080.rules"
fi
if [ -f "$state/gatewayports.bak" ]; then
  android_ue_restore_gatewayports "$sshd_config" "$state/gatewayports.bak"
  rm -f "$state/gatewayports.bak"
  reload_sshd
fi
rm -f "$state/tunnel-prepared"
echo "android-ue-tunnel: listener stopped, INPUT 1080 removed, GatewayPorts restored"
