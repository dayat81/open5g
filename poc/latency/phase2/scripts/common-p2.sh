# poc-phase2: konfigurasi bersama (host lab). Tag: poc-phase2
# Path kunci SSH: set LAB_USER, atau override LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS.
. ~/poc-latency/phase0/common-vm.sh 2>/dev/null || . ~/poc-latency/phase0/scripts/common-vm.sh
P2=~/poc-latency/phase2
VM_P2=/home/lab/poc-phase2                 # di lab5g-vm
ZIMG=netprobe/zeek-live:9.0.1-lte1.1-slim  # image yang sama dengan netprobe-zeek-live
ZCT=poc-phase2-zeek-mglt                   # container Zeek terpisah (tidak menyentuh netprobe-zeek-live)
ZLOG=/dev/shm/poc-phase2-zeek              # log JSON mglt/conn/tunnel (tmpfs)
PKG=id.magnon.poc.examine
SSHVM_OPTS="-i $LAB_SSH_KEY -o UserKnownHostsFile=$LAB_SSH_KNOWN_HOSTS -o BatchMode=yes -o ConnectTimeout=20 -o LogLevel=ERROR"
push_vm(){ $V "mkdir -p $VM_P2/zeek" && scp -q $SSHVM_OPTS "$@" lab@$VM:$VM_P2/zeek/; }
