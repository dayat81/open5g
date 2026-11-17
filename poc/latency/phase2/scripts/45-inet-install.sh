#!/bin/bash
# poc-inet CGNAT: pasang script inet baru dari ~/poc-latency/phase2/inet-stage ke ~/poc-latency/inet (backup dulu), lalu 40-inet-setup.sh
I=~/poc-latency/inet; S=~/poc-latency/phase2/inet-stage; B=$I/backup-$(date +%Y%m%d-%H%M%S)
[ -d $S ] || { echo "inet-stage tidak ada"; exit 1; }
mkdir -p $B && cp -a $I/*.sh $I/vm $I/laptop $I/README.md $B/ 2>/dev/null; echo "backup -> $B"
cp -a $S/*.sh $I/ && cp -a $S/vm/. $I/vm/ && cp -a $S/laptop/. $I/laptop/ && cp -a $S/README.md $I/ && chmod +x $I/*.sh $I/vm/*.sh
[ "${1:-}" = "--no-setup" ] || bash $I/40-inet-setup.sh
