#!/bin/bash
# Path kunci SSH di host lab. Set LAB_USER (atau LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS)
# ke akun lab; placeholder LAB_USER menggantikan username personal (repo public).
# Langkah 1c (read-only kecuali adb root di emulator): precheck sebelum perubahan.
C=b0-agen-emu; D="sudo -n docker"
echo "### zeek image di magen"; $D image ls zeek/zeek --format '{{.Repository}}:{{.Tag}} {{.Size}} {{.ID}}'
echo "### android: tabel route"; $D exec $C adb shell 'ip route show table all | grep -v -E "^(local|broadcast|ff|fe80|multicast|anycast)" | head -30'
echo "### android: whoami/root?"; $D exec $C adb shell 'id; getprop ro.debuggable; getprop ro.build.type'
echo "### android: tools"; $D exec $C adb shell 'which nc toybox curl ping; pm list packages | grep -i -E "chrome|browser|webview"'
echo "### android: tcp ke guest 172.22.20.21:22 (tes jalur slirp->magen)"; $D exec $C adb shell 'echo | timeout 5 nc -w 3 172.22.20.21 22 | head -c 40; echo rc=$?'
echo "### android: tcp ke 10.0.2.2:5555 (gateway slirp)"; $D exec $C adb shell 'timeout 3 nc -z -w 2 10.0.2.2 5555; echo rc=$?'
G="ssh -i /ftpdata/${LAB_USER:-LAB_USER}/lab5g-dev/vm/lab_id_ed25519 -o BatchMode=yes -o ConnectTimeout=20 lab@172.22.20.21"
$G 'bash -s' <<'GEOF'
echo "### guest rp_filter"; sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.ens3.rp_filter net.ipv4.conf.br-c13aa9d21de3.rp_filter net.ipv4.conf.default.rp_filter
echo "### guest raw PREROUTING"; sudo -n iptables -t raw -S | head
echo "### guest nat POSTROUTING full"; sudo -n iptables -t nat -S POSTROUTING
echo "### guest tools"; which tcpdump zeek tshark; sudo -n docker exec l5gd-server sh -c 'which socat nc python3 tcpdump'
echo "### ue rp_filter"; P=$(sudo -n docker inspect -f '{{.State.Pid}}' l5gd-ue); sudo -n nsenter -t $P -n sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.eth0.rp_filter net.ipv4.conf.tun_srsue.rp_filter
echo "### ue ping server via tunnel"; sudo -n docker exec l5gd-ue ping -c 3 -W 2 10.99.9.20 | tail -2
echo "### guest free disk"; df -h / | tail -1; sudo -n docker system df
GEOF
