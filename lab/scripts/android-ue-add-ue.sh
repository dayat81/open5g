#!/bin/sh
# Replace per-UE CGNAT rules. Arguments are pairs: <ue-ipv4> <port-block>.
# The UE address is the one the PGW put on tun_srsue, not a fixed pool slot.
# Reads /tmp/cgnat.if written by android-ue-cgnat.sh and CGNAT_* from the environment.
set -eu

meta=/tmp/cgnat.if
snippet=/tmp/cgnat-ue.nft

if [ ! -f "$meta" ]; then
  echo "add-ue: ${meta} is missing; start the cgnat service first" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$meta"
: "${sgi_if:?sgi_if}"
: "${egress_if:?egress_if}"
: "${CGNAT_SNAT_ADDR:?CGNAT_SNAT_ADDR}"
: "${CGNAT_CT_LIMIT:?CGNAT_CT_LIMIT}"

if [ "$#" -eq 0 ] || [ $(( $# % 2 )) -ne 0 ]; then
  echo "usage: android-ue-add-ue.sh <ue-ipv4> <port-block> [<ue-ipv4> <port-block> ...]" >&2
  exit 2
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=cgnat-rules.sh
. "$script_dir/cgnat-rules.sh"

{
  echo "flush chain ip cgnat per_ue"
  echo "flush chain ip cgnat per_ue_nat"
  while [ "$#" -ge 2 ]; do
    ue_ip=$1
    block=$2
    shift 2
    cgnat_ue_filter_lines "$ue_ip" "$CGNAT_CT_LIMIT" "$sgi_if" "$egress_if" | while IFS= read -r line; do
      printf 'add rule ip cgnat per_ue %s\n' "$line"
    done
    cgnat_ue_nat_lines "$ue_ip" "$CGNAT_SNAT_ADDR" "$block" "$egress_if" | while IFS= read -r line; do
      printf 'add rule ip cgnat per_ue_nat %s\n' "$line"
    done
  done
} >"$snippet"

nft -f "$snippet"
echo "cgnat: per-UE rules replaced ($(wc -l < "$snippet") lines)"
