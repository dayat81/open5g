# Lab reference (not executed here)

This directory is the Network Architect sanitized WIP snapshot for **lab5g-dev**.
Commands later in this file are that snapshot's notes. They were **not** run from this repository.
Do not point them at **lab5g-vm**. Nothing here was deployed by the scaffold work.

| Item | Label in the package |
|---|---|
| Gate A LTE attach + SGi | **VERIFIED** in the NA status table; evidence summary says **ACCEPTED**. NA-reported only. |
| Gate B integrated NR cell | **NOT ACCEPTED**. Separate SgNB is still the target. **WIP**. |
| `patches/pcrf-admin-rar.patch` | **DRAFT, NOT COMPILED, NOT TESTED**. Not applied here. |
| `config/examples/slicing-poc/` | **STAGED-NOT-DEPLOYED** |
| eBPF example | Placeholder. **DRAFT-UNTESTED** |
| `versions.md` image ids | Local `docker image inspect` ids from the snapshot. Registry RepoDigests were empty. Not new pins invented here. |
| `ue.conf.example` | Contains example IMEI `353490069873319`. Ki/OPc in examples stay `<REDACTED_…>` placeholders. |

A later run on lab5g-dev still needs an explicit user authorization. This scaffold does not grant it.

---

# WORK IN PROGRESS snapshot 2026-11-06 20:16:41 +07

# lab5g-dev — Open5GS SMF/UPF development lab

Isolated sibling of `lab5g-vm` **without** synthetic nodes (`l5g-syn-*`), clab, or probes.
Purpose: rebuild and iterate on **Open5GS SMF and UPF** (v2.8.0) while the rest of the EPC+RAN stack stays on stock images.

## Host resources (agen)

| Item | Value |
|------|-------|
| VM name | `lab5g-dev` |
| vCPU / RAM | 8 / 16G |
| Disk | `/ftpdata/<USER>/lab5g-dev/vm/lab5g-dev.qcow2` |
| Libvirt net | `lab5g-dev-iso` (bridge `virbr-l5gdev`, NAT `172.22.20.0/24`) |
| Guest IP | see `vm/guest_ip.txt` (typically `172.22.20.21`) |
| SSH key | `vm/lab_id_ed25519` |
| This tree | `/ftpdata/<USER>/lab5g-dev/` |

SSH from agen:

```bash
IP=$(cat /ftpdata/<USER>/lab5g-dev/vm/guest_ip.txt)
ssh -i /ftpdata/<USER>/lab5g-dev/vm/lab_id_ed25519 \
  -o ClearAllForwardings=yes -o ConnectTimeout=60 lab@$IP
```

**Do not** touch `lab5g-vm`, eve-ng, or other libvirt nets/containers.

## Guest stack

Path: `/home/lab/lab5g-dev/`

Containers (`l5gd-*`): mongo, hss, pcrf, mme, sgwc, sgwu, smf, upf, server, enb, ue.

Docker networks keep the same `10.99.x` scheme as the original lab (isolated inside this VM).

UE PDU / SGi: UE gets `10.45.0.0/16` via UPF `ogstun`; data server is `l5gd-server` at `10.99.9.20`.

### Start / stop

```bash
cd /home/lab/lab5g-dev
sudo bash lab-up.sh          # core + routes + RAN
# or manually:
sudo docker compose up -d
sudo bash lab-routes.sh
# RAN: start UE first (binds ZMQ :2001), then eNB (connects to UE)
sudo docker compose -f docker-compose-ran.yml up -d ue
sleep 5
sudo docker compose -f docker-compose-ran.yml up -d enb
sudo bash lab-routes.sh
```

ZMQ order matters: if eNB starts before UE is listening on `10.99.11.21:2001`, the UE may never find the cell. After any RAN restart, prefer **UE then eNB**.

### Verify

```bash
sudo docker exec l5gd-mme ss -Snp | grep 36412   # S1 ESTAB to 10.99.1.20
sudo docker logs l5gd-ue 2>&1 | grep -E "attach successful|IP:"
sudo docker exec l5gd-ue ip -br a                # expect tun_srsue 10.45.x
sudo docker exec l5gd-ue ping -c 3 10.99.9.20    # SGi to l5gd-server
```

## SMF / UPF source rebuild

Source tree (tag `v2.8.0`, branch `dev-smf-upf`):

`/home/lab/lab5g-dev/open5gs-src`

One-shot rebuild + restart **only** smf/upf:

```bash
cd /home/lab/lab5g-dev
sudo bash rebuild-smf-upf.sh
```

What that does (see script for details):

1. Builds Open5GS inside a build container with meson/ninja (or host toolchain if present).
2. Installs/copies `open5gs-smfd` / `open5gs-upfd` into a bind-mounted `bin/` (or retags a local image).
3. Recreates only `l5gd-smf` and `l5gd-upf` via `docker-compose.override.dev.yml` so they use the local binaries; other NFs untouched.
4. Re-applies `lab-routes.sh` (SMF S5/S11 and UPF S1-U / ogstun routes).

Override file: `docker-compose.override.dev.yml`  
Setup helper: `setup-open5gs-src.sh`

After rebuild, re-check UE (restart UE→eNB if the session dropped) and ping `10.99.9.20`.

## Layout

```
/ftpdata/<USER>/lab5g-dev/
  README.md          # this file (host copy)
  vm/                # qcow2, seed.iso, SSH key, guest_ip.txt, net XML
  images/            # optional cached images / open5gs tarball

/home/lab/lab5g-dev/ # inside VM
  docker-compose.yml
  docker-compose-ran.yml
  docker-compose.override.dev.yml
  ran.env
  conf/              # Open5GS YAML + freeDiameter
  open5gs-src/       # git checkout v2.8.0 / dev-smf-upf
  lab-up.sh lab-routes.sh rebuild-smf-upf.sh setup-open5gs-src.sh
  README.md
```


## EN-DC / NSA Option 3x (verified 2026-11-06)
`srsRAN 4G 25.10.0` runs an LTE FDD cell and an NR band-3 FDD secondary cell
(PCI 500, NR-ARFCN 368500). UE uses Release 15 and one NR carrier. LTE is the
control anchor and Open5GS remains the EPC (not a 5GC).

Bring up and verify:
```bash
sudo bash endc-up.sh
```
Start UE first, then eNB. Expect `Network attach successful` and `RRC NR
reconfiguration successful` followed by a second random-access completion.
RAN `/tmp` contains LTE/NR MAC captures and UE metrics. The embedded eNB S1AP
capture was zero bytes; use host tcpdump for transaction-level S1AP capture.

No E-RAB Modification Indication or SgNB S1-U endpoint was observed: S1-U
remains `10.99.2.20` (eNB) to `10.99.2.12` (SGW-U). NR SCG reconnects after RRC
idle release, which was observed during a soak test. This is a prototype lab
feature, not production-grade NSA.

Restore the exact LTE-only configuration (RAN restart only) with:
```bash
sudo bash lte-only-restore.sh
```
The original files have `.bak-endc` suffixes. `endc-up.sh` is reproducible;
`lab-up.sh` was intentionally left unchanged to retain a simple core+LTE base.
