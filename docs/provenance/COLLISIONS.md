# Collision paths — Soft Arch interim docs vs NA lab5g-dev-sanitized WIP v1

Generated: 2026-11-06 20:24:57 +0700 · Asia/Bangkok (UTC+7)

**Policy for cloud:** reconcile, **do not blind-overwrite**. Keep Soft Arch UX/design/pages pack separate from NA `docs/capabilities.md` / evidence / lab tree.

## Exact path collisions (same relative path under `docs/`)
- **None.** Soft Arch uses `docs/plans/`, `docs/ux/`, `docs/design/`, `docs/pages/`, `docs/prd/`; NA uses `docs/capabilities.md`, `docs/evidence/`, `docs/research/`, `docs/plan-poc-slicing-core.md`, `docs/SECRET_SCAN.md`.

## Soft collisions (same filename, different path) — critical
- **`plan-poc-slicing-core.md`**: Soft Arch `docs/plans/plan-poc-slicing-core.md` ↔ NA `docs/plan-poc-slicing-core.md`

## Soft collisions — plan duplicate
- **`plan-poc-slicing-core.md`**: Soft Arch `docs/plans/plan-poc-slicing-core.md` ↔ NA `docs/plan-poc-slicing-core.md` — likely same/near-same plan; cloud should pick one canonical path (prefer NA tree as lab-attached or Soft Arch `docs/plans/` — **diff before merge**).

## Soft Arch-only under docs/ (safe additive)
- `docs/DELIVERABLES.md`
- `docs/SOURCE-OF-TRUTH.md`
- `docs/architecture`
- `docs/design`
- `docs/design/draf-ia-dashboard-lab-5g.md`
- `docs/design/memo-kelayakan-dashboard-lab-5g-parsial.md`
- `docs/pages`
- `docs/pages/draf-ia-dashboard-lab-5g.md`
- `docs/pages/memo-kelayakan-dashboard-lab-5g-parsial.md`
- `docs/pages/prd-lab-5g-nsa-dashboard-v0.4.INTERIM-SNAPSHOT.md`
- `docs/plans`
- `docs/plans/plan-poc-slicing-core.md`
- `docs/prd`
- `docs/prd/README.md`
- `docs/ux`
- `docs/ux/README.md`
- `docs/ux/UX-FOR-REPO.md`
- `docs/ux/hifi`
- `docs/ux/hifi/01-overview-hifi.html`
- `docs/ux/hifi/02-imsi-profile-editor-hifi.html`
- `docs/ux/hifi/CHANGELOG.md`
- `docs/ux/hifi/README.md`
- `docs/ux/hifi/components.css`
- `docs/ux/hifi/design-system.html`
- `docs/ux/hifi/icons`
- `docs/ux/hifi/icons/enb.svg`
- `docs/ux/hifi/icons/pcrf.svg`
- `docs/ux/hifi/icons/pgw-c-smf.svg`
- `docs/ux/hifi/icons/sgw.svg`
- `docs/ux/hifi/icons/ue.svg`
- `docs/ux/hifi/icons/upf-pgw-u.svg`
- `docs/ux/hifi/tokens.css`
- `docs/ux/prototype`
- `docs/ux/prototype/README.md`
- `docs/ux/prototype/app.js`
- `docs/ux/prototype/components.css`
- `docs/ux/prototype/editor.html`
- `docs/ux/prototype/icons`
- `docs/ux/prototype/icons/enb.svg`
- `docs/ux/prototype/icons/pcrf.svg`
- … +12 more

## NA-only under docs/ (do not overwrite with Soft Arch)
- `docs/SECRET_SCAN.md`
- `docs/capabilities.md`
- `docs/evidence`
- `docs/evidence/gate-a-lab5g-dev`
- `docs/evidence/gate-a-lab5g-dev/SUMMARY.md`
- `docs/evidence/gate-b-endc-integrated`
- `docs/evidence/gate-b-endc-integrated/SUMMARY.md`
- `docs/evidence/gate-poc-slicing`
- `docs/evidence/gate-poc-slicing/SUMMARY.md`
- `docs/plan-poc-slicing-core.md`
- `docs/research`
- `docs/research/sgnb`
- `docs/research/sgnb/CLONES.md`
- `docs/research/sgnb/README.md`
- `docs/research/sgnb/nsa-5gc-feasibility-report.md`
- `docs/research/sgnb/readonly.sh.example`

## Top-level non-docs (NA only — keep separate)
- `lab/**` (compose, config examples, scripts, patches)
- `README.md`, `STATUS.md`, `CHANGELOG/`
- Soft Arch archive top-level: `MANIFEST.md`, `SCAN_SUMMARY.md`, `META/canvas-src/` — no collision with NA top-level names except generic README if both extracted flat (they are not: Soft Arch has no root README).
