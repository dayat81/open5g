#!/bin/bash
# poc-inet sisi laptop (WSL). Reverse dynamic SOCKS: host lab 127.0.0.1:11080 -> internet lewat laptop ini.
# Pakai (di WSL):  bash ~/poc-inet/poc-inet-laptop.sh start|stop|status|up-all|down-all
#   start    : buat ~/.ssh/poc-inet.conf (tanpa forward lain), jalankan loop tunnel tersembunyi (wsl.exe hidden via PowerShell)
#   up-all   : start + jalankan ~/poc-latency/lab-up-poc.sh di host lab
#   down-all : jalankan ~/poc-latency/lab-down-poc.sh di host lab + stop
# Dari PowerShell: wsl -e bash ~/poc-inet/poc-inet-laptop.sh up-all
#
# Wajib (atau isi Host magen di ~/.ssh/config):
#   export MAGEN_HOST=<IP atau hostname hypervisor lab>
#   export MAGEN_USER=<user SSH>          # atau LAB_USER
#   export MAGEN_SSH_KEY=<path kunci>     # opsional
D=~/poc-inet; CONF=~/.ssh/poc-inet.conf; PF=$D/tunnel.pid; LOG=$D/tunnel.log; PORT=11080
mkdir -p $D ~/.ssh

# Isi MAGEN_* dari env, atau dari alias SSH "magen" di ~/.ssh/config (nilai tidak di-hardcode di skrip).
_sshcfg() { awk -v k="$1" 'tolower($1)=="host"{h=($2=="magen")} h && tolower($1)==tolower(k){print $2; exit}' ~/.ssh/config 2>/dev/null; }
MAGEN_HOST="${MAGEN_HOST:-$(_sshcfg HostName)}"
MAGEN_USER="${MAGEN_USER:-${LAB_USER:-$(_sshcfg User)}}"
MAGEN_SSH_KEY="${MAGEN_SSH_KEY:-$(_sshcfg IdentityFile)}"

magen_dest() {
  if [ -n "${MAGEN_HOST:-}" ] && [ -n "${MAGEN_USER:-}" ]; then
    echo "${MAGEN_USER}@${MAGEN_HOST}"
  else
    echo "magen"
  fi
}

mkconf() {
  if [ -z "${MAGEN_HOST:-}" ] || [ -z "${MAGEN_USER:-}" ]; then
    echo "ERR: set MAGEN_HOST dan MAGEN_USER (atau LAB_USER), atau sediakan Host magen (HostName + User) di ~/.ssh/config." >&2
    exit 1
  fi
  local idf="${MAGEN_SSH_KEY:-}"
  cat > $CONF <<C
# poc-inet: config khusus tunnel (tidak memuat LocalForward alias lain)
Host magen-inet
    HostName ${MAGEN_HOST}
    User ${MAGEN_USER}
    IdentityFile ${idf:-~/.ssh/id_ed25519}
    IdentitiesOnly yes
    BatchMode yes
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
    ServerAliveInterval 15
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
    RemoteForward 127.0.0.1:$PORT
C
  chmod 600 $CONF
}
running() { [ -f $PF ] && kill -0 $(cat $PF) 2>/dev/null; }
mssh() {
  local dest; dest=$(magen_dest)
  local opts=(-T -o BatchMode=yes -o ClearAllForwardings=yes -o ConnectTimeout=30 -o LogLevel=ERROR)
  [ -n "${MAGEN_SSH_KEY:-}" ] && opts+=(-i "$MAGEN_SSH_KEY")
  ssh "${opts[@]}" "$dest" "$@"
}
case "${1:-status}" in
loop)  # dipanggil oleh start (proses wsl.exe tersembunyi)
  echo $$ > $PF
  while true; do
    ssh -F $CONF -N magen-inet; echo "$(date -Is) tunnel exit $?, retry 5 s"; sleep 5
  done >> $LOG 2>&1 ;;
start)
  mkconf
  if running; then echo "tunnel sudah jalan pid=$(cat $PF)"; else
    powershell.exe -NoProfile -Command "Start-Process -WindowStyle Hidden wsl.exe -ArgumentList '-d','$WSL_DISTRO_NAME','-e','bash','$D/poc-inet-laptop.sh','loop'"
    sleep 6; running && echo "tunnel pid=$(cat $PF)" || { echo "GAGAL start"; tail -5 $LOG; exit 1; }
  fi
  mssh "ss -ltn | grep -q '127.0.0.1:$PORT ' && echo 'host-lab: SOCKS 127.0.0.1:$PORT listen' || echo 'host-lab: SOCKS belum listen'" ;;
stop)
  running && { pkill -P $(cat $PF); kill $(cat $PF); }
  pkill -f "ssh -F $CONF -N magen-inet"; rm -f $PF; echo "tunnel stopped" ;;
status)
  running && echo "tunnel pid=$(cat $PF)" || echo "tunnel TIDAK jalan"; tail -3 $LOG 2>/dev/null
  curl -sS -m 10 -o /dev/null -w 'laptop internet: http=%{http_code}\n' https://example.com ;;
up-all)   "$0" start && mssh 'bash ~/poc-latency/lab-up-poc.sh' ;;
down-all) mssh 'bash ~/poc-latency/lab-down-poc.sh'; "$0" stop ;;
*) echo "pakai: $0 start|stop|status|up-all|down-all"; exit 2 ;;
esac
