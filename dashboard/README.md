# Dashboard

Multi-user IMSI profile intent for the EPC lab: a student on assigned IMSIs, an instructor inside one group, and an admin for assignment, catalog, and caps. Ki and OPc are not profile fields. Students and instructors do not get shared core controls.

## What is in the tree

`backend/` holds pure policy rules, the initial PostgreSQL migration, and unit tests.

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.lock
.venv/bin/pytest -q
```

`pytest -q` in this directory: 19 passed (12 domain tests plus the HTTP tests). The HTTP tests apply `migrations/001_init.sql` to a local PostgreSQL database and then roll the data back. They do not start a core.

The stock apply function rejects immediate QCI/ARP changes on an existing bearer and APN-AMBR RAR for Open5GS 2.8. `OPEN5G_ENABLE_GX_RAR=1` selects the draft admin-RAR adapter, which still returns `rejected` / `executed=false` because `lab/patches/pcrf-admin-rar` is not compiled or tested. A rejected result is not `pushed` or `active`. RAA 2001, when evaluated by the pure helper, is only `pushed`. Active still requires correlated session, PGW-C, or PFCP evidence.

Phase 1 subscriber provisioning is `POST /api/profiles/{id}/provision`. It writes APN, QCI, ARP, AMBR, and IP flow rules into the Open5GS MongoDB subscriber document and reads that document back. Ki and OPc are preserved and never returned. The call does not push a live session. `GET /api/core/status` reports NF scrapes: empty endpoint configuration is `not_configured`, and a down NF stays in the list as `down` without failing the response. There is no Docker socket and no Open5GS WebUI client.

## HTTP API (implemented, stock adapter rejects)

`python -m open5g_dashboard` serves the app after `OPEN5G_DATABASE_URL` and `OPEN5G_SESSION_PEPPER` (32+ characters) are set. There is no default password. Sessions use an HttpOnly `SameSite=Lax` cookie plus a CSRF token checked on mutating requests. Ownership is loaded from the assignment row. Immediate apply calls the policy port and is stored as `rejected`, `executed=false`, `core_restart=false` while the Gx flag is off, and the draft adapter does the same when the flag is on. RAA 2001 is not treated as `active`. The demo sample route is off unless `OPEN5G_ENABLE_DEMO_ROUTES=1`, and its body is labeled `fake`.

`OPEN5G_MONGO_URI` empty keeps the subscriber port disabled. Set it only for lab5g-dev. `OPEN5G_METRICS_ENDPOINTS` and `OPEN5G_HEALTH_ENDPOINTS` empty keep NF status at `not_configured`.

`frontend/` is the Next.js Overview, profile editor, emulator screen, and audit screen. It maps `docs/ux/hifi` classes. Demo mode is the default and is labeled as sample data. It does not replace or wrap `docs/ux/prototype/`.

The emulator tab reverse-proxies a ws-scrcpy sidecar for an assigned UE. It is off unless `OPEN5G_EMULATOR_ENABLED=1`. The runbook is [`docs/deploy/android-emulator-dashboard.md`](../docs/deploy/android-emulator-dashboard.md). A down emulator shows status only. There is no reset or wipe control, and this service does not call the core.

Not in this tree: a production identity provider, a loaded eBPF program, or a claim that Prometheus is already enabled on the lab NFs. `/api/metrics/drilldown` remains an empty stub. `/api/core/restart` does not restart anything. The eBPF skeleton under `ebpf/` compiles without loading. Live session proof waits until SMF is restored in the lab; this repository does not start that NF.

The localStorage prototype is `docs/ux/prototype/`. It is a no-auth demo and does not replace the Next.js app.
