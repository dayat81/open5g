#!/bin/bash
# Read-only preflight for the magen profile. It does not load modules,
# does not change sysctl, and does not delete containers.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

env_file=""
fixture=""
with_dashboard=0

usage() {
  echo "usage: magen-preflight.sh --env-file FILE [--fixture-root DIR] [--with-dashboard]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || usage
      env_file=$1
      ;;
    --fixture-root)
      shift
      [ "$#" -gt 0 ] || usage
      fixture=$1
      ;;
    --with-dashboard) with_dashboard=1 ;;
    *) usage ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  usage
fi

get() { magen_env_get "$env_file" "$1"; }

magen_check_docker_group() {
  local groups
  if [ -n "$fixture" ]; then
    groups=$(cat "$fixture/id-groups")
  else
    groups=$(id -nG)
  fi
  case " ${groups} " in
    *" docker "*) ;;
    *)
      echo "magen: id -nG does not include docker (${groups})." >&2
      echo "magen: the deploy user must already be in the docker group. This play does not use become." >&2
      return 1
      ;;
  esac
}

magen_check_kvm() {
  local want have
  want=$(get ANDROID_UE_KVM_GID)
  if [ -n "$fixture" ]; then
    [ -f "$fixture/kvm-ok" ] || {
      echo "magen: /dev/kvm is missing" >&2
      return 1
    }
    have=$(cat "$fixture/kvm-gid")
  else
    [ -e /dev/kvm ] || {
      echo "magen: /dev/kvm is missing" >&2
      return 1
    }
    have=$(stat -c %g /dev/kvm)
  fi
  if [ "$want" != "$have" ]; then
    echo "magen: ANDROID_UE_KVM_GID ${want} does not match ${have}" >&2
    return 1
  fi
}

magen_check_tun() {
  if [ -n "$fixture" ]; then
    [ -f "$fixture/tun-ok" ] || {
      echo "magen: /dev/net/tun is missing. The UPF uses a userspace TUN named ogstun and does not use gtp or gtp5g." >&2
      return 1
    }
  elif [ ! -e /dev/net/tun ]; then
    echo "magen: /dev/net/tun is missing. The UPF uses a userspace TUN named ogstun and does not use gtp or gtp5g." >&2
    return 1
  fi
  echo "magen: /dev/net/tun is present. A missing gtp or gtp5g module is expected and is not required."
}

magen_check_sctp() {
  local modules
  if [ -n "$fixture" ]; then
    modules=$(cat "$fixture/modules")
  else
    modules=$(cat /proc/modules)
  fi
  if ! printf '%s\n' "$modules" | awk '{ print $1 }' | grep -qx sctp; then
    echo "magen: sctp is not loaded. S1AP needs it." >&2
    echo "magen: ask for approval, then run: sudo modprobe sctp" >&2
    echo "magen: this script does not load kernel modules." >&2
    return 1
  fi
}

magen_check_docker_version() {
  local have
  if [ -n "$fixture" ]; then
    have=$(cat "$fixture/docker-version")
  else
    have=$(docker version --format '{{.Server.Version}}')
  fi
  python3 - "$have" <<'PY'
import sys
def parts(text):
    out = []
    for item in text.split("."):
        digits = ""
        for ch in item:
            if ch.isdigit():
                digits += ch
            else:
                break
        out.append(int(digits or "0"))
    while len(out) < 3:
        out.append(0)
    return tuple(out[:3])
have = parts(sys.argv[1])
need = (26, 1, 4)
if have < need:
    sys.stderr.write("magen: docker %s is older than 26.1.4\n" % sys.argv[1])
    sys.exit(1)
PY
}

magen_check_ip_forward() {
  local value
  if [ -n "$fixture" ]; then
    value=$(cat "$fixture/ip-forward")
  else
    value=$(cat /proc/sys/net/ipv4/ip_forward)
  fi
  if [ "$value" != "1" ]; then
    echo "magen: net.ipv4.ip_forward is ${value}. Docker egress NAT needs it to be 1." >&2
    echo "magen: ask for approval, then run: sudo sysctl net.ipv4.ip_forward=1" >&2
    echo "magen: this script does not change host sysctl." >&2
    return 1
  fi
}

magen_host_ipv6_off() {
  local mode
  if [ -n "$fixture" ]; then
    mode=$(cat "$fixture/host-ipv6")
    [ "$mode" = "off" ]
    return
  fi
  if [ ! -e /proc/net/if_inet6 ]; then
    return 0
  fi
  local value
  value=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)
  [ "$value" = "1" ]
}

magen_check_ip6tables() {
  if magen_host_ipv6_off; then
    echo "magen: host IPv6 is off. Skipping the unshare ip6tables probe. ::1 on lo inside the emulator netns stays mandatory."
    return 0
  fi
  if [ -n "$fixture" ]; then
    local code
    code=$(cat "$fixture/unshare-result")
    if [ "$code" != "0" ]; then
      echo "magen: ip6tables failed inside unshare -n. The host network was not changed." >&2
      return 1
    fi
    return 0
  fi
  if ! grep -qw ip6table_filter /proc/modules 2>/dev/null; then
    echo "magen: ip6table_filter is not loaded." >&2
    echo "magen: ask for approval, then run: sudo modprobe ip6table_filter" >&2
    echo "magen: this script does not load kernel modules." >&2
    return 1
  fi
  if ! command -v unshare >/dev/null 2>&1 || ! command -v ip6tables >/dev/null 2>&1; then
    echo "magen: unshare or ip6tables is missing. Refusing to probe on the host netns." >&2
    return 1
  fi
  if ! unshare -n ip6tables -L -n >/dev/null 2>&1; then
    echo "magen: ip6tables failed inside unshare -n. The host network was not changed." >&2
    return 1
  fi
}

magen_check_conntrack() {
  local count max
  if [ -n "$fixture" ]; then
    count=$(cat "$fixture/conntrack-count")
    max=$(cat "$fixture/conntrack-max")
  else
    count=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
    max=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
  fi
  echo "magen: nf_conntrack_count=${count} nf_conntrack_max=${max}"
  python3 - "$count" "$max" <<'PY'
import sys
count, limit = int(sys.argv[1]), int(sys.argv[2])
if limit <= 0 or count * 100 > limit * 80:
    sys.stderr.write("magen: conntrack is above 80 percent. Host sysctl was not changed.\n")
    sys.exit(1)
PY
}

magen_check_disk() {
  local avail image avd dump
  image=$(get O5G_DISK_IMAGE_BYTES)
  avd=$(get O5G_DISK_AVD_BYTES)
  dump=$(get O5G_DISK_DUMP_BYTES)
  if [ -n "$fixture" ]; then
    avail=$(cat "$fixture/df-avail")
  else
    avail=$(df -B1 --output=avail /var | awk 'NR == 2 { print $1 }')
  fi
  python3 - "$avail" "$image" "$avd" "$dump" <<'PY'
import sys
avail, image, avd, dump = (int(x) for x in sys.argv[1:])
need = image + avd * 2 + dump
remain = avail - need
floor = 20 * 1024 * 1024 * 1024
print("magen: disk avail=%s need=%s remain=%s floor=%s" % (avail, need, remain, floor))
if remain < floor:
    sys.stderr.write("magen: free space after image, AVD, and dump is under 20 GiB\n")
    sys.exit(1)
PY
}

magen_check_ports() {
  local compose ss
  compose=$(get O5G_COMPOSE_FILE)
  if [ -z "$compose" ]; then
    compose="$(magen_root)/lab/compose/compose.magen.yml"
  fi
  python3 - "$compose" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
blocked = ("5432", "5555", "5900", "3000", "0.0.0.0")
in_ports = False
for raw in text.splitlines():
    if raw.startswith("    ports:"):
        in_ports = True
        continue
    if in_ports and raw.startswith("      - "):
        entry = raw.split("-", 1)[1].strip().strip('"')
        for token in blocked:
            if token in entry:
                sys.stderr.write("magen: published port list contains %s\n" % token)
                sys.exit(1)
        if not entry.startswith("127.0.0.1:"):
            sys.stderr.write("magen: published port is not bound to 127.0.0.1: %s\n" % entry)
            sys.exit(1)
        continue
    if in_ports and raw and not raw.startswith("      "):
        in_ports = False
PY
  if [ -n "$fixture" ]; then
    ss=$(cat "$fixture/ss.txt")
  else
    ss=$(ss -ltn)
  fi
  printf '%s\n' "$ss" | awk '
    $1 == "LISTEN" || $0 ~ /LISTEN/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /:3300$/ || $i ~ /:3301$/) {
          print $i
          exit 1
        }
      }
    }
  ' && return 0
  echo "magen: 127.0.0.1:3300 or 127.0.0.1:3301 is already in use" >&2
  return 1
}

magen_check_protected_containers() {
  local names name
  if [ -n "$fixture" ]; then
    names=$(cat "$fixture/containers.txt")
  else
    names=$(docker ps -a --format '{{.Names}}')
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
      o5g-*) ;;
      *)
        if magen_deletable_name "$name" >/dev/null 2>&1; then
          echo "magen: delete set would include ${name}" >&2
          return 1
        fi
        echo "magen: leaving ${name} in place"
        ;;
    esac
  done <<EOF
$names
EOF
}

magen_subnets() {
  local key
  for key in \
    O5G_CORE_SUBNET O5G_MGMT_SUBNET O5G_S1_SUBNET O5G_UU_SUBNET \
    O5G_EGRESS_SUBNET O5G_DASH_SUBNET O5G_SCREEN_SUBNET \
    ANDROID_UE_UEMU1_SUBNET ANDROID_UE_UEMU2_SUBNET
  do
    printf '%s %s\n' "$key" "$(get "$key")"
  done
}

magen_check_overlap() {
  local proposed existing
  proposed=$(magen_subnets)
  if [ -n "$fixture" ]; then
    existing=$(cat "$fixture/networks.json")
  else
    mapfile -t ids < <(docker network ls -q)
    if [ "${#ids[@]}" -eq 0 ]; then
      existing="[]"
    else
      existing=$(docker network inspect "${ids[@]}" --format '{{json .}}')
    fi
  fi
  PROPOSED="$proposed" EXISTING="$existing" python3 - <<'PY'
import ipaddress, json, os, sys
rows = []
for line in os.environ["PROPOSED"].splitlines():
    if not line.strip():
        continue
    key, value = line.split(" ", 1)
    if not value or "REPLACE_" in value or "CHANGEME" in value:
        sys.stderr.write("magen: %s is empty or still a placeholder\n" % key)
        sys.exit(1)
    rows.append((key, ipaddress.ip_network(value, strict=True)))
for i, (left_k, left) in enumerate(rows):
    for right_k, right in rows[i + 1:]:
        if left.overlaps(right):
            sys.stderr.write("magen: %s overlaps %s\n" % (left_k, right_k))
            sys.exit(1)
raw = os.environ["EXISTING"].strip()
nets = []
if raw.startswith("["):
    data = json.loads(raw)
    for item in data:
        for subnet in item.get("Subnets", []):
            if subnet:
                nets.append((item.get("Name", "?"), ipaddress.ip_network(subnet, strict=False)))
else:
    for blob in raw.splitlines():
        blob = blob.strip()
        if not blob:
            continue
        item = json.loads(blob)
        for cfg in item.get("IPAM", {}).get("Config") or []:
            subnet = cfg.get("Subnet")
            if subnet:
                nets.append((item.get("Name", "?"), ipaddress.ip_network(subnet, strict=False)))
for key, ours in rows:
    for name, other in nets:
        if ours.overlaps(other):
            sys.stderr.write("magen: %s overlaps docker network %s %s\n" % (key, name, other))
            sys.exit(1)
PY
}

magen_check_images() {
  local key value
  for key in O5G_OPEN5GS_IMAGE O5G_MONGO_IMAGE O5G_SRS_IMAGE O5G_ANDROID_IMAGE; do
    value=$(get "$key")
    if magen_is_placeholder "$value" || ! magen_digest_ok "$value"; then
      echo "magen: ${key} must be an image pinned with @sha256" >&2
      return 1
    fi
  done
  local closed=0
  for key in O5G_DASHBOARD_API_IMAGE O5G_DASHBOARD_WEB_IMAGE O5G_POSTGRES_IMAGE; do
    value=$(get "$key")
    if magen_is_placeholder "$value" || ! magen_digest_ok "$value"; then
      closed=1
    fi
  done
  if [ "$closed" -eq 1 ]; then
    echo "magen: dashboard profile is closed until a digest built from the PR #13 tree is pinned. See docs/deploy/magen.md." >&2
    if [ "$with_dashboard" -eq 1 ]; then
      return 1
    fi
  fi
}

magen_check_docker_group
magen_check_kvm
magen_check_tun
magen_check_sctp
magen_check_docker_version
magen_check_ip_forward
magen_check_ip6tables
magen_check_conntrack
magen_check_disk
magen_check_ports
magen_check_protected_containers
magen_check_overlap
magen_check_images
echo "magen: preflight passed"
echo "changed=0"
