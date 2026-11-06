# Sanitized bootstrap reference

#!/bin/bash
# Setup EPC+RAN (no synthetic) + Open5GS SMF/UPF source build workflow on lab5g-dev
set -euo pipefail
B=/home/lab/lab5g-dev
cd "$B"
sudo modprobe sctp || true
echo sctp | sudo tee /etc/modules-load.d/sctp.conf >/dev/null

# --- configs from packaged files ---
mkdir -p conf/fd secrets mongo-data open5gs-src open5gs-install/bin bin
cp -a fd-default/. conf/fd/
# rewrite ConnectTo to IPs
sed -i 's|ConnectTo = "mme"|ConnectTo = "10.99.7.10"|' conf/fd/hss.conf
sed -i 's|ConnectTo = "hss"|ConnectTo = "10.99.7.11"|' conf/fd/mme.conf
sed -i 's|ConnectTo = "pcrf"|ConnectTo = "10.99.8.11"|' conf/fd/smf.conf
sed -i 's|ConnectTo = "smf"|ConnectTo = "10.99.8.12"|' conf/fd/pcrf.conf

LOG=$'logger:\n  level: info'
cat > conf/mme.yaml <<YAML
$LOG
mme:
  freeDiameter: /etc/o5/fd/mme.conf
  s1ap:
    server:
    - address: 10.99.1.10
  gtpc:
    server:
    - address: 10.99.4.10
    client:
      sgwc:
      - address: 10.99.4.11
        tac: 1
      smf:
      - address: 10.99.5.12
        tac: 1
  gummei:
  - plmn_id: {mcc: 001, mnc: 01}
    mme_gid: 2
    mme_code: 1
  tai:
  - plmn_id: {mcc: 001, mnc: 01}
    tac: 1
  security:
    integrity_order: [EIA2, EIA1, EIA0]
    ciphering_order: [EEA0, EEA1, EEA2]
  network_name: {full: Lab5G-Dev, short: LabDev}
  mme_name: lab5g-dev-mme0
YAML
cat > conf/sgwc.yaml <<YAML
$LOG
sgwc:
  gtpc:
    server:
    - address: 10.99.4.11
    - address: 10.99.5.11
  pfcp:
    server:
    - address: 10.99.6.11
    client:
      sgwu:
      - address: 10.99.6.12
        tac: 1
YAML
cat > conf/sgwu.yaml <<YAML
$LOG
sgwu:
  pfcp:
    server:
    - address: 10.99.6.12
  gtpu:
    server:
    - address: 10.99.2.12
    - address: 10.99.5.13
YAML
cat > conf/smf.yaml <<YAML
$LOG
smf:
  freeDiameter: /etc/o5/fd/smf.conf
  pfcp:
    server:
    - address: 10.99.6.13
    client:
      upf:
      - address: 10.99.6.14
  gtpc:
    server:
    - address: 10.99.5.12
  gtpu:
    server:
    - address: 10.99.5.12
  session:
    - subnet: 10.45.0.0/16
      gateway: 10.45.0.1
      dnn: internet
  dns:
  - 10.99.9.20
  mtu: 1400
  ctf:
    enabled: no
YAML
cat > conf/upf.yaml <<YAML
$LOG
upf:
  pfcp:
    server:
    - address: 10.99.6.14
  gtpu:
    server:
    - address: 10.99.5.14
  session:
    - subnet: 10.45.0.0/16
      gateway: 10.45.0.1
      dnn: internet
YAML
cat > conf/hss.yaml <<YAML
db_uri: mongodb://10.99.10.2/open5gs
$LOG
hss:
  freeDiameter: /etc/o5/fd/hss.conf
YAML
cat > conf/pcrf.yaml <<YAML
db_uri: mongodb://10.99.10.2/open5gs
$LOG
pcrf:
  freeDiameter: /etc/o5/fd/pcrf.conf
YAML

# UE keys aligned with ran.env
KEY=<REDACTED_KI>
OPC=<REDACTED_OPC>
cat > secrets/subs.csv <<CSV
001010000000001,$KEY,$OPC
001010000000002,$(openssl rand -hex 16),$(openssl rand -hex 16)
001010000000003,$(openssl rand -hex 16),$(openssl rand -hex 16)
CSV
chmod 600 secrets/subs.csv

cat > ran.env <<ENV
MCC=001
MNC=01
MSISDN=0000000001
ALGO=milenage
KEY=$KEY
OPC=$OPC
ENB_ID=0x19B
TAC=0x0001;
N_PRB=50
TX_GAIN=80
RX_GAIN=40
MME_ADDR=10.99.1.10
S1C_BIND_ADDR=10.99.1.20
GTP_BIND_ADDR=10.99.2.20
ENB_ADDRESS=10.99.11.20
UE_ADDRESS=10.99.11.21
ENV
chmod 600 ran.env

# Compose: stock image by default; SMF/UPF optionally override via ./bin bind-mount when USE_LOCAL_BIN=1
cat > docker-compose.yml <<'YML'
name: lab5g-dev
x-o5: &o5
  image: gradiant/open5gs:2.8.0
  restart: "no"
  cpus: 1.0
  mem_limit: 512m
  volumes:
    - ./conf:/etc/o5:ro
networks:
  s1mme: {internal: true, ipam: {config: [{subnet: 10.99.1.0/24, gateway: 10.99.1.254}]}}
  s1u:   {internal: true, ipam: {config: [{subnet: 10.99.2.0/24, gateway: 10.99.2.254}]}}
  s11:   {internal: true, ipam: {config: [{subnet: 10.99.4.0/24, gateway: 10.99.4.254}]}}
  s5s8:  {internal: true, ipam: {config: [{subnet: 10.99.5.0/24, gateway: 10.99.5.254}]}}
  pfcp:  {internal: true, ipam: {config: [{subnet: 10.99.6.0/24, gateway: 10.99.6.254}]}}
  s6a:   {internal: true, ipam: {config: [{subnet: 10.99.7.0/24, gateway: 10.99.7.254}]}}
  gx:    {internal: true, ipam: {config: [{subnet: 10.99.8.0/24, gateway: 10.99.8.254}]}}
  sgi:   {internal: true, ipam: {config: [{subnet: 10.99.9.0/24, gateway: 10.99.9.254}]}}
  mgmt:  {internal: true, ipam: {config: [{subnet: 10.99.10.0/24, gateway: 10.99.10.254}]}}
services:
  mongo:
    image: mongo:7.0
    container_name: l5gd-mongo
    command: ["mongod","--bind_ip_all","--wiredTigerCacheSizeGB","0.25"]
    cpus: 1.0
    mem_limit: 768m
    networks: {mgmt: {ipv4_address: 10.99.10.2}}
    volumes: ["./mongo-data:/data/db"]
  hss:
    <<: *o5
    container_name: l5gd-hss
    command: ["/opt/open5gs/bin/open5gs-hssd","-c","/etc/o5/hss.yaml"]
    networks: {s6a: {ipv4_address: 10.99.7.11}, mgmt: {ipv4_address: 10.99.10.3}}
    depends_on: [mongo]
  pcrf:
    <<: *o5
    container_name: l5gd-pcrf
    command: ["/opt/open5gs/bin/open5gs-pcrfd","-c","/etc/o5/pcrf.yaml"]
    networks: {gx: {ipv4_address: 10.99.8.11}, mgmt: {ipv4_address: 10.99.10.4}}
    depends_on: [mongo]
  mme:
    <<: *o5
    container_name: l5gd-mme
    command: ["/opt/open5gs/bin/open5gs-mmed","-c","/etc/o5/mme.yaml"]
    networks: {s1mme: {ipv4_address: 10.99.1.10}, s11: {ipv4_address: 10.99.4.10}, s6a: {ipv4_address: 10.99.7.10}}
  sgwc:
    <<: *o5
    container_name: l5gd-sgwc
    command: ["/opt/open5gs/bin/open5gs-sgwcd","-c","/etc/o5/sgwc.yaml"]
    networks: {s11: {ipv4_address: 10.99.4.11}, s5s8: {ipv4_address: 10.99.5.11}, pfcp: {ipv4_address: 10.99.6.11}}
  sgwu:
    <<: *o5
    container_name: l5gd-sgwu
    command: ["/opt/open5gs/bin/open5gs-sgwud","-c","/etc/o5/sgwu.yaml"]
    networks: {pfcp: {ipv4_address: 10.99.6.12}, s1u: {ipv4_address: 10.99.2.12}, s5s8: {ipv4_address: 10.99.5.13}}
  smf:
    <<: *o5
    container_name: l5gd-smf
    command: ["/opt/open5gs/bin/open5gs-smfd","-c","/etc/o5/smf.yaml"]
    networks: {s5s8: {ipv4_address: 10.99.5.12}, pfcp: {ipv4_address: 10.99.6.13}, gx: {ipv4_address: 10.99.8.12}}
  upf:
    <<: *o5
    container_name: l5gd-upf
    user: root
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun:/dev/net/tun"]
    sysctls: {net.ipv4.ip_forward: "1"}
    entrypoint: ["/bin/bash","-c","ip tuntap add name ogstun mode tun && ip addr add 10.45.0.1/16 dev ogstun && ip link set ogstun up && exec /opt/open5gs/bin/open5gs-upfd -c /etc/o5/upf.yaml"]
    networks: {pfcp: {ipv4_address: 10.99.6.14}, s5s8: {ipv4_address: 10.99.5.14}, sgi: {ipv4_address: 10.99.9.10}}
  server:
    image: nicolaka/netshoot:latest
    container_name: l5gd-server
    cpus: 0.5
    mem_limit: 256m
    cap_add: [NET_ADMIN]
    command: ["/bin/sh","-c","ip route add 10.45.0.0/16 via 10.99.9.10; exec iperf3 -s"]
    networks: {sgi: {ipv4_address: 10.99.9.20}}
YML

# override file for local SMF/UPF binaries
cat > docker-compose.override.dev.yml <<'YML'
services:
  smf:
    volumes:
      - ./conf:/etc/o5:ro
      - ./bin/open5gs-smfd:/opt/open5gs/bin/open5gs-smfd:ro
  upf:
    volumes:
      - ./conf:/etc/o5:ro
      - ./bin/open5gs-upfd:/opt/open5gs/bin/open5gs-upfd:ro
YML

cat > docker-compose-ran.yml <<'YML'
name: lab5g-dev-ran
x-srs: &srs
  image: gradiant/srsran-4g:25_10
  restart: "no"
  cpus: 1.0
  mem_limit: 512m
  env_file: ./ran.env
networks:
  s1mme: {external: true, name: lab5g-dev_s1mme}
  s1u: {external: true, name: lab5g-dev_s1u}
  uu: {internal: true, ipam: {config: [{subnet: 10.99.11.0/24, gateway: 10.99.11.254}]}}
services:
  enb:
    <<: *srs
    container_name: l5gd-enb
    command: ["enb","--rf.device_name=zmq","--rf.device_args=tx_port=tcp://*:2000,rx_port=tcp://10.99.11.21:2001,id=enb,base_srate=23.04e6"]
    networks: {s1mme: {ipv4_address: 10.99.1.20}, s1u: {ipv4_address: 10.99.2.20}, uu: {ipv4_address: 10.99.11.20}}
  ue:
    <<: *srs
    container_name: l5gd-ue
    command: ["ue","--rf.device_name=zmq","--rf.device_args=tx_port=tcp://10.99.11.21:2001,rx_port=tcp://10.99.11.20:2000,id=ue,base_srate=23.04e6"]
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun"]
    networks: {uu: {ipv4_address: 10.99.11.21}}
YML

cat > lab-routes.sh <<'SH'
#!/bin/bash
set -u
r() { c=$1; shift; pid=$(docker inspect -f '{{.State.Pid}}' "$c" 2>/dev/null); [ -z "$pid" ] || [ "$pid" = 0 ] && { echo "SKIP $c"; return 1; }
  nsenter -t "$pid" -n ip route replace "$@" && echo "OK $c: $*"; }
r l5gd-smf 10.99.4.0/24 dev eth2
r l5gd-upf 10.99.2.12/32 dev eth1
r l5gd-enb 10.99.5.13/32 dev eth2
docker exec l5gd-ue ip route replace 10.99.9.0/24 dev tun_srsue 2>/dev/null || echo "D5 skip (no tun yet)"
SH
chmod +x lab-routes.sh

cat > lab-up.sh <<'SH'
#!/bin/bash
set -euo pipefail
cd /home/lab/lab5g-dev
COMPOSE=(docker-compose)
# If local bins present, use override
if [ -x bin/open5gs-smfd ] && [ -x bin/open5gs-upfd ]; then
  COMPOSE=(docker-compose -f docker-compose.yml -f docker-compose.override.dev.yml)
  echo "Using LOCAL SMF/UPF binaries from ./bin"
fi
"${COMPOSE[@]}" up -d mongo
for i in $(seq 1 40); do
  docker exec l5gd-mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1 && break
  sleep 2
done
JS="db = db.getSiblingDB('open5gs'); db.subscribers.deleteMany({imsi:/^00101/});"
while IFS=, read imsi k opc; do
  JS="$JS db.subscribers.insertOne({imsi:'$imsi',security:{k:'$k',opc:'$opc',amf:'<REDACTED_AMF>',sqn:NumberLong(0)},ambr:{downlink:{value:1,unit:3},uplink:{value:1,unit:3}},slice:[{sst:1,default_indicator:true,session:[{name:'internet',type:3,qos:{index:9,arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},ambr:{downlink:{value:1,unit:3},uplink:{value:1,unit:3}}}]}],access_restriction_data:32,network_access_mode:0,subscriber_status:0,operator_determined_barring:0,subscribed_rau_tau_timer:12,schema_version:1});"
done < secrets/subs.csv
docker exec l5gd-mongo mongosh --quiet --eval "$JS; print('subscribers=' + db.subscribers.countDocuments({}))"
"${COMPOSE[@]}" up -d hss pcrf mme sgwc sgwu smf upf server
sleep 20
docker-compose -f docker-compose-ran.yml up -d enb
sleep 8
sudo bash ./lab-routes.sh || bash ./lab-routes.sh
docker-compose -f docker-compose-ran.yml up -d ue
sleep 15
sudo bash ./lab-routes.sh || bash ./lab-routes.sh
docker ps --format '{{.Names}} {{.Status}}' | sort
SH
chmod +x lab-up.sh

# rebuild helper
cat > rebuild-smf-upf.sh <<'SH'
#!/bin/bash
# Rebuild Open5GS SMF+UPF from ./open5gs-src (branch dev-smf-upf) and restart only those containers.
set -euo pipefail
cd /home/lab/lab5g-dev
SRC=$PWD/open5gs-src
INSTALL=$PWD/open5gs-install
mkdir -p bin "$INSTALL"
if [ ! -d "$SRC/.git" ]; then
  echo "ERROR: $SRC missing; run setup-open5gs-src.sh first" >&2
  exit 1
fi
echo "Building open5gs from $(git -C "$SRC" rev-parse --abbrev-ref HEAD) @ $(git -C "$SRC" rev-parse --short HEAD)"
# Build inside container using ubuntu + deps; reuse gradiant image libs by building on ubuntu:24.04
docker run --rm --network host \
  -v "$SRC:/src:rw" -v "$INSTALL:/opt/open5gs:rw" \
  -w /src ubuntu:24.04 bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential meson ninja-build pkg-config cmake \
  libgnutls28-dev libgcrypt-dev libssl-dev libidn11-dev libmongoc-dev \
  libbson-dev libyaml-dev libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev \
  libtalloc-dev libsctp-dev flex bison git ca-certificates python3-pip
meson setup build --prefix=/opt/open5gs --buildtype=debugoptimized -Ddocs=false || meson setup build --reconfigure --prefix=/opt/open5gs --buildtype=debugoptimized -Ddocs=false
ninja -C build
ninja -C build install
'
cp -f "$INSTALL/bin/open5gs-smfd" "$INSTALL/bin/open5gs-upfd" bin/
chmod +x bin/open5gs-smfd bin/open5gs-upfd
echo "Installed to ./bin — restarting l5gd-smf l5gd-upf only"
docker-compose -f docker-compose.yml -f docker-compose.override.dev.yml up -d --force-recreate smf upf
sleep 5
docker ps --filter name=l5gd-smf --filter name=l5gd-upf --format '{{.Names}} {{.Status}}'
SH
chmod +x rebuild-smf-upf.sh

cat > setup-open5gs-src.sh <<'SH'
#!/bin/bash
set -euo pipefail
cd /home/lab/lab5g-dev
if [ -d open5gs-src/.git ]; then
  echo "open5gs-src already present"; git -C open5gs-src status -sb; exit 0
fi
# Prefer local tarball if provided
if [ -f /home/lab/images/open5gs-v2.8.0.tar.gz ]; then
  mkdir -p open5gs-src
  tar xzf /home/lab/images/open5gs-v2.8.0.tar.gz -C open5gs-src --strip-components=1
  git -C open5gs-src init
  git -C open5gs-src checkout -b dev-smf-upf
else
  git clone --depth 1 --branch v2.8.0 https://github.com/open5gs/open5gs.git open5gs-src
  git -C open5gs-src checkout -b dev-smf-upf
fi
echo "Source ready on branch $(git -C open5gs-src rev-parse --abbrev-ref HEAD)"
SH
chmod +x setup-open5gs-src.sh

echo "setup-stack files written"
