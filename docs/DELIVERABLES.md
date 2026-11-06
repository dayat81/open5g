# Deliverables

Status of branch `cursor/open5g-scaffold-341a` after the docs pack and the sanitized lab WIP pack. This repository did not re-run the lab.

## Included

| Item | Path | State |
|---|---|---|
| Repository purpose, Affero GPL notes, ignore rules | `README.md`, `NOTICE`, `.gitignore` | On `master` |
| Profile policy module, FastAPI session API, PostgreSQL migration | `dashboard/backend/` | Committed. `pytest -q`: 19 passed, including migration apply and object-level authz. Stock apply is stored as rejected. |
| UX sanitized pack | `docs/ux/` | Included. `prototype/` is localStorage, no auth, not the Next.js app. |
| Feasibility memo and IA | `docs/design/` and `docs/pages/` mirrors | Included Markdown digests. |
| Canonical PRD v0.6 | `docs/prd/PRD-v0.6.md`, `ROADMAP.md`, `DECISIONS.md`, `RISKS.md`, `README.md` | Included. Bytes match `docs/provenance/prd-v0.6/MANIFEST.md`. Supersedes the v0.4 snapshot and the pending v0.5 export. |
| PRD v0.4 Page snapshot | `docs/pages/historical/prd-lab-5g-nsa-dashboard-v0.4.INTERIM-SNAPSHOT.md` | Historical only. The old path is a pointer, not the current PRD. |
| Docs archive manifest | `docs/provenance/interim-docs-MANIFEST.md` | Provenance. Canvas `META/` sources were not committed. |
| Lab sanitized WIP v1 | `lab/compose/`, `lab/config/examples/`, `lab/scripts/`, `lab/versions.md` | Included as reference. **Not deployed** from this checkout. |
| Local image ids | `lab/versions.md` | NA snapshot `docker image inspect` ids. RepoDigests were empty. Not re-pinned here. |
| PCRF admin-RAR draft | `lab/patches/pcrf-admin-rar.patch` and `lab/patches/pcrf-admin-rar/` | **DRAFT, NOT COMPILED, NOT TESTED.** Not applied. |
| Slicing PoC examples | `lab/config/examples/slicing-poc/` | **STAGED-NOT-DEPLOYED** |
| eBPF skeleton | `ebpf/classifier/app_classifier.bpf.c`, `ebpf/exporter/contract.py` | Skeleton compiles here (`loaded=false`). It does not parse DNS/TLS/QUIC and does not read a map. Lab placeholder under `lab/config/examples/ebpf/` stays **DRAFT-UNTESTED**. |
| Capability extract | `docs/capabilities.md` | NA reading of Open5GS v2.8.0. Not a live RAR integration in this repo. |
| Evidence summaries | `docs/evidence/` | NA-reported. See that README for the exact labels. |
| SgNB research | `docs/research/sgnb/` | **IN PROGRESS** |
| PoC plan | `docs/plan-poc-slicing-core.md` | Canonical sanitized copy. `docs/plans/plan-poc-slicing-core.md` is a pointer. |
| NA secret-scan note | `docs/SECRET_SCAN.md` | Package self-scan `CLEAN`, plus the independent scan under `docs/provenance/`. A fresh scan of this tree before the lab commit found no raw key assignments. |
| Example IMEI | `lab/config/examples/ran/ue.conf.example` | `353490069873319` kept as the srsRAN-style example noted by the independent scan. Ki/OPc remain `<REDACTED_…>` placeholders. |

## Pending

| Item | Path | State |
|---|---|---|
| Next.js Overview and IMSI editor | `dashboard/frontend/` | Not committed. Hi-fi under `docs/ux/hifi/` is the mapping source, not the app. |
| eBPF packet parsing, loader, and lab BTF check | `ebpf/` | Not implemented. Compile check does not attach a program. Kernel/BTF/hook compatibility on lab5g-dev is unverified. |

## Gates A–F

| Gate | Outcome |
|---|---|
| A | NA status table: **VERIFIED** (LTE attach + SGi ping). Evidence summary heading: **ACCEPTED**. NA-reported only. Not re-tested here. PRD v0.6 roadmap text still says Gate A is **PLANNED / BUILD**. Both labels are kept; neither was re-run in this checkout. |
| B | Integrated NR cell snapshot **NOT ACCEPTED** (NA evidence: achieved-but-not-accepted). PRD D3 requires a **separate SgNB**. **WIP**. The OAI stack note in the PRD is a recommendation **pending approval**, not a decision. `/workspace/sgnb-feasibility.md` is **not in this repo**. |
| C | PRD roadmap names eBPF app detection as **PLANNED** and BTF **UNKNOWN**. A non-parsing skeleton compiles in this environment and is not attached. No lab evidence summary. |
| D | PRD roadmap names live RAR as **PLANNED**. The scaffold rejects immediate apply. The PCRF patch is draft and was not compiled or tested. |
| E | PRD roadmap names the self-service dashboard as **PLANNED**. Session authz is implemented and tested. The Next.js UI is not. |
| F | PRD roadmap marks further usage as **Later**. Not started. |

PoC slicing gates 1–4 in `docs/evidence/gate-poc-slicing/SUMMARY.md` are a different list. They are not Gates C–F.

## D1–D3 against this scaffold

These are requirement notes, not new lab results.

| Decision | What the code does | What it does not do |
|---|---|---|
| D1 Gx RAR, per operation | `diff_operations` marks existing-bearer QCI, existing-bearer ARP, and APN-AMBR RAR as unsupported on stock Open5GS 2.8. `stock_immediate_apply` stores `rejected`, `executed=false`, `core_restart=false`. A confirmed re-attach is also stored as not executed. HTTP tests cover that path. | No operation is reported `pushed` or `active`. `new_pcc_rule_rar` stays **unverified**, not supported. There is no RAR trigger. The draft patch was not applied. |
| D2 Instructor in-group | `authorize` allows an instructor only in the assignment's group. A cross-group call returns **403** `cross_group_forbidden` and the audit row stores **actor** and **owner**. Covered by `test_object_authz_group_boundary_and_audit`. | Not a lab session test. |
| D3 Separate SgNB | Gate B evidence stays **NOT ACCEPTED** for the integrated NR cell. The target remains a separate SgNB. | No separate-SgNB build, no acceptance, and `/workspace/sgnb-feasibility.md` is not in the tree. The OAI recommendation is still pending approval. |
