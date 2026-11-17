#!/bin/bash
# Path kunci SSH di host lab. Set LAB_USER (atau LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS)
# ke akun lab; placeholder LAB_USER menggantikan username personal (repo public).
# read-only diagnosa lab5g-vm: data plane UE dan lokasi log Zeek probe.
V="ssh -i /ftpdata/${LAB_USER:-LAB_USER}/lab5g/vm/lab_id_ed25519 -o UserKnownHostsFile=/ftpdata/${LAB_USER:-LAB_USER}/lab5g/vm/known_hosts -o BatchMode=yes -o ConnectTimeout=20 -o LogLevel=ERROR lab@172.22.10.32"
$V 'sudo -n bash -s' <<'VEOF'
pid(){ docker inspect -f '{{.State.Pid}}' $1; }
echo "### routes core (D1-D3 ada?)"; for c in l5g-smf l5g-upf l5g-enb l5g-sgwu; do echo "-- $c"; nsenter -t $(pid $c) -n ip r; done
echo "### tc netem"; for c in l5g-enb l5g-sgwu l5g-upf l5g-ue l5g-server; do nsenter -t $(pid $c) -n tc qdisc show | grep -i netem | sed "s/^/$c: /"; done
echo "### ue log"; docker logs --tail 15 l5g-ue 2>&1
echo "### ping + tcpdump s1u/sgi"
timeout 8 tcpdump -ni br-0f45653459a0 -c 12 udp port 2152 > /tmp/d-s1u.txt 2>&1 &
timeout 8 tcpdump -ni br-250e9b29a2ee -c 12 host 10.99.9.20 > /tmp/d-sgi.txt 2>&1 &
sleep 1; docker exec l5g-ue ping -c 4 -W 2 10.99.9.20 | tail -2; wait; echo "-- s1u"; cat /tmp/d-s1u.txt; echo "-- sgi"; cat /tmp/d-sgi.txt
echo "### zeek probe workdir & isi"
for c in l5g-probe-zeek-s1u l5g-probe-zeek-sgi; do echo "-- $c wd=$(docker inspect -f '{{.Config.WorkingDir}}' $c)"; docker exec $c sh -c 'pwd; ls -la . /out | head -30'; done
echo "### netprobe-zeek-live"; cat /home/lab/lab5g/zeek-live/tap-map.csv; ls -la /dev/shm/netprobe-zeek-live | head -30
docker inspect netprobe-zeek-live --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -v -i -E 'key|pass|secret|token'
docker logs --tail 10 netprobe-zeek-live 2>&1
VEOF
