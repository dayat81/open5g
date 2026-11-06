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

The stock apply function rejects immediate QCI/ARP changes on an existing bearer and APN-AMBR RAR for Open5GS 2.8, and it rejects any immediate Gx RAR because no adapter is implemented. A rejected result is not `pushed` or `active`. RAA 2001, when evaluated by the pure helper, is only `pushed`. Active still requires correlated session, PGW-C, or PFCP evidence. No live RAR or metric path is connected.

## HTTP API (implemented, stock adapter rejects)

`python -m open5g_dashboard` serves the app after `OPEN5G_DATABASE_URL` and `OPEN5G_SESSION_PEPPER` (32+ characters) are set. There is no default password. Sessions use an HttpOnly `SameSite=Lax` cookie plus a CSRF token checked on mutating requests. Ownership is loaded from the assignment row. Immediate apply calls `stock_immediate_apply` and is stored as `rejected`, `executed=false`, `core_restart=false`. RAA 2001 is not treated as `active`. The demo sample route is off unless `OPEN5G_ENABLE_DEMO_ROUTES=1`, and its body is labeled `fake`.

`frontend/` is the Next.js Overview, profile editor, and audit screen. It maps `docs/ux/hifi` classes. Demo mode is the default and is labeled as sample data. It does not replace or wrap `docs/ux/prototype/`.

Not in this tree: a production identity provider, a connected metric exporter, and eBPF counters read from the kernel. `/api/metrics/drilldown` returns an empty stub. `/api/core/restart` does not restart anything. The eBPF skeleton under `ebpf/` compiles without loading.

The localStorage prototype is `docs/ux/prototype/`. It is a no-auth demo and does not replace the Next.js app.
