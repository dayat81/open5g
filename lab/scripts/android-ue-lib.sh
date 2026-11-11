#!/bin/bash
# Shared helpers for android-ue-up.sh and android-ue-down.sh.
set -euo pipefail

android_ue_root() {
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd
}

android_ue_state_dir() {
  printf '%s\n' "${ANDROID_UE_STATE_DIR:-/var/lib/open5g-android-ue}"
}

# Prints install or skip for one UE /32 policy rule. Does not touch the main table.
android_ue_upf_rule_decide() {
  local rules=$1
  local ue_cidr=$2
  local state_file=$3
  local needle="from ${ue_cidr} lookup 1080"
  local have=0
  case "$rules" in
    *"$needle"*) have=1 ;;
  esac
  if [ -f "$state_file" ]; then
    if [ "$have" -eq 1 ]; then
      echo skip
      return 0
    fi
    echo "android-ue: ${state_file} already exists and the policy rule is missing" >&2
    return 1
  fi
  if [ "$have" -eq 1 ]; then
    echo "android-ue: policy rule ${needle} is present and was not saved by this script" >&2
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

android_ue_mib() {
  local raw=$1
  local n
  case "$raw" in
    ''|*[!0-9mMgG]*)
      return 1
      ;;
  esac
  case "$raw" in
    *g|*G)
      n=${raw%[gG]}
      printf '%s\n' "$((n * 1024))"
      ;;
    *m|*M)
      printf '%s\n' "${raw%[mM]}"
      ;;
    *)
      printf '%s\n' "$raw"
      ;;
  esac
}

android_ue_addr_in_pool() {
  python3 - "$1" "$2" <<'PY'
import sys
addr, pool = sys.argv[1], sys.argv[2]
def ip4(text):
    parts = text.split(".")
    if len(parts) != 4:
        return None
    value = 0
    for part in parts:
        if not part.isdigit():
            return None
        number = int(part)
        if number > 255:
            return None
        value = value * 256 + number
    return value
if "/" not in pool:
    sys.exit(1)
net, bits = pool.split("/", 1)
if not bits.isdigit():
    sys.exit(1)
width = int(bits)
if width > 32:
    sys.exit(1)
left, right = ip4(addr), ip4(net)
if left is None or right is None:
    sys.exit(1)
if width == 0:
    sys.exit(0)
shift = 1 << (32 - width)
sys.exit(0 if left // shift == right // shift else 1)
PY
}

# Args: /proc/net/if_inet6 contents file, sysfs net root.
# A usable fe80 is not lo, not tentative (0x40), not dadfailed (0x08), and IFF_UP.
android_ue_fe80_proc_ok() {
  local procfile=$1
  local sysroot=$2
  local addr _idx _plen _scope flags name iflag
  while read -r addr _idx _plen _scope flags name; do
    case "$addr" in
      fe80*) ;;
      *) continue ;;
    esac
    if [ "$name" = "lo" ]; then
      continue
    fi
    flags=$((16#$flags))
    if [ $((flags & 16#48)) -ne 0 ]; then
      continue
    fi
    iflag=$(cat "${sysroot}/${name}/flags" 2>/dev/null || echo 0)
    iflag=$((iflag))
    if [ $((iflag & 1)) -eq 1 ]; then
      return 0
    fi
  done <"$procfile"
  return 1
}

android_ue_android_image_ok() {
  local image=$1
  case "$image" in
    open5g-android-emulator:local) return 0 ;;
    *@sha256:[0-9A-Fa-f]*) return 0 ;;
    *) return 1 ;;
  esac
}

android_ue_kvm_gid_ok() {
  local want=$1
  local have=$2
  printf '%s\n' "$want" | grep -Eq '^[1-9][0-9]*$' || return 1
  [ "$want" = "$have" ]
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
