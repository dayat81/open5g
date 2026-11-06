> Repository note: checked in from the Network Architect sanitized WIP package. This checkout did not run the lab, compile the PCRF patch, or re-verify the result below. lab5g-vm was not used.

# Gate B — EN-DC (integrated srsRAN NR cell)

**Status:** integrated srsRAN NR cell works; **NOT ACCEPTED**, Hidayat requires a separate SgNB (X2 SgNB Addition, E-RAB Modification, S1-U switch to the gNB); **WIP**.

**Snapshot time:** 2026-11-06 20:17:38 +07 (Asia/Bangkok).  
**Scope:** `lab5g-dev` only. Live `lab5g-vm` not modified.

## Source / versions

| Component | Version / note |
|---|---|
| srsRAN 4G | **25.10** (`gradiant/srsran-4g:25_10`) |
| Topology under test | Dual-channel ZMQ; LTE anchor + NR cell **inside the same srsENB** (integrated), not a separate SgNB |
| LTE | band 7 / EARFCN **3350**, PCI **1** |
| NR | band **3** / NR-ARFCN **368500**, PCI **500**, `nr_cell_list` in `rr.conf` |
| UE | `--rat.nr.bands=3`, `--rat.nr.nof_carriers=1` |

## Redacted results (numbers from actual logs/metrics)

| Check | Result |
|---|---|
| Network attach | Success. UE IP **`10.45.0.4`** (earlier successful run **`10.45.0.3`**) |
| RRC NR reconfiguration | Success (srsRAN dual-connectivity model) |
| Random Access Complete | `c-rnti=0x4601`, `ta=0` |
| NR load (UE cc=1 / PCI 500) | DL **3.50–4.66 Mbps**, UL **3.66–4.75 Mbps**; **0%** MAC BLER in recorded `nr-load-metrics` excerpt |
| S1-MME SCTP | `10.99.1.10:36412` ↔ `10.99.1.20:47556` **ESTAB** |
| Host S1-U (UDP/2152) | eNB `10.99.2.20` ↔ SGW-U `10.99.2.12` (also path via `10.99.5.13` in GTP-U excerpt) |

### Short redacted tshark-style excerpt (no IMSI/keys)

```
S1-MME: ESTAB 10.99.1.10:36412 <-> 10.99.1.20:47556 (open5gs-mmed)
S1-U:   10.99.2.20.2152 > 10.99.2.12.2152 UDP
        10.99.5.13.2152 > 10.99.2.20.2152 UDP
```

## Why NOT ACCEPTED

- Current setup is **integrated** NR cell in srsENB (one process / one S1), not a **separate SgNB**.
- Required for acceptance: **X2 SgNB Addition**, **E-RAB Modification**, and **S1-U switch toward the gNB**.
- E-RAB Modification Indication was **not** observed; no SgNB-specific S1-U tunnel exists in this emulated topology.
- Embedded eNB S1AP pcap was empty in the evidence set; do not treat this as proof of split-bearer / measurement semantics beyond srsRAN's dual-connectivity model.

## Config touchpoints (sanitized examples in this package)

- `lab/compose/docker-compose-ran.yml` — ZMQ `tx_port0/1`, `rx_port0/1`, `--pcap.nr_filename`, UE `--rat.nr.*`
- `lab/config/examples/ran/rr.conf.example` — `nr_cell_list`
- `lab/scripts/endc-up.sh`, `endc-down.sh`, `lte-only-restore.sh`

## Coordination / limits

- RAN restarts coordinated via busy locks with slicing PoC worker.
- Default HSS `access_restriction_data=32` worked unchanged.
- Prefer `docker compose` v2 (`sudo docker compose`); legacy v1 unreliable.
