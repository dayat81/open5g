# poc-inet: konfigurasi bersama (dijalankan di host lab). Tag semua perubahan: poc-inet
# Path kunci SSH ke VM: set LAB_USER, atau override LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS
# (sama seperti phase0/scripts/common-vm.sh; default "LAB_USER" adalah placeholder).
INET_DIR=~/poc-latency/inet
RUN=$INET_DIR/run                 # pid/log di host lab
SOCKS_PORT=11080                  # host lab 127.0.0.1:11080 = reverse dynamic SOCKS dari laptop (ssh -R)
UDP_PORT=11081                    # host lab 127.0.0.1:11081 = gost relay (UDP-over-TCP) di laptop WSL (ssh -R terpisah) -> CGNAT UDP
TBL_INET=2100                     # ip rule/table di host lab, VM, UPF
VM_DIR=/home/lab/poc-inet         # binari + script di lab5g-vm
LAB_USER="${LAB_USER:-LAB_USER}"
LAB_SSH_KEY="${LAB_SSH_KEY:-/ftpdata/${LAB_USER}/lab5g/vm/lab_id_ed25519}"
LAB_SSH_KNOWN_HOSTS="${LAB_SSH_KNOWN_HOSTS:-/ftpdata/${LAB_USER}/lab5g/vm/known_hosts}"
SSHVM_OPTS="-i $LAB_SSH_KEY -o UserKnownHostsFile=$LAB_SSH_KNOWN_HOSTS -o BatchMode=yes -o ConnectTimeout=20 -o LogLevel=ERROR"
PRIV="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4"
mkdir -p $RUN
