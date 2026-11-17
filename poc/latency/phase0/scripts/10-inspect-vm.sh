#!/bin/bash
# Path kunci SSH di host lab. Set LAB_USER (atau LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS)
# ke akun lab; placeholder LAB_USER menggantikan username personal (repo public).
# lab5g-vm read-only: cara emulator tersambung ke UE, probe Zeek yang sudah ada.
echo "### ops-b0-agen"; ls -la ~/ops-b0-agen; for f in ~/ops-b0-agen/*.sh ~/ops-b0-agen/*.md ~/ops-b0-agen/*.yml ~/ops-b0-agen/*.txt; do [ -f "$f" ] && { echo "----- $f"; sed -n '1,120p' "$f"; }; done 2>/dev/null
echo "### magen route/rule ke 172.22.10.x / 10.45"; ip rule show; ip r | grep -E '172.22.10|10.45|10.99|10.0' 
echo "### magen iptables yang menyebut 172.26/172.22.10"; sudo -n iptables-save | grep -E '172\.26|172\.22\.10|b0-agen|virbr-lab5g ' | head -40
echo "### emulator: koneksi aktif & proses"; sudo -n docker exec b0-agen-emu sh -c 'ss -tnp 2>/dev/null | head -20; ps -eo pid,args | grep -v -E "^ *[0-9]+ \[" | cut -c1-200 | head -30'
echo "### android: proxy/vpn/settings"; sudo -n docker exec b0-agen-emu adb shell 'settings get global http_proxy; dumpsys connectivity | grep -i -E "vpn|NetworkAgentInfo" | head -10; ip -br a | grep -v DOWN'
V="ssh -i /ftpdata/${LAB_USER:-LAB_USER}/lab5g/vm/lab_id_ed25519 -o UserKnownHostsFile=/ftpdata/${LAB_USER:-LAB_USER}/lab5g/vm/known_hosts -o BatchMode=yes -o ConnectTimeout=20 -o LogLevel=ERROR lab@172.22.10.32"
$V 'bash -s' <<'VEOF'
echo "===== VM $(hostname) $(date -u)"; ip -br a | grep -v -E '^veth'; ip r; ip rule; df -h / | tail -1
echo "### docker ps"; sudo -n docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
echo "### networks"; for n in $(sudo -n docker network ls --format '{{.Name}}'); do printf "%s " $n; sudo -n docker network inspect $n --format '{{range .IPAM.Config}}{{.Subnet}}{{end}} {{range $k,$v := .Containers}}{{$v.Name}}={{$v.IPv4Address}} {{end}}'; done
echo "### ue netns"; P=$(sudo -n docker inspect -f '{{.State.Pid}}' l5g-ue); sudo -n nsenter -t $P -n sh -c 'ip -br a; ip r; ip rule; iptables-save 2>/dev/null | grep -v "^#"'
echo "### server"; P=$(sudo -n docker inspect -f '{{.State.Pid}}' l5g-server); sudo -n nsenter -t $P -n sh -c 'ip -br a; ip r; ss -lntu'
echo "### probe containers"; for c in $(sudo -n docker ps --format '{{.Names}}' | grep -E 'probe|zeek'); do echo "-- $c"; sudo -n docker inspect $c --format 'net={{.HostConfig.NetworkMode}} cmd={{json .Config.Cmd}} ep={{json .Config.Entrypoint}}'; sudo -n docker inspect $c --format '{{range .Mounts}}{{.Source}}->{{.Destination}} {{end}}'; done
echo "### host iptables yang menyebut 172.22.10.1/10.45"; sudo -n iptables-save | grep -E '172\.22\.10|10\.45|DOCKER-USER' | head -30
echo "### runbook/scripts"; ls ~ ; ls ~/lab5g* 2>/dev/null | head -50
VEOF
