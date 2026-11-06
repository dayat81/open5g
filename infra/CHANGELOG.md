# Changelog

## 2026-11-06 — Independent integration

- Dropped environment-specific identifiers from the secret-scan denylist. The scan now uses generic key, credential, and personal-path detectors.
- Offline renderer writes `.sh.j2` templates to a `.sh` filename.
- Added `docs/iac-independent-validation.md` and refreshed `MANIFEST.txt` hashes for the files this integration changed.
- Deployment and evidence were not run.

## 2026-11-06 — Offline IaC handoff

- Add variable-driven KVM/VM, Docker, EPC-CUPS, srsRAN and verification roles.
- Template two per-APN slice UPFs and default UE pools from the IP plan.
- Add vault-only subscriber examples and localhost-only dry-run validation.
- OAI X2 SgNB and cgnat/tun2socks Internet egress remain explicitly WIP/off.
- Not applied anywhere; no network or attach evidence generated.
