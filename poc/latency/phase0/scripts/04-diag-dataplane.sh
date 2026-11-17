#!/bin/bash
# Path kunci SSH di host lab. Set LAB_USER (atau LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS)
# ke akun lab; placeholder LAB_USER menggantikan username personal (repo public).
# Diagnosa data plane UE->server (read-only + lab-routes.sh yang memang runbook lab).
G="ssh -i /ftpdata/${LAB_USER:-LAB_USER}/lab5g-dev/vm/lab_id_ed25519 -o BatchMode=yes -o ConnectTimeout=20 lab@172.22.20.21"
$G 'bash -s' <<'GEOF'
D="sudo -n docker"
pid(){ $D inspect -f '{{.State.Pid}}' $1; }
echo "### tc qdisc di netns lab"; for c in l5gd-enb l5gd-sgwu l5gd-upf l5gd-ue l5gd-server; do echo "-- $c"; sudo -n nsenter -t $(pid $c) -n tc qdisc show | grep -v -E 'noqueue|pfifo_fast 0:|mq 0:' ; done
echo "### routes enb/sgwu"; for c in l5gd-enb l5gd-sgwu; do echo "-- $c"; sudo -n nsenter -t $(pid $c) -n ip r; done
echo "### lab-routes.sh"; sudo -n bash ~/lab5g-dev/lab-routes.sh
echo "### ue log tail"; $D logs --tail 25 l5gd-ue 2>&1 | tail -25
echo "### ping + tcpdump s1u"; sudo -n timeout 8 tcpdump -ni br-4724ba3f624c -c 20 udp port 2152 > /tmp/p0-s1u.txt 2>&1 &
sudo -n timeout 8 tcpdump -ni br-ba8f283d800b -c 20 host 10.99.9.20 > /tmp/p0-sgi.txt 2>&1 &
sleep 1; $D exec l5gd-ue ping -c 4 -W 2 10.99.9.20 | tail -3; wait
echo "-- s1u"; cat /tmp/p0-s1u.txt; echo "-- sgi"; cat /tmp/p0-sgi.txt
echo "### upf ogstun stats"; sudo -n nsenter -t $(pid l5gd-upf) -n ip -s l show ogstun | head -8
echo "### upf log tail"; $D logs --tail 15 l5gd-upf 2>&1 | tail -15
GEOF
