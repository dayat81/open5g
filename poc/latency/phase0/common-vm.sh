# Dipakai oleh skrip 10–29 (target lab5g-vm). Dijalankan di host lab (hypervisor emulator).
# Path kunci SSH: set LAB_USER, atau override LAB_SSH_KEY / LAB_SSH_KNOWN_HOSTS.
# Default "LAB_USER" adalah placeholder (username personal diredaksi karena repo public).
EMU=b0-agen-emu
EMU_BR=br-cc78098cfad4          # docker network b0-agen-net (172.26.0.0/16) di host lab
VM=172.22.10.32
VIRBR=virbr-lab5g               # host lab 172.22.10.1
SERVER=10.99.9.20               # l5g-server
TBL=2099
D="sudo -n docker"
LAB_USER="${LAB_USER:-LAB_USER}"
LAB_SSH_KEY="${LAB_SSH_KEY:-/ftpdata/${LAB_USER}/lab5g/vm/lab_id_ed25519}"
LAB_SSH_KNOWN_HOSTS="${LAB_SSH_KNOWN_HOSTS:-/ftpdata/${LAB_USER}/lab5g/vm/known_hosts}"
V="ssh -i $LAB_SSH_KEY -o UserKnownHostsFile=$LAB_SSH_KNOWN_HOSTS -o BatchMode=yes -o ConnectTimeout=20 -o LogLevel=ERROR lab@$VM"
