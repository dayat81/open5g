# Deliverables

Status of branch `cursor/open5g-scaffold-341a` after the docs pack and the sanitized lab WIP pack. This repository did not re-run the lab.

## Included

| Item | Path | State |
|---|---|---|
| Repository purpose, Affero GPL notes, ignore rules | `README.md`, `NOTICE`, `.gitignore` | On `master` |
| Profile policy module, PostgreSQL schema, hashed test lock | `dashboard/backend/` | Committed. Domain `pytest -q`: 12 passed. Migration not applied in that run. |
| UX sanitized pack | `docs/ux/` | Included. `prototype/` is localStorage, no auth, not the Next.js app. |
| Feasibility memo and IA | `docs/design/` and `docs/pages/` mirrors | Included Markdown digests. |
| PRD v0.4 Page snapshot | `docs/pages/prd-lab-5g-nsa-dashboard-v0.4.INTERIM-SNAPSHOT.md` | **Superseded / pending v0.5.** Not canonical. |
| Docs archive manifest | `docs/provenance/interim-docs-MANIFEST.md` | Provenance. Canvas `META/` sources were not committed. |
| Lab sanitized WIP v1 | `lab/compose/`, `lab/config/examples/`, `lab/scripts/`, `lab/versions.md` | Included as reference. **Not deployed** from this checkout. |
| Local image ids | `lab/versions.md` | NA snapshot `docker image inspect` ids. RepoDigests were empty. Not re-pinned here. |
| PCRF admin-RAR draft | `lab/patches/pcrf-admin-rar.patch` and `lab/patches/pcrf-admin-rar/` | **DRAFT, NOT COMPILED, NOT TESTED.** Not applied. |
| Slicing PoC examples | `lab/config/examples/slicing-poc/` | **STAGED-NOT-DEPLOYED** |
| eBPF lab note | `lab/config/examples/ebpf/` | Placeholder. **DRAFT-UNTESTED** |
| Capability extract | `docs/capabilities.md` | NA reading of Open5GS v2.8.0. Not a live RAR integration in this repo. |
| Evidence summaries | `docs/evidence/` | NA-reported. See that README for the exact labels. |
| SgNB research | `docs/research/sgnb/` | **IN PROGRESS** |
| PoC plan | `docs/plan-poc-slicing-core.md` | Canonical sanitized copy. `docs/plans/plan-poc-slicing-core.md` is a pointer. |
| NA secret-scan note | `docs/SECRET_SCAN.md` | Package self-scan `CLEAN`, plus the independent scan under `docs/provenance/`. A fresh scan of this tree before the lab commit found no raw key assignments. |
| Example IMEI | `lab/config/examples/ran/ue.conf.example` | `353490069873319` kept as the srsRAN-style example noted by the independent scan. Ki/OPc remain `<REDACTED_…>` placeholders. |

## Pending

| Item | Path | State |
|---|---|---|
| Canonical Product Manager PRD v0.5, roadmap, decision log, risk register | `docs/prd/` | **Pending.** Placeholder only. |
| Next.js Overview and IMSI editor | `dashboard/frontend/` | Not committed. |
| FastAPI app and PostgreSQL migration test | `dashboard/backend` HTTP layer | Not in these archive commits. Uncommitted local files may exist and are not part of this manifest until they are committed. |
| eBPF classifier skeleton and exporter | `ebpf/` beyond the README | Not committed. The lab package placeholder is not that skeleton. |

## Gates A–F

| Gate | Outcome |
|---|---|
| A | NA status table: **VERIFIED** (LTE attach + SGi ping). Evidence summary heading: **ACCEPTED**. NA-reported only. Not re-tested here. |
| B | Integrated NR cell snapshot **NOT ACCEPTED**. Requirement is a **separate SgNB**. **WIP**. Research notes are **IN PROGRESS**. An integrated eNB NR cell is not accepted separate-SgNB EN-DC. |
| C | Not supplied. Unknown. |
| D | Not supplied. Unknown. |
| E | Not supplied. Unknown. |
| F | Not supplied. Unknown. |

PoC slicing gates 1–4 in `docs/evidence/gate-poc-slicing/SUMMARY.md` are a different list. They are not Gates C–F.
