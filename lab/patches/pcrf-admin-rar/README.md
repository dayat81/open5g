# PCRF admin-RAR patch (draft)

**DRAFT, NOT COMPILED, NOT TESTED**

Snapshot: 2026-11-06 20:21:01 +07 (Asia/Bangkok). Source: `/workspace/pcrf-patch/`.

## Contents
- `src/pcrf/pcrf-admin-rar.c` / `.h` — Unix-socket admin trigger (`PCRF_ADMIN_TOKEN`, `/run/open5gs-pcrf-admin.sock`)
- `gx-admin.patch` — hooks into `pcrf-init.c`, `pcrf-fd-path.h`, `meson.build`
- `fragments/gx-rar.c.add` — appended body for `pcrf_gx_send_pcc_rar()`
- `fragments/hash.c.add` — orphan draft helper (do not apply blindly; stock Open5GS already provides `pcrf_sess_find_by_ipv4`)

Unified diff for Git: `../pcrf-admin-rar.patch` (against Open5GS v2.8.0 touched files only).

## Status
Not built into `lab5g-dev` open5gs-src, not linked into running `l5gd-pcrf`, no RAR/RAA pcap evidence yet.
