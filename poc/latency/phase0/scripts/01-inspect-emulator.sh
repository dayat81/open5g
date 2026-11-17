#!/bin/bash
# Langkah 1 (read-only): inspeksi container emulator di magen.
C=e679044a1016
D="sudo -n docker"
echo "### inspect"
$D inspect $C --format 'Name={{.Name}} Image={{.Config.Image}} NetMode={{.HostConfig.NetworkMode}} Priv={{.HostConfig.Privileged}} CapAdd={{.HostConfig.CapAdd}} Devices={{json .HostConfig.Devices}}'
$D inspect $C --format '{{json .NetworkSettings.Networks}}'
$D inspect $C --format '{{json .Config.Labels}}'
echo "### env (masked secrets)"
$D inspect $C --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -E 's/((KEY|PASS|SECRET|TOKEN|KI|OPC)[A-Z_]*=).*/\1***MASKED***/I'
echo "### mounts"
$D inspect $C --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}} {{.Mode}}{{println}}{{end}}'
echo "### ports"; $D inspect $C --format '{{json .HostConfig.PortBindings}}'
echo "### cmd/entrypoint"; $D inspect $C --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}'
echo "### all containers (names only)"; $D ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
echo "### networks"; $D network ls
echo "### ip in container"; $D exec $C sh -c 'ip -br a; ip r' 2>&1 | head -40
echo "### adb devices"; $D exec $C sh -c 'adb devices -l' 2>&1
echo "### android props"; $D exec $C sh -c 'adb shell getprop ro.build.version.release; adb shell getprop ro.build.version.sdk; adb shell getprop sys.boot_completed; adb shell ip -br a; adb shell ip r; adb shell ip rule' 2>&1 | head -60
echo "### emulator proc"; $D exec $C sh -c 'ps -eo pid,args | grep -E "qemu|emulator" | grep -v grep | cut -c1-600' 2>&1
echo "### compose files on magen"; ls -la ~ | head -50; find ~ -maxdepth 3 -name 'docker-compose*.yml' 2>/dev/null | head -20
echo "### host routes to lab"; ip r | grep -E '172.22.20|10.99|10.45' ; ip -br a | grep -E 'virbr|vnet|br-' | head -20
