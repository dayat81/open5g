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

# fc00::/7 with prefix /128. ::1, fe80, and global unicast are rejected.
android_ue_ula_cidr_ok() {
  local ula=$1
  local addr head
  case "$ula" in
    */128) ;;
    *) return 1 ;;
  esac
  addr=${ula%/*}
  case "$addr" in
    ::*) return 1 ;;
    *:*) ;;
    *) return 1 ;;
  esac
  head=$(printf '%s' "${addr%%:*}" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$head" | grep -Eq '^(fc|fd)[0-9a-f]{0,2}$' || return 1
  printf '%s\n' "$addr" | grep -Eq '^[0-9A-Fa-f:]+$' || return 1
  case "$addr" in
    *:::*) return 1 ;;
  esac
}

# One `ip -o link show` line. UP is the flag inside <...>, not a host sysfs bit.
android_ue_link_is_up() {
  local line=$1
  [ -n "$line" ] || return 1
  printf '%s\n' "$line" | grep -Eq '<([^>]*,)?UP(,[^>]*)?>'
}

# Lines from `ip -6 -o addr show dev dummy0 scope global`.
# A passing address is fc00::/7 /128 and is not tentative or dadfailed.
android_ue_dummy0_ula_ok() {
  local line addr
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$line" | grep -q 'inet6 ' || continue
    printf '%s\n' "$line" | grep -q 'scope global' || continue
    if printf '%s\n' "$line" | grep -Eq '(^|[[:space:]])(tentative|dadfailed)([[:space:]]|$)'; then
      continue
    fi
    addr=$(printf '%s\n' "$line" | awk '{ for (i = 1; i <= NF; i++) if ($i == "inet6") { print $(i + 1); exit } }')
    android_ue_ula_cidr_ok "$addr" && return 0
  done
  return 1
}

# A non-tentative ULA on an UP dummy0. fe80 does not satisfy this check.
android_ue_ula_proc_ok() {
  local procfile=$1
  local sysroot=$2
  local addr _idx _plen _scope flags name iflag prefix
  while read -r addr _idx _plen _scope flags name; do
    [ -n "${name:-}" ] || continue
    if [ "$name" != "dummy0" ]; then
      continue
    fi
    prefix=$(printf '%s' "$addr" | cut -c1-2 | tr 'A-F' 'a-f')
    if [ "$prefix" != "fd" ] && [ "$prefix" != "fc" ]; then
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

android_ue_nonloop_v6_ok() {
  android_ue_ula_proc_ok "$@"
}

android_ue_android_image_ok() {
  local image=$1
  case "$image" in
    open5g-android-emulator:local) return 0 ;;
  esac
  printf '%s\n' "$image" | grep -Eq '@sha256:[0-9A-Fa-f]{64}$'
}

# Both sides are sha256 digests. A placeholder or a different id fails closed.
# The local tag is not accepted by this function.
android_ue_image_id_ok() {
  local want=$1
  local have=$2
  case "$want" in
    sha256:*) ;;
    *) want="sha256:${want}" ;;
  esac
  case "$have" in
    sha256:*) ;;
    *) have="sha256:${have}" ;;
  esac
  printf '%s\n' "$want" | grep -Eq '^sha256:[0-9A-Fa-f]{64}$' || return 1
  printf '%s\n' "$have" | grep -Eq '^sha256:[0-9A-Fa-f]{64}$' || return 1
  [ "$want" = "$have" ]
}

# Host nft rules for the UE netns. lo is accepted, so ::1 on lo stays open.
# policy drop covers every other interface. No extra ::1 match.
android_ue_render_ip6_nft() {
  cat <<'EOF'
table ip6 android_ue {
	chain input {
		type filter hook input priority 0; policy drop;
		iif "lo" accept
	}
	chain output {
		type filter hook output priority 0; policy drop;
		oif "lo" accept
	}
}
EOF
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

android_ue_adb_host_port() {
  local n=$1
  printf '%s\n' "$((14555 + n * 1000))"
}

android_ue_console_host_port() {
  local n=$1
  printf '%s\n' "$((14554 + n * 1000))"
}

android_ue_uemu_network_name() {
  printf 'open5g-uemu%s\n' "$1"
}

# Print the pid of a named container. Refuse any other name so a sysctl or
# route write cannot land on the host, the UPF, or an EPC container.
android_ue_container_pid() {
  local name=$1
  local shown pid
  shown=$(docker inspect -f '{{.Name}} {{.State.Pid}}' "$name" 2>/dev/null || true)
  case "$shown" in
    "/${name} "[1-9]*) ;;
    *)
      echo "android-ue: refusing to change netns state; ${name} is not that container (${shown:-missing})" >&2
      return 1
      ;;
  esac
  pid=${shown##* }
  printf '%s\n' "$pid"
}

# Fail closed unless the UEMU prefix is canonical IPv4 and misses every
# canonical UE/PDN pool, uu address, PDN address, and cgnat address.
# Empty values and REPLACE_/CHANGEME placeholders are not overlap inputs.
# OTHER_SUBNET is the other user's UEMU prefix. Later args are kind=value
# with kind pool, uu, pdn, or cgnat.
android_ue_uemu_check() {
  python3 - "$@" <<'PY'
import ipaddress
import sys

args = sys.argv[1:]
if len(args) < 4:
    sys.stderr.write("android-ue: UEMU check needs subnet, gateway, android address, and the other subnet\n")
    sys.exit(1)

def fail(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)

def skipped(text):
    if text is None:
        return True
    stripped = text.strip()
    if not stripped:
        return True
    return "REPLACE_" in stripped or "CHANGEME" in stripped

def network(text, label):
    if skipped(text):
        fail("android-ue: %s is empty or still a placeholder" % label)
    try:
        net = ipaddress.ip_network(text, strict=True)
    except ValueError as exc:
        fail("android-ue: %s %s is not a canonical IPv4 prefix (%s)" % (label, text, exc))
    if net.version != 4:
        fail("android-ue: %s must be IPv4" % label)
    return net

def address(text, label):
    if skipped(text):
        fail("android-ue: %s is empty or still a placeholder" % label)
    try:
        ip = ipaddress.ip_address(text)
    except ValueError as exc:
        fail("android-ue: %s %s is not an IPv4 address (%s)" % (label, text, exc))
    if ip.version != 4:
        fail("android-ue: %s must be IPv4" % label)
    return ip

subnet = network(args[0], "ANDROID_UE_UEMU_SUBNET")
gateway = address(args[1], "ANDROID_UE_UEMU_GW")
android = address(args[2], "ANDROID_UE_UEMU_ANDROID")
other = network(args[3], "ANDROID_UE_UEMU_SUBNET")
if subnet.overlaps(other):
    fail("android-ue: per-user UEMU subnets %s and %s overlap" % (subnet, other))
if gateway not in subnet or android not in subnet:
    fail("android-ue: UEMU gateway and android address must be inside %s" % subnet)
if gateway == android:
    fail("android-ue: UEMU gateway and android address must differ")
if gateway == subnet.network_address or android == subnet.network_address:
    fail("android-ue: UEMU addresses must not be the subnet address")
if subnet.prefixlen <= 30:
    if gateway == subnet.broadcast_address or android == subnet.broadcast_address:
        fail("android-ue: UEMU addresses must not be the broadcast address")
for item in args[4:]:
    if "=" not in item:
        fail("android-ue: UEMU overlap entry must be kind=value")
    kind, value = item.split("=", 1)
    if kind not in {"pool", "uu", "pdn", "cgnat"}:
        fail("android-ue: unknown UEMU overlap kind %s" % kind)
    if skipped(value):
        continue
    if kind == "pool":
        pool = network(value, "UE pool")
        if subnet.overlaps(pool):
            fail("android-ue: UEMU subnet %s overlaps UE/PDN pool %s" % (subnet, pool))
        continue
    ip = address(value, kind)
    if ip in subnet:
        fail("android-ue: UEMU subnet %s contains %s address %s" % (subnet, kind, ip))
PY
}

android_ue_apply_dns_flag() {
  local flags=$1
  local dns=$2
  case "$dns" in
    ""|*REPLACE*|*CHANGEME*)
      printf '%s\n' "$flags"
      return 0
      ;;
  esac
  if ! printf '%s\n' "$dns" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "android-ue: ANDROID_UE_DNS must be an IPv4 address" >&2
    return 1
  fi
  if [ "$dns" = "127.0.0.11" ]; then
    echo "android-ue: ANDROID_UE_DNS must not be Docker's 127.0.0.11 resolver" >&2
    return 1
  fi
  printf '%s -dns-server %s\n' "$flags" "$dns"
}

android_ue_help_has_metrics() {
  local help_text=$1
  printf '%s\n' "$help_text" | grep -q -- '-no-metrics'
}

android_ue_drop_metrics_flag() {
  python3 - "$1" <<'PY'
import shlex
import sys
parts = shlex.split(sys.argv[1])
print(" ".join(part for part in parts if part != "-no-metrics"))
PY
}

# Drop adb keys, account databases, and userdata from an opted-in AVD directory.
# /root/.android is refused so adbkey is not kept with the AVD.
android_ue_avd_sanitize() {
  local dir=$1
  local base leftover
  if [ -z "$dir" ] || [ "$dir" = "/" ] || [ "$dir" = "/root" ] || [ "$dir" = "/root/.android" ]; then
    echo "android-ue: refusing to sanitize ${dir:-an empty path}" >&2
    return 1
  fi
  base=$(basename -- "$dir")
  if [ "$base" = ".android" ]; then
    echo "android-ue: AVD directory must not be named .android. That directory holds adbkey." >&2
    return 1
  fi
  if [ ! -d "$dir" ]; then
    mkdir -m 0700 -- "$dir"
  fi
  find "$dir" -type d -name snapshots -print0 | while IFS= read -r -d '' snap; do
    rm -rf -- "$snap"
  done
  find "$dir" \( \
    -name adbkey -o -name adbkey.pub -o -name userdata-qemu.img \
    -o -name userdata-qemu.img.qcow2 -o -name cache.img -o -name accounts.db \
  \) -print0 | while IFS= read -r -d '' junk; do
    rm -f -- "$junk"
  done
  leftover=$(find "$dir" \( -name adbkey -o -name adbkey.pub -o -name userdata-qemu.img -o -name accounts.db \) -print)
  if [ -n "$leftover" ]; then
    echo "android-ue: AVD directory still has an adb key, account database, or userdata image" >&2
    printf '%s\n' "$leftover" >&2
    return 1
  fi
}

android_ue_avd_wipe() {
  local dir=$1
  android_ue_avd_sanitize "$dir"
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
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
