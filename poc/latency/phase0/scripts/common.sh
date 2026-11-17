# Dipakai oleh 05/06/99. Dijalankan di host lab (hypervisor emulator).
# Path kunci SSH: set LAB_USER, atau override LAB_SSH_KEY_DEV.
# Default "LAB_USER" adalah placeholder (username personal diredaksi karena repo public).
EMU=b0-agen-emu
EMU_BR=br-cc78098cfad4          # docker network b0-agen-net (172.26.0.0/16)
GUEST=172.22.20.21
SERVER=10.99.9.20
TBL=2099                        # tabel routing & prioritas rule khusus PoC
D="sudo -n docker"
LAB_USER="${LAB_USER:-LAB_USER}"
LAB_SSH_KEY_DEV="${LAB_SSH_KEY_DEV:-/ftpdata/${LAB_USER}/lab5g-dev/vm/lab_id_ed25519}"
G="ssh -i $LAB_SSH_KEY_DEV -o BatchMode=yes -o ConnectTimeout=20 -o LogLevel=ERROR lab@$GUEST"
