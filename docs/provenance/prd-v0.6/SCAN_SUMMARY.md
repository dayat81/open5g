# SCAN_SUMMARY — open5g-prd-v0.6

Scan time: 2026-11-06 20:28:21 +0700 · Asia/Bangkok (UTC+7)  
Source (frozen): `/workspace/prd/export/docs/prd/`  
Archive payload: **`docs/prd/*` only** (canonical PM Markdown).  
Independent scan — PM README sanitasi claims not treated as sole evidence.

## Packaging

| Check | Result |
|-------|--------|
| Hierarchy | `docs/prd/{README,PRD-v0.6,ROADMAP,DECISIONS,RISKS}.md` |
| Non-md / cache / .env / raw TSX/JSON | **Excluded** (none present in source) |
| Prior interim archive | **Untouched** (`/workspace/open5g-interim-docs.tar.gz`) |
| Byte fidelity vs export | **Verified identical** before tar |

## Secrets / sensitive

| Check | Result |
|-------|--------|
| PEM / private keys | **None** |
| password / token / api_key assigned values | **None** |
| Mongo/URI with credentials | **None** |
| Ki / OPc / AMF hex values | **None** |
| IMSI-like 14–15 digit sequences | **None** |
| Hex blobs ≥32 chars | **None** |

## Non-secret context noted

| Item | Detail |
|------|--------|
| Lab-internal IPv4 | **Present** in `PRD-v0.6.md`: host `10.17.7.160`, lab5g-dev `172.22.20.21` — allowed per PM as nonsecret lab topology context |
| Absolute box path mentions | **Present** as provenance refs in `ROADMAP.md` / `DECISIONS.md`: `/workspace/sgnb-feasibility.md` (recommendation source path, not a secret) |

## Provenance / supersession (documented, not fabricated)

- Canonical **v0.6** replaces pending v0.4/v0.5 PRD packs in cloud.
- Soft Arch interim Page snapshot (`…v0.4.INTERIM-SNAPSHOT.md` inside prior interim docs tar) is **superseded** by this pack; do not invent new approvals or gate evidence beyond what these five files state.
- This agent did **not** edit Canvas Pages, push, or access laptop/lab.

## Verdict

**PASS** — safe to forward `docs/prd/` hierarchy for cloud commit reconciliation.
