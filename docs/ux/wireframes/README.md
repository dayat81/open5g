# Wireframe lo-fi — Dashboard lab 5G

Wireframe **grayscale/blueprint** (bukan hi-fi) untuk **final review Hidayat**, aligned ke **PRD v0.2→v0.3→v0.4** + Soft Arch (PASS + penutup).

**Header file:** `aligned PRD v0.2→v0.3→v0.4 + Soft Arch closing — for Hidayat final review`

Field names & komponen UI mengikuti **draft Soft Arch** (bukan kontrak API final). Semua angka/teks = contoh. Wireframe = **mock spec only / bukan bukti adapter** tersedia. Lab PoC / frontend belum dimulai dari file ini.

## File

| File | Isi |
|------|-----|
| [`01-overview-lofi.html`](./01-overview-lofi.html) | Overview: Gx RAR per-operasi, **RAA ACK ≠ Active**, capability matrix v0.4, instructor 403 `cross_group_forbidden`, classifier ≠ enforcement, KPI provenance |
| [`02-imsi-profile-editor-lofi.html`](./02-imsi-profile-editor-lofi.html) | Editor: Intent 60% / status 40%, usage `app_id` + `version_etag`, **Apply tidak auto-restart core**, modal A/B + reject QCI/ARP existing & APN-AMBR |
| [`CHANGELOG-align-prd.md`](./CHANGELOG-align-prd.md) | Riwayat align |
| [`README.md`](./README.md) | Dokumen ini |

Buka HTML di browser (self-contained). Lebar target ~1280px. Role primary = **Student**.

## Keputusan produk (tertutup)

| ID | Keputusan | UI |
|----|-----------|-----|
| **K1 · Apply** | Primary = **Gx RAR immediate** per operasi. Status: `saved \| pushed \| active \| partial \| timeout \| gagal` + freshness. **RAA ACK ≠ Active**. Apply **tidak** auto-restart core. Fallback re-attach = confirm. | Banner; tabel apply_job; modal A/B |
| **K2 · Instructor** | Edit/apply IMSI student **in-group saja**. Out-of-group = **HTTP 403 `cross_group_forbidden`** + audit `actor`/`owner`. | `#instructor-scope`; nav Kelas |
| **PRD v0.4** | Capability **per operasi** (bukan satu toggle RAR). RAR new PCC rule = supported (contoh). RAR modify QCI/ARP on **existing bearer** + **APN-AMBR** = unsupported stock Open5GS 2.8 → **reject-with-reason** sampai patch. | `#capability-matrix` chips |

## Soft Arch checklist

| # | Poin | Status |
|---|------|--------|
| 1–7 | Sebelumnya (classifier≠enforcement, app_rules, lifecycle, QoS/ARP, KPI, unverified adapters, a11y) | PASS |
| Closing | RAA ACK≠Active; no auto-restart core; 403 cross_group; usage `app_id`; `version_etag` | Done (v0.4 sync) |

## Prinsip

- Intent ≠ Applied ≠ Measured · Ki/OPc hidden · S-NSSAI n/a (EPC)
- Label EPC: S1-U, S5-U, SGi, Gx, Sx — jangan N3/N4/N6
- Mock spec only / bukan bukti adapter

## Sumber

- PRD canvas (+ K1/K2 v0.3, capability per-operasi v0.4)
- Soft Arch field review + penutup (kelulusan mock, bukan adapter)

Versi wireframe: **LOFI aligned PRD v0.4 + Soft Arch closing**
