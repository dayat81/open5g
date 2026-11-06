# CHANGELOG — align PRD + Soft Arch

Tanggal: 6 Nov 2026 (Asia/Bangkok, UTC+7)

## Soft Arch closing + PRD v0.4

Perubahan **minimal** in-place (Soft Arch PASS penutup + Product Manager PRD v0.4). Bukan rewrite. Klaim tetap: **mock spec only / bukan bukti adapter**.

### Soft Arch penutup
1. Overview PCRF/Gx RAR: status dari RAR/RAA ACK = `pushed` saja; label **RAA ACK ≠ Active**; Active hanya bukti session per operasi.
2. Editor banner + modal A/B: **Apply tidak memicu auto restart core**.
3. Out-of-group: contoh **HTTP 403 `cross_group_forbidden`** + audit `actor`/`owner`/`reason` (Overview `#instructor-scope`, editor states).
4. Usage scope=app: field **`app_id`**; Intent panel: **`version_etag`** (ganti label etag generik).

### PRD v0.4
- Capability **per operasi** (bukan satu toggle RAR) — chips `#capability-matrix` di Overview + Editor.
- Immediate apply **modify QCI/ARP on existing bearer** dan **APN-AMBR** = unsupported stock Open5GS 2.8 → UI **reject-with-reason** sampai patch (modal B + chips).
- RAR new PCC rule = supported (contoh data). Fallback re-attach = confirm.
- Tidak mengklaim backend/adapter selesai.

### File disentuh
- `01-overview-lofi.html`, `02-imsi-profile-editor-lofi.html`, `README.md`, `CHANGELOG-align-prd.md`

---

# CHANGELOG — align PRD v0.2 + Soft Arch + keputusan Hidayat (PRD v0.3)

Tanggal: 6 Nov 2026 (Asia/Bangkok, UTC+7)

## Update terkini — keputusan Hidayat (K1 / K2)

Menggantikan asumsi terbuka A1/A2. A1/A2 **tidak** lagi disebut sebagai open assumptions di README/UI.

### K1 — Apply via Gx RAR (primary)
- Banner Overview/Editor: primary path = **Gx RAR immediate**; re-attach = **fallback** saja.
- Status apply/RAR **per IMSI**: `saved | pushed | active | partial | timeout | gagal/failed` + `freshness` (di samping lifecycle Soft Arch).
- Modal editor **state A**: “Apply via Gx RAR”.
- Modal editor **state B**: “RAR unsupported → Reject + Confirm re-attach fallback” (bukan silent success).
- Hapus label Asumsi / “reattach sebagai jalur utama” / “Gx RAR = UNKNOWN/requires-code” sebagai primary messaging.

### K2 — Instructor edit/apply in-group
- Instructor **boleh** edit & apply profil IMSI student **hanya di grup sendiri**; out-of-group = `no-access`.
- Audit: `actor` + `owner` (student pemilik).
- Hapus “Instructor TIDAK boleh edit” / “TBD edit” / A2.
- Overview `#instructor-scope` + nav Kelas aktif (tautan catatan); editor header group/ownership.

## Sebelumnya — align PRD v0.2 + Soft Arch 7 poin

### PRD / user stories (v0.2 baseline)
- US-01…US-04, US-06, US-07 digambarkan di UI + mapping.
- Strip FR-15 EN-DC option 3x = PLANNED/unverified; core **Open5GS EPC CUPS**.

### Soft Arch 1–7
1. classifier_source ≠ enforcement (blocker)
2. app_rules[] + badge per-rule SNI/hostname
3. Lifecycle saved|validated|queued|pushed|active|failed|drift + label UI
4. QoS/ARP/usage field terpisah; GBR≤MBR
5. KPI exporter/clf/reset/freshness; IMSI assigned-only
6. DB/PCRF = contoh/unverified
7. `<button>`; dialog aria; nav disabled tanpa href="#"

## Tidak diubah (sengaja)
- Hi-fi / design tokens — ditahan sampai approve final.
- Angka kuota admin — usulan/TBD.
- Implementasi frontend / adapter lab — di luar scope wireframe.
