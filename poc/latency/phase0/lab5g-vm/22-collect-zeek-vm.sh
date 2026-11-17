#!/bin/bash
# read-only: salin log zeek-live yang relevan (conn/tunnel/gtpu_agg/gtpv2 rotasi 04-50 UTC) + baris tunnel parent.
set -u
. "$(dirname "$0")/common-vm.sh"
OUT=$(ls -d ~/poc-latency/phase0/vm-run-*/ | tail -1)zeek-live; mkdir -p $OUT
for f in conn.2026-11-17-04-50-00.log tunnel.2026-11-17-04-50-00.log gtpu_agg.2026-11-17-04-50-00.log gtpv2.2026-11-17-04-50-00.log; do
  $V "sudo -n cat /dev/shm/netprobe-zeek-live/$f" > $OUT/$f
done
ls -la $OUT
echo "### tunnel parents"; grep -E 'CixY1LCEG62pYPOve|CD4Rfe2CoJncdyHpd|Cyvvtm36t6KTXDxIrg|CL32z3kw8uR4Cc8zg' $OUT/tunnel.2026-11-17-04-50-00.log $OUT/conn.2026-11-17-04-50-00.log | cut -c1-600
echo "### gtpu_agg"; head -c 2500 $OUT/gtpu_agg.2026-11-17-04-50-00.log
cd ~/poc-latency/phase0 && tar czf phase0-vm-all.tgz $(basename $(dirname $OUT))  2*.out 1*.out *.sh
