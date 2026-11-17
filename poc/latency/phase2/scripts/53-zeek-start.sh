#!/bin/bash
# poc-phase2: jalankan instance Zeek TERPISAH (container poc-phase2-zeek-mglt, image sama dgn netprobe-zeek-live) yang
# membaca mirror0 via libpcap (BUKAN af_packet -> tidak ikut fanout group netprobe-zeek-live, tidak membagi paket).
# netprobe-zeek-live tidak diubah/di-restart. Log: VM /dev/shm/poc-phase2-zeek/mglt.log. Stop: 59-rollback.sh (atau 53 stop).
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
push_vm zeek/mglt.zeek zeek/run-local.zeek zeek/run-live.zeek
$V "sudo -n env ACT=${1:-start} ZCT=$ZCT ZIMG=$ZIMG ZLOG=$ZLOG VM_P2=$VM_P2 bash -s" <<'VEOF'
case "$ACT" in
stop) docker rm -f $ZCT 2>&1; exit 0 ;;
esac
mkdir -p $ZLOG
if docker ps --format '{{.Names}}' | grep -qx $ZCT; then echo "$ZCT sudah jalan -> restart dgn script terbaru"; docker rm -f $ZCT >/dev/null; fi
docker rm -f $ZCT >/dev/null 2>&1
docker run -d --name $ZCT --label poc-phase2=1 --network host --cap-add NET_RAW --cap-add NET_ADMIN \
  --memory 512m --cpus 1 --restart unless-stopped --log-opt max-size=1m \
  -v $VM_P2/zeek:/z:ro -v $ZLOG:/logs -w /logs --entrypoint zeek $ZIMG -C -i mirror0 /z/run-live.zeek
sleep 6; docker ps --filter name=$ZCT --format '{{.Names}} {{.Status}}'; docker logs --tail 10 $ZCT 2>&1
ls -la $ZLOG; docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}' $ZCT netprobe-zeek-live
VEOF
