# Hi-fi + design system · Dashboard lab 5G

> **Status: FINAL untuk Soft Arch** — disetujui Hidayat (6 Nov 2026, Asia/Bangkok). Soft Arch boleh mapping komponen / mulai implementasi frontend dari paket ini. Isi tetap **mock spec only / bukan bukti adapter**.

Hi-fi final berdasarkan **1:1 lo-fi final yang disetujui Hidayat**. Struktur, ID, field, contoh, keputusan produk, dan copy Indonesia dipertahankan; perubahan hanya visual. Semua data adalah contoh: **mock spec only / bukan bukti adapter**.

## Konsumsi Soft Arch

```html
<link rel="stylesheet" href="tokens.css">
<link rel="stylesheet" href="components.css">
```

1. Gunakan variabel CSS langsung pada React (`className="badge intent"`, `className="state-card measured"`, dsb.). Jangan hard-code hex di komponen.
2. Untuk Tailwind/theme kemudian, map `colors.intent.DEFAULT/text/soft/border` ke `--intent`, `--intent-text`, `--intent-soft`, `--intent-border`; lakukan pola sama untuk applied/measured/unknown/stale/fail/success/warn.
3. Map `spacing.{1,2,3,4,5,6,8,10}` ke grid 4px; font `sans`/`mono`; radius dan shadow sesuai token. Token adalah kontrak visual, nama komponen HTML saat ini adalah referensi implementasi—bukan frontend final.
4. Jangan menyamakan primary action dengan applied state, atau measured dengan status lifecycle active tanpa evidence.

## Makna warna

| Token | Hex utama | Makna wajib |
|---|---|---|
| Intent | `#2563eb` | Desired/draft/Decided; belum berarti terpasang |
| Applied | `#c2410c` | Pushed/installed; RAA ACK hanya `pushed` |
| Measured | `#16803c` | Observed/bukti session atau telemetry |
| Unknown | `#71717a` | Unknown/missing/unsupported/unverified; dashed |
| Stale | `#a16207` | Data kedaluwarsa/drift/partial |
| Fail | `#dc2626` | Failed/timeout/reject; bukan silent success |
| Success | `#16803c` | Sukses eksplisit; jangan jadikan bukti Active |
| Warn | `#a16207` | Peringatan/konfirmasi/mismatch |
| Surface | `#f4f4f5` | Page; default white, subtle zinc |
| Border | `#d4d4d8` | Divider/subtle outline |
| Text | `#18181b` | Primary; secondary `#52525b` |

## File map

- `tokens.css`: warna semantik, tipografi, 4px spacing, radii, shadow, focus ring.
- `components.css`: layout topbar/nav, callout, cards, badges, tabel, split 60/40, form, dialog, chips, status.
- `icons/`: UE, eNB, SGW, PGW-C/SMF, UPF/PGW-U, PCRF (24×24, currentColor).
- `design-system.html`: showcase review terpisah, bukan layar produk baru.
- `01-overview-hifi.html`, `02-imsi-profile-editor-hifi.html`: mockup React-ready yang memakai CSS relatif dan bekerja offline.
- `CHANGELOG.md`: transisi approval lo-fi ke hi-fi pertama.

Buka seluruh HTML langsung di browser dengan folder tetap utuh. Target 1280px; layout merespons layar sempit. Tidak ada dark mode di v1. Lo-fi approved tetap di `../wireframes/` dan tidak dimodifikasi.

## Soft Arch delta · Applied ≠ Active (class)

- `badge applied` / `dot applied` = pushed / installed only (RAA ACK → `pushed`).
- Session-proven Active uses `badge lifecycle-active` (measured palette) — never `applied`.
- Optional: `badge decided` for classifier Decided (same palette as Intent; distinct class for React).
- `applied_version` field stays in the Applied column; only the Active status label changed.
