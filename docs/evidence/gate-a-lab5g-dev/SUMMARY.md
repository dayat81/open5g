> Repository note: checked in from the Network Architect sanitized WIP package. This checkout did not run the lab, compile the PCRF patch, or re-verify the result below. lab5g-vm was not used.

# Gate A — lab5g-dev baseline (LTE EPC CUPS)

**Status:** ACCEPTED (baseline VM + attach path).  
**Snapshot time:** 2026-11-06 20:17:38 +07 (Asia/Bangkok).  
**Scope:** `lab5g-dev` only (`172.22.20.21`). Live lab `lab5g-vm` not modified.

## Source / versions

| Component | Version |
|---|---|
| Open5GS (containers) | gradiant/open5gs:**2.8.0** (image id `sha256:1740bc23cc56…7996d`) |
| srsRAN 4G | gradiant/srsran-4g:**25_10** (image id `sha256:f4d513637001…8315`) |
| MongoDB | mongo:**7.0** |
| open5gs-src branch | `dev-smf-upf` @ `3d4023c6b6c0b1faee4b072907f3a58858aeb77e` |

## Redacted results (numbers from lab verification)

| Check | Result |
|---|---|
| VM resources | 8 vCPU / 16 GiB; management IP `172.22.20.21` on `lab5g-dev-iso` (`172.22.20.0/24`) |
| Containers | 11× `l5gd-*` (mongo, hss, pcrf, mme, sgwc, sgwu, smf, upf, server, enb, ue) — no synthetic nodes |
| S1-MME | Associated: MME `10.99.1.10` ↔ eNB `10.99.1.20` |
| UE attach | Success; UE PDN address **`10.45.0.2`** (initial Gate A run) |
| SGi reachability | Ping UE → server `10.99.9.20` success (~**30 ms** RTT) |
| Slicing / eBPF / PCRF RAR patch | **Not in Gate A** — planned only |

## What is stable vs WIP

| Item | State |
|---|---|
| Compose core (`docker-compose.yml`), Open5GS YAMLs, lab-up/lab-routes, LTE attach path | **Stable baseline** for this snapshot |
| `docker-compose.override.dev.yml` + `rebuild-smf-upf.sh` | Present; rebuild E2E **not verified** |
| EN-DC (`nr_cell_list`, endc-*.sh, ran compose ZMQ dual-port) | **WIP** — see Gate B |
| APN-per-slice / PCC / eBPF / PCRF admin RAR | **Planned / not configured** in this snapshot |

## Notes

- No raw pcaps or subscriber dumps included.
- Example IMSIs in templates use `00101000000000N`; Ki/OPc replaced with placeholders.
