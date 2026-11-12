#!/bin/bash
# Bring up one android-ue user. Does not edit Open5GS config and does not
# start the core. Default user is ue1. ue2 stays off unless ANDROID_UE_ALLOW_SECOND=1.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=android-ue-lib.sh
. "$script_dir/android-ue-lib.sh"

env_file=""
user=ue1
with_cgnat=0
with_socks=0
install_upf_route=0
print_services=0
boot_only=0
wipe=0
log_dir=""

usage() {
  echo "usage: android-ue-up.sh --env-file FILE [--user ue1|ue2] [--with-cgnat] [--with-socks-egress] [--install-upf-route] [--boot-only] [--wipe] [--log-dir DIR] [--print-services]" >&2
  exit 2
}

android_ue_ipv4() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

android_ue_install_gtpu_route() {
  local n=$1
  local enb pid s1u gtpu dev got
  enb="l5gd-enb${n}"
  s1u=$(get "UE${n}_ENB_S1U")
  gtpu=$(get ANDROID_UE_SGWU_GTPU_ROUTE)
  android_ue_reject_placeholder "UE${n}_ENB_S1U" "$s1u"
  android_ue_reject_placeholder ANDROID_UE_SGWU_GTPU_ROUTE "$gtpu"
  if ! android_ue_ipv4 "$s1u" || ! android_ue_ipv4 "$gtpu"; then
    echo "android-ue: GTP-U route addresses must be IPv4" >&2
    exit 1
  fi
  if ! command -v nsenter >/dev/null 2>&1; then
    echo "android-ue: nsenter is missing. The eNB container has no NET_ADMIN." >&2
    exit 1
  fi
  pid=$(docker inspect -f '{{.State.Pid}}' "$enb")
  dev=$(nsenter -t "$pid" -n ip -4 -o addr show | awk -v ip="$s1u" 'index($4, ip "/") == 1 { print $2; exit }')
  if [ -z "$dev" ]; then
    echo "android-ue: enb${n} has no interface with its S1-U address" >&2
    exit 1
  fi
  nsenter -t "$pid" -n ip route replace "${gtpu}/32" dev "$dev"
  got=$(nsenter -t "$pid" -n ip route get "$gtpu")
  case "$got" in
    *"dev ${dev}"*) ;;
    *)
      echo "android-ue: ip route get ${gtpu} is not via ${dev}: ${got}" >&2
      exit 1
      ;;
  esac
  echo "android-ue: enb${n} reaches ${gtpu} via ${dev}"
}

android_ue_wait_route() {
  local n=$1
  local cid rc
  cid="l5gd-ue${n}-route"
  if ! rc=$(docker wait "$cid"); then
    echo "android-ue: docker wait ${cid} failed" >&2
    exit 1
  fi
  if [ "$rc" != "0" ]; then
    echo "android-ue: ${cid} exited ${rc}" >&2
    docker logs --tail 50 "$cid" >&2 || true
    exit 1
  fi
  echo "android-ue: ${cid} exited 0"
}

android_ue_ue_pid() {
  local n=$1
  local name
  name="l5gd-ue${n}"
  case "$name" in
    l5gd-ue1|l5gd-ue2) ;;
    *)
      echo "android-ue: refusing to change sysctls outside l5gd-ue1 and l5gd-ue2" >&2
      exit 1
      ;;
  esac
  android_ue_container_pid "$name"
}

android_ue_require_host_tools() {
  if ! command -v nsenter >/dev/null 2>&1; then
    echo "android-ue: nsenter is missing on the host" >&2
    exit 1
  fi
  if ! command -v ip >/dev/null 2>&1; then
    echo "android-ue: ip is missing on the host" >&2
    exit 1
  fi
  if ! command -v sysctl >/dev/null 2>&1; then
    echo "android-ue: sysctl is missing on the host" >&2
    exit 1
  fi
}

android_ue_netns_read() {
  local pid=$1
  local path=$2
  # -m selects the container filesystem so /bin/cat is the container binary.
  # /proc/sys/net itself follows the network namespace of this process.
  nsenter -t "$pid" -n -m /bin/cat "$path"
}

# Host sysctl, target netns only. Do not enter the mount namespace: the
# container /proc/sys is often read-only, while the host one is writable and
# still addresses the caller's network namespace.
android_ue_host_sysctl_set() {
  local pid=$1
  local key=$2
  local value=$3
  local path got
  if ! nsenter -t "$pid" -n sysctl -w "${key}=${value}" >/dev/null; then
    echo "android-ue: host sysctl ${key}=${value} failed" >&2
    return 1
  fi
  path=/proc/sys/$(printf '%s\n' "$key" | tr '.' '/')
  got=$(android_ue_netns_read "$pid" "$path" 2>/dev/null || echo missing)
  if [ "$got" != "$value" ]; then
    echo "android-ue: ${key} is ${got}, expected ${value}" >&2
    return 1
  fi
}

# Interfaces that exist before attach (eth0, and l5gd-screen when present)
# do not inherit all/default. Set them from the host before the route sidecar
# reads them. tun_srsue is set later, after it exists.
android_ue_preset_existing_iface_sysctls() {
  local n=$1
  local pid iface knob
  pid=$(android_ue_ue_pid "$n")
  for key in all default; do
    for knob in accept_ra autoconf forwarding; do
      android_ue_host_sysctl_set "$pid" "net.ipv6.conf.${key}.${knob}" 0
    done
  done
  while IFS= read -r iface; do
    [ -n "$iface" ] || continue
    if [ "$iface" = lo ] || [ "$iface" = tun_srsue ]; then
      continue
    fi
    for knob in accept_ra autoconf forwarding; do
      android_ue_host_sysctl_set "$pid" "net.ipv6.conf.${iface}.${knob}" 0
    done
  done < <(nsenter -t "$pid" -n ip -o link show | awk -F': ' '{ print $2 }' | cut -d@ -f1)
  echo "android-ue: host set accept_ra, autoconf, and forwarding on existing ue${n} interfaces"
}

android_ue_require_ipv6() {
  local n=$1
  local pid link addrs iface knob val key
  android_ue_require_host_tools
  pid=$(android_ue_ue_pid "$n")
  if ! nsenter -t "$pid" -n ip -6 addr show dev lo | grep -q 'inet6 ::1'; then
    echo "android-ue: ::1 is missing on lo in the ue${n} netns" >&2
    exit 1
  fi
  link=$(nsenter -t "$pid" -n ip -o link show dev dummy0 2>/dev/null || true)
  if ! android_ue_link_is_up "$link"; then
    echo "android-ue: ue${n} dummy0 is not UP" >&2
    exit 1
  fi
  addrs=$(nsenter -t "$pid" -n ip -6 -o addr show dev dummy0 scope global 2>/dev/null || true)
  if ! printf '%s\n' "$addrs" | android_ue_dummy0_ula_ok; then
    echo "android-ue: ue${n} dummy0 has no UP non-tentative ULA. fe80 does not replace it." >&2
    exit 1
  fi
  if ! nsenter -t "$pid" -n ip -6 route show | grep -q 'unreachable default'; then
    echo "android-ue: ue${n} is missing the unreachable IPv6 default route" >&2
    exit 1
  fi
  if nsenter -t "$pid" -n ip -6 route show default | grep -v 'unreachable' | grep -q .; then
    echo "android-ue: ue${n} still has a usable IPv6 default route" >&2
    exit 1
  fi
  for key in all default; do
    for knob in accept_ra autoconf forwarding; do
      android_ue_host_sysctl_set "$pid" "net.ipv6.conf.${key}.${knob}" 0
    done
    android_ue_host_sysctl_set "$pid" "net.ipv6.conf.${key}.disable_ipv6" 0
  done
  android_ue_host_sysctl_set "$pid" "net.ipv6.conf.lo.disable_ipv6" 0
  android_ue_host_sysctl_set "$pid" "net.ipv6.conf.dummy0.disable_ipv6" 0
  while IFS= read -r iface; do
    [ -n "$iface" ] || continue
    if [ "$iface" = lo ]; then
      continue
    fi
    for knob in accept_ra autoconf forwarding; do
      android_ue_host_sysctl_set "$pid" "net.ipv6.conf.${iface}.${knob}" 0
    done
  done < <(nsenter -t "$pid" -n ip -o link show | awk -F': ' '{ print $2 }' | cut -d@ -f1)
  for key in all default lo dummy0; do
    val=$(android_ue_netns_read "$pid" "/proc/sys/net/ipv6/conf/${key}/disable_ipv6" 2>/dev/null || echo missing)
    if [ "$val" != "0" ]; then
      echo "android-ue: disable_ipv6 on ${key} is ${val}, expected 0" >&2
      exit 1
    fi
  done
  for iface in $(nsenter -t "$pid" -n ip -o link show | awk -F': ' '{ print $2 }' | cut -d@ -f1); do
    if [ "$iface" = "lo" ]; then
      continue
    fi
    for knob in accept_ra autoconf forwarding; do
      val=$(android_ue_netns_read "$pid" "/proc/sys/net/ipv6/conf/${iface}/${knob}")
      if [ "$val" != "0" ]; then
        echo "android-ue: ${knob} on ${iface} is ${val}, expected 0" >&2
        exit 1
      fi
    done
  done
  for chain in ANDROID_UE_GUARD ANDROID_UE_IN4; do
    if ! nsenter -t "$pid" -n iptables -S "$chain" >/dev/null 2>&1; then
      echo "android-ue: iptables chain ${chain} is missing in the UE netns" >&2
      exit 1
    fi
  done
  echo "android-ue: ue${n} has ::1, a dummy0 ULA, and IPv6 is fail-closed"
}

android_ue_install_ip6_filter() {
  local n=$1
  local pid rendered
  if [ "${ANDROID_UE_IPV6_NO_FILTER_OK:-0}" = "1" ]; then
    echo "android-ue: ANDROID_UE_IPV6_NO_FILTER_OK=1, not installing the IPv6 filter"
    return 0
  fi
  if ! command -v nft >/dev/null 2>&1; then
    echo "android-ue: nft is missing on the host. Refusing to continue without an IPv6 filter." >&2
    exit 1
  fi
  pid=$(docker inspect -f '{{.State.Pid}}' "l5gd-ue${n}")
  rendered=$(mktemp)
  android_ue_render_ip6_nft >"$rendered"
  nsenter -t "$pid" -n nft delete table ip6 android_ue >/dev/null 2>&1 || true
  if ! nsenter -t "$pid" -n nft -f "$rendered"; then
    echo "android-ue: nft IPv6 filter failed in the ue${n} netns. The srsRAN image ip6tables is not used." >&2
    rm -f "$rendered"
    exit 1
  fi
  rm -f "$rendered"
  if ! nsenter -t "$pid" -n nft list table ip6 android_ue | grep -q 'hook input'; then
    echo "android-ue: nft table ip6 android_ue is missing after install" >&2
    exit 1
  fi
  echo "android-ue: IPv6 filter installed with nft in the ue${n} netns"
}

android_ue_boot_diag() {
  local n=$1
  local pid
  pid=$(docker inspect -f '{{.State.Pid}}' "l5gd-ue${n}" 2>/dev/null || true)
  echo "android-ue: emulator log:" >&2
  docker logs --tail 80 "l5gd-android${n}" >&2 || true
  echo "android-ue: IPv6 addresses in the ue${n} netns:" >&2
  if [ -n "$pid" ]; then
    nsenter -t "$pid" -n ip -6 addr >&2 || true
    nsenter -t "$pid" -n getent ahosts ::1 >&2 || true
  fi
  echo "android-ue: host /dev/kvm:" >&2
  ls -l /dev/kvm >&2 || true
  echo "android-ue: AI_ADDRCONFIG and emulator identity:" >&2
  docker exec "l5gd-android${n}" python3 -c 'import socket; socket.getaddrinfo("::1", 5554, type=socket.SOCK_STREAM, flags=socket.AI_ADDRCONFIG)' >&2 || true
  docker exec "l5gd-android${n}" sh -c 'ls -l /dev/kvm; id; ps -o user,uid,gid,args; emulator -accel-check' >&2 || true
}

android_ue_accel_check() {
  local n=$1
  if ! docker exec "l5gd-android${n}" emulator -accel-check; then
    echo "android-ue: emulator -accel-check failed" >&2
    android_ue_boot_diag "$n"
    exit 1
  fi
}

android_ue_wait_boot() {
  local n=$1
  if ! docker inspect -f '{{.State.Running}}' "l5gd-android${n}" 2>/dev/null | grep -qx true; then
    echo "android-ue: android${n} is not running" >&2
    exit 1
  fi
  echo "android-ue: android${n} is running. The boot gate already ran. The modem ::1 anchor stays off."
}

android_ue_enable_ip_forward() {
  local n=$1
  local pid subnet chain nat_rules fwd_rules in4_rules policy_rules
  pid=$(android_ue_ue_pid "$n")
  subnet=$(get "ANDROID_UE_UEMU${n}_SUBNET")
  for chain in ANDROID_UE_FWD ANDROID_UE_IN4 ANDROID_UE_GUARD; do
    if ! nsenter -t "$pid" -n iptables -S "$chain" >/dev/null 2>&1; then
      echo "android-ue: iptables chain ${chain} is missing; not enabling ip_forward" >&2
      exit 1
    fi
  done
  if ! nat_rules=$(nsenter -t "$pid" -n iptables -t nat -S ANDROID_UE_NAT); then
    echo "android-ue: nat chain ANDROID_UE_NAT is missing; not enabling ip_forward" >&2
    exit 1
  fi
  fwd_rules=$(nsenter -t "$pid" -n iptables -S ANDROID_UE_FWD)
  in4_rules=$(nsenter -t "$pid" -n iptables -S ANDROID_UE_IN4)
  policy_rules=$(nsenter -t "$pid" -n iptables -S)
  if ! grep -F -q -- 'MASQUERADE' <<< "$nat_rules"; then
    echo "android-ue: nat chain ANDROID_UE_NAT is missing MASQUERADE; not enabling ip_forward" >&2
    exit 1
  fi
  if ! grep -F -q -- '--clamp-mss-to-pmtu' <<< "$fwd_rules"; then
    echo "android-ue: ANDROID_UE_FWD is missing TCPMSS; not enabling ip_forward" >&2
    exit 1
  fi
  if ! grep -F -q -- "-d ${subnet} " <<< "$in4_rules"; then
    echo "android-ue: ANDROID_UE_IN4 does not drop new packets toward ${subnet}; not enabling ip_forward" >&2
    exit 1
  fi
  if ! grep -F -q -- '-P FORWARD DROP' <<< "$policy_rules"; then
    echo "android-ue: FORWARD policy is not DROP; not enabling ip_forward" >&2
    exit 1
  fi
  if ! android_ue_host_sysctl_set "$pid" net.ipv4.ip_forward 1; then
    exit 1
  fi
  echo "android-ue: ue${n} ip_forward is 1 after the gateway chains were verified"
}

android_ue_phase_b_attach() {
  local n=$1
  local apid gw probe
  gw=$(get "ANDROID_UE_UEMU${n}_GW")
  apid=$(android_ue_container_pid "l5gd-android${n}")
  if ! nsenter -t "$apid" -n ip route replace default via "$gw"; then
    echo "android-ue: could not set the android${n} default route via ${gw}" >&2
    exit 1
  fi
  probe=$(nsenter -t "$apid" -n ip route get 1.1.1.1)
  case "$probe" in
    *"via ${gw}"*) ;;
    *)
      echo "android-ue: android${n} default is not via ${gw}: ${probe}" >&2
      exit 1
      ;;
  esac
  echo "android-ue: android${n} default route is via ${gw}. Name lookup uses ANDROID_UE_DNS through the EPC."
}

android_ue_prepare_extra_flags() {
  local image=$1
  local flags=$2
  local dns=$3
  local help
  flags=$(android_ue_apply_dns_flag "$flags" "$dns")
  case "$flags" in
    *-no-metrics*)
      if help=$(docker run --rm --network none --entrypoint emulator "$image" -help-all 2>&1); then
        if ! android_ue_help_has_metrics "$help"; then
          echo "android-ue: this emulator does not advertise -no-metrics; removing it" >&2
          flags=$(android_ue_drop_metrics_flag "$flags")
        fi
      else
        echo "android-ue: could not probe emulator -help-all; EXTRA_FLAGS left unchanged" >&2
      fi
      ;;
  esac
  printf '%s\n' "$flags"
}

android_ue_measure_boot() {
  local n=$1
  local adb_port use_log_dir log_file timeout deadline completed state stable elapsed
  local boot_seconds stable_ok
  adb_port=$(android_ue_adb_host_port "$n")
  use_log_dir=${log_dir:-${ANDROID_UE_LOG_DIR:-/tmp/open5g-android-boot}}
  mkdir -p -- "$use_log_dir"
  chmod 0700 "$use_log_dir"
  log_file="${use_log_dir}/android${n}-boot.log"
  : >"$log_file"
  if ! command -v adb >/dev/null 2>&1; then
    echo "android-ue: adb is not installed on this host" >&2
    exit 1
  fi
  # Gate is 600s. ANDROID_UE_BOOT_TIMEOUT is the image watcher default.
  # ANDROID_UE_BOOT_GATE=0 does not skip --boot-only.
  timeout=600
  if [ -z "${boot_started:-}" ]; then
    boot_started=$(date +%s)
  fi
  deadline=$((SECONDS + timeout))
  completed=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    adb connect "127.0.0.1:${adb_port}" >/dev/null 2>&1 || true
    completed=$(adb -s "127.0.0.1:${adb_port}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
    if [ "$completed" = "1" ]; then
      break
    fi
    sleep 5
  done
  boot_seconds=$(( $(date +%s) - boot_started ))
  if [ "$completed" != "1" ]; then
    echo "android-ue: sys.boot_completed was not 1 within ${timeout}s" | tee -a "$log_file" >&2
    docker logs --tail 80 "l5gd-android${n}" >>"$log_file" 2>&1 || true
    exit 1
  fi
  stable=${ANDROID_UE_ADB_STABLE:-120}
  if ! printf '%s\n' "$stable" | grep -Eq '^[0-9]+$'; then
    echo "android-ue: ANDROID_UE_ADB_STABLE must be a number of seconds" >&2
    exit 1
  fi
  stable_ok=1
  elapsed=0
  while [ "$elapsed" -lt "$stable" ]; do
    state=$(adb -s "127.0.0.1:${adb_port}" get-state 2>/dev/null | tr -d '\r' || true)
    if [ "$state" != "device" ]; then
      stable_ok=0
      echo "android-ue: adb state is ${state:-missing} after ${elapsed}s" | tee -a "$log_file" >&2
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  {
    echo "=== boot_progress logcat ==="
    adb -s "127.0.0.1:${adb_port}" shell logcat -b events -d | grep boot_progress || true
    echo "=== dmesg ==="
    adb -s "127.0.0.1:${adb_port}" shell dmesg | grep -E 'boot_progress|Booting Linux' || true
  } >>"$log_file" 2>&1 || true
  echo "android-ue: sys.boot_completed=1 in ${boot_seconds}s on 127.0.0.1:${adb_port}" | tee -a "$log_file"
  if [ "$stable_ok" -eq 1 ]; then
    echo "android-ue: adb stayed device for ${stable}s" | tee -a "$log_file"
  fi
  echo "android-ue: boot_progress log ${log_file}" | tee -a "$log_file"
  echo "android-ue: modem errors for ::1 and a guest without egress are expected on this boot" | tee -a "$log_file"
  if [ "$stable_ok" -ne 1 ]; then
    exit 1
  fi
}

android_ue_boot_only() {
  local n=$1
  local allow image kvm_gid host_kvm_gid mem_raw limit_raw mem_mib limit_mib flags dns
  local subnet gw android bridge other_subnet persist avd_dir boot_tmp isolated_file persist_file
  local -a overlap
  if [ "$user" = "ue2" ]; then
    allow=$(get ANDROID_UE_ALLOW_SECOND)
    if [ "$allow" != 1 ]; then
      echo "android-ue: ue2 is off until ANDROID_UE_ALLOW_SECOND=1. One emulator is the cap for this guest." >&2
      exit 1
    fi
  fi
  if [ ! -e /dev/kvm ]; then
    echo "android-ue: /dev/kvm is missing. Nested KVM is a Lab Ops prerequisite." >&2
    exit 1
  fi
  image=$(get ANDROID_UE_ANDROID_IMAGE)
  if [ -z "$image" ]; then
    image=open5g-android-emulator:local
  fi
  if ! android_ue_android_image_ok "$image"; then
    echo "android-ue: ANDROID_UE_ANDROID_IMAGE must be open5g-android-emulator:local or include @sha256" >&2
    exit 1
  fi
  if [ "$image" = "open5g-android-emulator:local" ]; then
    local pin actual
    pin=$(get ANDROID_UE_ANDROID_IMAGE_ID)
    android_ue_reject_placeholder ANDROID_UE_ANDROID_IMAGE_ID "$pin"
    actual=$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null || true)
    if ! android_ue_image_id_ok "$pin" "$actual"; then
      echo "android-ue: ${image} id ${actual:-missing} does not match ANDROID_UE_ANDROID_IMAGE_ID" >&2
      exit 1
    fi
  fi
  kvm_gid=$(get ANDROID_UE_KVM_GID)
  host_kvm_gid=$(stat -c %g /dev/kvm)
  if [ -z "$kvm_gid" ] || printf '%s\n' "$kvm_gid" | grep -Eq 'REPLACE_|CHANGEME'; then
    kvm_gid=$host_kvm_gid
    echo "android-ue: ANDROID_UE_KVM_GID taken from stat /dev/kvm (${kvm_gid})"
  fi
  if ! android_ue_kvm_gid_ok "$kvm_gid" "$host_kvm_gid"; then
    echo "android-ue: ANDROID_UE_KVM_GID must be a non-zero number and equal ${host_kvm_gid} from stat /dev/kvm" >&2
    exit 1
  fi
  mem_raw=$(get ANDROID_UE_MEMORY)
  limit_raw=$(get ANDROID_UE_MEM_LIMIT)
  if [ -z "$limit_raw" ]; then
    limit_raw=4096m
  fi
  if ! mem_mib=$(android_ue_mib "$mem_raw"); then
    echo "android-ue: ANDROID_UE_MEMORY is not a size in MiB" >&2
    exit 1
  fi
  if ! limit_mib=$(android_ue_mib "$limit_raw"); then
    echo "android-ue: ANDROID_UE_MEM_LIMIT is not a size" >&2
    exit 1
  fi
  if [ "$limit_mib" -lt $((mem_mib + 1536)) ]; then
    echo "android-ue: ANDROID_UE_MEM_LIMIT (${limit_mib} MiB) is below ANDROID_UE_MEMORY (${mem_mib} MiB) plus 1536 MiB headroom" >&2
    exit 1
  fi
  flags=$(get ANDROID_UE_EXTRA_FLAGS)
  case "$flags" in
    *partition-size=*)
      echo "android-ue: ANDROID_UE_EXTRA_FLAGS uses -partition-size= which api-33 rejects. Use -partition-size <MiB>." >&2
      exit 1
      ;;
  esac
  dns=$(get ANDROID_UE_DNS)
  if [ "$boot_only" -eq 1 ]; then
    android_ue_dns_ok boot-only "$dns"
  else
    android_ue_dns_ok integrated "$dns"
  fi
  subnet=$(get "ANDROID_UE_UEMU${n}_SUBNET")
  gw=$(get "ANDROID_UE_UEMU${n}_GW")
  android=$(get "ANDROID_UE_UEMU${n}_ANDROID")
  bridge=$(get "ANDROID_UE_UEMU${n}_BRIDGE")
  if [ "$n" = 1 ]; then
    other_subnet=$(get ANDROID_UE_UEMU2_SUBNET)
  else
    other_subnet=$(get ANDROID_UE_UEMU1_SUBNET)
  fi
  overlap=()
  overlap+=("pool=$(get UE_POOL)")
  overlap+=("uu=$(get UE1_UU)" "uu=$(get UE1_ENB_UU)" "uu=$(get UE2_UU)" "uu=$(get UE2_ENB_UU)")
  overlap+=("pdn=$(get UE1_ADDR)" "pdn=$(get UE2_ADDR)")
  overlap+=("cgnat=$(get CGNAT_SGI_ADDR)" "cgnat=$(get CGNAT_EGRESS_ADDR)" "cgnat=$(get CGNAT_SNAT_ADDR)")
  android_ue_uemu_check "$subnet" "$gw" "$android" "$bridge" "$other_subnet" "${overlap[@]}"
  flags=$(android_ue_prepare_extra_flags "$image" "$flags" "$dns")
  export ANDROID_UE_EXTRA_FLAGS="$flags"
  export ANDROID_UE_KVM_GID="$kvm_gid"
  export ANDROID_UE_ANDROID_IMAGE="$image"
  persist=$(get ANDROID_UE_AVD_PERSIST)
  boot_tmp=$(mktemp -d)
  trap 'rm -rf "$boot_tmp"' EXIT
  isolated_file="${boot_tmp}/isolated.yml"
  persist_file=""
  cat >"$isolated_file" <<EOF
services:
  android${n}:
    environment:
      ANDROID_UE_ISOLATED: "1"
EOF
  if [ "$persist" = "1" ]; then
    avd_dir=$(get "ANDROID_UE_AVD${n}_DIR")
    android_ue_require_set "ANDROID_UE_AVD${n}_DIR" "$avd_dir"
    case "$avd_dir" in
      /*)
        ;;
      *)
        echo "android-ue: ANDROID_UE_AVD${n}_DIR must be an absolute path" >&2
        exit 1
        ;;
    esac
    case "$avd_dir" in
      *:*|*[[:space:]]*|*/.android|*/.android/*)
        echo "android-ue: ANDROID_UE_AVD${n}_DIR must not be .android or contain a colon or space" >&2
        exit 1
        ;;
    esac
    if [ "$wipe" -eq 1 ]; then
      android_ue_avd_wipe "$avd_dir"
    else
      android_ue_avd_sanitize "$avd_dir"
    fi
    persist_file="${boot_tmp}/avd.yml"
    cat >"$persist_file" <<EOF
services:
  android${n}:
    environment:
      ANDROID_AVD_HOME: /opt/open5g-avd
    volumes:
      - ${avd_dir}:/opt/open5g-avd
EOF
    echo "android-ue: AVD persistence is on. userdata, accounts.db, and adbkey are removed before boot."
  elif [ "$wipe" -eq 1 ]; then
    docker rm -f -v "l5gd-android${n}" >/dev/null 2>&1 || true
  fi
  boot_started=$(date +%s)
  android_ue_boot_compose "$root" "$env_file" "$isolated_file" "$persist_file" up -d "android${n}"
  android_ue_measure_boot "$n"
  if [ "$boot_only" -eq 1 ]; then
    echo "android-ue: --boot-only starts android${n} on $(android_ue_uemu_network_name "$n"). Phase B is not attached."
  else
    echo "android-ue: android${n} boot finished on $(android_ue_uemu_network_name "$n"). Phase B continues."
  fi
}

android_ue_boot_compose() {
  local root=$1
  local env_file=$2
  local isolated_file=$3
  local persist_file=$4
  shift 4
  local -a compose files
  if [ -n "${ANDROID_UE_COMPOSE_BIN:-}" ]; then
    # shellcheck disable=SC2206
    compose=($ANDROID_UE_COMPOSE_BIN)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose=(docker-compose)
  else
    compose=(docker compose)
  fi
  files=(
    -f "$root/lab/compose/docker-compose.android-emulator.standalone.yml"
    -f "$isolated_file"
  )
  if [ -n "$persist_file" ]; then
    files+=(-f "$persist_file")
  fi
  "${compose[@]}" "${files[@]}" --env-file "$env_file" --profile android-standalone "$@"
}

android_ue_probe_sgi() {
  local n=$1
  local ue pid probe
  ue="l5gd-ue${n}"
  probe=$(get ANDROID_UE_SGI_PROBE)
  android_ue_reject_placeholder ANDROID_UE_SGI_PROBE "$probe"
  if ! android_ue_ipv4 "$probe"; then
    echo "android-ue: ANDROID_UE_SGI_PROBE must be an IPv4 address" >&2
    exit 1
  fi
  pid=$(docker inspect -f '{{.State.Pid}}' "$ue")
  if ! nsenter -t "$pid" -n ping -c 3 -I tun_srsue "$probe"; then
    echo "android-ue: SGi ping from ue${n} failed" >&2
    nsenter -t "$pid" -n ip -4 route >&2 || true
    exit 1
  fi
  echo "android-ue: SGi ping from ue${n} succeeded"
}

if [ "${ANDROID_UE_SOURCE_ONLY:-0}" = 1 ]; then
  return 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      [ "$#" -gt 0 ] || usage
      env_file=$1
      ;;
    --user)
      shift
      [ "$#" -gt 0 ] || usage
      user=$1
      ;;
    --with-cgnat) with_cgnat=1 ;;
    --with-socks-egress) with_socks=1 ;;
    --install-upf-route) install_upf_route=1 ;;
    --boot-only) boot_only=1 ;;
    --wipe) wipe=1 ;;
    --log-dir)
      shift
      [ "$#" -gt 0 ] || usage
      log_dir=$1
      ;;
    --print-services) print_services=1 ;;
    *) usage ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
  usage
fi
case "$user" in
  ue1|ue2) ;;
  *)
    echo "android-ue: user must be ue1 or ue2" >&2
    exit 2
    ;;
esac

root=$(android_ue_root)
state=$(android_ue_state_dir)
get() { android_ue_env_get "$env_file" "$1"; }
n=${user#ue}

if [ "$with_socks" -eq 1 ]; then
  with_cgnat=1
fi

if [ "$print_services" -eq 1 ]; then
  if [ "$boot_only" -eq 1 ]; then
    printf '%s\n' "android${n}"
    exit 0
  fi
  printf '%s\n' "android${n}" "ue${n}" "enb${n}" "ue${n}-route"
  if [ "$with_cgnat" -eq 1 ]; then
    echo cgnat
  fi
  if [ "$with_socks" -eq 1 ]; then
    printf '%s\n' egress egress-dns
  fi
  exit 0
fi

if [ "$boot_only" -eq 1 ]; then
  if [ "$with_cgnat" -eq 1 ] || [ "$with_socks" -eq 1 ] || [ "$install_upf_route" -eq 1 ]; then
    echo "android-ue: --boot-only does not start cgnat, the SOCKS tunnel, or the UPF route" >&2
    exit 2
  fi
  android_ue_boot_only "$n"
  exit 0
fi

mkdir -p "$state"

if [ "$user" = "ue2" ]; then
  allow=$(get ANDROID_UE_ALLOW_SECOND)
  if [ "$allow" != 1 ]; then
    echo "android-ue: ue2 is off until ANDROID_UE_ALLOW_SECOND=1. One emulator is the cap for this guest." >&2
    exit 1
  fi
fi

android_ue_reject_placeholder "UE${n}_IMSI" "$(get "UE${n}_IMSI")"
android_ue_reject_placeholder "UE${n}_KI" "$(get "UE${n}_KI")"
android_ue_reject_placeholder "UE${n}_OPC" "$(get "UE${n}_OPC")"
android_ue_reject_placeholder "UE${n}_IMEI" "$(get "UE${n}_IMEI")"
imsi=$(get "UE${n}_IMSI")
ki=$(get "UE${n}_KI")
opc=$(get "UE${n}_OPC")
imei=$(get "UE${n}_IMEI")
if ! printf '%s\n' "$imsi" | grep -Eq '^[0-9]{15}$'; then
  echo "android-ue: UE${n}_IMSI must be 15 digits" >&2
  exit 1
fi
if ! printf '%s\n' "$ki" | grep -Eq '^[0-9A-Fa-f]{32}$'; then
  echo "android-ue: UE${n}_KI must be 32 hex characters" >&2
  exit 1
fi
if ! printf '%s\n' "$opc" | grep -Eq '^[0-9A-Fa-f]{32}$'; then
  echo "android-ue: UE${n}_OPC must be 32 hex characters" >&2
  exit 1
fi
if ! printf '%s\n' "$imei" | grep -Eq '^[0-9]{15}$'; then
  echo "android-ue: UE${n}_IMEI must be 15 digits" >&2
  exit 1
fi
if [ ! -e /dev/kvm ]; then
  echo "android-ue: /dev/kvm is missing. Nested KVM is a Lab Ops prerequisite." >&2
  exit 1
fi
android_image=$(get ANDROID_UE_ANDROID_IMAGE)
if [ -z "$android_image" ]; then
  android_image=open5g-android-emulator:local
fi
if ! android_ue_android_image_ok "$android_image"; then
  echo "android-ue: ANDROID_UE_ANDROID_IMAGE must be open5g-android-emulator:local or include @sha256" >&2
  exit 1
fi
kvm_gid=$(get ANDROID_UE_KVM_GID)
android_ue_reject_placeholder ANDROID_UE_KVM_GID "$kvm_gid"
host_kvm_gid=$(stat -c %g /dev/kvm)
if ! android_ue_kvm_gid_ok "$kvm_gid" "$host_kvm_gid"; then
  echo "android-ue: ANDROID_UE_KVM_GID must be a non-zero number and equal ${host_kvm_gid} from stat /dev/kvm" >&2
  exit 1
fi
mem_raw=$(get ANDROID_UE_MEMORY)
limit_raw=$(get ANDROID_UE_MEM_LIMIT)
if [ -z "$limit_raw" ]; then
  limit_raw=4096m
fi
if ! mem_mib=$(android_ue_mib "$mem_raw"); then
  echo "android-ue: ANDROID_UE_MEMORY is not a size in MiB" >&2
  exit 1
fi
if ! limit_mib=$(android_ue_mib "$limit_raw"); then
  echo "android-ue: ANDROID_UE_MEM_LIMIT is not a size" >&2
  exit 1
fi
if [ "$limit_mib" -lt $((mem_mib + 1536)) ]; then
  echo "android-ue: ANDROID_UE_MEM_LIMIT (${limit_mib} MiB) is below ANDROID_UE_MEMORY (${mem_mib} MiB) plus 1536 MiB headroom" >&2
  exit 1
fi
flags=$(get ANDROID_UE_EXTRA_FLAGS)
case "$flags" in
  *partition-size=*)
    echo "android-ue: ANDROID_UE_EXTRA_FLAGS uses -partition-size= which api-33 rejects. Use -partition-size <MiB>." >&2
    exit 1
    ;;
esac

need_net() {
  local name=$1
  if ! docker network inspect "$name" >/dev/null 2>&1; then
    echo "android-ue: docker network ${name} is missing" >&2
    return 1
  fi
}

need_net "$(get ANDROID_UE_S1MME_NETWORK)"
need_net "$(get ANDROID_UE_S1U_NETWORK)"
need_net "$(get ANDROID_UE_UU_NETWORK)"
need_net "$(get ANDROID_UE_SGI_NETWORK)"
egress=$(get ANDROID_UE_EGRESS_NETWORK)
android_ue_reject_placeholder ANDROID_UE_EGRESS_NETWORK "$egress"
if ! docker network inspect "$egress" >/dev/null 2>&1; then
  echo "android-ue: create the egress network before up. Until Netdrive approves egress, create it internal so it cannot reach the internet:" >&2
  echo "  docker network create --internal ${egress}" >&2
  exit 1
fi

if [ "$with_socks" -eq 1 ]; then
  android_ue_reject_placeholder ANDROID_UE_TUN2SOCKS_IMAGE "$(get ANDROID_UE_TUN2SOCKS_IMAGE)"
  android_ue_reject_placeholder ANDROID_UE_DNS_IMAGE "$(get ANDROID_UE_DNS_IMAGE)"
  android_ue_reject_placeholder ANDROID_UE_SOCKS_ADDR "$(get ANDROID_UE_SOCKS_ADDR)"
  android_ue_reject_placeholder ANDROID_UE_LAB_SUBNET "$(get ANDROID_UE_LAB_SUBNET)"
  socks_addr=$(get ANDROID_UE_SOCKS_ADDR)
  if ! printf '%s\n' "$socks_addr" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:1080$'; then
    echo "android-ue: ANDROID_UE_SOCKS_ADDR must look like an IPv4 address and port 1080" >&2
    exit 1
  fi
  if ! printf '%s\n' "$(get ANDROID_UE_LAB_SUBNET)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
    echo "android-ue: ANDROID_UE_LAB_SUBNET must be an IPv4 prefix" >&2
    exit 1
  fi
  socks_internal=$(docker network inspect -f '{{.Internal}}' "$egress")
  if [ "$socks_internal" != "true" ]; then
    echo "android-ue: the egress network must stay internal for the SOCKS path" >&2
    exit 1
  fi
  export ANDROID_UE_SOCKS_PROFILE=1
  gw=${socks_addr%%:*}
  if ! bash "$script_dir/android-ue-tunnel.sh" check-listen --gw "$gw"; then
    echo "android-ue: port 1080 is not listening only on ${gw}" >&2
    exit 1
  fi
fi

if [ "$install_upf_route" -eq 1 ] && [ "$with_socks" -eq 1 ]; then
  ue_addr=$(get "UE${n}_ADDR")
  android_ue_reject_placeholder "UE${n}_ADDR" "$ue_addr"
  if [ "$(get UE_POOL)" != "${ue_addr}/32" ]; then
    echo "android-ue: UE_POOL must be ${ue_addr}/32 so other UEs are not steered to the laptop" >&2
    exit 1
  fi
fi

if ! docker inspect -f '{{.State.Running}}' "l5gd-android${n}" 2>/dev/null | grep -qx true; then
  android_ue_boot_only "$n"
fi
echo "android-ue: starting ${user}. Core config is not modified."
android_ue_require_host_tools
android_ue_compose "$root" "$env_file" up -d "ue${n}"
android_ue_preset_existing_iface_sysctls "$n"
android_ue_compose "$root" "$env_file" up -d \
  "enb${n}" "ue${n}-route"
android_ue_wait_route "$n"
android_ue_enable_ip_forward "$n"
android_ue_require_ipv6 "$n"
android_ue_install_ip6_filter "$n"
android_ue_install_gtpu_route "$n"
android_ue_probe_sgi "$n"
android_ue_phase_b_attach "$n"
android_ue_wait_boot "$n"

if [ "$with_cgnat" -eq 1 ]; then
  android_ue_reject_placeholder ANDROID_UE_CGNAT_IMAGE "$(get ANDROID_UE_CGNAT_IMAGE)"
  android_ue_compose "$root" "$env_file" up -d cgnat
  ready=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    if docker exec l5gd-cgnat test -f /tmp/cgnat.if; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" -ne 1 ]; then
    echo "android-ue: cgnat did not write /tmp/cgnat.if" >&2
    exit 1
  fi
  echo "android-ue: cgnat policy is loaded. No per-UE SNAT rule is added."
fi

if [ "$with_socks" -eq 1 ]; then
  android_ue_compose "$root" "$env_file" up -d egress
  tun_ready=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    if docker exec l5gd-cgnat ip -4 route show default | grep -q 'dev tun0'; then
      tun_ready=1
      break
    fi
    sleep 1
  done
  if [ "$tun_ready" -ne 1 ]; then
    echo "android-ue: tun0 is not the default route in the cgnat netns" >&2
    exit 1
  fi
  dns_upstream=$(get ANDROID_UE_DNS_UPSTREAM)
  if [ -z "$dns_upstream" ]; then
    dns_upstream=1.1.1.1
  fi
  ANDROID_UE_DNS_UPSTREAM="$dns_upstream" \
    bash "$script_dir/render-corefile.sh" >"$state/Corefile"
  android_ue_compose "$root" "$env_file" up -d egress-dns
  echo "android-ue: SOCKS egress is up. The egress docker network stays internal."
fi

if [ "$install_upf_route" -eq 1 ]; then
  flag=$(get ANDROID_UE_INSTALL_UPF_ROUTE)
  if [ "$flag" != 1 ]; then
    echo "android-ue: --install-upf-route also needs ANDROID_UE_INSTALL_UPF_ROUTE=1" >&2
    exit 1
  fi
  if [ "$with_socks" -ne 1 ]; then
    echo "android-ue: the UPF route is only for the SOCKS test window. Pass --with-socks-egress as well." >&2
    exit 1
  fi
  upf=$(get ANDROID_UE_UPF_CONTAINER)
  android_ue_require_set ANDROID_UE_UPF_CONTAINER "$upf"
  cgnat_ip=$(get CGNAT_SGI_ADDR)
  android_ue_reject_placeholder CGNAT_SGI_ADDR "$cgnat_ip"
  ue_addr=$(get "UE${n}_ADDR")
  tun_cidr=$(docker exec "l5gd-ue${n}" ip -4 -o addr show dev tun_srsue | awk '{ print $4; exit }')
  tun_ip=${tun_cidr%%/*}
  if [ "$tun_ip" != "$ue_addr" ]; then
    echo "android-ue: tun_srsue has ${tun_ip:-no address}; the static UE address is ${ue_addr}" >&2
    exit 1
  fi
  rules=$(docker exec "$upf" ip rule show)
  decision=$(android_ue_upf_rule_decide "$rules" "${ue_addr}/32" "$state/upf-rule.txt")
  if [ "$decision" = "skip" ]; then
    echo "android-ue: UPF policy rule for ${ue_addr}/32 is already installed"
  else
    docker exec "$upf" ip route replace default via "$cgnat_ip" table 1080
    docker exec "$upf" ip rule add from "${ue_addr}/32" lookup 1080 priority 100
    printf 'from %s/32 lookup 1080\n' "$ue_addr" >"$state/upf-rule.txt"
    echo "android-ue: UPF steers only ${ue_addr}/32 via table 1080. The main default route was not changed."
  fi
fi

echo "android-ue: ${user} is up. adb connect $(get "ANDROID_UE_UEMU${n}_ANDROID"):5555, or 127.0.0.1:$(android_ue_adb_host_port "$n"). Core containers were not restarted."
