# lab5g-dev sanitized reference — **WIP package v1**

**This is a sanitized reference snapshot for Git scaffolding — not a deployable mirror of the real lab.**

| Field | Value |
|---|---|
| Version | **WIP v1** |
| Snapshot time | **2026-11-06 20:22:13 +07** (Asia/Bangkok) |
| Lab target | `lab5g-dev` (`172.22.20.21`) only |
| Lab mutations | **None** (read-only copy) |

See `CHANGELOG/STATUS.md` for the status table.

## Layout

```
CHANGELOG/STATUS.md
lab/compose/
lab/config/examples/{open5gs,freediameter,ran,subscribers,slicing-poc,ebpf}/
lab/scripts/
lab/patches/pcrf-admin-rar/ + pcrf-admin-rar.patch   # DRAFT
lab/versions.md
docs/plan-poc-slicing-core.md
docs/capabilities.md
docs/research/sgnb/                                  # IN PROGRESS
docs/evidence/gate-a-lab5g-dev/
docs/evidence/gate-b-endc-integrated/                # NOT ACCEPTED
docs/evidence/gate-poc-slicing/                      # no gates executed
docs/SECRET_SCAN.md
```

## Sanitization

Ki/OPc/AMF, passwords/tokens, PEM bodies, corporate `<HOST>`/`<HOST_IP>`/`<USER>` redacted or omitted. Lab-internal `10.99.x`/`172.22.x`/`10.45.x`/`10.46.x`/`10.47.x` kept.
