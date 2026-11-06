# open5g

## Goal

The target architecture is **NSA EN-DC Option 3x** with an **Open5GS EPC CUPS** core: LTE eNB plus a **separate SgNB**, policy and user plane staying on EPC. That target is recorded here so the scaffold has a direction. It is not an implemented or accepted EN-DC result. See Gates in [`docs/DELIVERABLES.md`](docs/DELIVERABLES.md).

The dashboard work is **core-side per-application slicing verification**: APN-based logical segmentation and PCC, checked against the core touchpoints below. It is not a proof of end-to-end 3GPP slicing or URSP.

| Touchpoint | Role in this EPC CUPS layout |
|---|---|
| S1-U | eNB toward SGW-U |
| S5/S8-U | SGW-U toward PGW-U |
| UPF (PGW-U) | PGW user plane and SGi egress |
| SMF (PGW-C) | PGW control, including Sx toward the user plane |
| PCRF | EPC policy (Gx). PCRF is not a 5GC PCF |

APN is not S-NSSAI. 5GC N3, N6, N4, and a PCF are a different core. Putting AMF beside this EPC is not NSA through the 5GC.

**eBPF detection is proposed** as a later classifier and counter source. No eBPF program, loader, or metrics exporter is in this tree, and none is claimed to be parsing DNS, TLS, or QUIC.

**Gx RAR is capability-dependent.** The desired primary apply path is a live Gx RAR. The policy module rejects stock Open5GS 2.8 immediate QCI/ARP changes on an existing bearer and APN-AMBR RAR until a verified patch exists. This repository does not contain a working RAR integration, a PCRF adapter, or measured session evidence.

**Multi-user dashboard.** Students work on server-assigned IMSIs. An instructor can edit and apply student IMSIs only inside that instructor's group. An admin manages assignment, catalog, and caps, and does not get a shared core-control panel. The checked-in piece is the policy module and PostgreSQL schema under [`dashboard/backend`](dashboard/backend). The HTTP service and the Next.js UI are not in this commit.

## Topology

```
UE ---- LTE ---- eNB ---- S1-U ---- SGW-U ---- S5/S8-U ---- UPF (PGW-U) ---- SGi
                            |                     |
                          S1-MME                 Sx
                            |                     |
                           MME                 SMF (PGW-C) ---- Gx ---- PCRF

EN-DC Option 3x target (separate SgNB, not implemented or accepted):
eNB ---- X2 ---- SgNB
Core remains this EPC. Gate B does not accept an integrated eNB NR cell as that result.
```

eBPF, if it is later built, would be a proposed detection point. It would not be the PCRF decision, the installed PCC rule, or the measured traffic by itself.

## Layout

| Path | What it is |
|---|---|
| [`lab/`](lab/README.md) | Future lab5g-dev material. Run steps there are not authorized and were not executed. |
| [`ebpf/`](ebpf/README.md) | Proposed detection. No program is checked in. |
| [`dashboard/`](dashboard/README.md) | Multi-user dashboard scaffold. Policy rules and schema only, so far. |
| [`docs/prd/`](docs/prd/README.md) | Placeholder. Canonical PRD v0.5 is still pending. The v0.4 Page snapshot under `docs/pages/` is superseded. |
| [`docs/ux/`](docs/ux/README.md) | Sanitized UX pack: hi-fi, localStorage prototype, lo-fi. The prototype is not the app. |
| [`docs/evidence/`](docs/evidence/README.md) | Gate evidence only when a summary is actually in the tree. |
| [`docs/DELIVERABLES.md`](docs/DELIVERABLES.md) | Included and pending deliverables, Gates A–F. |
| [`NOTICE`](NOTICE) | Affero GPL facts for the upstream programs. |

`main` on GitHub is the untouched initial commit. `master` is the integration branch. See [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md).

## Setup

Local policy tests from this commit, on a developer machine:

```bash
cd dashboard/backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.lock
.venv/bin/pytest -q
```

That run covers the pure policy module. It does not migrate PostgreSQL, start an API, build a UI, load eBPF, or contact a core.

Lab execution is a separate, later step. The only host named for that future work is **lab5g-dev**, and only after an explicit user authorization. The sequence is written in [`lab/README.md`](lab/README.md). It was not run for this repository. **lab5g-vm is outside this work.**

## License

Open5GS `v2.8.0` (commit `157f611a530e292e40ec50f9d23f0ef5d4fcd6a6`) and srsRAN 4G `release_25_10` (commit `6bcbd9e5bf8686aa7085202cd847c5ddd64a9c16`) are GNU Affero General Public License version 3 only:

- https://github.com/open5gs/open5gs/blob/v2.8.0/LICENSE
- https://github.com/srsran/srsRAN_4G/blob/release_25_10/LICENSE

Those sources are not vendored here. [`NOTICE`](NOTICE) records the tag details, the unsigned Open5GS tag, and the separate Apache-2.0 image-label fact on the Gradiant Dockerfiles. No license is selected for new code in this repository.
