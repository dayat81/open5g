# Sanitized script reference

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
