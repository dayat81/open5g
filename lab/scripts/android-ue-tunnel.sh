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
  local cgnat_ip=$1
  printf '%s\n' "-p tcp --dport 1080 ! -s ${cgnat_ip} -j DROP"
}

android_ue_parse_gatewayports() {
  awk 'tolower($1) == "gatewayports" { print tolower($2); exit }'
}

android_ue_gatewayports_is_ok() {
  local value
  value=$(android_ue_parse_gatewayports)
  [ "$value" = "clientspecified" ]
}

android_ue_check_listen_lines() {
  local gw=$1
  local line addrport addr port found=0 bad=0
  while IFS= read -r line; do
    addrport=$(printf '%s\n' "$line" | awk '{ print $4 }')
    [ -n "$addrport" ] || continue
    port=${addrport##*:}
    addr=${addrport%:*}
    if [ "$port" != "1080" ]; then
      continue
    fi
    found=1
    case "$addr" in
      "$gw"|"[$gw]") ;;
      *) bad=1 ;;
    esac
  done
  if [ "$found" -eq 0 ] || [ "$bad" -eq 1 ]; then
    return 1
  fi
}

android_ue_install_dropin() {
  local etc_root=$1
  local state=$2
  local dir dest
  dir="${etc_root}/etc/ssh/sshd_config.d"
  dest="${dir}/00-open5g-android-ue.conf"
  mkdir -p "$dir" "$state"
  if [ -f "$dest" ]; then
    cp "$dest" "$state/gatewayports-dropin.bak"
  else
    printf 'absent\n' >"$state/gatewayports-dropin.bak"
  fi
  printf 'GatewayPorts clientspecified\n' >"$dest"
}

android_ue_restore_dropin() {
  local etc_root=$1
  local state=$2
  local dest bak
  dest="${etc_root}/etc/ssh/sshd_config.d/00-open5g-android-ue.conf"
  bak="${state}/gatewayports-dropin.bak"
  if [ ! -f "$bak" ]; then
    return 0
  fi
  if [ "$(head -n 1 "$bak")" = "absent" ]; then
    rm -f "$dest"
  else
    cp "$bak" "$dest"
  fi
  rm -f "$bak"
}

android_ue_write_iptables_persist() {
  local etc_root=$1
  local state=$2
  local unit_dir restore
  unit_dir="${etc_root}/etc/systemd/system"
  restore="${state}/restore-input-1080.sh"
  mkdir -p "$unit_dir" "$state"
  cat >"$restore" <<EOF
#!/bin/sh
set -eu
rules="${state}/input-1080.rules"
pos=1
while IFS= read -r spec; do
  [ -n "\$spec" ] || continue
  # shellcheck disable=SC2086
  iptables -C INPUT \$spec 2>/dev/null || iptables -I INPUT "\$pos" \$spec
  pos=\$((pos + 1))
done < "\$rules"
EOF
  chmod 0755 "$restore"
  cat >"${unit_dir}/open5g-android-ue-iptables.service" <<EOF
[Unit]
Description=Restore android-ue INPUT rules for port 1080
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=${restore}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

android_ue_remove_iptables_persist() {
  local etc_root=$1
  local state=$2
  rm -f "${etc_root}/etc/systemd/system/open5g-android-ue-iptables.service"
  rm -f "${state}/restore-input-1080.sh" "${state}/iptables.rules"
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
  rules=$(android_ue_input_rules 192.0.2.20)
  printf '%s\n' "$rules" | grep -q -- '-p tcp --dport 1080 ! -s 192.0.2.20 -j DROP'
  if printf '%s\n' "$rules" | grep -q ' -d '; then
    echo "tunnel self-test: port 1080 drop still matches a destination address" >&2
    exit 1
  fi
  if printf 'gatewayports clientspecified\n' | android_ue_gatewayports_is_ok; then
    :
  else
    echo "tunnel self-test: clientspecified fixture was rejected" >&2
    exit 1
  fi
  if printf 'gatewayports yes\n' | android_ue_gatewayports_is_ok; then
    echo "tunnel self-test: gatewayports yes was accepted" >&2
    exit 1
  fi
  if ! printf '%s\n' 'LISTEN 0 128 192.0.2.10:1080 0.0.0.0:*' | android_ue_check_listen_lines 192.0.2.10; then
    echo "tunnel self-test: listener on the gateway address was rejected" >&2
    exit 1
  fi
  if printf '%s\n' 'LISTEN 0 128 0.0.0.0:1080 0.0.0.0:*' | android_ue_check_listen_lines 192.0.2.10; then
    echo "tunnel self-test: listener on 0.0.0.0 was accepted" >&2
    exit 1
  fi
  if printf '%s\n' 'LISTEN 0 128 *:1080 *:*' | android_ue_check_listen_lines 192.0.2.10; then
    echo "tunnel self-test: listener on every address was accepted" >&2
    exit 1
  fi
  pid=$(printf '%s\n' 'users:(("sshd",pid=4242,fd=3))' | android_ue_listener_pids)
  if [ "$pid" != "4242" ]; then
    echo "tunnel self-test: listener pid was not parsed" >&2
    exit 1
  fi
  mkdir -p "$dir/state"
  printf '%s\n' "-p tcp -d 192.0.2.10 --dport 1080 -j DROP" >"$dir/state/input-1080.rules"
  android_ue_write_iptables_persist "$dir/root" "$dir/state"
  if ! grep -q 'iptables -I INPUT' "$dir/state/restore-input-1080.sh"; then
    echo "tunnel self-test: restore script does not reinstall the saved rules" >&2
    exit 1
  fi
  if ! grep -q 'dport 1080' "$dir/state/input-1080.rules"; then
    echo "tunnel self-test: saved rules do not mention port 1080" >&2
    exit 1
  fi
  if ! grep -q 'WantedBy=multi-user.target' "$dir/root/etc/systemd/system/open5g-android-ue-iptables.service"; then
    echo "tunnel self-test: systemd unit was not written" >&2
    exit 1
  fi
  android_ue_remove_iptables_persist "$dir/root" "$dir/state"
  if [ -f "$dir/root/etc/systemd/system/open5g-android-ue-iptables.service" ]; then
    echo "tunnel self-test: systemd unit was not removed" >&2
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
if [ "$cmd" = "check-listen" ]; then
  shift || usage
  gw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gw)
        shift
        [ "$#" -gt 0 ] || usage
        gw=$1
        ;;
      *) usage ;;
    esac
    shift
  done
  if [ -z "$gw" ]; then
    usage
  fi
  if ! ss -H -ltn | android_ue_check_listen_lines "$gw"; then
    echo "android-ue-tunnel: port 1080 is not listening only on ${gw}" >&2
    exit 1
  fi
  echo "android-ue-tunnel: port 1080 is listening only on ${gw}"
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
  sshd -t
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload ssh
  else
    service ssh reload
  fi
}

android_ue_sshd_t() {
  if [ -n "${ANDROID_UE_SSHD_T_BIN:-}" ]; then
    "$ANDROID_UE_SSHD_T_BIN"
  else
    sshd -T
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
  if [ -f "$state/gatewayports-dropin.bak" ]; then
    echo "android-ue-tunnel: ${state}/gatewayports-dropin.bak already exists; not backing up over it" >&2
    exit 1
  fi
  android_ue_install_dropin "${ANDROID_UE_ETC_ROOT:-}" "$state"
  android_ue_input_rules "$cgnat_ip" >"$state/input-1080.rules"
  if [ "$dry_run" -eq 0 ]; then
    pos=1
    while IFS= read -r spec; do
      # shellcheck disable=SC2086
      iptables -C INPUT $spec 2>/dev/null || iptables -I INPUT "$pos" $spec
      pos=$((pos + 1))
    done <"$state/input-1080.rules"
  fi
  android_ue_write_iptables_persist "${ANDROID_UE_ETC_ROOT:-}" "$state"
  if [ "$dry_run" -eq 0 ]; then
    if command -v iptables-save >/dev/null 2>&1; then
      iptables-save >"$state/iptables.rules"
    fi
    if command -v systemctl >/dev/null 2>&1; then
      systemctl daemon-reload
      systemctl enable open5g-android-ue-iptables.service
    fi
  fi
  : >"$state/tunnel-prepared"
  reload_sshd
  if [ "$dry_run" -eq 1 ]; then
    echo "sshd -T gatewayports check"
  else
    effective=$(android_ue_sshd_t | android_ue_parse_gatewayports || true)
    if [ "$effective" != "clientspecified" ]; then
      android_ue_restore_dropin "${ANDROID_UE_ETC_ROOT:-}" "$state"
      reload_sshd || true
      echo "android-ue-tunnel: effective GatewayPorts is '${effective:-empty}', not clientspecified" >&2
      exit 1
    fi
  fi
  echo "android-ue-tunnel: GatewayPorts clientspecified is effective, INPUT 1080 persisted"
  exit 0
fi

if [ ! -f "$state/tunnel-prepared" ] && [ ! -f "$state/gatewayports.bak" ] && [ ! -f "$state/gatewayports-dropin.bak" ]; then
  echo "android-ue-tunnel: no tunnel state in ${state}"
  exit 0
fi
android_ue_restore_dropin "${ANDROID_UE_ETC_ROOT:-}" "$state"
if [ -f "$state/gatewayports.bak" ]; then
  android_ue_restore_gatewayports "$sshd_config" "$state/gatewayports.bak"
  rm -f "$state/gatewayports.bak"
fi
reload_sshd
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
if [ "$dry_run" -eq 1 ]; then
  echo "iptables-save and remove the persisted port 1080 unit"
else
  if command -v iptables-save >/dev/null 2>&1; then
    iptables-save >"$state/iptables.rules" || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable open5g-android-ue-iptables.service >/dev/null 2>&1 || true
    systemctl daemon-reload || true
  fi
  android_ue_remove_iptables_persist "${ANDROID_UE_ETC_ROOT:-}" "$state"
fi
rm -f "$state/tunnel-prepared"
echo "android-ue-tunnel: GatewayPorts restored, listener stopped, INPUT 1080 removed"
