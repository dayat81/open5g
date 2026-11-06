> Repository note: checked in from the Network Architect sanitized WIP package. This checkout did not run the lab, compile the PCRF patch, or re-verify the result below. lab5g-vm was not used.

# Gate PoC slicing — evidence summary

**Status:** no gates executed yet.  
**Time:** 2026-11-06 20:21:58 +07 (Asia/Bangkok).  
**Target:** `lab5g-dev` only (staged artifacts here are **not deployed**).

| Gate | Intent | Status |
|---|---|---|
| Gate 1 — APN/UPF per slice (T1) | Multi-DNN + dedicated UPF | **Not executed** (STAGED only) |
| Gate 2 — Sx URR / usage (T2) | PFCP Session Report | **Not executed** |
| Gate 3 — live Gx RAR / PCC (T4–T6) | Admin-trigger RAR → bearer | **Draft only** (PCRF patch DRAFT, NOT COMPILED, NOT TESTED) |
| Gate 4 — eBPF app detection (T3) | IP / DNS / TLS-SNI | **Not executed** (no eBPF code present) |

No pcaps / RAR-RAA / PFCP mod / dedicated-bearer S1AP evidence in WIP v1.
