#!/bin/sh
# Kept so an older command cannot be replaced with an open SNAT rule.
# Per-UE rate and connection limits are meters in the base ruleset.
set -eu
echo "android-ue-add-ue: not adding accept or SNAT rules. Limits are in table ip cgnat." >&2
exit 0
