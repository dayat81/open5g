#!/bin/bash
# Keepalive PERMANEN agar UE l5g-ue tidak idle: loop di host lab5g-vm, tiap 3 s ping 1x dari netns l5g-ue ke 10.99.9.20.
# PID l5g-ue di-resolve tiap iterasi (tahan restart container); bila tun_srsue ada tapi route D5 hilang, dipasang ulang (runbook lab-routes.sh).
# Pakai: 35-keepalive.sh start | stop | status     Stop manual di VM: sudo kill $(cat /tmp/poc-phase1-ka.pid)
. ~/poc-latency/phase0/common-vm.sh
$V "sudo -n env ACT=${1:-start} bash -s" <<'VEOF'
PF=/tmp/poc-phase1-ka.pid; LOG=/tmp/poc-phase1-ka.log
running() { [ -f $PF ] && kill -0 $(cat $PF) 2>/dev/null; }
case "$ACT" in
start)
  pkill -f 'ping -i 2 -W 1 10.99.9.20' 2>/dev/null   # keepalive versi lama (900 s)
  if running; then echo "sudah jalan pid=$(cat $PF)"; else
  cat > /tmp/poc-phase1-ka.sh <<'KA'
#!/bin/bash
# poc-phase1 keepalive UE (permanen). Stop: kill $(cat /tmp/poc-phase1-ka.pid)
n=0
while true; do
  P=$(docker inspect -f '{{.State.Pid}}' l5g-ue 2>/dev/null)
  if [ -n "$P" ] && [ "$P" != 0 ] && nsenter -t $P -n ip link show tun_srsue >/dev/null 2>&1; then
    nsenter -t $P -n ip route show 10.99.9.0/24 | grep -q tun_srsue || { nsenter -t $P -n ip route replace 10.99.9.0/24 dev tun_srsue; echo "$(date -Is) D5 route re-added"; }
    if nsenter -t $P -n ping -c 1 -W 2 10.99.9.20 >/dev/null 2>&1; then r=ok; else r=FAIL; fi
  else r=no-tun; fi
  n=$((n+1)); { [ $r != ok ] || [ $((n % 100)) -eq 1 ]; } && echo "$(date -Is) n=$n $r"
  sleep 3
done
KA
  chmod +x /tmp/poc-phase1-ka.sh
  setsid nohup /tmp/poc-phase1-ka.sh >> $LOG 2>&1 < /dev/null &
  echo $! > $PF; sleep 4
  fi
  echo "pid=$(cat $PF)"; tail -3 $LOG ;;
stop)
  running && kill $(cat $PF); pkill -f poc-phase1-ka.sh; rm -f $PF; echo "keepalive stopped"; tail -3 $LOG ;;
*) running && echo "running pid=$(cat $PF)" || echo "not running"; tail -5 $LOG ;;
esac
VEOF
