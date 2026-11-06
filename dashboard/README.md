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

The last local run of that command reported 12 passed. It does not apply the migration or open a port.

The stock apply function rejects immediate QCI/ARP changes on an existing bearer and APN-AMBR RAR for Open5GS 2.8, and it rejects any immediate Gx RAR because no adapter is implemented. A rejected result is not `pushed` or `active`. RAA 2001, when evaluated by the pure helper, is only `pushed`. Active still requires correlated session, PGW-C, or PFCP evidence. No live RAR or metric path is connected.

## What is not in the tree

- HTTP API and session cookies
- Next.js UI
- A production identity provider
- Exporters, drill-down data from a core, or eBPF counters

`docs/design/prototype/`, when a localStorage prototype is supplied later, is a no-auth simulation. It does not replace the Next.js app.
