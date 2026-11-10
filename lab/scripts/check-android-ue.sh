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
  lab/scripts/cgnat-rules.sh
  lab/scripts/render-cgnat.sh
  lab/scripts/android-ue-cgnat.sh
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
  ANDROID_UE_CGNAT_IMAGE ANDROID_UE_EGRESS_NETWORK; do
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
  lab/scripts/cgnat-rules.sh
  lab/scripts/render-cgnat.sh
  lab/scripts/android-ue-cgnat.sh
  lab/scripts/android-ue-add-ue.sh
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
for needle in ("table ip cgnat", "chain forward", "chain postrouting", "policy drop;", "jump per_ue"):
    if needle not in text:
        errors.append("missing " + needle)
if mode == "full":
    for needle in ("ct count over", "tcp dport 0-65535 snat to", "udp dport 0-65535 snat to", "ip protocol icmp snat to"):
        if needle not in text:
            errors.append("missing " + needle)
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
CGNAT_SNAT_ADDR=$(env_get CGNAT_SNAT_ADDR)
CGNAT_CT_LIMIT=$(env_get CGNAT_CT_LIMIT)
SGI_IF=eth0
EGRESS_IF=eth1
NFT_UE_1=10.45.0.2
NFT_BLOCK_1=$(env_get UE1_PORT_BLOCK)
NFT_UE_2=10.45.0.3
NFT_BLOCK_2=$(env_get UE2_PORT_BLOCK)
export UE_POOL CGNAT_SNAT_ADDR CGNAT_CT_LIMIT SGI_IF EGRESS_IF
export NFT_UE_1 NFT_BLOCK_1 NFT_UE_2 NFT_BLOCK_2
lab/scripts/render-cgnat.sh base lab/config/cgnat/cgnat.nft.template >"$tmp/base.nft"
lab/scripts/render-cgnat.sh full lab/config/cgnat/cgnat.nft.template >"$tmp/full.nft"
syntax_check "$tmp/base.nft" base
syntax_check "$tmp/full.nft" full
nft_rc=0
nft_check "$tmp/base.nft" || nft_rc=$?
if [ "$nft_rc" -eq 1 ]; then
  exit 1
fi
if [ "$nft_rc" -eq 2 ]; then
  echo "base ruleset passed the fallback syntax checker"
else
  nft_check "$tmp/full.nft"
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
grep -q 'container_name: l5gd-cgnat' "$rendered"
grep -q 'android-ue' "$rendered"
if grep -E -n '[0-9A-Fa-f]{32}' "$rendered"; then
  echo "rendered compose contains a 32-hex USIM value" >&2
  exit 1
fi
echo "android-ue checks passed"
