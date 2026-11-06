# Deliverables

Status of this branch. Incoming packs are listed so the paths stay stable. Their files are not invented here.

## Included

| Item | Path | State |
|---|---|---|
| Repository purpose, Affero GPL notes, ignore rules | `README.md`, `NOTICE`, `.gitignore` | On `master` |
| Profile policy module, PostgreSQL schema, hashed test lock | `dashboard/backend/` | On this branch. `pytest -q`: 12 passed. Migration not applied in that run. |
| This deliverable list and the directory READMEs | `docs/`, `lab/`, `ebpf/`, `dashboard/` | This commit |

## Pending

| Item | Intended path | State |
|---|---|---|
| UX ready pack | `docs/ux/` | Incoming. Not checked in. |
| Canonical Product Manager PRD, roadmap, decisions, and risks | `docs/prd/` | Incoming. Not checked in. |
| Sanitized lab package (versions, digests, configs, capabilities) | `lab/` | Incoming from the Network Architect. Not checked in. Gate B below is a reported review result, not that package. |
| Design and information-architecture snapshot | `docs/` | Incoming. Not checked in. |
| Dynamic localStorage UX prototype | `docs/design/prototype/` | Not supplied. When it arrives it stays a labeled no-auth simulation and does not replace the Next.js app. |

`lab/patches/pcrf-admin-rar.patch` is absent because no real patch was supplied.

## Gates A–F

Definitions and pass/fail outcomes are recorded only when supplied. This table does not invent the meaning of a gate.

| Gate | Definition in this tree | Outcome in this tree |
|---|---|---|
| A | Not supplied | Unknown |
| B | Not redefined here | Network Architect report: integrated NR cell snapshot is **NOT ACCEPTED**. The requirement is a **separate SgNB**. Status: **WIP**. An integrated eNB NR cell is a different snapshot and is not an accepted separate-SgNB EN-DC result. |
| C | Not supplied | Unknown |
| D | Not supplied | Unknown |
| E | Not supplied | Unknown |
| F | Not supplied | Unknown |

No `docs/evidence/<gate>/SUMMARY.md` file is added for these gates.
