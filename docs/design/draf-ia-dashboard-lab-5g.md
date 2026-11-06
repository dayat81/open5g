# Draf IA — Dashboard lab 5G

> **WIP / interim export from Cursor Canvas TSX source (string-literal digest).**
> Exported: 2026-11-06 20:22:08 +0700 · timezone: Asia/Bangkok (UTC+7)
> Canvas URL: https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/23246725-58bf-426d-bbc5-7c300ef7439f
> canvas_id: `23246725-58bf-426d-bbc5-7c300ef7439f`
> **Method:** regex extraction of JSX text / string props — not a browser-rendered DOM dump; Status/Diagram/interactive widgets partially flattened.
> **Not** a product approval, API contract, or new decision. Phrases below are as written in the Canvas source.
> Information architecture + screen catalog draft from Soft Arch / UX handoff. Field names = draft for wireframes — **not API final**.

**Summary (from Page):** IA + katalog layar + arah visual + nama field draft dari Software Architect (bukan API final). Wireframe lo-fi Overview dan editor IMSI memakai kontrak nama ini untuk review sebelum frontend.

**Page `sources` prop:**
- https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/464ec2f8-0481-469e-82d4-9c8aca720dcb

---

> **Status draf:** Versi 0.9 — HTML sinkron Soft Arch closing + PRD v0.4 dikirim untuk final review Hidayat. Hi-fi ditahan sampai disetujui.

## Prinsip UX {#prinsip}

- Jangan pernah menyamakan draft tersimpan dengan kebijakan aktif di PCRF
- Setiap angka usage/throughput wajib punya provenance (Gx / PFCP / eBPF / capture / unsupported)
- missing / stale / unsupported / ambiguous berbeda dari zero / failed
- Label antarmuka EPC (S1-U, S5/S8-U, SGi); N3/N4/N6 hanya jika 5GC terverifikasi
- IMSI hanya dari assignment server-side â bukan klaim loginâIMSI sendiri
- Apply butuh konfirmasi + dampak reattach; Active butuh bukti sesi
- Policy intent â  enforcement â  measured


## Model empat keadaan (jangan digabung) {#state}

| Lapisan | Label UI | Wajib ditampilkan |
| --- | --- | --- |
| Detection | Detected | evidence + time + source |
| Policy decision | Decided | evidence + time + source |
| Installed enforcement | Installed | evidence + time + source |
| Observed traffic | Observed | evidence + time + source |

| Versi / apply | Arti |
| --- | --- |
| desired_version | Intent yang user inginkan (draft/valid) |
| applied_version | Versi yang sudah di-push ke target |
| observed_version | Versi yang terlihat dari bukti sesi/traffic |
| apply_job | Job apply + status per-target |
| per-target | subscriber DB \| PCRF \| eBPF \| session â masing-masing last_error / reason / time |

> **Active ≠ save sukses:** Status Active hanya jika ada bukti sesi. Sukses simpan DB atau push PCRF saja tidak cukup untuk badge Active global.


## Field draft (Software Architect) {#fields}

> **Bukan API final:** Nama di bawah = draft untuk wireframe/mockup. Repo/koding belum dimulai. Mockup pakai data contoh saja.


### Scope & authz

- Selector: instance / experiment + IMSI assigned server-side
- Role kandidat: admin | instructor | student
- Global core controls: tidak tersedia bagi student


### Profile editor

- profile_id, version
- APN (EPC) / DNN (5GC) + logical slice / template
- QCI; ARP terpisah: priority, preemption_capability, preemption_vulnerability
- ambr_ul/dl, mbr_ul/dl, gbr_ul/dl + unit; validasi GBR â¤ MBR per arah
- app_rules[]: match_type IP|hostname|SNI, pattern, app_id, priority, enabled, apply_targets â badge per-rule jika SNI/hostname (intent klasifikasi; native PCC belum terverifikasi)
- usage: scope app|session, threshold, unit, window_s
- Ki/OPc tidak ditampilkan
- S-NSSAI hanya bila 5GC terverifikasi â bukan sinonim APN


### Actions

- Save draft
- Validate
- Review diff
- Apply (konfirmasi + dampak reattach)
- Restore version (membuat versi baru)


### Observation & KPI

- Sessions/bearers: UE IP, APN/DNN, bearer/session IDs, QCI, TEID+endpoints, PGW-C/SMF, PGW-U/UPF instance
- KPI: bytes / packets / rate / window; source eBPF|Gx|PFCP|capture; capture point; freshness; counter reset; classifier/rule version; attribution confidence; unknown traffic


### States UI wajib

- Audit / version history
- Permission / ownership conflict
- Concurrent update conflict
- Pending reattach
- Loading / empty / no-access
- Admin limit/template: usulan â jangan isi angka seolah approved


## Peran dan sitemap {#sitemap}

- **Student:** Edit profil PCRF IMSI assigned; observability eksperimen sendiri; tanpa global core controls
- **Instructor:** Pantau eksperimen grup/kelas; baca-saja atau kuota terbatas (detail TBD)
- **Admin:** Assign IMSI, katalog/template/kuota, lab status, restart shared core, audit global


## Katalog layar MVP {#screens}

1. Login / session
  - Auth + role; land di Overview
  - Scope: instance/experiment + IMSI assigned (bukan IMSI dari login claim)
2. Overview â lab & slice/APN status (wireframe lo-fi)
  - desired vs applied vs observed ringkas
  - Mismatch / stale / unsupported strips
  - Cuplikan Detected/Decided/Installed/Observed
3. IMSI profile editor (wireframe lo-fi)
  - Field draft SA di atas
  - Actions: Save draft, Validate, Review diff, Apply, Restore version
  - Panel per-target apply status
4. PCC & app rules view
  - Decided vs Installed + evidence
  - app_rules IP|hostname|SNI (native PCC belum terverifikasi)
5. Usage per-app & per-slice
  - KPI ber-provenance; capture point S1-U/SGi benar
6. Topology view
  - eNB, SGW-U, PGW-U/UPF, SMF/PGW-C, PCRF; edges S1-U/S5-U/SGi/Gx/Sx
7. Admin â assignment, katalog, kuota, audit
  - Limit/template = usulan; audit immutable; core controls + blast radius


## Arah visual {#visual}

- **Tone:** Lab ops â rapi, padat, tenang
- **Mode:** Dark-first diusulkan; light setara
- **Tipografi:** Sans UI; mono untuk IMSI, TEID, IP, SNI, version ids
- **Warna status:** Intent/desired = biru; Applied = amber; Observed/Measured = hijau; Unknown/stale/unsupported = abu dashed; Failed/Drift/conflict = merah
- **Komponen kunci:** ( StateChip {", ProvenanceBadge, DiffStrip, ConfirmApplyModal, PerTargetApplyRow, NodeIcon"} )


## Alur utama mahasiswa {#flow-student}

1. **Pilih scope** — instance/experiment + IMSI assigned
2. **Edit desired profil** — Field dalam katalog; Save draft â Validate
3. **Review diff** — desired_version vs applied_version
4. **Apply** — Konfirmasi reattach; pantau apply_job per-target
5. **Bandingkan observed** — observed_version + Detected/Decided/Installed/Observed


## Alur apply profil (detail) {#flow-apply}


## Navigasi yang diusulkan {#nav}

**Nav mahasiswa**
- Profil + Apply per-target
- Observability ber-provenance
- Audit / version history milik sendiri

**Cons**
- Global core controls / restart
- Assignment IMSI / Ki OPc
- Angka kuota seolah approved


## Keputusan desain terbuka {#open}

- [ ] Scope instructor: baca-saja vs apply terbatas
- [ ] Angka kuota aggregate: pending vs ada approved values
- [x] Wireframe Overview + IMSI editor memakai field draft SA
- [ ] Bahasa UI: ID / EN / bilingual teknis
- [ ] Dark-first vs light-first

HTML terbaru (RAA≠Active, no auto-restart, 403 cross_group, app_id/etag, reject QCI/ARP/AMBR) di chat untuk final review. Setelah disetujui: design tokens + hi-fi.


## Sumber

Memo Software Architect: https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/464ec2f8-0481-469e-82d4-9c8aca720dcb — plus field/component draft yang dikirim ke UX Designer.
