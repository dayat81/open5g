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
  lab/scripts/check-android-ue.sh
)
sh_scripts=(
  lab/scripts/render-cgnat.sh
  lab/scripts/android-ue-cgnat.sh
  lab/scripts/android-ue-egress.sh
  lab/scripts/android-ue-add-ue.sh
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
  ANDROID_UE_DNS_IMAGE ANDROID_UE_SOCKS_ADDR ANDROID_UE_LAB_SUBNET; do
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
  lab/config/cgnat/Corefile
  lab/scripts/android-ue-enb.sh
  lab/scripts/android-ue-route.sh
  lab/scripts/android-ue-lib.sh
  lab/scripts/android-ue-up.sh
  lab/scripts/android-ue-down.sh
  lab/scripts/check-android-ue.sh
  docs/integration/android-ue-per-user.md
  docs/deploy/android-ue-lab5g-dev.md
  .github/workflows/android-ue.yml
)
if grep -R -E -n --exclude-dir=.git \
  -e '[0-9A-Fa-f]{32}' \
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

echo "resolver is TCP-only"
corefile=lab/config/cgnat/Corefile
grep -q 'force_tcp' "$corefile"
grep -q 'tcp://' "$corefile"
if grep -q 'udp://' "$corefile"; then
  echo "resolver config has a UDP upstream" >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*log([[:space:]]|$)' "$corefile"; then
  echo "resolver config logs queries" >&2
  exit 1
fi
if grep -Eq 'forward \. ([^t]|t[^c]|tc[^p])' "$corefile"; then
  echo "resolver forward is not tcp://" >&2
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
if grep -E -n '[0-9A-Fa-f]{32}' "$rendered" "$socks_rendered"; then
  echo "rendered compose contains a 32-hex USIM value" >&2
  exit 1
fi
echo "android-ue checks passed"
