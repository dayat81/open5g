#!/bin/sh
# Render lab/config/cgnat/cgnat.nft.template to stdout.
# Usage: render-cgnat.sh base|full /path/to/cgnat.nft.template
# base: empty per-UE chains.
# full: rules for NFT_UE_1/NFT_BLOCK_1 and, if set, NFT_UE_2/NFT_BLOCK_2.
# Required env: UE_POOL SGI_IF EGRESS_IF. full also needs CGNAT_SNAT_ADDR and
# CGNAT_CT_LIMIT. Fixture addresses are a syntax sample, not a PGW allocation.
set -eu

mode=${1:?base or full}
template=${2:?template path}
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=cgnat-rules.sh
. "$script_dir/cgnat-rules.sh"

: "${UE_POOL:?UE_POOL}"
: "${SGI_IF:?SGI_IF}"
: "${EGRESS_IF:?EGRESS_IF}"

filter_file=$(mktemp)
nat_file=$(mktemp)
trap 'rm -f "$filter_file" "$nat_file"' EXIT

if [ "$mode" = "full" ]; then
  : "${CGNAT_SNAT_ADDR:?CGNAT_SNAT_ADDR}"
  : "${CGNAT_CT_LIMIT:?CGNAT_CT_LIMIT}"
  : "${NFT_UE_1:?NFT_UE_1}"
  : "${NFT_BLOCK_1:?NFT_BLOCK_1}"
  cgnat_ue_filter_lines "$NFT_UE_1" "$CGNAT_CT_LIMIT" "$SGI_IF" "$EGRESS_IF" >"$filter_file"
  cgnat_ue_nat_lines "$NFT_UE_1" "$CGNAT_SNAT_ADDR" "$NFT_BLOCK_1" "$EGRESS_IF" >"$nat_file"
  if [ -n "${NFT_UE_2:-}" ]; then
    : "${NFT_BLOCK_2:?NFT_BLOCK_2}"
    cgnat_ue_filter_lines "$NFT_UE_2" "$CGNAT_CT_LIMIT" "$SGI_IF" "$EGRESS_IF" >>"$filter_file"
    cgnat_ue_nat_lines "$NFT_UE_2" "$CGNAT_SNAT_ADDR" "$NFT_BLOCK_2" "$EGRESS_IF" >>"$nat_file"
  fi
elif [ "$mode" != "base" ]; then
  echo "render-cgnat.sh: mode must be base or full" >&2
  exit 2
fi

awk -v pool="$UE_POOL" -v sgi="$SGI_IF" -v egress="$EGRESS_IF" \
  -v filter_file="$filter_file" -v nat_file="$nat_file" '
  function dump(path, line) {
    while ((getline line < path) > 0) {
      print line
    }
    close(path)
  }
  {
    gsub(/__UE_POOL__/, pool)
    gsub(/__SGI_IF__/, sgi)
    gsub(/__EGRESS_IF__/, egress)
  }
  $0 ~ /__PER_UE_RULES__/ { dump(filter_file); next }
  $0 ~ /__PER_UE_NAT_RULES__/ { dump(nat_file); next }
  { print }
' "$template"
