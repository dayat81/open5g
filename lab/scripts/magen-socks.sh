#!/bin/bash
# Rewrite the magen compose so the UPF leaves the egress network.
# Traffic to the Internet then has one next hop, the cgnat service.
# This file does not install policy routing.
set -euo pipefail

magen_socks_render() {
  local src=$1
  python3 - "$src" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines(True)
out = []
in_upf = False
in_networks = False
skip = False
for line in lines:
    if line.startswith("  upf:"):
        in_upf = True
        in_networks = False
    elif in_upf and line.startswith("  ") and not line.startswith("   "):
        in_upf = False
        in_networks = False
    if in_upf and line.startswith("    networks:"):
        in_networks = True
    if in_networks and line.startswith("      egress:"):
        skip = True
        continue
    if skip:
        if line.startswith("        "):
            continue
        skip = False
    out.append(line)
sys.stdout.write("".join(out))
sys.stdout.write("""
  cgnat:
    image: ${O5G_CGNAT_IMAGE:?O5G_CGNAT_IMAGE}
    container_name: o5g-cgnat
    restart: "no"
    cpus: ${O5G_NF_CPUS:?O5G_NF_CPUS}
    mem_limit: ${O5G_NF_MEM:?O5G_NF_MEM}
    cap_add: [NET_ADMIN]
    entrypoint: ["/bin/sh", "/opt/cgnat/android-ue-cgnat.sh"]
    environment:
      UE_POOL: ${O5G_UE_POOL:?O5G_UE_POOL}
      UPF_SGI_ADDR: ${O5G_UPF_CORE:?O5G_UPF_CORE}
      CGNAT_SGI_ADDR: ${O5G_CGNAT_CORE:?O5G_CGNAT_CORE}
      CGNAT_CT_LIMIT: ${CGNAT_CT_LIMIT:?CGNAT_CT_LIMIT}
      ANDROID_UE_LAB_SUBNET: ${O5G_LAB_SUBNET:?O5G_LAB_SUBNET}
      ANDROID_UE_SOCKS_ADDR: ${O5G_SOCKS_ADDR:?O5G_SOCKS_ADDR}
    volumes:
      - ../config/cgnat:/etc/cgnat:ro
      - ../scripts/render-cgnat.sh:/opt/cgnat/render-cgnat.sh:ro
      - ../scripts/android-ue-cgnat.sh:/opt/cgnat/android-ue-cgnat.sh:ro
      - ../scripts/android-ue-add-ue.sh:/opt/cgnat/android-ue-add-ue.sh:ro
    networks:
      core:
        ipv4_address: ${O5G_CGNAT_CORE:?O5G_CGNAT_CORE}
      egress:
        ipv4_address: ${O5G_CGNAT_EGRESS:?O5G_CGNAT_EGRESS}
""")
PY
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

magen_sgi_render() {
  local src=$1
  echo "magen: needs Netdrive approval: egress via host" >&2
  python3 - "$src" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines(True)
out = []
in_upf = False
in_networks = False
inserted = False
for line in lines:
    if line.startswith("  upf:"):
        in_upf = True
        in_networks = False
    elif in_upf and line.startswith("  ") and not line.startswith("   "):
        if in_networks and not inserted:
            out.append("      egress:\n")
            out.append("        ipv4_address: ${O5G_UPF_EGRESS:?O5G_UPF_EGRESS}\n")
            inserted = True
        in_upf = False
        in_networks = False
    if in_upf and line.startswith("    networks:"):
        in_networks = True
    out.append(line)
if not inserted:
    sys.stderr.write("magen: could not attach egress to the UPF\n")
    sys.exit(1)
sys.stdout.write("".join(out))
PY
}

case "${1:-}" in
  --render)
    magen_socks_render "${2:?compose file}"
    ;;
  --sgi-render)
    magen_sgi_render "${2:?compose file}"
    ;;
  *)
    echo "usage: magen-socks.sh --render COMPOSE | --sgi-render COMPOSE" >&2
    exit 2
    ;;
esac
