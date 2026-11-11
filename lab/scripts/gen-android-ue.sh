#!/bin/bash
# Emit the android-ue Compose overlay. The committed file is the N=2 output.
# Cap is 2: one eNB+UE+emulator per user, which is all this guest can describe.
set -euo pipefail

count=2
mode="write"
out=""

usage() {
  echo "usage: gen-android-ue.sh [--check | --stdout | --write] [--count 1|2]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) mode="check" ;;
    --stdout) mode="stdout" ;;
    --write) mode="write" ;;
    --count)
      shift
      [ "$#" -gt 0 ] || usage
      count=$1
      ;;
    *) usage ;;
  esac
  shift
done

case "$count" in
  1|2) ;;
  *)
    echo "android-ue cap is 2 (got ${count})" >&2
    exit 2
    ;;
esac

if [ "$mode" = "check" ] && [ "$count" != 2 ]; then
  echo "--check compares the committed N=2 overlay" >&2
  exit 2
fi

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
dest=${out:-"$root/lab/compose/docker-compose.android-ue.optional.yml"}

emit_user() {
  local n=$1
  cat <<EOF
  ue${n}:
    image: \${ANDROID_UE_SRS_IMAGE:?ANDROID_UE_SRS_IMAGE}
    container_name: l5gd-ue${n}
    restart: "no"
    profiles: ["android-ue"]
    cpus: 2.0
    mem_limit: 2048m
    cap_add: [NET_ADMIN]
    devices:
      - "/dev/net/tun:/dev/net/tun"
    command:
      - ue
      - "--rf.device_name=zmq"
      - "--rf.device_args=tx_port0=tcp://\${UE${n}_UU:?UE${n}_UU}:2001,rx_port0=tcp://\${UE${n}_ENB_UU:?UE${n}_ENB_UU}:2000,tx_port1=tcp://\${UE${n}_UU}:2101,rx_port1=tcp://\${UE${n}_ENB_UU}:2100,id=ue,base_srate=\${ZMQ_BASE_SRATE:?ZMQ_BASE_SRATE}"
    environment:
      UE_IMSI: \${UE${n}_IMSI:?UE${n}_IMSI}
      UE_KI: \${UE${n}_KI:?UE${n}_KI}
      UE_OPC: \${UE${n}_OPC:?UE${n}_OPC}
      UE_IMEI: \${UE${n}_IMEI:?UE${n}_IMEI}
      UE_ALGO: \${UE_ALGO:?UE_ALGO}
      KEY: \${UE${n}_KI}
      OPC: \${UE${n}_OPC}
      ALGO: \${UE_ALGO}
      UE_ADDRESS: \${UE${n}_UU}
      ENB_ADDRESS: \${UE${n}_ENB_UU}
      ZMQ_BASE_SRATE: \${ZMQ_BASE_SRATE}
      DL_EARFCN: \${DL_EARFCN:?DL_EARFCN}
      TX_GAIN: \${TX_GAIN:?TX_GAIN}
      APN: \${APN:?APN}
      ENABLE_NAT: "false"
      ZMQ: "false"
    dns:
      - \${ANDROID_UE_PGW_DNS:?ANDROID_UE_PGW_DNS}
    volumes:
      - ../config/ran/android-ue.conf.template:/etc/srsran/ue.conf:ro
    networks:
      uu:
        ipv4_address: \${UE${n}_UU}

  enb${n}:
    image: \${ANDROID_UE_SRS_IMAGE}
    container_name: l5gd-enb${n}
    restart: "no"
    profiles: ["android-ue"]
    cpus: 2.0
    mem_limit: 2048m
    entrypoint: ["/bin/bash", "/opt/android-ue/android-ue-enb.sh"]
    command:
      - "--rf.device_name=zmq"
      - "--rf.device_args=fail_on_disconnect=true,tx_port0=tcp://*:2000,rx_port0=tcp://\${UE${n}_UU}:2001,tx_port1=tcp://*:2100,rx_port1=tcp://\${UE${n}_UU}:2101,id=enb,base_srate=\${ZMQ_BASE_SRATE}"
    environment:
      ENB_ID: \${UE${n}_ENB_ID:?UE${n}_ENB_ID}
      MCC: \${MCC:?MCC}
      MNC: \${MNC:?MNC}
      TAC: \${TAC:?TAC}
      N_PRB: \${N_PRB:?N_PRB}
      TX_GAIN: \${TX_GAIN}
      RX_GAIN: \${RX_GAIN:?RX_GAIN}
      MME_ADDR: \${MME_ADDR:?MME_ADDR}
      GTP_BIND_ADDR: \${UE${n}_ENB_S1U:?UE${n}_ENB_S1U}
      S1C_BIND_ADDR: \${UE${n}_ENB_S1:?UE${n}_ENB_S1}
      UE_ADDRESS: \${UE${n}_UU}
      ANDROID_UE_ZMQ_WAIT: \${ANDROID_UE_ZMQ_WAIT:?ANDROID_UE_ZMQ_WAIT}
      ENABLE_NAT: "false"
      ZMQ: "false"
    volumes:
      - ../scripts/android-ue-enb.sh:/opt/android-ue/android-ue-enb.sh:ro
    networks:
      s1mme:
        ipv4_address: \${UE${n}_ENB_S1}
      s1u:
        ipv4_address: \${UE${n}_ENB_S1U}
      uu:
        ipv4_address: \${UE${n}_ENB_UU}
    depends_on:
      ue${n}:
        condition: service_started

  ue${n}-route:
    image: \${ANDROID_UE_SRS_IMAGE}
    container_name: l5gd-ue${n}-route
    restart: "no"
    profiles: ["android-ue"]
    cpus: 0.25
    mem_limit: 128m
    network_mode: "service:ue${n}"
    cap_add: [NET_ADMIN]
    entrypoint: ["/bin/bash", "/opt/android-ue/android-ue-route.sh"]
    environment:
      ANDROID_UE_ENB_UU: \${UE${n}_ENB_UU}
      ANDROID_UE_TUN: tun_srsue
      ANDROID_UE_ATTACH_TIMEOUT: \${ANDROID_UE_ATTACH_TIMEOUT:?ANDROID_UE_ATTACH_TIMEOUT}
    volumes:
      - ../scripts/android-ue-route.sh:/opt/android-ue/android-ue-route.sh:ro
    depends_on:
      enb${n}:
        condition: service_started

  android${n}:
    image: \${ANDROID_UE_ANDROID_IMAGE:?ANDROID_UE_ANDROID_IMAGE}
    container_name: l5gd-android${n}
    restart: "no"
    profiles: ["android-ue"]
    cpus: 2.0
    mem_limit: \${ANDROID_UE_MEM_LIMIT:-4096m}
    shm_size: "1gb"
    network_mode: "service:ue${n}"
    devices:
      - "/dev/kvm:/dev/kvm"
    environment:
      MEMORY: \${ANDROID_UE_MEMORY:?ANDROID_UE_MEMORY}
      CORES: \${ANDROID_UE_CORES:?ANDROID_UE_CORES}
      SKIP_AUTH: \${ANDROID_UE_SKIP_AUTH:?ANDROID_UE_SKIP_AUTH}
      DISABLE_ANIMATION: \${ANDROID_UE_DISABLE_ANIMATION:?ANDROID_UE_DISABLE_ANIMATION}
      EXTRA_FLAGS: "\${ANDROID_UE_EXTRA_FLAGS:?ANDROID_UE_EXTRA_FLAGS} -dns-server \${ANDROID_UE_PGW_DNS:?ANDROID_UE_PGW_DNS}"
    depends_on:
      ue${n}-route:
        condition: service_completed_successfully

EOF
}

emit_all() {
  cat <<'EOF'
# Optional android-ue overlay. Generated by lab/scripts/gen-android-ue.sh.
# Do not edit by hand. Profile android-ue is off unless compose is asked for it.
# Run this file on its own. Do not combine it with the core compose file.
# Addresses, images, and USIM values come from the env file. ZMQ TCP ports are
# the lab's verified single-pair ports and stay inside each container netns.

EOF
  cat <<'EOF'
services:
EOF
  local n
  for n in $(seq 1 "$count"); do
    emit_user "$n"
  done
  cat <<'EOF'
  cgnat:
    image: ${ANDROID_UE_CGNAT_IMAGE:?ANDROID_UE_CGNAT_IMAGE}
    container_name: l5gd-cgnat
    restart: "no"
    profiles: ["android-ue"]
    cpus: 0.25
    mem_limit: 128m
    cap_add: [NET_ADMIN]
    sysctls:
      net.ipv4.ip_forward: "1"
      net.ipv4.conf.all.route_localnet: "1"
    entrypoint: ["/bin/sh", "/opt/cgnat/android-ue-cgnat.sh"]
    environment:
      UE_POOL: ${UE_POOL:?UE_POOL}
      UPF_SGI_ADDR: ${UPF_SGI_ADDR:?UPF_SGI_ADDR}
      CGNAT_SGI_ADDR: ${CGNAT_SGI_ADDR:?CGNAT_SGI_ADDR}
      CGNAT_CT_LIMIT: ${CGNAT_CT_LIMIT:?CGNAT_CT_LIMIT}
      ANDROID_UE_LAB_SUBNET: ${ANDROID_UE_LAB_SUBNET:?ANDROID_UE_LAB_SUBNET}
      ANDROID_UE_SOCKS_ADDR: ${ANDROID_UE_SOCKS_ADDR:?ANDROID_UE_SOCKS_ADDR}
    volumes:
      - ../config/cgnat:/etc/cgnat:ro
      - ../scripts/render-cgnat.sh:/opt/cgnat/render-cgnat.sh:ro
      - ../scripts/android-ue-cgnat.sh:/opt/cgnat/android-ue-cgnat.sh:ro
      - ../scripts/android-ue-add-ue.sh:/opt/cgnat/android-ue-add-ue.sh:ro
    networks:
      sgi:
        ipv4_address: ${CGNAT_SGI_ADDR}
      egress:
        ipv4_address: ${CGNAT_EGRESS_ADDR:?CGNAT_EGRESS_ADDR}

  egress:
    image: ${ANDROID_UE_TUN2SOCKS_IMAGE:?ANDROID_UE_TUN2SOCKS_IMAGE}
    container_name: l5gd-egress
    restart: "no"
    profiles: ["socks-egress"]
    cpus: 0.5
    mem_limit: 256m
    network_mode: "service:cgnat"
    cap_add: [NET_ADMIN]
    devices:
      - "/dev/net/tun:/dev/net/tun"
    entrypoint: ["/bin/sh", "/opt/cgnat/android-ue-egress.sh"]
    environment:
      ANDROID_UE_SOCKS_ADDR: ${ANDROID_UE_SOCKS_ADDR}
    volumes:
      - ../scripts/android-ue-egress.sh:/opt/cgnat/android-ue-egress.sh:ro
    depends_on:
      cgnat:
        condition: service_started

  egress-dns:
    image: ${ANDROID_UE_DNS_IMAGE:?ANDROID_UE_DNS_IMAGE}
    container_name: l5gd-egress-dns
    restart: "no"
    profiles: ["socks-egress"]
    cpus: 0.25
    mem_limit: 128m
    network_mode: "service:cgnat"
    cap_add: [NET_BIND_SERVICE]
    command: ["-conf", "/etc/cgnat/Corefile"]
    volumes:
      - ${ANDROID_UE_STATE_DIR:-/var/lib/open5g-android-ue}/Corefile:/etc/cgnat/Corefile:ro
    depends_on:
      egress:
        condition: service_started

networks:
  s1mme:
    external: true
    name: ${ANDROID_UE_S1MME_NETWORK:?ANDROID_UE_S1MME_NETWORK}
  s1u:
    external: true
    name: ${ANDROID_UE_S1U_NETWORK:?ANDROID_UE_S1U_NETWORK}
  uu:
    external: true
    name: ${ANDROID_UE_UU_NETWORK:?ANDROID_UE_UU_NETWORK}
  sgi:
    external: true
    name: ${ANDROID_UE_SGI_NETWORK:?ANDROID_UE_SGI_NETWORK}
  egress:
    external: true
    name: ${ANDROID_UE_EGRESS_NETWORK:?ANDROID_UE_EGRESS_NETWORK}
EOF
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
emit_all >"$tmp"

case "$mode" in
  stdout) cat "$tmp" ;;
  write)
    mkdir -p "$(dirname -- "$dest")"
    cp "$tmp" "$dest"
    ;;
  check)
    if ! cmp -s "$tmp" "$dest"; then
      echo "overlay is stale; run lab/scripts/gen-android-ue.sh --write" >&2
      diff -u "$dest" "$tmp" || true
      exit 1
    fi
    ;;
esac
