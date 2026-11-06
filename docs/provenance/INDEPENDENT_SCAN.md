# Independent scan — lab5g-dev-sanitized WIP v1

**Scanner:** Soft Arch packaging agent (not NA self-scan)  
**Time:** 2026-11-06 20:24:57 +0700 · Asia/Bangkok (UTC+7)  
**Tar:** `/workspace/lab5g-dev-sanitized-wip-v1.tar.gz`  
**SHA256:** `630cbe089fb2795f3ff0c659311a715e00ba68621c4d40090e470ec27c49fe65`  
**Size:** 58775 bytes (~58K)  
**Tree:** `/workspace/lab5g-dev-sanitized/`  
**NA self-claim:** `docs/SECRET_SCAN.md` = CLEAN — **not sufficient alone**; results below are independent.

## Path safety

| Check | Result |
|-------|--------|
| Absolute paths in tar | **0** |
| `..` traversal | **0** |
| Entries outside `lab5g-dev-sanitized/` prefix | **0** |
| Control chars in paths | **0** |

**PASS** path safety for extract.

## Secrets / sensitive configs (independent)

| Check | Result |
|-------|--------|
| PEM / OpenSSH private keys in tree | **None** |
| `password|secret|api_key|token` assigned string values | **None** found |
| Mongo/URI with embedded credentials | **None** |
| Ki/OPc/AMF hex assignments | **None** — placeholders `<REDACTED_KI>`, `<REDACTED_OPC>`, `<REDACTED_AMF>` in examples/scripts |
| `PCRF_ADMIN_TOKEN` | **Env var name only** in draft patch; no token value |
| SSH private key files | **Not packaged**; docs reference `/ftpdata/<USER>/…/lab_id_ed25519` path template only |
| Full production IMSI (non-test) | Test-range `00101000000000N` in examples; no operator IMSIs found |
| IMEI in `ue.conf.example` | Present: `353490069873319` (srsRAN example-style; not a key; note for awareness) |
| Lab-internal IPv4 (`10.99/10.45/10.46/10.47/172.22`) | **Kept intentionally** (~184 hits) — expected for lab reference |

**Verdict secrets:** **PASS for sanitized reference forward** — no Ki/OPc/PEM/password values observed. Remains a lab-internal IP map; not for public internet dump without policy check.

## Evidence / maturity labels (as labeled in package; not re-verified on live lab this turn)

| Item | Label in package | Soft Arch note |
|------|------------------|----------------|
| Gate A LTE attach + SGi ping | **VERIFIED / ACCEPTED** (NA-reported) | Treat as NA-reported evidence summary only — this agent did **not** re-run lab tests |
| Gate B EN-DC integrated NR cell | **NOT ACCEPTED** (needs separate SgNB) | Do not claim EN-DC Option 3x split-SgNB done |
| PCRF admin-RAR patch | **DRAFT, NOT COMPILED, NOT TESTED** | R-03 delivery risk still open |
| Slicing PoC UPF/SMF configs | **STAGED-NOT-DEPLOYED** | Examples only |
| eBPF | **DRAFT-UNTESTED / absent placeholder** | |
| SgNB research docs | **IN PROGRESS** | |
| Gate PoC slicing 1/2/4 | **Not executed** | |
| Gate PoC slicing 3 (RAR) | **DRAFT-UNTESTED** | |

## Forwarding recommendation

- **OK to forward** `lab5g-dev-sanitized-wip-v1.tar.gz` as a **separate** NA archive to cloud.
- **Do not merge-overwrite** Soft Arch `docs/` onto NA `docs/capabilities.md` / evidence / research (see `COLLISIONS.md`).
- Cloud should **reconcile** (additive paths; diff `plan-poc-slicing-core.md` duplicate).

## Files produced by this independent scan

- `INDEPENDENT_SCAN.md` (this file)
- `COLLISIONS.md`
- `path-safety.txt`, `content-scan.txt`, `tar-paths.txt`
