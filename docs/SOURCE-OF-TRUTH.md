# Source of truth

Priority when artifacts disagree. A claim in a document is not evidence by itself.

| Artifact | Path | Authority | Notes |
|---|---|---|---|
| UX hi-fi | `docs/ux/hifi/` | UI component-mapping source supplied by UX | Tokens, components, icons, Overview and IMSI editor HTML. Not a screenshot of a Next.js app in this repo. |
| UX prototype | `docs/ux/prototype/` | Demo only | localStorage HTML/JS. No auth. Not the Next.js or FastAPI app. |
| UX wireframes | `docs/ux/wireframes/` | Lo-fi archive | Not the latest visual contract. |
| UX pack README | `docs/ux/README.md` | Map of the sanitized UX pack | Included. |
| Feasibility memo | `docs/design/memo-kelayakan-dashboard-lab-5g-parsial.md` | Design narrative | Markdown digest. Mirror under `docs/pages/`. |
| IA draft | `docs/design/draf-ia-dashboard-lab-5g.md` | IA draft | Field names are not the API contract. Mirror under `docs/pages/`. |
| PRD v0.4 Page snapshot | `docs/pages/historical/prd-lab-5g-nsa-dashboard-v0.4.INTERIM-SNAPSHOT.md` | Historical only | Superseded by PRD v0.6. Not current. |
| Canonical PRD, roadmap, decisions, risks | `docs/prd/PRD-v0.6.md` and siblings | Current Product Manager pack v0.6 | Byte-identical to the supplied export. v0.5 was never the canonical body. |
| PoC plan | `docs/plan-poc-slicing-core.md` | Lab-attached sanitized plan | `docs/plans/plan-poc-slicing-core.md` is a pointer only. |
| Lab sanitized WIP | `lab/` | Network Architect reference, not a deploy | See `docs/DELIVERABLES.md` for gate labels. |
| Scaffold policy code | `dashboard/backend/src/open5g_dashboard/domain.py` | Implemented rules and unit tests | Not a live Gx RAR or metric integration. |

UX conflict priority from the supplied pack: `hifi/` over prototype tokens over wireframes.

Raw Canvas sources under the archive `META/canvas-src/` are not checked in. Provenance for the docs drop is `docs/provenance/interim-docs-MANIFEST.md`.
