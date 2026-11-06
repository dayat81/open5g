# Deliverables

Status of branch `cursor/open5g-scaffold-341a`. Labels match the supplied packs. This repository did not re-run the lab.

## Included

| Item | Path | State |
|---|---|---|
| Repository purpose, Affero GPL notes, ignore rules | `README.md`, `NOTICE`, `.gitignore` | On `master` |
| Profile policy module, PostgreSQL schema, hashed test lock | `dashboard/backend/` | On this branch. `pytest -q` on the domain tests: 12 passed. Migration not applied in that run. HTTP API not in this commit. |
| UX sanitized pack | `docs/ux/` (`hifi/`, `prototype/`, `wireframes/`) | Included from the interim docs archive. Prototype is demo-only localStorage, not production and not the Next.js app. |
| Feasibility memo and IA draft | `docs/design/` and mirrors in `docs/pages/` | Included Markdown digests. |
| PRD v0.4 Page snapshot | `docs/pages/prd-lab-5g-nsa-dashboard-v0.4.INTERIM-SNAPSHOT.md` | Included. **Superseded / pending v0.5.** Not canonical. |
| Docs archive manifest | `docs/provenance/interim-docs-MANIFEST.md` | Provenance only. Canvas `META/` sources were not committed. |

## Pending

| Item | Path | State |
|---|---|---|
| Canonical Product Manager PRD v0.5, roadmap, decision log, risk register | `docs/prd/` | **Pending.** Placeholder README only. Do not treat the v0.4 snapshot as this pack. |
| Sanitized Network Architect lab package | `lab/`, `docs/capabilities.md`, `docs/evidence/`, `docs/research/` | Separate archive, integrated in the following lab-WIP commit when that commit is on the branch. |
| Next.js Overview and IMSI editor, FastAPI app, eBPF skeleton | `dashboard/frontend/`, `dashboard/backend` HTTP layer, `ebpf/` | Not in the docs commit. |

## Gates A–F

Definitions are not invented. Outcomes below are only what was supplied.

| Gate | Outcome recorded here |
|---|---|
| A | Not yet copied in the docs-only commit. The Network Architect package reports Gate A **VERIFIED** as NA-reported evidence. This repository did not re-test it. |
| B | Integrated NR cell snapshot is **NOT ACCEPTED**. Requirement is a **separate SgNB**. **WIP**. An integrated eNB NR cell is not an accepted separate-SgNB EN-DC result. |
| C | Not supplied. Unknown. |
| D | Not supplied. Unknown. |
| E | Not supplied. Unknown. |
| F | Not supplied. Unknown. |

`lab/patches/pcrf-admin-rar.patch` is not in the docs-only commit. The lab archive marks that draft **NOT COMPILED / NOT TESTED**.
