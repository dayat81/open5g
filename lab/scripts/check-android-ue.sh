#!/bin/bash
# Static checks for the android-ue overlay. Does not start containers or pull images.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"

scripts=(
  lab/scripts/gen-android-ue.sh
  lab/scripts/android-ue-lib.sh
  lab/scripts/android-ue-up.sh
  lab/scripts/android-ue-down.sh
  lab/scripts/android-ue-enb.sh
  lab/scripts/android-ue-route.sh
  lab/scripts/android-ue-seed.sh
  lab/scripts/android-ue-set-addr.sh
  lab/scripts/android-ue-tunnel.sh
  lab/scripts/check-android-ue.sh
  lab/images/android-emulator/build.sh
  lab/images/android-emulator/open5g-preflight.sh
)
sh_scripts=(
  lab/scripts/render-cgnat.sh
  lab/scripts/android-ue-cgnat.sh
  lab/scripts/android-ue-egress.sh
  lab/scripts/android-ue-add-ue.sh
  lab/scripts/render-corefile.sh
)

echo "shellcheck"
shellcheck -x -P SCRIPTDIR "${scripts[@]}"
shellcheck -s sh -x -P SCRIPTDIR "${sh_scripts[@]}"

echo "generator"
lab/scripts/gen-android-ue.sh --check
if lab/scripts/gen-android-ue.sh --count 3 --stdout >/dev/null 2>/tmp/android-ue-cap.err; then
  echo "generator accepted a count above the cap" >&2
  exit 1
fi

echo "placeholders"
example=lab/compose/android-ue.env.example
for key in UE1_IMSI UE1_KI UE1_OPC UE1_IMEI UE2_IMSI UE2_KI UE2_OPC UE2_IMEI \
  ANDROID_UE_CGNAT_IMAGE ANDROID_UE_EGRESS_NETWORK ANDROID_UE_TUN2SOCKS_IMAGE \
  ANDROID_UE_DNS_IMAGE ANDROID_UE_SOCKS_ADDR ANDROID_UE_LAB_SUBNET \
  ANDROID_UE_PGW_DNS UE1_ADDR UE2_ADDR CGNAT_EGRESS_ADDR \
  ANDROID_UE_TUNNEL_USER ANDROID_UE_TUNNEL_PUBKEY \
  ANDROID_UE_SGWU_GTPU_ROUTE ANDROID_UE_SGI_PROBE ANDROID_UE_KVM_GID; do
  value=$(awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$example")
  case "$value" in
    REPLACE_*) ;;
    *)
      echo "example env ${key} must stay a REPLACE_ placeholder" >&2
      exit 1
      ;;
  esac
done

echo "secret scan"
scan_paths=(
  lab/compose/docker-compose.android-ue.optional.yml
  lab/compose/android-ue.env.example
  lab/config/ran/android-ue.conf.template
  lab/config/cgnat
  lab/scripts/gen-android-ue.sh
  lab/scripts/render-cgnat.sh
  lab/scripts/android-ue-cgnat.sh
  lab/scripts/android-ue-egress.sh
  lab/scripts/android-ue-add-ue.sh
  lab/config/cgnat/Corefile.template
  lab/scripts/render-corefile.sh
  lab/scripts/android-ue-enb.sh
  lab/scripts/android-ue-route.sh
  lab/scripts/android-ue-lib.sh
  lab/scripts/android-ue-up.sh
  lab/scripts/android-ue-down.sh
  lab/scripts/android-ue-seed.sh
  lab/scripts/android-ue-set-addr.sh
  lab/scripts/android-ue-tunnel.sh
  lab/scripts/check-android-ue.sh
  docs/integration/android-ue-per-user.md
  docs/deploy/android-ue-lab5g-dev.md
  .github/workflows/android-ue.yml
  lab/images/android-emulator
)
if grep -R -E -n --exclude-dir=.git \
  -e '(^|[^0-9A-Fa-f])[0-9A-Fa-f]{32}([^0-9A-Fa-f]|$)' \
  -e '(^|[^0-9])[0-9]{15}([^0-9]|$)' \
  "${scan_paths[@]}"; then
  echo "found a 32-hex value or a 15-digit IMSI/IMEI in android-ue files" >&2
  exit 1
fi
# shellcheck disable=SC2016
imsi_ph='imsi = ${UE_IMSI}'
# shellcheck disable=SC2016
ki_ph='k = ${UE_KI}'
# shellcheck disable=SC2016
opc_ph='opc = ${UE_OPC}'
if ! grep -qF "$imsi_ph" lab/config/ran/android-ue.conf.template \
  || ! grep -qF "$ki_ph" lab/config/ran/android-ue.conf.template \
  || ! grep -qF "$opc_ph" lab/config/ran/android-ue.conf.template; then
  echo "UE template is missing USIM placeholders" >&2
  exit 1
fi

env_get() {
  awk -F= -v k="$1" '
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ /^[[:space:]]*$/ { next }
    $1 == k { sub(/^[^=]*=/, ""); print; exit }
  ' "$example"
}

syntax_check() {
  local file=$1
  local mode=$2
  python3 - "$file" "$mode" <<'PY'
import sys
path, mode = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
errors = []
if "__" in text:
    errors.append("unreplaced token")
depth = 0
for ch in text:
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth < 0:
            errors.append("unbalanced brace")
            break
if depth != 0:
    errors.append("unbalanced brace")
for needle in (
    "table ip cgnat",
    "policy drop;",
    "oifname \"tun0\"",
    "tcp dport { 80, 443 }",
    "dnat to 127.0.0.1:53",
    "reject with icmp type port-unreachable",
    "ct count over 200",
    "1250 kbytes/second",
    "log prefix \"cgnat-fwd-drop \"",
    "maxseg size set rt mtu",
    "127.0.0.11",
):
    if needle not in text:
        errors.append("missing " + needle)
if "snat to" in text:
    errors.append("unexpected snat")
if "flags all" in text:
    errors.append("log flags include more than metadata")
if errors:
    sys.stderr.write("nft syntax check failed: " + ", ".join(errors) + "\n")
    sys.exit(1)
PY
}

nft_check() {
  local file=$1
  local err
  err=$(mktemp)
  if command -v nft >/dev/null 2>&1; then
    if nft -c -f "$file" 2>"$err"; then
      rm -f "$err"
      echo "nft -c ok ($file)"
      return 0
    fi
    if grep -q "Operation not permitted" "$err"; then
      if sudo nft -c -f "$file" 2>"$err"; then
        rm -f "$err"
        echo "nft -c ok via sudo ($file)"
        return 0
      fi
    fi
    cat "$err" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  echo "nft is not installed; using the syntax checker"
  return 2
}

echo "nftables"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
UE_POOL=$(env_get UE_POOL)
# Documentation prefixes for nft -c. Not lab addresses and not a laptop.
LAB_SUBNET=192.0.2.0/24
SOCKS_ADDR=192.0.2.10
CT_LIMIT=200
export UE_POOL LAB_SUBNET SOCKS_ADDR CT_LIMIT
lab/scripts/render-cgnat.sh lab/config/cgnat/cgnat.nft.template >"$tmp/cgnat.nft"
syntax_check "$tmp/cgnat.nft" rendered
nft_rc=0
nft_check "$tmp/cgnat.nft" || nft_rc=$?
if [ "$nft_rc" -eq 1 ]; then
  exit 1
fi
if [ "$nft_rc" -eq 2 ]; then
  echo "rendered ruleset passed the fallback syntax checker"
fi
meter_line=$(grep -n 'meter ue_bw_out' "$tmp/cgnat.nft" | head -n 1 | cut -d: -f1)
est_line=$(grep -n 'ct state established,related accept' "$tmp/cgnat.nft" | head -n 1 | cut -d: -f1)
if [ -z "$meter_line" ] || [ -z "$est_line" ] || [ "$meter_line" -ge "$est_line" ]; then
  echo "per-UE meter is not before the established rule" >&2
  exit 1
fi
if ! grep -q 'meter ue_bw_in' "$tmp/cgnat.nft"; then
  echo "return-path meter is missing" >&2
  exit 1
fi

echo "emulator DNS"
if grep -q '127.0.0.11' lab/scripts/android-ue-route.sh; then
  echo "UE guard still matches 127.0.0.11 after Docker rewrites the DNS port" >&2
  exit 1
fi
if ! grep -q -- '-dns-server' lab/compose/docker-compose.android-ue.optional.yml; then
  echo "emulator is missing -dns-server" >&2
  exit 1
fi

echo "seed is insert-only"
js=$(lab/scripts/android-ue-seed.sh --print-js)
printf '%s\n' "$js" | grep -q 'insertOne'
printf '%s\n' "$js" | grep -q 'countDocuments({imsi: imsi})'
printf '%s\n' "$js" | grep -q 'ANDROID_UE_SEED_ADDR'
if printf '%s\n' "$js" | grep -Eq 'replaceOne|upsert'; then
  echo "seed program would overwrite an existing subscriber" >&2
  exit 1
fi
if grep -E -q -- '-e ANDROID_UE_SEED_(KI|OPC)=' lab/scripts/android-ue-seed.sh; then
  echo "seed puts Ki or OPc on the docker exec command line" >&2
  exit 1
fi
exec_line=$(ANDROID_UE_SEED_KI=not-in-argv-marker ANDROID_UE_SEED_OPC=also-not-in-argv lab/scripts/android-ue-seed.sh --print-exec)
case "$exec_line" in
  *not-in-argv-marker*|*also-not-in-argv*)
    echo "seed exec line contains a secret value" >&2
    exit 1
    ;;
esac
printf '%s\n' "$exec_line" | grep -q -- '-e ANDROID_UE_SEED_KI'
printf '%s\n' "$js" | grep -q 'ANDROID_UE_SEED_POOL'
printf '%s\n' "$js" | grep -q 'slice.session.ue.addr'
if grep -q 'updateOne' lab/scripts/android-ue-seed.sh; then
  echo "seed is no longer insert-only" >&2
  exit 1
fi

echo "existing subscriber address"
addr_js=$(lab/scripts/android-ue-set-addr.sh --print-js)
printf '%s\n' "$addr_js" | grep -q 'updateOne'
printf '%s\n' "$addr_js" | grep -F -q "\$set"
printf '%s\n' "$addr_js" | grep -q 'modifiedCount'
printf '%s\n' "$addr_js" | grep -q 'ANDROID_UE_SEED_POOL'
printf '%s\n' "$addr_js" | grep -q 'slice.session.ue.addr'
printf '%s\n' "$addr_js" | grep -q 'arrayFilters'
printf '%s\n' "$addr_js" | grep -q 'upsert: false'
if printf '%s\n' "$addr_js" | grep -Eq 'insertOne|upsert: true'; then
  echo "address update would insert a subscriber" >&2
  exit 1
fi
unset_js=$(lab/scripts/android-ue-set-addr.sh --print-unset)
printf '%s\n' "$unset_js" | grep -F -q "\$unset"
printf '%s\n' "$unset_js" | grep -q 'ANDROID_UE_SEED_OLD_ADDR'
printf '%s\n' "$unset_js" | grep -q 'upsert: false'
addr_exec=$(ANDROID_UE_SEED_ADDR=not-in-argv-marker lab/scripts/android-ue-set-addr.sh --print-exec)
case "$addr_exec" in
  *not-in-argv-marker*)
    echo "address update puts the address on the command line" >&2
    exit 1
    ;;
esac

echo "tunnel rollback"
lab/scripts/android-ue-tunnel.sh self-test
grep -q 'android-ue-tunnel.sh" rollback' lab/scripts/android-ue-down.sh
grep -q 'sport = :1080' lab/scripts/android-ue-tunnel.sh
grep -q 'CGNAT_EGRESS_ADDR' lab/scripts/android-ue-tunnel.sh
grep -q 'sshd -T -C' lab/scripts/android-ue-tunnel.sh
grep -q 'ssh.socket' lab/scripts/android-ue-tunnel.sh
grep -q 'permitlisten=' lab/scripts/android-ue-tunnel.sh
grep -q 'without the tunnel options' lab/scripts/android-ue-tunnel.sh
grep -q 'nsenter -t' lab/scripts/android-ue-up.sh
grep -q 'ip route get' lab/scripts/android-ue-up.sh
grep -q 'ping -c 3 -I tun_srsue' lab/scripts/android-ue-up.sh
grep -q 'ANDROID_UE_SGWU_GTPU_ROUTE' lab/scripts/android-ue-up.sh
if grep -q 'ANDROID_UE_UPF_S1U_SUBNET' lab/scripts/android-ue-up.sh lab/scripts/android-ue-down.sh lab/compose/android-ue.env.example; then
  echo "UPF S1-U route is still present" >&2
  exit 1
fi
if grep -E -q 'dev eth[0-9]' lab/scripts/android-ue-up.sh lab/scripts/android-ue-down.sh; then
  echo "eNB route hardcodes an interface name" >&2
  exit 1
fi
gtpu_at=$(grep -n -F "android_ue_install_gtpu_route \"\$n\"" lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
probe_at=$(grep -n -F "android_ue_probe_sgi \"\$n\"" lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
wait_at=$(grep -n -F "android_ue_wait_route \"\$n\"" lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
lo_at=$(grep -n -F "android_ue_require_ipv6 \"\$n\"" lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
boot_at=$(grep -n -F "android_ue_wait_boot \"\$n\"" lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
if [ -z "$wait_at" ] || [ -z "$lo_at" ] || [ -z "$gtpu_at" ] || [ -z "$probe_at" ] || [ -z "$boot_at" ] || [ "$wait_at" -ge "$lo_at" ] || [ "$lo_at" -ge "$gtpu_at" ] || [ "$gtpu_at" -ge "$probe_at" ] || [ "$probe_at" -ge "$boot_at" ]; then
  echo "boot gate is not after the route wait, IPv6 check, and SGi probe" >&2
  exit 1
fi
grep -q 'unreachable default' lab/scripts/android-ue-route.sh
grep -q 'ANDROID_UE_IPV6_NO_FILTER_OK' lab/scripts/android-ue-route.sh
grep -q '16#48' lab/scripts/android-ue-route.sh
grep -q 'ANDROID_UE_BOOT_GATE' lab/scripts/android-ue-up.sh
grep -q 'accept_ra' lab/scripts/android-ue-route.sh
grep -q 'autoconf' lab/scripts/android-ue-route.sh
if grep -F "printf '1" lab/scripts/android-ue-route.sh; then
  echo "route script sets disable_ipv6 to 1" >&2
  exit 1
fi
if ! grep -q -F "printf '0" lab/scripts/android-ue-route.sh; then
  echo "route script does not write disable_ipv6=0" >&2
  exit 1
fi
grep -q 'forwarding' lab/scripts/android-ue-route.sh
grep -q 'accept_ra autoconf forwarding' lab/scripts/android-ue-route.sh
emu_at=$(grep -n -F 'emulator is already running' lab/scripts/android-ue-route.sh | head -n 1 | cut -d: -f1)
lock_at=$(grep -n -x 'android_ue_route_ipv6_lock' lab/scripts/android-ue-route.sh | head -n 1 | cut -d: -f1)
if [ -z "$emu_at" ] || [ -z "$lock_at" ] || [ "$emu_at" -ge "$lock_at" ]; then
  echo "IPv6 lock is not after the emulator-already-running guard" >&2
  exit 1
fi
again_at=$(grep -n -F 'refusing to run the route sidecar again' lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
route_up_at=$(awk '/up -d \\$/ { print NR; exit }' lab/scripts/android-ue-up.sh)
if [ -z "$again_at" ] || [ -z "$route_up_at" ] || [ "$again_at" -ge "$route_up_at" ]; then
  echo "up starts the route sidecar after android is already running" >&2
  exit 1
fi
# shellcheck disable=SC2016
grep -q 'disable_ipv6 on ${key}' lab/scripts/android-ue-up.sh
grep -q 'accept_ra autoconf forwarding' lab/scripts/android-ue-up.sh
grep -q 'ANDROID_UE_IPV6_NO_FILTER_OK:-0' lab/scripts/android-ue-route.sh
grep -q 'dummy0 type dummy' lab/scripts/android-ue-route.sh
grep -q 'nodad' lab/scripts/android-ue-route.sh
grep -q 'ANDROID_UE_IN6' lab/scripts/android-ue-route.sh
grep -q -- '-P INPUT DROP' lab/scripts/android-ue-route.sh

echo "cgnat sysctl"
sh lab/scripts/android-ue-cgnat.sh --sysctl-self-test

echo "ipv6 input filter"
rules=$(bash lab/scripts/android-ue-route.sh --render-ip6-input)
printf '%s\n' "$rules" | grep -q ':INPUT DROP'
printf '%s\n' "$rules" | grep -q -- '-i lo -j ACCEPT'
printf '%s\n' "$rules" | grep -q -- '-d ::1 -j ACCEPT'
printf '%s\n' "$rules" | grep -q -- '-s ::1 -j ACCEPT'
printf '%s\n' "$rules" | grep -q -- '! -i lo -j DROP'
if printf '%s\n' "$rules" | grep -E -- '-j ACCEPT' | grep -v -E -- '-i lo|-s ::1|-d ::1'; then
  echo "INPUT v6 accepts something other than lo and ::1" >&2
  exit 1
fi

echo "emulator image patch"
image_root=lab/images/android-emulator
if find "$image_root" -name 'adbkey' -o -name 'adbkey.pub' | grep -q .; then
  echo "ADB keys are vendored" >&2
  exit 1
fi
grep -q 'f569246983ee994aed06517bf8e06a3f10547b6d' "$image_root/NOTICE"
grep -q '2026-05-07' "$image_root/NOTICE"
grep -q 'sha256:83f4a7fc27df94dcc7b8de04d14cbbba8da14406f921e966969c3b09000aa507' "$image_root/patches/0001-open5g-boot.patch"
grep -q 'bd1aa17c7ef10066949c88dc6c9c8d536be27f992a1f3b5a584f9bd2ba5646a0' "$image_root/patches/0001-open5g-boot.patch"
grep -q 'HEALTHCHECK --start-period=600s' "$image_root/patches/0001-open5g-boot.patch"
# shellcheck disable=SC2016
grep -q 'TIMEOUT=${BOOT_TIMEOUT:-600}' "$image_root/patches/0001-open5g-boot.patch"
grep -q '^-COPY keys/\*' "$image_root/patches/0001-open5g-boot.patch"
grep -q 'AI_ADDRCONFIG' "$image_root/open5g-preflight.sh"
grep -q 'fd00::1/128' "$image_root/open5g-preflight.sh"
grep -q 'nodad' "$image_root/open5g-preflight.sh"
if grep -q 'ANDROID_UE_IPV6_ANCHOR' "$image_root/open5g-preflight.sh" lab/scripts/android-ue-route.sh lab/scripts/gen-android-ue.sh; then
  echo "IPv6 anchor is still an opt-in flag" >&2
  exit 1
fi
patched=$(mktemp -d)
cp -a "$image_root/upstream/." "$patched/"
patch -p1 -d "$patched" <"$image_root/patches/0001-open5g-boot.patch" >/dev/null
if grep -q 'COPY keys' "$patched/Dockerfile"; then
  echo "patched Dockerfile still copies ADB keys" >&2
  exit 1
fi
pre_line=$(grep -n -F '/opt/open5g-preflight.sh' "$patched/scripts/start-emulator.sh" | head -n 1 | cut -d: -f1)
emu_line=$(awk '/^emulator / { print NR; exit }' "$patched/scripts/start-emulator.sh")
if [ -z "$pre_line" ] || [ -z "$emu_line" ] || [ "$pre_line" -ge "$emu_line" ]; then
  echo "preflight does not run before the emulator" >&2
  exit 1
fi
rm -rf "$patched"
grep -q 'ANDROID_UE_BOOT_TIMEOUT' lab/scripts/android-ue-up.sh
grep -q 'sys.boot_completed' lab/scripts/android-ue-up.sh
grep -q 'emulator -accel-check' lab/scripts/android-ue-up.sh
grep -q 'getent ahosts ::1' lab/scripts/android-ue-up.sh
grep -q 'ANDROID_UE_KVM_GID' lab/scripts/gen-android-ue.sh
grep -q 'group_add:' lab/compose/docker-compose.android-ue.optional.yml
grep -q 'upf-enb-s1u' lab/scripts/android-ue-down.sh
if grep -q 'ANDROID_UE_UPF_S1U_SUBNET' docs/deploy/android-ue-lab5g-dev.md docs/integration/android-ue-per-user.md; then
  echo "ANDROID_UE_UPF_S1U_SUBNET is still documented" >&2
  exit 1
fi
grep -q 'ip6tables-nft' lab/scripts/android-ue-route.sh
if grep -n -E '^[[:space:]]*ports:' lab/compose/docker-compose.android-ue.optional.yml lab/scripts/gen-android-ue.sh; then
  echo "android-ue still publishes a port; uu is an internal network" >&2
  exit 1
fi
if grep -n -E 'ADB_HOST_PORT|:[0-9]*:(5554|5555|5900|6080)' lab/compose/docker-compose.android-ue.optional.yml lab/scripts/gen-android-ue.sh; then
  echo "android-ue still publishes ADB or VNC to the host" >&2
  exit 1
fi
extra_flags=$(awk -F= '$1 == "ANDROID_UE_EXTRA_FLAGS" { sub(/^[^=]*=/, ""); print; exit }' lab/compose/android-ue.env.example)
case "$extra_flags" in
  *partition-size=*)
    echo "example still passes -partition-size= to the emulator" >&2
    exit 1
    ;;
esac
if grep -q '2560m' lab/compose/docker-compose.android-ue.optional.yml; then
  echo "emulator mem_limit is still 2560m" >&2
  exit 1
fi
if grep -q 'CGNAT_SGI_ADDR' lab/scripts/android-ue-tunnel.sh; then
  echo "port 1080 rules still use the SGi address" >&2
  exit 1
fi

echo "UPF policy rule is idempotent"
# shellcheck source=android-ue-lib.sh
. lab/scripts/android-ue-lib.sh
upf_dir=$(mktemp -d)
upf_file=$upf_dir/upf-rule.txt
decision=$(android_ue_upf_rule_decide "0: from all lookup local" "192.0.2.50/32" "$upf_file")
if [ "$decision" != "install" ]; then
  echo "UPF decide should install, got ${decision}" >&2
  exit 1
fi
printf '%s\n' "from 192.0.2.50/32 lookup 1080" >"$upf_file"
decision=$(android_ue_upf_rule_decide "100: from 192.0.2.50/32 lookup 1080" "192.0.2.50/32" "$upf_file")
if [ "$decision" != "skip" ]; then
  echo "UPF decide should skip, got ${decision}" >&2
  exit 1
fi
if android_ue_upf_rule_decide "0: from all lookup local" "192.0.2.50/32" "$upf_file" >/dev/null 2>&1; then
  echo "UPF decide overwrote a saved policy rule" >&2
  exit 1
fi
rm -rf "$upf_dir"

echo "memory and pool"
if [ "$(android_ue_mib 4096m)" != "4096" ] || [ "$(android_ue_mib 2048)" != "2048" ]; then
  echo "memory size parser failed" >&2
  exit 1
fi
if [ "$(( $(android_ue_mib 2048) + 1536 ))" -gt "$(android_ue_mib 2560m)" ]; then
  :
else
  echo "2560 MiB was accepted as enough headroom for 2048" >&2
  exit 1
fi
if [ "$(( $(android_ue_mib 2048) + 1536 ))" -le "$(android_ue_mib 4096m)" ]; then
  :
else
  echo "4096 MiB was rejected as headroom for 2048" >&2
  exit 1
fi
android_ue_addr_in_pool 192.0.2.10 192.0.2.0/24
android_ue_addr_in_pool 192.0.2.10 192.0.2.10/32
if android_ue_addr_in_pool 192.0.2.10 198.51.100.0/24; then
  echo "an address outside the pool was accepted" >&2
  exit 1
fi
v6_proc=$(mktemp -d)
v6_addr=$(printf 'fe80%028x' 1)
printf '%s\n' "$v6_addr 02 40 20 80 eth0" >"$v6_proc/if_inet6"
mkdir -p "$v6_proc/sys/eth0"
printf '0x1003\n' >"$v6_proc/sys/eth0/flags"
if ! android_ue_fe80_proc_ok "$v6_proc/if_inet6" "$v6_proc/sys"; then
  echo "fe80 check rejected an UP permanent link-local address" >&2
  exit 1
fi
printf '%s\n' "$v6_addr 02 40 20 40 eth0" >"$v6_proc/if_inet6"
if android_ue_fe80_proc_ok "$v6_proc/if_inet6" "$v6_proc/sys"; then
  echo "fe80 check accepted a tentative address" >&2
  exit 1
fi
printf '%s\n' "$v6_addr 02 40 20 08 eth0" >"$v6_proc/if_inet6"
if android_ue_fe80_proc_ok "$v6_proc/if_inet6" "$v6_proc/sys"; then
  echo "fe80 check accepted a dadfailed address" >&2
  exit 1
fi
rm -rf "$v6_proc"
v6_lab=$(mktemp -d)
ula_addr=$(printf 'fd00%028x' 1)
lo_addr=$(printf '%032x' 1)
{
  printf '%s 01 80 10 80 lo\n' "$lo_addr"
  printf '%s 03 80 00 80 dummy0\n' "$ula_addr"
} >"$v6_lab/if_inet6"
mkdir -p "$v6_lab/sys/lo" "$v6_lab/sys/dummy0" "$v6_lab/sys/eth0" "$v6_lab/sys/tun_srsue"
printf '0x1003\n' >"$v6_lab/sys/dummy0/flags"
printf '0x1003\n' >"$v6_lab/sys/lo/flags"
printf '0x1003\n' >"$v6_lab/sys/eth0/flags"
printf '0x1003\n' >"$v6_lab/sys/tun_srsue/flags"
printf '1\n' >"$v6_lab/sys/eth0/disable_ipv6"
printf '0\n' >"$v6_lab/sys/tun_srsue/disable_ipv6"
if ! android_ue_nonloop_v6_ok "$v6_lab/if_inet6" "$v6_lab/sys"; then
  echo "ULA anchor was rejected when eth0 disable_ipv6=1 and tun has no fe80" >&2
  exit 1
fi
printf '%s 01 80 10 80 lo\n' "$lo_addr" >"$v6_lab/if_inet6"
if android_ue_nonloop_v6_ok "$v6_lab/if_inet6" "$v6_lab/sys"; then
  echo "non-loopback check passed with only ::1" >&2
  exit 1
fi
fe_addr=$(printf 'fe80%028x' 1)
printf '%s 02 40 20 80 eth0\n' "$fe_addr" >"$v6_lab/if_inet6"
if ! android_ue_nonloop_v6_ok "$v6_lab/if_inet6" "$v6_lab/sys"; then
  echo "fe80 alternative was rejected" >&2
  exit 1
fi
printf '%s 03 80 00 40 dummy0\n' "$ula_addr" >"$v6_lab/if_inet6"
if android_ue_nonloop_v6_ok "$v6_lab/if_inet6" "$v6_lab/sys"; then
  echo "tentative ULA was accepted" >&2
  exit 1
fi
rm -rf "$v6_lab"
if android_ue_android_image_ok 'halimqarroum/docker-android:api-33'; then
  echo "registry image without a digest was accepted" >&2
  exit 1
fi
android_ue_android_image_ok 'open5g-android-emulator:local'
android_ue_android_image_ok 'example.invalid/android@sha256:0123456789abcdef'
if android_ue_kvm_gid_ok 0 0 || android_ue_kvm_gid_ok abc 44; then
  echo "KVM gid check accepted a bad value" >&2
  exit 1
fi
android_ue_kvm_gid_ok 44 44

echo "resolver is TCP-only"
default_core=$(lab/scripts/render-corefile.sh)
printf '%s\n' "$default_core" | grep -q 'force_tcp'
printf '%s\n' "$default_core" | grep -q 'tcp://1.1.1.1'
if printf '%s\n' "$default_core" | grep -q 'udp://'; then
  echo "resolver config has a UDP upstream" >&2
  exit 1
fi
if printf '%s\n' "$default_core" | grep -Eq '^[[:space:]]*log([[:space:]]|$)'; then
  echo "resolver config logs queries" >&2
  exit 1
fi
custom_core=$(ANDROID_UE_DNS_UPSTREAM=192.0.2.53 lab/scripts/render-corefile.sh)
printf '%s\n' "$custom_core" | grep -q 'tcp://192.0.2.53'
if printf '%s\n' "$custom_core" | grep -q 'tcp://1.1.1.1'; then
  echo "resolver upstream is still hardcoded" >&2
  exit 1
fi

echo "up-script service list"
without=$(lab/scripts/android-ue-up.sh --env-file "$example" --print-services)
printf '%s\n' "$without" | grep -qx 'ue1'
if printf '%s\n' "$without" | grep -qx 'egress'; then
  echo "egress is in the default service list" >&2
  exit 1
fi
with_socks=$(lab/scripts/android-ue-up.sh --env-file "$example" --with-socks-egress --print-services)
printf '%s\n' "$with_socks" | grep -qx 'egress'
printf '%s\n' "$with_socks" | grep -qx 'egress-dns'
printf '%s\n' "$with_socks" | grep -qx 'cgnat'

echo "compose config"
if [ -n "${ANDROID_UE_COMPOSE_BIN:-}" ]; then
  # shellcheck disable=SC2206
  compose=($ANDROID_UE_COMPOSE_BIN)
elif command -v docker-compose >/dev/null 2>&1; then
  compose=(docker-compose)
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
else
  echo "docker compose is not installed" >&2
  exit 1
fi
version=$("${compose[@]}" version --short 2>/dev/null || "${compose[@]}" version | awk '{ print $NF }')
if [ -n "${ANDROID_UE_REQUIRE_COMPOSE_VERSION:-}" ] && [ "$version" != "${ANDROID_UE_REQUIRE_COMPOSE_VERSION}" ] && [ "$version" != "v${ANDROID_UE_REQUIRE_COMPOSE_VERSION}" ]; then
  echo "compose version ${version} != ${ANDROID_UE_REQUIRE_COMPOSE_VERSION}" >&2
  exit 1
fi
rendered=$tmp/rendered.yml
"${compose[@]}" \
  -f lab/compose/docker-compose.android-ue.optional.yml \
  --env-file "$example" \
  --profile android-ue \
  config >"$rendered"
grep -q 'service:ue1' "$rendered"
grep -q 'service:ue2' "$rendered"
grep -q 'container_name: l5gd-android1' "$rendered"
grep -q 'container_name: l5gd-cgnat' "$rendered"
grep -q 'android-ue' "$rendered"
grep -q 'REPLACE_ANDROID_UE_PGW_DNS' "$rendered"
grep -q -- '-dns-server' "$rendered"
if grep -q '127.0.0.11' "$rendered"; then
  echo "compose config sends DNS to 127.0.0.11" >&2
  exit 1
fi
if grep -E -q 'container_name: l5gd-egress$' "$rendered"; then
  echo "socks egress service is present without the socks-egress profile" >&2
  exit 1
fi
if grep -q 'service:cgnat' "$rendered"; then
  echo "cgnat network mode is present without the socks-egress profile" >&2
  exit 1
fi
socks_rendered=$tmp/rendered-socks.yml
"${compose[@]}" \
  -f lab/compose/docker-compose.android-ue.optional.yml \
  --env-file "$example" \
  --profile android-ue \
  --profile socks-egress \
  config >"$socks_rendered"
grep -E -q 'container_name: l5gd-egress$' "$socks_rendered"
grep -q 'container_name: l5gd-egress-dns' "$socks_rendered"
grep -q 'service:cgnat' "$socks_rendered"
grep -q 'REPLACE_CGNAT_EGRESS_ADDR' "$socks_rendered"
if grep -E -n '(^|[^0-9A-Fa-f])[0-9A-Fa-f]{32}([^0-9A-Fa-f]|$)' "$rendered" "$socks_rendered"; then
  echo "rendered compose contains a 32-hex USIM value" >&2
  exit 1
fi

echo "cgnat volume mounts"
python3 - <<'PY'
import pathlib
import sys
path = pathlib.Path("lab/compose/docker-compose.android-ue.optional.yml")
text = path.read_text(encoding="utf-8")
services = {}
current = None
in_volumes = False
for raw in text.splitlines():
    if raw.startswith("  ") and not raw.startswith("   ") and raw.rstrip().endswith(":"):
        current = raw.strip()[:-1]
        services[current] = []
        in_volumes = False
        continue
    if current is None:
        continue
    if raw.startswith("    volumes:"):
        in_volumes = True
        continue
    if in_volumes and raw.startswith("      - "):
        services[current].append(raw.strip()[2:].strip().strip('"'))
        continue
    if in_volumes and raw.startswith("    ") and not raw.startswith("      "):
        in_volumes = False
problems = []
for name, vols in services.items():
    dirs = []
    files = []
    for spec in vols:
        parts = spec.split(":")
        if len(parts) < 2:
            continue
        # source may be ${VAR:-default}/file, so the target is the last path-like field before ro
        mode = parts[-1] if parts[-1] in {"ro", "rw"} else ""
        target = parts[-2] if mode else parts[-1]
        source = ":".join(parts[:-2] if mode else parts[:-1])
        if source.endswith(".template") or source.endswith(".sh") or source.endswith("Corefile"):
            files.append(target)
        else:
            dirs.append(target.rstrip("/"))
    for target in files:
        for directory in dirs:
            if target == directory or target.startswith(directory + "/"):
                problems.append(f"{name}: {target} is inside read-only directory mount {directory}")
if problems:
    sys.stderr.write("\n".join(problems) + "\n")
    sys.exit(1)
PY

if docker info >/dev/null 2>&1; then
  docker_cmd=(docker)
elif sudo docker info >/dev/null 2>&1; then
  docker_cmd=(sudo docker)
else
  echo "docker daemon is not available; mount create was not run" >&2
  exit 1
fi
mount_image=${ANDROID_UE_MOUNT_IMAGE:-alpine:3.20}
if ! "${docker_cmd[@]}" image inspect "$mount_image" >/dev/null 2>&1; then
  "${docker_cmd[@]}" pull "$mount_image"
fi
ip6_rules=$(bash lab/scripts/android-ue-route.sh --render-ip6-input)
if ! printf '%s\n' "$ip6_rules" | "${docker_cmd[@]}" run --rm -i --cap-add NET_ADMIN "$mount_image" \
  sh -c 'apk add --no-cache iptables >/dev/null && ip6tables-restore --test'; then
  echo "rendered INPUT v6 rules failed ip6tables-restore --test" >&2
  exit 1
fi
echo "ip6tables-restore --test accepted the INPUT v6 rules"
mount_env=$(mktemp)
mount_override=$(mktemp)
if [ "${docker_cmd[0]}" = sudo ]; then
  mount_compose=(sudo "${compose[@]}")
else
  mount_compose=("${compose[@]}")
fi
cleanup_mount() {
  "${mount_compose[@]}" -p android-ue-mountcheck -f lab/compose/docker-compose.android-ue.optional.yml \
    -f "$mount_override" --env-file "$mount_env" --profile android-ue --profile socks-egress \
    rm -sf cgnat egress >/dev/null 2>&1 || true
  "${docker_cmd[@]}" rm -f android-ue-egress-proc >/dev/null 2>&1 || true
  "${docker_cmd[@]}" network rm android-ue-mount-sgi android-ue-mount-egress >/dev/null 2>&1 || true
  rm -f "$mount_env" "$mount_override"
  rm -rf "$tmp"
}
trap cleanup_mount EXIT
python3 - "$example" "$mount_env" "$mount_image" <<'PY'
import sys
src, dest, image = sys.argv[1:]
overrides = {
    "ANDROID_UE_CGNAT_IMAGE": image,
    "ANDROID_UE_TUN2SOCKS_IMAGE": image,
    "ANDROID_UE_DNS_IMAGE": image,
    "ANDROID_UE_SGI_NETWORK": "android-ue-mount-sgi",
    "ANDROID_UE_EGRESS_NETWORK": "android-ue-mount-egress",
    "CGNAT_SGI_ADDR": "192.0.2.30",
    "CGNAT_EGRESS_ADDR": "198.51.100.40",
    "ANDROID_UE_SOCKS_ADDR": "192.0.2.10:1080",
    "ANDROID_UE_LAB_SUBNET": "192.0.2.0/24",
}
lines = []
seen = set()
for raw in open(src, encoding="utf-8"):
    text = raw.strip()
    if not text or text.startswith("#") or "=" not in text:
        continue
    key = text.split("=", 1)[0]
    if key in overrides:
        lines.append(f"{key}={overrides[key]}")
        seen.add(key)
    else:
        lines.append(text)
for key, value in overrides.items():
    if key not in seen:
        lines.append(f"{key}={value}")
open(dest, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
cat >"$mount_override" <<'EOF'
services:
  cgnat:
    container_name: android-ue-mount-cgnat
    entrypoint: ["/bin/sh", "-c", "test -f /opt/cgnat/android-ue-cgnat.sh && test -f /opt/cgnat/render-cgnat.sh && test -f /opt/cgnat/android-ue-add-ue.sh && test -f /etc/cgnat/cgnat.nft.template"]
  egress:
    container_name: android-ue-mount-egress
    network_mode: none
    entrypoint: ["/bin/sh", "-c", "test -f /opt/cgnat/android-ue-egress.sh"]
EOF
"${docker_cmd[@]}" network create --subnet 192.0.2.0/24 android-ue-mount-sgi >/dev/null
"${docker_cmd[@]}" network create --internal --subnet 198.51.100.0/24 android-ue-mount-egress >/dev/null
# The probe entrypoint only checks that the mounts exist. nft and tun2socks are not started.
if ! "${mount_compose[@]}" -p android-ue-mountcheck \
  -f lab/compose/docker-compose.android-ue.optional.yml \
  -f "$mount_override" \
  --env-file "$mount_env" \
  --profile android-ue \
  --profile socks-egress \
  run --rm --no-deps cgnat; then
  echo "cgnat did not start far enough to see its mounted files" >&2
  exit 1
fi
if ! "${mount_compose[@]}" -p android-ue-mountcheck \
  -f lab/compose/docker-compose.android-ue.optional.yml \
  -f "$mount_override" \
  --env-file "$mount_env" \
  --profile android-ue \
  --profile socks-egress \
  run --rm --no-deps egress; then
  echo "egress did not start far enough to see its mounted script" >&2
  exit 1
fi
echo "cgnat and egress mounts started"
ci_image=open5g-android-ue-ci:local
if ! "${docker_cmd[@]}" image inspect "$ci_image" >/dev/null 2>&1; then
  "${docker_cmd[@]}" build -t "$ci_image" - <<'EOF'
FROM alpine:3.20
RUN apk add --no-cache nftables iproute2
RUN printf '%s\n' '#!/bin/sh' 'ip tuntap add name tun0 mode tun' 'ip link set tun0 up' 'exec sleep 60' > /usr/bin/tun2socks && chmod 0755 /usr/bin/tun2socks
EOF
fi
nft_err=$tmp/nft-container.err
if "${docker_cmd[@]}" run --rm --network none --cap-add NET_ADMIN \
  -v "$PWD/lab/config/cgnat:/etc/cgnat:ro" \
  -v "$PWD/lab/scripts/render-cgnat.sh:/opt/cgnat/render-cgnat.sh:ro" \
  -e UE_POOL=192.0.2.0/24 \
  -e LAB_SUBNET=198.51.100.0/24 \
  -e SOCKS_ADDR=192.0.2.10 \
  -e CT_LIMIT=200 \
  "$ci_image" \
  /bin/sh -c '/opt/cgnat/render-cgnat.sh /etc/cgnat/cgnat.nft.template > /tmp/c.nft && nft -c -f /tmp/c.nft' \
  >"$tmp/nft-container.out" 2>"$nft_err"; then
  echo "cgnat container nft -c -f passed"
else
  if grep -q 'Operation not permitted' "$nft_err"; then
    echo "cgnat container nft -c -f is not permitted here; checking the rendered ruleset on the host" >&2
    UE_POOL=192.0.2.0/24 LAB_SUBNET=198.51.100.0/24 SOCKS_ADDR=192.0.2.10 CT_LIMIT=200 \
      lab/scripts/render-cgnat.sh lab/config/cgnat/cgnat.nft.template >"$tmp/c.nft"
    if ! nft -c -f "$tmp/c.nft" && ! sudo nft -c -f "$tmp/c.nft"; then
      cat "$nft_err" >&2
      echo "rendered ruleset did not pass nft -c" >&2
      exit 1
    fi
    echo "host nft -c passed. The runner refused nft inside the container."
  else
    cat "$nft_err" >&2
    echo "cgnat container nft -c -f failed" >&2
    exit 1
  fi
fi
egress_id=$("${docker_cmd[@]}" run -d --name android-ue-egress-proc --network android-ue-mount-egress --cap-add NET_ADMIN \
  -v "$PWD/lab/scripts/android-ue-egress.sh:/opt/cgnat/android-ue-egress.sh:ro" \
  -e ANDROID_UE_SOCKS_ADDR=198.51.100.10:1080 \
  --device /dev/net/tun \
  "$ci_image" \
  /bin/sh /opt/cgnat/android-ue-egress.sh || true)
if [ -z "$egress_id" ]; then
  echo "egress sidecar did not start" >&2
  exit 1
fi
sleep 1
if ! "${docker_cmd[@]}" inspect -f '{{.State.Running}}' android-ue-egress-proc | grep -qx true; then
  "${docker_cmd[@]}" logs android-ue-egress-proc >&2 || true
  "${docker_cmd[@]}" rm -f android-ue-egress-proc >/dev/null 2>&1 || true
  echo "egress sidecar exited before its process was running" >&2
  exit 1
fi
"${docker_cmd[@]}" rm -f android-ue-egress-proc >/dev/null
echo "egress sidecar process was running"
echo "android-ue checks passed"
