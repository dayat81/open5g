#!/bin/bash
# Path kunci SSH di host lab. Set LAB_USER (atau LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS)
# ke akun lab; placeholder LAB_USER menggantikan username personal (repo public).
# read-only: socat-proxy di magen yang dipakai emulator (http_proxy=172.26.0.1:8080)
P=$(cat ~/ops-b0-agen/socat-proxy.pid); echo "pid=$P"; ps -o pid,user,lstart,args -p $P
sudo -n ss -ltnp | grep -E ':8080 ' 
echo "### log tail (alamat apa adanya)"; tail -30 ~/ops-b0-agen/socat-proxy.log | cut -c1-200
echo "### tujuan unik di log"; grep -o -E 'connect(ing)? to [^ ]+|AF=2 [0-9.:]+' ~/ops-b0-agen/socat-proxy.log | sort | uniq -c | sort -rn | head -15
grep -n -i -E 'socat|proxy|8080' ~/.bash_history | tail -15
V="ssh -i /ftpdata/${LAB_USER:-LAB_USER}/lab5g/vm/lab_id_ed25519 -o UserKnownHostsFile=/ftpdata/${LAB_USER:-LAB_USER}/lab5g/vm/known_hosts -o BatchMode=yes -o ConnectTimeout=20 -o LogLevel=ERROR lab@172.22.10.32"
$V 'bash -s' <<'VEOF'
echo "### lab-routes.sh VM"; cat ~/lab5g/lab-routes.sh
echo "### lab.zeek"; cat ~/lab5g/probe/lab.zeek
echo "### zeek out s1u/sgi"; ls -la ~/lab5g/probe/zeek/s1u ~/lab5g/probe/zeek/sgi | head -40
echo "### ue ping server"; sudo -n docker exec l5g-ue ping -c 3 -W 2 10.99.9.20 | tail -2
echo "### ue sysctl"; P=$(sudo -n docker inspect -f '{{.State.Pid}}' l5g-ue); sudo -n nsenter -t $P -n sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter
echo "### VM forward/rp"; sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter; sudo -n iptables -S FORWARD | head -5; sudo -n iptables -t nat -S POSTROUTING
ip rule | grep 2099 || echo "no rule 2099"; ip route show table 2099 2>&1
VEOF
