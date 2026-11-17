#!/bin/bash
# poc-inet CGNAT: inspeksi READ-ONLY prasyarat (tidak mengubah apa pun).
. ~/poc-latency/phase0/common-vm.sh; cd ~/poc-latency/inet 2>/dev/null && . ./common-inet.sh
echo "### magen: port 11081 (calon relay UDP laptop)"; ss -ltn | grep -E ':1108[0-9] ' ; which conntrack nft 2>&1 | head
$V "sudo -n bash -s" <<'VEOF'
echo "### VM kernel/modul"; uname -r; lsmod | grep -iE 'tproxy|nf_tproxy|xt_socket|nf_conntrack ' ; modinfo xt_TPROXY 2>&1 | head -2
which conntrack nft iptables iptables-legacy iptables-nft 2>&1; iptables -V
echo "### VM host routes/rules"; ip rule; ip -br a | grep -E 'br-|ens3'; ip r | head -20; ip r show table all | grep -E '100\.64' | head
ss -lunp | grep -E ':1234[0-9]|:1108' ; ss -ltnp | grep -E ':1108'
sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter
iptables -t mangle -S | head -20
S=$(docker inspect -f '{{.State.Pid}}' l5g-server); N="nsenter -t $S -n"
echo "### l5g-server netns"; $N ip -br a; $N ip r; $N ip rule; $N sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter
$N iptables -t nat -S | head -40; $N iptables -t mangle -S | head; $N iptables -S | head
$N ss -lunp | head -20
echo "### docker net SGi"; docker network ls | head -20; docker inspect l5g-server -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}} gw={{$v.Gateway}}{{"\n"}}{{end}}'
U=$(docker inspect -f '{{.State.Pid}}' l5g-upf); nsenter -t $U -n ip rule; nsenter -t $U -n ip r show table 2100
E=$(docker inspect -f '{{.State.Pid}}' l5g-ue); nsenter -t $E -n which dig curl; nsenter -t $E -n curl -V 2>&1 | head -2
docker exec l5g-ue sh -c 'which dig curl; curl -V | head -3' 2>&1
VEOF
