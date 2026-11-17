#!/bin/bash
# Path kunci SSH di host lab. Set LAB_USER (atau LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS)
# ke akun lab; placeholder LAB_USER menggantikan username personal (repo public).
# Langkah 1b (read-only): jalur jaringan magen -> lab5g-dev guest -> l5gd-ue.
echo "### magen ip_forward"; cat /proc/sys/net/ipv4/ip_forward
echo "### magen route get 10.99.9.20"; ip route get 10.99.9.20
echo "### libvirt net l5gdev"; for n in $(sudo -n virsh net-list --name); do sudo -n virsh net-dumpxml $n | grep -q virbr-l5gdev && sudo -n virsh net-dumpxml $n; done
echo "### magen FORWARD"; sudo -n iptables -S FORWARD; sudo -n iptables -S DOCKER-USER 2>/dev/null
sudo -n iptables -S | grep -E 'l5gdev|172.26|LIBVIRT_FW' | head -30
echo "### magen nat POSTROUTING"; sudo -n iptables -t nat -S POSTROUTING | head -40
echo "### nft present?"; sudo -n nft list tables 2>/dev/null | head
G="ssh -i /ftpdata/${LAB_USER:-LAB_USER}/lab5g-dev/vm/lab_id_ed25519 -o BatchMode=yes -o ConnectTimeout=20 lab@172.22.20.21"
$G 'bash -s' <<'GEOF'
echo "===== GUEST $(hostname) $(date -u)"
ip -br a; ip r; cat /proc/sys/net/ipv4/ip_forward; df -h / | tail -1
echo "### guest docker ps"; sudo -n docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
echo "### guest networks"; sudo -n docker network ls
for n in $(sudo -n docker network ls --format '{{.Name}}' | grep lab5g); do echo "-- $n"; sudo -n docker network inspect $n --format '{{range .IPAM.Config}}{{.Subnet}} gw={{.Gateway}}{{end}} br={{index .Options "com.docker.network.bridge.name"}} id={{.Id}}'; sudo -n docker network inspect $n --format '{{range $k,$v := .Containers}}{{$v.Name}}={{$v.IPv4Address}} {{end}}'; done
echo "### l5gd-ue netns"; P=$(sudo -n docker inspect -f '{{.State.Pid}}' l5gd-ue); echo pid=$P
sudo -n nsenter -t $P -n sh -c 'ip -br a; ip r; ip rule; cat /proc/sys/net/ipv4/ip_forward; iptables -S 2>/dev/null; iptables -t nat -S 2>/dev/null' 
echo "### l5gd-server"; S=$(sudo -n docker inspect -f '{{.State.Pid}}' l5gd-server); sudo -n nsenter -t $S -n sh -c 'ip -br a; ip r'
echo "### UPF"; U=$(sudo -n docker inspect -f '{{.State.Pid}}' l5gd-upf); sudo -n nsenter -t $U -n sh -c 'ip -br a; ip r'
echo "### guest FORWARD/DOCKER-USER"; sudo -n iptables -S FORWARD; sudo -n iptables -S DOCKER-USER; sudo -n iptables -t nat -S POSTROUTING
echo "### lab-routes.sh"; cat ~/lab5g-dev/lab-routes.sh
echo "### zeek images"; sudo -n docker images | grep -Ei 'zeek|netshoot|tcpdump'
echo "### netem"; for i in $(ip -br l | awk '{print $1}' | cut -d@ -f1); do tc qdisc show dev $i 2>/dev/null | grep -q netem && echo "$i: $(tc qdisc show dev $i | grep netem)"; done
GEOF
