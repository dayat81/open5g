# Sanitized script reference

#!/bin/bash
set -u
r() { c=$1; shift; pid=$(docker inspect -f '{{.State.Pid}}' "$c" 2>/dev/null); [ -z "$pid" ] || [ "$pid" = 0 ] && { echo "SKIP $c"; return 1; }
  nsenter -t "$pid" -n ip route replace "$@" && echo "OK $c: $*"; }
r l5gd-smf 10.99.4.0/24 dev eth2
r l5gd-upf 10.99.2.12/32 dev eth1
r l5gd-enb 10.99.5.13/32 dev eth2
docker exec l5gd-ue ip route replace 10.99.9.0/24 dev tun_srsue 2>/dev/null || echo "D5 skip (no tun yet)"
