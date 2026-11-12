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
  lab/scripts/android-ue-magen.sh
  lab/scripts/android-ue-screen-smoke.sh
  lab/images/android-emulator/build.sh
  lab/images/android-emulator/open5g-preflight.sh
  lab/images/ws-scrcpy/check-serve.sh
)
sh_scripts=(
  lab/scripts/render-cgnat.sh
  lab/scripts/android-ue-cgnat.sh
  lab/scripts/android-ue-egress.sh
  lab/scripts/android-ue-add-ue.sh
  lab/scripts/render-corefile.sh
  lab/scripts/android-ue-screen.sh
  lab/scripts/android-ue-screen-bind.sh
  lab/scripts/android-ue-screen-chain.sh
  lab/scripts/android-ue-screen-publish.sh
  lab/scripts/android-ue-screen-tunnel.sh
  lab/scripts/android-ue-screen-mode.sh
  lab/scripts/android-ue-screen-standalone.sh
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
  ANDROID_UE_SGWU_GTPU_ROUTE ANDROID_UE_SGI_PROBE \
  ANDROID_UE_SCREEN_IMAGE ANDROID_UE_KVM_GID \
  O5G_SCREEN_SUBNET O5G_SCREEN_GATEWAY O5G_SCREEN_EMULATOR_ADDR \
  O5G_SCREEN_LISTENER_ADDR O5G_SCREEN_LISTENER_IMAGE O5G_DASHBOARD_NETWORK; do
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
  docs/deploy/android-emulator-dashboard.md
  docs/deploy/android-emulator-host-screen.md
  lab/compose/compose.screen-standalone.yml
  lab/compose/screen-standalone.env.example
  lab/scripts/android-ue-screen.sh
  lab/scripts/android-ue-screen-bind.sh
  lab/scripts/android-ue-screen-chain.sh
  lab/scripts/android-ue-screen-publish.sh
  lab/scripts/android-ue-screen-tunnel.sh
  lab/scripts/android-ue-screen-mode.sh
  lab/scripts/android-ue-screen-standalone.sh
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
grep -q 'ANDROID_UE_IPV6_NO_FILTER_OK' lab/scripts/android-ue-up.sh
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
if grep -q 'ps -eo comm=' lab/scripts/android-ue-route.sh; then
  echo "route script still looks for the emulator with ps" >&2
  exit 1
fi
again_at=$(grep -n -F 'refusing to run the route sidecar again' lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
route_up_at=$(awk '/up -d \\$/ { print NR; exit }' lab/scripts/android-ue-up.sh)
# shellcheck disable=SC2016
ue_only_at=$(grep -n -F 'up -d "ue${n}"' lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
# shellcheck disable=SC2016
preset_at=$(grep -n -F 'android_ue_preset_existing_iface_sysctls "$n"' lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
if [ -z "$ue_only_at" ] || [ -z "$preset_at" ] || [ -z "$route_up_at" ] || [ "$ue_only_at" -ge "$preset_at" ] || [ "$preset_at" -ge "$route_up_at" ]; then
  echo "up starts the route sidecar before the host sysctl check" >&2
  exit 1
fi
if [ -z "$again_at" ] || [ -z "$route_up_at" ] || [ "$again_at" -ge "$route_up_at" ]; then
  echo "up starts the route sidecar after android is already running" >&2
  exit 1
fi
screen_only_at=$(grep -n -F -- '--install-screen' lab/scripts/android-ue-up.sh | head -n 1 | cut -d: -f1)
if [ -z "$screen_only_at" ] || [ "$screen_only_at" -ge "$again_at" ]; then
  echo "screen-only path does not install ANDROID_UE_SCREEN before the second up is refused" >&2
  exit 1
fi
# shellcheck disable=SC2016
grep -q 'disable_ipv6 on ${key}' lab/scripts/android-ue-up.sh
grep -q 'accept_ra autoconf forwarding' lab/scripts/android-ue-up.sh
grep -q 'ANDROID_UE_IPV6_NO_FILTER_OK:-0' lab/scripts/android-ue-up.sh
# shellcheck disable=SC2016
grep -q 'nsenter -t "$pid" -n nft -f' lab/scripts/android-ue-up.sh
grep -q 'ip -o link show dev dummy0' lab/scripts/android-ue-up.sh
grep -q 'ip -6 -o addr show dev dummy0 scope global' lab/scripts/android-ue-up.sh
if grep -n 'nsenter -t' lab/scripts/android-ue-up.sh | grep -v -- '-m' | grep -E '/sys/class/net|/proc/sys/net'; then
  echo "nsenter -n reads host sysfs or proc sysctl" >&2
  exit 1
fi
if grep -n -E 'cat[[:space:]]+"/sys/class/net|cat[[:space:]]+/sys/class/net' lab/scripts/android-ue-up.sh lab/scripts/check-android-ue.sh; then
  echo "a script still cats host sysfs for a netns interface" >&2
  exit 1
fi
grep -q 'dummy0 type dummy' lab/scripts/android-ue-route.sh
grep -q 'nodad' lab/scripts/android-ue-route.sh
grep -q 'expected 0' lab/scripts/android-ue-route.sh
if grep -q 'WARN' lab/scripts/android-ue-route.sh; then
  echo "route sidecar still warns and continues when a sysctl is not 0" >&2
  exit 1
fi
if grep -n -F '[ -w ' lab/scripts/android-ue-route.sh lab/scripts/android-ue-up.sh; then
  echo "a sysctl write is still skipped when the file looks unwritable" >&2
  exit 1
fi
grep -q '/bin/cat' lab/scripts/android-ue-up.sh
grep -q 'android_ue_require_host_tools' lab/scripts/android-ue-up.sh
grep -q 'net.ipv6.conf.all.accept_ra' lab/compose/docker-compose.android-ue.optional.yml
grep -q 'net.ipv6.conf.all.disable_ipv6' lab/compose/docker-compose.android-ue.optional.yml
grep -q 'net.ipv6.conf.default.accept_ra' lab/compose/docker-compose.android-ue.optional.yml
grep -q 'net.ipv6.conf.default.disable_ipv6' lab/compose/docker-compose.android-ue.optional.yml
gen_out=$(lab/scripts/gen-android-ue.sh --stdout)
for sysctl_key in \
  net.ipv6.conf.all.accept_ra \
  net.ipv6.conf.all.autoconf \
  net.ipv6.conf.all.forwarding \
  net.ipv6.conf.all.disable_ipv6 \
  net.ipv6.conf.default.accept_ra \
  net.ipv6.conf.default.autoconf \
  net.ipv6.conf.default.forwarding \
  net.ipv6.conf.default.disable_ipv6
do
  if ! printf '%s\n' "$gen_out" | grep -q "$sysctl_key"; then
    echo "generator output is missing ${sysctl_key}" >&2
    exit 1
  fi
done
ue_sysctls=$(printf '%s\n' "$gen_out" | awk '$1=="ue1:"{s=1} $1=="enb1:"{s=0} s && /net.ipv6.conf.all.accept_ra/{c++} END{print c+0}')
android_sysctls=$(printf '%s\n' "$gen_out" | awk '$1=="android1:"{s=1} $1=="ue2:"{s=0} s && /net.ipv6.conf.all.accept_ra/{c++} END{print c+0}')
if [ "$ue_sysctls" != 1 ] || [ "$android_sysctls" != 0 ]; then
  echo "IPv6 sysctls must be on ue1, the netns owner, not on android1" >&2
  exit 1
fi
grep -q 'ANDROID_UE_IN4' lab/scripts/android-ue-route.sh
# shellcheck disable=SC2016
grep -q 'route del "${addr}/128" dev dummy0 || true' lab/scripts/android-ue-route.sh
if grep -q 'ip6tables' lab/scripts/android-ue-route.sh; then
  echo "route script still depends on ip6tables" >&2
  exit 1
fi

echo "cgnat sysctl"
sh lab/scripts/android-ue-cgnat.sh --sysctl-self-test

echo "route sidecar sees eth0 only after the host write"
ro_src=$(mktemp -d)
ro_mnt=$(mktemp -d)
printf '1\n' >"$ro_src/accept_ra"
sudo mount --bind "$ro_src" "$ro_mnt"
sudo mount -o remount,bind,ro "$ro_mnt"
ro_cleanup() { sudo umount "$ro_mnt" >/dev/null 2>&1 || true; rm -rf "$ro_src" "$ro_mnt"; }
if bash lab/scripts/android-ue-route.sh --write-zero-self-test "$ro_mnt/accept_ra"; then
  ro_cleanup
  echo "sidecar accepted eth0=1 on a read-only sysctl" >&2
  exit 1
fi
printf '0\n' >"$ro_src/accept_ra"
if ! bash lab/scripts/android-ue-route.sh --write-zero-self-test "$ro_mnt/accept_ra"; then
  ro_cleanup
  echo "sidecar rejected eth0 after the host had set it to 0" >&2
  exit 1
fi
ro_cleanup

echo "ipv4 input filter"
v4rules=$(bash lab/scripts/android-ue-route.sh --render-ip4-input)
printf '%s\n' "$v4rules" | grep -q -- '-i lo -j ACCEPT'
printf '%s\n' "$v4rules" | grep -q -- '-m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT'
printf '%s\n' "$v4rules" | grep -q -- '-i tun_srsue -j DROP'
if printf '%s\n' "$v4rules" | grep -E -- '-j DROP' | grep -v 'tun_srsue'; then
  echo "IPv4 INPUT drops an interface other than tun_srsue" >&2
  exit 1
fi

echo "ipv6 nft filter"
# shellcheck source=android-ue-lib.sh
. lab/scripts/android-ue-lib.sh
nft_rules=$(android_ue_render_ip6_nft)
printf '%s\n' "$nft_rules" | grep -q 'hook input'
printf '%s\n' "$nft_rules" | grep -q 'policy drop'
printf '%s\n' "$nft_rules" | grep -q 'iif "lo" accept'
printf '%s\n' "$nft_rules" | grep -q 'oif "lo" accept'
if printf '%s\n' "$nft_rules" | grep 'iif' | grep -v 'iif "lo"'; then
  echo "IPv6 input accepts an interface other than lo, so l5gd-screen would stay open" >&2
  exit 1
fi
if printf '%s\n' "$nft_rules" | grep -q '::1'; then
  echo "IPv6 nft filter still has a redundant ::1 rule" >&2
  exit 1
fi
nft_file=$(mktemp)
printf '%s\n' "$nft_rules" >"$nft_file"
if ! nft -c -f "$nft_file" 2>/dev/null && ! sudo nft -c -f "$nft_file"; then
  echo "rendered IPv6 nft filter failed nft -c" >&2
  exit 1
fi
rm -f "$nft_file"
if android_ue_ula_cidr_ok '::1/128' || android_ue_ula_cidr_ok 'fe80::1/128' || android_ue_ula_cidr_ok '2001:db8::1/128' || android_ue_ula_cidr_ok 'fdc2:fd97:24a4::1/64'; then
  echo "ULA check accepted an address outside fc00::/7 /128" >&2
  exit 1
fi
android_ue_ula_cidr_ok 'fdc2:fd97:24a4::1/128'

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
grep -q 'HEALTHCHECK --start-period=900s' "$image_root/patches/0001-open5g-boot.patch"
grep -q 'python3 iproute2' "$image_root/patches/0001-open5g-boot.patch"
# shellcheck disable=SC2016
grep -q 'TIMEOUT=${BOOT_TIMEOUT:-600}' "$image_root/patches/0001-open5g-boot.patch"
grep -q '^-COPY keys/\*' "$image_root/patches/0001-open5g-boot.patch"
grep -q 'AI_ADDRCONFIG' "$image_root/open5g-preflight.sh"
grep -q 'fdc2:fd97:24a4::1/128' "$image_root/open5g-preflight.sh"
grep -q 'fc00::/7' "$image_root/open5g-preflight.sh"
grep -q 'route sidecar' "$image_root/open5g-preflight.sh"
if grep -E -q 'ip link (add|set)|ip -6 addr add|route del' "$image_root/open5g-preflight.sh"; then
  echo "preflight still mutates the netns" >&2
  exit 1
fi
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
if grep -q 'adb -a' "$patched/scripts/start-emulator.sh"; then
  echo "patched emulator still starts adb on every interface" >&2
  exit 1
fi
grep -q 'adb -P 5037 server nodaemon' "$patched/scripts/start-emulator.sh"
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
if grep -n -E '^[[:space:]]*ports:' lab/compose/docker-compose.android-ue.optional.yml lab/scripts/gen-android-ue.sh; then
  echo "android-ue still publishes a port; uu is an internal network" >&2
  exit 1
fi
if grep -n -E 'ADB_HOST_PORT|:[0-9]*:(5554|5555|5900|6080)' lab/compose/docker-compose.android-ue.optional.yml lab/scripts/gen-android-ue.sh; then
  echo "android-ue still publishes ADB or VNC to the host" >&2
  exit 1
fi
python3 - <<'PY'
import pathlib
import sys

text = pathlib.Path("lab/compose/docker-compose.android-ue.optional.yml").read_text()
blocks = {}
name = None
buf = []
for line in text.splitlines():
    if line.startswith("  ") and not line.startswith("   ") and line.endswith(":"):
        if name:
            blocks[name] = "\n".join(buf)
        name = line.strip()[:-1]
        buf = [line]
    else:
        buf.append(line)
if name:
    blocks[name] = "\n".join(buf)
for key in ("android1", "android2", "ue1-screen", "ue2-screen"):
    body = blocks.get(key, "")
    if "NET_ADMIN" in body:
        sys.exit(f"{key} has NET_ADMIN")
for key in ("ue1-screen", "ue2-screen"):
    body = blocks.get(key, "")
    if "network_mode:" not in body or "SCREEN_ADDR" not in body:
        sys.exit(f"{key} is missing its screen-network bind")
    if "SCREEN_BIND:" in body and "UU}" in body.split("SCREEN_BIND:", 1)[1].splitlines()[0]:
        sys.exit(f"{key} binds the screen listener to the uu address")
    if "ports:" in body or "0.0.0.0" in body or "ADB_HOST_PORT" in body:
        sys.exit(f"{key} publishes a port or binds every interface")
    if "5038" not in body and "ANDROID_UE_UU" not in body:
        sys.exit(f"{key} does not give ws-scrcpy its own adb target")
PY
echo "screen bind"
if ANDROID_UE_SCREEN_BIND=0.0.0.0 lab/scripts/android-ue-screen.sh --check-bind; then
  echo "screen bind accepted 0.0.0.0" >&2
  exit 1
fi
if ANDROID_UE_SCREEN_BIND=127.0.0.1 lab/scripts/android-ue-screen.sh --check-bind; then
  echo "screen bind accepted loopback" >&2
  exit 1
fi
if ! ANDROID_UE_SCREEN_MODE=standalone ANDROID_UE_SCREEN_BIND=127.0.0.1 lab/scripts/android-ue-screen.sh --check-bind; then
  echo "standalone screen bind rejected loopback" >&2
  exit 1
fi
if ANDROID_UE_SCREEN_MODE=standalone ANDROID_UE_SCREEN_BIND=0.0.0.0 lab/scripts/android-ue-screen.sh --check-bind; then
  echo "standalone screen bind accepted 0.0.0.0" >&2
  exit 1
fi
if ! ANDROID_UE_SCREEN_BIND=192.0.2.32 lab/scripts/android-ue-screen.sh --check-bind; then
  echo "screen bind rejected a unicast address" >&2
  exit 1
fi
if ANDROID_UE_SCREEN_ALLOW_FROM=0.0.0.0 lab/scripts/android-ue-route.sh --check-allow; then
  echo "screen allow accepted 0.0.0.0" >&2
  exit 1
fi
if ! ANDROID_UE_SCREEN_ALLOW_FROM=192.0.2.1 lab/scripts/android-ue-route.sh --check-allow; then
  echo "screen allow rejected a unicast address" >&2
  exit 1
fi
skipped=$(lab/scripts/android-ue-route.sh --print-screen-rule)
if [ "$skipped" != "skipped" ]; then
  echo "screen rule ran while the image is still a placeholder: ${skipped}" >&2
  exit 1
fi
digest=$(python3 -c 'print("b"*64)')
rule=$(ANDROID_UE_SCREEN_IMAGE="example.invalid/ws-scrcpy@sha256:${digest}" \
  ANDROID_UE_SCREEN_IFACE=eth1 \
  ANDROID_UE_SCREEN_ALLOW_FROM=192.0.2.1 \
  ANDROID_UE_SCREEN_PORT=8000 \
  lab/scripts/android-ue-route.sh --print-screen-rule)
case "$rule" in
  *"-A INPUT -j ANDROID_UE_SCREEN"*) ;;
  *)
    echo "screen chain is not appended to INPUT: ${rule}" >&2
    exit 1
    ;;
esac
printf '%s\n' "$rule" | grep -q -- '-A ANDROID_UE_SCREEN -i eth1 -p tcp --dport 8000 -s 192.0.2.1 -j ACCEPT'
printf '%s\n' "$rule" | grep -q -- '-A ANDROID_UE_SCREEN -p tcp --dport 8000 -j DROP'
if printf '%s\n' "$rule" | grep -q -- '-I INPUT'; then
  echo "screen chain is inserted ahead of ANDROID_UE_IN4: ${rule}" >&2
  exit 1
fi
adb_rule=$(ANDROID_UE_ADB_IFACE=uu0 bash lab/scripts/android-ue-route.sh --print-adb-allow)
printf '%s\n' "$adb_rule" | grep -q -- '-i uu0'
printf '%s\n' "$adb_rule" | grep -q -- '-m multiport --dports 5554,5555 -j ACCEPT'
if grep -q -- '-P INPUT' lab/scripts/android-ue-route.sh; then
  echo "route script changes the INPUT policy" >&2
  exit 1
fi
# shellcheck disable=SC2016
if ! grep -q -- '-A INPUT -j "$chain"' lab/scripts/android-ue-route.sh; then
  echo "adb allowlist is not appended after ANDROID_UE_IN4" >&2
  exit 1
fi
echo "magen standalone screen"
magen=lab/compose/docker-compose.magen-screen.optional.yml
grep -q 'network_mode: "container:l5gd-android-magen"' "$magen"
grep -q 'ANDROID_UE_SCREEN_MODE: standalone' "$magen"
grep -q 'ANDROID_UE_ADB_MODE: standalone' "$magen"
grep -q 'o5g-screen:' "$magen"
grep -q 'internal: true' "$magen"
grep -q 'enable_ipv6: false' "$magen"
# shellcheck disable=SC2016
grep -q '127.0.0.1:${OPEN5G_EMULATOR_SCREEN_BIND_PORT:-3301}:3301' "$magen"
if grep -q 'ANDROID_UE_UU' "$magen" || grep -q '0.0.0.0' "$magen" || grep -q 'NET_ADMIN' "$magen"; then
  echo "magen compose passes ANDROID_UE_UU, binds every address, or adds NET_ADMIN" >&2
  exit 1
fi
if grep -q '8000:8000' "$magen"; then
  echo "magen compose publishes the screen port" >&2
  exit 1
fi
python3 - "$magen" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
emulator = text.split("  magen-emulator:", 1)[1].split("  magen-screen:", 1)[0]
sidecar = text.split("  magen-screen:", 1)[1].split("  magen-listener:", 1)[0]
if "ports:" in emulator or "ports:" in sidecar:
    sys.exit("magen emulator or sidecar publishes a port")
if "ANDROID_UE_SCREEN_BIND: 127.0.0.1" in text:
    sys.exit("magen sidecar still binds loopback")
if "O5G_SCREEN_EMULATOR_ADDR" not in sidecar:
    sys.exit("magen sidecar does not bind the emulator address on o5g-screen")
PY
if grep -q 'magen-screen' lab/scripts/android-ue-up.sh; then
  echo "android-ue-up loads the magen screen profile" >&2
  exit 1
fi
digest=$(python3 -c 'print("c"*64)')
magen_env=$tmp/magen.env
cat >"$magen_env" <<EOF
ANDROID_UE_ANDROID_IMAGE=example.invalid/android@sha256:${digest}
ANDROID_UE_SCREEN_IMAGE=example.invalid/ws-scrcpy@sha256:${digest}
O5G_SCREEN_LISTENER_IMAGE=example.invalid/listener@sha256:${digest}
O5G_SCREEN_EMULATOR_ADDR=192.0.2.32
O5G_SCREEN_LISTENER_ADDR=192.0.2.33
O5G_SCREEN_SUBNET=192.0.2.0/24
O5G_SCREEN_GATEWAY=192.0.2.1
O5G_DASHBOARD_NETWORK=dashboard
ANDROID_UE_SCREEN_PORT=8000
EOF
if ! lab/scripts/android-ue-magen.sh --env-file "$magen_env" --check; then
  echo "magen wrapper rejected a pinned image" >&2
  exit 1
fi
sed 's/@sha256:.*/:local/' "$magen_env" >"$tmp/magen-local.env"
if lab/scripts/android-ue-magen.sh --env-file "$tmp/magen-local.env" --check; then
  echo "magen wrapper accepted an image without a digest" >&2
  exit 1
fi
printf '\nANDROID_UE_UU=192.0.2.40\n' >>"$magen_env"
if lab/scripts/android-ue-magen.sh --env-file "$magen_env" --check; then
  echo "magen wrapper accepted ANDROID_UE_UU" >&2
  exit 1
fi
patched=$(mktemp -d)
cp -a lab/images/android-emulator/upstream/. "$patched"
patch -p1 -d "$patched" <lab/images/android-emulator/patches/0001-open5g-boot.patch >/dev/null
start_script=$patched/scripts/start-emulator.sh
grep -q 'adb -P 5037 server nodaemon' "$start_script"
if grep -q 'adb -a' "$start_script"; then
  echo "vendored emulator still starts adb -a" >&2
  exit 1
fi
# shellcheck disable=SC2016
grep -q 'bind="${ANDROID_UE_UU}"' "$start_script"
grep -q 'ANDROID_UE_ADB_MODE' "$start_script"
grep -q 'standalone mode does not take ANDROID_UE_UU' "$start_script"
if grep -q 'ip addr list eth0' "$start_script" || grep -q 'bind="0.0.0.0"' "$start_script" || grep -q 'bind="eth0"' "$start_script"; then
  echo "vendored socat still binds eth0 or every address" >&2
  exit 1
fi
rm -rf "$patched"
grep -q '5038' lab/scripts/android-ue-screen.sh
grep -q 'ANDROID_UE_UU' lab/scripts/android-ue-screen.sh
grep -q 'adb_target=127.0.0.1:5555' lab/scripts/android-ue-screen.sh
if grep -q 'adb -P 5037' lab/scripts/android-ue-screen.sh || grep -q 'adb -a' lab/scripts/android-ue-screen.sh; then
  echo "screen sidecar still shares the emulator adb server" >&2
  exit 1
fi
grep -q 'l5gd-screen address' lab/scripts/android-ue-up.sh
empty=$(ANDROID_UE_SCREEN_IMAGE='' lab/scripts/android-ue-route.sh --print-screen-rule)
if [ "$empty" != "skipped" ]; then
  echo "screen rule ran while the image is empty: ${empty}" >&2
  exit 1
fi
grep -q 'INCLUDE_ADB_SHELL": false' lab/images/ws-scrcpy/build.config.override.json
grep -q '@sha256:' lab/images/ws-scrcpy/Dockerfile
grep -q 'WS_SCRCPY_COMMIT=' lab/images/ws-scrcpy/Dockerfile
grep -q 'WS_SCRCPY_PATHNAME' lab/images/ws-scrcpy/patches/0001-pathname.patch
grep -q 'server.listen(port, listenHost' lab/images/ws-scrcpy/patches/0002-open5g-bind.patch
grep -q '2000000' lab/images/ws-scrcpy/patches/0002-open5g-bind.patch
grep -q 'open5g-limits.js' lab/scripts/android-ue-screen.sh
grep -q -- '--screen-only' docs/deploy/android-emulator-dashboard.md
grep -q 'o5g-screen' docs/deploy/android-emulator-dashboard.md
grep -q 'S1 evidence is pending' docs/deploy/android-emulator-dashboard.md
grep -q 'name: l5gd-screen' lab/compose/docker-compose.android-ue.optional.yml
grep -q 'internal: true' lab/compose/docker-compose.android-ue.optional.yml
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
digest=$(python3 -c 'print("a"*64)')
if ! android_ue_screen_image_ok "example.invalid/ws-scrcpy@sha256:${digest}"; then
  echo "pinned screen image was rejected" >&2
  exit 1
fi
if android_ue_screen_image_ok "example.invalid/ws-scrcpy:test"; then
  echo "unpinned screen image was accepted" >&2
  exit 1
fi
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
if android_ue_nonloop_v6_ok "$v6_lab/if_inet6" "$v6_lab/sys"; then
  echo "fe80 alone was accepted as the IPv6 anchor" >&2
  exit 1
fi
printf '%s 03 80 00 40 dummy0\n' "$ula_addr" >"$v6_lab/if_inet6"
if android_ue_nonloop_v6_ok "$v6_lab/if_inet6" "$v6_lab/sys"; then
  echo "tentative ULA was accepted" >&2
  exit 1
fi
rm -rf "$v6_lab"

echo "require_ipv6 ignores host sysfs"
if [ -e /sys/class/net/dummy0 ]; then
  echo "this host has dummy0; the fixture must still ignore host sysfs" >&2
fi
fixdir=$(mktemp -d)
cat >"$fixdir/docker" <<'EOF'
#!/bin/bash
target=${*: -1}
case "$target" in
  l5gd-ue1) printf '%s\n' "/l5gd-ue1 4242" ;;
  *)
    echo "refusing sysctl target ${target}" >&2
    exit 1
    ;;
esac
EOF
cat >"$fixdir/nsenter" <<'EOF'
#!/bin/bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    -t) shift 2 ;;
    -n|-m) shift ;;
    *) break ;;
  esac
done
cmd=${1:-}
base=${cmd##*/}
if [ "$base" = cat ]; then
  case "${2:-}" in
    /proc/sys/*)
      rel=${2#/proc/sys/}
      key=$(printf '%s\n' "$rel" | tr '/' '.')
      file="${ANDROID_UE_FIXTURE_STATE}/${key}"
      if [ -f "$file" ]; then
        cat "$file"
      else
        printf '1\n'
      fi
      ;;
    /sys/*)
      echo "fixture refused a host sysfs read: ${2:-}" >&2
      exit 1
      ;;
    *)
      echo "fixture nsenter cat unexpected path: ${2:-}" >&2
      exit 1
      ;;
  esac
  exit 0
fi
if [ "$base" = sysctl ]; then
  if [ "${2:-}" != -w ]; then
    echo "fixture sysctl expected -w, got: $*" >&2
    exit 1
  fi
  spec=${3:-}
  key=${spec%%=*}
  val=${spec#*=}
  if [ "${ANDROID_UE_FIXTURE_MODE:-up}" = writefail ]; then
    echo "host sysctl write failed" >&2
    exit 1
  fi
  if [ "${ANDROID_UE_FIXTURE_MODE:-up}" = stay1 ]; then
    printf '1\n' >"${ANDROID_UE_FIXTURE_STATE}/${key}"
    exit 0
  fi
  if [ "${ANDROID_UE_FIXTURE_MODE:-up}" = eth0autoconf ] && [ "$key" = net.ipv6.conf.eth0.autoconf ]; then
    printf '1\n' >"${ANDROID_UE_FIXTURE_STATE}/${key}"
    exit 0
  fi
  printf '%s\n' "$val" >"${ANDROID_UE_FIXTURE_STATE}/${key}"
  exit 0
fi
if [ "$base" = iptables ]; then
  if [ "${2:-}" = -S ] && { [ "${3:-}" = ANDROID_UE_GUARD ] || [ "${3:-}" = ANDROID_UE_IN4 ]; }; then
    exit 0
  fi
  echo "fixture iptables unexpected: $*" >&2
  exit 1
fi
exec "$@"
EOF
cat >"$fixdir/ip" <<'EOF'
#!/bin/bash
joined="$*"
mode=${ANDROID_UE_FIXTURE_MODE:-up}
case "$joined" in
  "-6 addr show dev lo")
    printf '%s\n' "1: lo    inet6 ::1/128 scope host"
    ;;
  "-o link show dev dummy0")
    if [ "$mode" = down ]; then
      printf '%s\n' "2: dummy0: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000"
    else
      printf '%s\n' "2: dummy0: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
    fi
    ;;
  "-6 -o addr show dev dummy0 scope global")
    if [ "$mode" = tentative ]; then
      printf '%s\n' "2: dummy0    inet6 fdc2:fd97:24a4::1/128 scope global tentative"
    else
      printf '%s\n' "2: dummy0    inet6 fdc2:fd97:24a4::1/128 scope global nodad"
    fi
    ;;
  "-6 route show default")
    printf '%s\n' "unreachable default metric 1"
    ;;
  "-6 route show")
    printf '%s\n' "unreachable default metric 1"
    ;;
  "link show dev tun_srsue"|"link show dev dummy0"|"link show dev eth0")
    exit 0
    ;;
  "link show dev l5gd-screen")
    exit 1
    ;;
  "-o link show")
    printf '%s\n' "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
    printf '%s\n' "2: dummy0: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
    printf '%s\n' "3: eth0: <BROADCAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
    printf '%s\n' "4: tun_srsue: <POINTOPOINT,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
    printf '%s\n' "5: l5gd-screen: <BROADCAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
    ;;
  *)
    echo "fixture ip unexpected: $joined" >&2
    exit 1
    ;;
esac
EOF
chmod 0755 "$fixdir/docker" "$fixdir/nsenter" "$fixdir/ip"
run_require() {
  local mode=$1
  rm -rf "$fixdir/state"
  mkdir -p "$fixdir/state"
  (
    ANDROID_UE_SOURCE_ONLY=1
    # shellcheck disable=SC1091
    . lab/scripts/android-ue-up.sh
    ANDROID_UE_FIXTURE_MODE=$mode ANDROID_UE_FIXTURE_STATE="$fixdir/state" ANDROID_UE_TUN_WAIT=1 PATH="$fixdir:$PATH" android_ue_require_ipv6 1
  )
}
if ! run_require up >/tmp/android-ue-require-up.out; then
  echo "require_ipv6 rejected an UP dummy0 ULA while host sysfs has no dummy0" >&2
  exit 1
fi
if ! grep -q 'dummy0 ULA' /tmp/android-ue-require-up.out; then
  echo "require_ipv6 did not report the ULA anchor" >&2
  exit 1
fi
if ! grep -qx 0 "$fixdir/state/net.ipv6.conf.tun_srsue.accept_ra"; then
  echo "host did not set accept_ra=0 on tun_srsue after the sidecar write was skipped" >&2
  exit 1
fi
if run_require down >/dev/null 2>&1; then
  echo "require_ipv6 accepted a DOWN dummy0" >&2
  exit 1
fi
if run_require tentative >/dev/null 2>&1; then
  echo "require_ipv6 accepted a tentative ULA" >&2
  exit 1
fi
if run_require writefail >/tmp/android-ue-require-write.out 2>/tmp/android-ue-require-write.err; then
  echo "require_ipv6 continued after the host sysctl write failed" >&2
  exit 1
fi
if ! grep -q 'host sysctl' /tmp/android-ue-require-write.err; then
  cat /tmp/android-ue-require-write.err >&2
  echo "a failed host sysctl write was not reported" >&2
  exit 1
fi
if run_require stay1 >/tmp/android-ue-require-stay.out 2>/tmp/android-ue-require-stay.err; then
  echo "require_ipv6 accepted a sysctl that stayed at 1" >&2
  exit 1
fi
if ! grep -q 'is 1, expected 0' /tmp/android-ue-require-stay.err; then
  cat /tmp/android-ue-require-stay.err >&2
  echo "a sysctl left at 1 was not rejected" >&2
  exit 1
fi
if run_require eth0autoconf >/tmp/android-ue-require-eth0.out 2>/tmp/android-ue-require-eth0.err; then
  echo "require_ipv6 accepted autoconf=1 on eth0" >&2
  exit 1
fi
if ! grep -q 'net.ipv6.conf.eth0.autoconf is 1, expected 0' /tmp/android-ue-require-eth0.err; then
  cat /tmp/android-ue-require-eth0.err >&2
  echo "eth0 autoconf=1 was not fail-closed" >&2
  exit 1
fi
rm -rf "$fixdir"

echo "tun created after defaults inherits 0"
inherit_ns=android-ue-inherit-$$
(
  set -euo pipefail
  trap 'sudo ip netns del "$inherit_ns" >/dev/null 2>&1 || true' EXIT
  sudo ip netns add "$inherit_ns"
  sudo ip netns exec "$inherit_ns" sysctl -w \
    net.ipv6.conf.all.accept_ra=0 \
    net.ipv6.conf.all.autoconf=0 \
    net.ipv6.conf.all.forwarding=0 \
    net.ipv6.conf.default.accept_ra=0 \
    net.ipv6.conf.default.autoconf=0 \
    net.ipv6.conf.default.forwarding=0 >/dev/null
  sudo ip netns exec "$inherit_ns" ip link add tun_srsue type veth peer name tun_peer
  for knob in accept_ra autoconf forwarding; do
    got=$(sudo ip netns exec "$inherit_ns" cat "/proc/sys/net/ipv6/conf/tun_srsue/${knob}")
    if [ "$got" != 0 ]; then
      echo "tun created after up inherited ${knob}=${got}" >&2
      exit 1
    fi
  done
  sudo ip netns exec "$inherit_ns" ip link del tun_srsue
  sudo ip netns exec "$inherit_ns" ip link add tun_srsue type veth peer name tun_peer
  for knob in accept_ra autoconf forwarding; do
    got=$(sudo ip netns exec "$inherit_ns" cat "/proc/sys/net/ipv6/conf/tun_srsue/${knob}")
    if [ "$got" != 0 ]; then
      echo "re-attached tun kept ${knob}=${got}" >&2
      exit 1
    fi
  done
)

if android_ue_android_image_ok 'halimqarroum/docker-android:api-33'; then
  echo "registry image without a digest was accepted" >&2
  exit 1
fi
android_ue_android_image_ok 'open5g-android-emulator:local'
if android_ue_android_image_ok 'example.invalid/android@sha256:0123456789abcdef'; then
  echo "a short image digest was accepted" >&2
  exit 1
fi
android_ue_android_image_ok 'example.invalid/android@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
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
if printf '%s\n' "$without" | grep -qx 'ue1-screen'; then
  echo "screen sidecar starts while its image is still a placeholder" >&2
  exit 1
fi
screen_env=$tmp/screen.env
sed 's/^ANDROID_UE_SCREEN_IMAGE=.*/ANDROID_UE_SCREEN_IMAGE=example.invalid\/ws-scrcpy:test/' "$example" >"$screen_env"
screen_list=$(lab/scripts/android-ue-up.sh --env-file "$screen_env" --print-services)
printf '%s\n' "$screen_list" | grep -qx 'ue1-screen'
if printf '%s\n' "$screen_list" | grep -qx 'egress'; then
  echo "screen list started egress" >&2
  exit 1
fi
if printf '%s\n' "$without" | grep -qx 'egress'; then
  echo "egress is in the default service list" >&2
  exit 1
fi
with_socks=$(lab/scripts/android-ue-up.sh --env-file "$example" --with-socks-egress --print-services)
printf '%s\n' "$with_socks" | grep -qx 'egress'
printf '%s\n' "$with_socks" | grep -qx 'egress-dns'
printf '%s\n' "$with_socks" | grep -qx 'cgnat'

echo "host screen demo"
lab/scripts/android-ue-screen-standalone.sh --check
if SCREEN_STANDALONE_ENV=lab/compose/screen-standalone.env.example \
  lab/scripts/android-ue-screen-standalone.sh --print; then
  echo "standalone print accepted the placeholder env" >&2
  exit 1
fi
pin=$(python3 -c 'print("b"*64)')
good_bind=192.0.2.32
if ANDROID_UE_SCREEN_IMAGE="sha256:${pin}" \
  SCREEN_PUBLISH_ADDR=192.0.2.33 \
  ANDROID_UE_SCREEN_BIND="$good_bind" \
  lab/scripts/android-ue-screen-standalone.sh --print; then
  echo "standalone print accepted an image id without @sha256" >&2
  exit 1
fi
if ANDROID_UE_SCREEN_IMAGE="example.invalid/ws-scrcpy:local" \
  SCREEN_PUBLISH_ADDR=192.0.2.33 \
  ANDROID_UE_SCREEN_BIND="$good_bind" \
  lab/scripts/android-ue-screen-standalone.sh --print; then
  echo "standalone print accepted an unpinned tag" >&2
  exit 1
fi
if ANDROID_UE_SCREEN_IMAGE="example.invalid/ws-scrcpy@sha256:${pin}" \
  SCREEN_PUBLISH_ADDR=192.0.2.33 \
  ANDROID_UE_SCREEN_BIND=127.0.0.1 \
  lab/scripts/android-ue-screen-standalone.sh --print; then
  echo "standalone print accepted a loopback screen bind" >&2
  exit 1
fi
digest_print=$(ANDROID_UE_SCREEN_IMAGE="example.invalid/ws-scrcpy@sha256:${pin}" \
  SCREEN_PUBLISH_ADDR=192.0.2.33 \
  ANDROID_UE_SCREEN_BIND="$good_bind" \
  lab/scripts/android-ue-screen-standalone.sh --print)
printf '%s\n' "$digest_print" | grep -q 'compose.screen-standalone.yml'
printf '%s\n' "$digest_print" | grep -q ' up -d'
printf '%s\n' "$digest_print" | grep -q 'nsenter -t <pid> -n'
printf '%s\n' "$digest_print" | grep -q 'docker network connect'
if printf '%s\n' "$digest_print" | grep -q 'sha256:'; then
  echo "standalone print leaked the image digest" >&2
  exit 1
fi
down_print=$(lab/scripts/android-ue-screen-standalone.sh --print-down)
printf '%s\n' "$down_print" | grep -q 'network disconnect b0-screen b0-agen-emu'
printf '%s\n' "$down_print" | grep -q 'network rm b0-screen'
if printf '%s\n' "$down_print" | grep -E 'docker (stop|rm).*b0-agen-emu'; then
  echo "standalone down stops or removes the emulator" >&2
  exit 1
fi
chain=$(lab/scripts/android-ue-screen-chain.sh --render 192.0.2.33)
printf '%s\n' "$chain" | grep -q -- '-s 192.0.2.33 --dport 8000 -j ACCEPT'
printf '%s\n' "$chain" | grep -q -- '--dport 8000 -j DROP'
if lab/scripts/android-ue-screen-chain.sh --render 127.0.0.1; then
  echo "screen chain accepted a loopback publisher" >&2
  exit 1
fi
if lab/scripts/android-ue-screen-chain.sh --pid-ok other 12 12; then
  echo "screen chain entered a container other than b0-agen-emu" >&2
  exit 1
fi
if lab/scripts/android-ue-screen-chain.sh --pid-ok b0-agen-emu 12 13; then
  echo "screen chain accepted a pid that does not belong to b0-agen-emu" >&2
  exit 1
fi
lab/scripts/android-ue-screen-chain.sh --pid-ok b0-agen-emu 12 12
if lab/scripts/android-ue-screen-chain.sh --bind-match 192.0.2.32 192.0.2.33; then
  echo "screen bind matched a different inspect address" >&2
  exit 1
fi
lab/scripts/android-ue-screen-chain.sh --bind-match 192.0.2.32 192.0.2.32
if lab/scripts/android-ue-screen-chain.sh --smoke-judge 0 0; then
  echo "smoke accepted a host path to port 8000" >&2
  exit 1
fi
lab/scripts/android-ue-screen-chain.sh --smoke-judge 7 0
grep -q 'Netdrive-only' docs/deploy/android-emulator-host-screen.md
grep -q 'no RBAC/409/revoke/audit on 3301' docs/deploy/android-emulator-host-screen.md
grep -q 'docker inspect' docs/deploy/android-emulator-host-screen.md
grep -q 'android-ue-screen.sh' lab/compose/compose.screen-standalone.yml
grep -q '/emulator/ue1' lab/compose/compose.screen-standalone.yml
grep -q 'ANDROID_UE_SCREEN_MAX_SIZE' lab/compose/compose.screen-standalone.yml
if grep -q 'ada di `/' docs/deploy/android-emulator-host-screen.md; then
  echo "host runbook still says the UI is only at /" >&2
  exit 1
fi
grep -q '/emulator/ue1/' docs/deploy/android-emulator-host-screen.md
if SCREEN_PUBLISH_BIND=0.0.0.0 lab/scripts/android-ue-screen-publish.sh --check-bind; then
  echo "screen publish accepted every interface" >&2
  exit 1
fi
if ! ANDROID_EMULATOR_CONTAINER=b0-agen-emu lab/scripts/android-ue-screen-publish.sh --check-upstream; then
  echo "screen publish rejected the emulator container name" >&2
  exit 1
fi
if ANDROID_EMULATOR_CONTAINER=0.0.0.0 lab/scripts/android-ue-screen-publish.sh --check-upstream; then
  echo "screen publish accepted an unspecified upstream" >&2
  exit 1
fi
if ANDROID_EMULATOR_SSH_TARGET=REPLACE_ANDROID_EMULATOR_SSH_TARGET lab/scripts/android-ue-screen-tunnel.sh --print; then
  echo "screen tunnel accepted a placeholder target" >&2
  exit 1
fi
tunnel=$(ANDROID_EMULATOR_SSH_TARGET=operator@example.invalid lab/scripts/android-ue-screen-tunnel.sh --print)
printf '%s\n' "$tunnel" | grep -q -- '-L 127.0.0.1:3302:127.0.0.1:3301'
if printf '%s\n' "$tunnel" | grep -Eq -- '(^|[[:space:]])-R([[:space:]]|$)|0\.0\.0\.0|-g([[:space:]]|$)'; then
  echo "screen tunnel is not loopback-only: ${tunnel}" >&2
  exit 1
fi
laptop=$(ANDROID_EMULATOR_SSH_TARGET=operator@example.invalid SCREEN_TUNNEL_LOCAL_PORT=3301 \
  lab/scripts/android-ue-screen-tunnel.sh --print)
printf '%s\n' "$laptop" | grep -q -- '-L 127.0.0.1:3301:127.0.0.1:3301'
mode_guest=$(lab/scripts/android-ue-screen-mode.sh)
printf '%s\n' "$mode_guest" | grep -qx 'mode=guest'
poison=$(OPEN5G_EMULATOR_SCREEN_MODE=guest SCREEN_UPSTREAM_URL='http://198.51.100.10:3301' \
  lab/scripts/android-ue-screen-mode.sh)
printf '%s\n' "$poison" | grep -qx 'mode=guest'
if OPEN5G_EMULATOR_SCREEN_MODE=host-agen lab/scripts/android-ue-screen-mode.sh; then
  echo "host-agen mode ran with an empty upstream" >&2
  exit 1
fi
if OPEN5G_EMULATOR_SCREEN_MODE=host-agen SCREEN_UPSTREAM_URL='http://198.51.100.10:3301' \
  lab/scripts/android-ue-screen-mode.sh; then
  echo "host-agen mode accepted a non-loopback upstream" >&2
  exit 1
fi
ready=$(OPEN5G_EMULATOR_SCREEN_MODE=host-agen SCREEN_UPSTREAM_URL='http://127.0.0.1:3302' \
  lab/scripts/android-ue-screen-mode.sh)
printf '%s\n' "$ready" | grep -qx 'mode=host-agen upstream=loopback'
if printf '%s\n' "$ready" | grep -q '3302'; then
  echo "mode check printed the upstream URL" >&2
  exit 1
fi
grep -q 'ANDROID_EMULATOR_CONTAINER=b0-agen-emu' lab/compose/screen-standalone.env.example
grep -q 'B0_SCREEN_SUBNET=192.0.2.0/24' lab/compose/screen-standalone.env.example
grep -q 'REPLACE_ANDROID_UE_SCREEN_IMAGE' lab/compose/screen-standalone.env.example
if grep -q 'ANDROID_EMULATOR_NETWORK' lab/compose/screen-standalone.env.example lab/compose/compose.screen-standalone.yml; then
  echo "standalone screen still attaches the emulator bridge" >&2
  exit 1
fi
if grep -q 'group_add:' lab/compose/compose.screen-standalone.yml || grep -q '/dev/kvm' lab/compose/compose.screen-standalone.yml; then
  echo "standalone screen compose claims kvm" >&2
  exit 1
fi

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
grep -q 'container_name: l5gd-ue1-screen' "$rendered"
grep -q 'container_name: l5gd-ue2-screen' "$rendered"
grep -q 'ANDROID_UE_SCREEN_BIND' lab/compose/docker-compose.android-ue.optional.yml
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

echo "standalone screen compose render"
standalone_rendered=$tmp/rendered-screen.json
"${compose[@]}" -f lab/compose/compose.screen-standalone.yml \
  --env-file lab/compose/screen-standalone.env.example \
  config --format json >"$standalone_rendered"
python3 - "$standalone_rendered" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    rendered = json.load(handle)
services = rendered.get("services") or {}
if set(services) != {"screen", "screen-publish"}:
    sys.exit(f"unexpected services: {sorted(services)}")
screen = services["screen"]
publish = services["screen-publish"]
if screen.get("network_mode") != "container:b0-agen-emu":
    sys.exit(f"screen network mode is {screen.get('network_mode')}")
nets = publish.get("networks") or {}
if set(nets) != {"b0-screen"}:
    sys.exit(f"screen-publish networks are {sorted(nets)}")
b0 = (rendered.get("networks") or {}).get("b0-screen") or {}
if b0.get("internal") is not True or b0.get("enable_ipv6") not in (False,):
    sys.exit(f"b0-screen is not an internal IPv4 network: {b0}")
if screen.get("ports") or screen.get("build") or publish.get("build"):
    sys.exit("screen publishes a port or the file builds an image")
ports = publish.get("ports") or []
if len(ports) != 1:
    sys.exit(f"expected one published port, got {ports}")
binding = ports[0]
host_ip = str(binding.get("host_ip") or "")
published = str(binding.get("published") or "")
target = str(binding.get("target") or "")
if host_ip != "127.0.0.1" or published != "3301" or target != "3301":
    sys.exit(f"published port is not loopback 3301: {binding}")
for service in (screen, publish):
    if service.get("privileged"):
        sys.exit("standalone screen service is privileged")
    if "NET_ADMIN" in " ".join(service.get("cap_add") or []):
        sys.exit("standalone screen service adds NET_ADMIN")
blob = json.dumps(rendered)
for banned in ("0.0.0.0", "/dev/kvm", "group_add"):
    if banned in blob:
        sys.exit(f"rendered standalone compose contains {banned}")
PY

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
preflight_image=open5g-android-ue-preflight:local
if ! "${docker_cmd[@]}" image inspect "$preflight_image" >/dev/null 2>&1; then
  "${docker_cmd[@]}" build -t "$preflight_image" - <<'EOF'
FROM alpine:3.20
RUN apk add --no-cache bash iproute2 python3
RUN printf '%s\n' '#!/bin/sh' 'exit 0' > /usr/bin/emulator && chmod 0755 /usr/bin/emulator
EOF
fi
"${docker_cmd[@]}" rm -f android-ue-preflight-ns >/dev/null 2>&1 || true
if ! "${docker_cmd[@]}" run -d --name android-ue-preflight-ns --network none --cap-add NET_ADMIN \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  --sysctl net.ipv6.conf.default.disable_ipv6=0 \
  --sysctl net.ipv6.conf.lo.disable_ipv6=0 \
  "$preflight_image" sleep 60 >/dev/null; then
  echo "preflight netns holder did not start" >&2
  exit 1
fi
if ! "${docker_cmd[@]}" exec android-ue-preflight-ns sh -c '
  set -eu
  ip link add dummy0 type veth peer name dummy0peer
  ip link set dummy0 addrgenmode none
  ip link set dummy0 up
  ip link set dummy0peer up
  ip -6 addr show dev lo | grep -q "inet6 ::1" || ip -6 addr add ::1/128 dev lo
  # This shell is docker exec inside the preflight netns, not the host.
  ip -o link show dev dummy0 | grep -Eq "<([^>]*,)?UP(,[^>]*)?>"
  ip -6 addr add fdc2:fd97:24a4::1/128 dev dummy0 nodad
  ip -6 route del fdc2:fd97:24a4::1/128 dev dummy0 >/dev/null 2>&1 || true
  ip -6 route del fe80::/64 dev dummy0 >/dev/null 2>&1 || true
  ip -6 route replace unreachable default metric 1
'; then
  "${docker_cmd[@]}" logs android-ue-preflight-ns >&2 || true
  "${docker_cmd[@]}" rm -f android-ue-preflight-ns >/dev/null 2>&1 || true
  echo "could not prepare dummy0 in the preflight netns" >&2
  exit 1
fi
if ! "${docker_cmd[@]}" run --rm --network container:android-ue-preflight-ns --cap-drop ALL \
  -v "$PWD/lab/images/android-emulator/open5g-preflight.sh:/opt/open5g-preflight.sh:ro" \
  -v /dev/zero:/dev/kvm:ro \
  -e ANDROID_UE_IPV6_ULA=fdc2:fd97:24a4::1/128 \
  "$preflight_image" bash /opt/open5g-preflight.sh; then
  "${docker_cmd[@]}" rm -f android-ue-preflight-ns >/dev/null 2>&1 || true
  echo "preflight failed in a container without NET_ADMIN" >&2
  exit 1
fi
"${docker_cmd[@]}" rm -f android-ue-preflight-ns >/dev/null
echo "preflight passed without NET_ADMIN"
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
