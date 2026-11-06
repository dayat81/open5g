# CHANGELOG / STATUS — WIP package v1

**Package:** `lab5g-dev-sanitized` WIP v1  
**Time:** 2026-11-06 20:22:13 +07 (Asia/Bangkok)  
**Lab mutations during packaging:** none (read-only)

| Item | Status |
|---|---|
| Gate A — lab5g-dev LTE attach + ping SGi | **VERIFIED** |
| Gate B — integrated srsRAN NR cell (EN-DC in one eNB) | **NOT ACCEPTED** (needs separate SgNB) |
| PCRF admin-RAR patch (`lab/patches/pcrf-admin-rar*`) | **DRAFT-UNTESTED** |
| Slicing PoC UPF/SMF staged configs (`lab/config/examples/slicing-poc/`) | **STAGED-NOT-DEPLOYED** |
| eBPF app detection code/tests | **DRAFT-UNTESTED** (absent — placeholder only) |
| SgNB / Opt7 research notes (`docs/research/sgnb/`) | **IN PROGRESS** |
| Gate PoC slicing Gates 1/2/4 | **Not executed** |
| Gate PoC slicing Gate 3 (RAR) | **DRAFT-UNTESTED** |
| Subscriber rewrite `subscriber-a.js` | **Excluded** (non-additive) |
| Secret scan | see `docs/SECRET_SCAN.md` |

## Changelog (v1)

- Initial sanitized reference layout for Software Architect.
- Added PCRF admin-RAR draft snapshot + unified diff vs Open5GS v2.8.0.
- Added staged slice UPF/SMF/compose examples from `poc-stage` (no deploy, no subscriber script, no mongo dump).
- Documented missing eBPF artifacts.
- Added SgNB research notes (feasibility report + clone pins); `sgnb-feasibility.md` absent.
- Evidence summaries for Gate A, Gate B (NOT ACCEPTED), Gate PoC slicing (none executed).
