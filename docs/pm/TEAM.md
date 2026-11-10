# Tim open5g

Brief tim, 10 Nov 2026 (WIB). Repositori publik: <https://github.com/dayat81/open5g>. PRD kanonik: [`docs/prd/PRD-v0.6.md`](../prd/PRD-v0.6.md).

Dokumen ini hanya memuat peran dan aturan kerja. Pengenal pelaksana dan rincian komputer pribadi tidak dicatat.

## Ringkas

- Lab NSA EN-DC Option 3x. Core Open5GS v2.8.0 EPC CUPS (bukan 5GC). RAN srsRAN 4G `release_25_10`.
- Dashboard slicing APN/PCC (FastAPI, PostgreSQL, Next.js 15). Classifier eBPF tc masih kerangka: belum parse dan belum attach. Patch PCRF admin-RAR masih draft.
- Gate A–F sebagian besar berstatus planned. NR terintegrasi pada srsENB tidak diterima sebagai Gate B.
- Stack Gate B sudah diputuskan OAI pada 10 Nov 2026 pukul 15:06 WIB. Amarisoft tidak dipakai.
- `main` (ujung `d0d4bc4`, tanpa `infra/`) dan `master` (ujung `3af0834`, dengan `infra/` lewat PR #5) berdivergensi.
- Belum ada CI. Belum ada lisensi untuk kode baru. Templat secret yang ada hanya contoh (`.env.example`, `vault.yml.example`), tanpa nilai.
- Target tulis hanya lab5g-dev. lab5g-vm read-only.
- Pemulihan lab5g-dev ke baseline `master` disetujui pemilik pada 10 Nov 2026 pukul 15:11 WIB. Butir itu ada di [timeline](DELIVERY-TIMELINE.md) sebagai MR dan menjadi dependensi uji e2e dashboard (M5).

## Peran

| Peran | Cakupan |
|---|---|
| Architect | Desain dan kesesuaian 3GPP. Review GO/NO-GO. |
| Dev | Perubahan kode dan dokumen lewat pull request. |
| Lab Ops | lab5g-dev: deploy dan bukti gate. Operator tunggal lab. |
| QA | Test plan gate, verifikasi SHA, dan uji e2e di lab. |

Pemilik repo menyetujui keputusan, approval, dan merge. Pemilik bukan peran pelaksana di tabel di atas.

## Aturan kerja

- Semua deliverable masuk lewat pull request. Tidak ada tulis langsung ke `main` atau `master`.
- Approval dan merge dilakukan manual oleh pemilik repo.
- Deploy lab hanya ke lab5g-dev, dan hanya dengan persetujuan pemilik.
- lab5g-vm read-only. Bukan target deploy dan bukan target perubahan.
- Jangan menulis secret, Ki, atau OPc ke git, dokumen, atau percakapan.
- Jangan menulis IMSI.
- Jangan menulis alamat IP internal, hostname internal, pengguna SSH, atau kunci.
- Bahasa kerja Indonesia, zona WIB. Laporan milestone harus punya bukti.
- Tidak ada keputusan biaya tanpa persetujuan pemilik.

## Pertanyaan terbuka untuk pemilik

1. Sinkronkan salinan kerja lokal pemilik ke `master`?
2. Merge `master` ke `main`, lalu perbarui README dan BOOTSTRAP yang tertinggal?
3. Pasang CI GitHub Actions?
4. Prioritas sisa setelah stack Gate B ditutup: RAR hidup, atau dashboard ke lab5g-dev? Pilihan OAI sudah diputuskan 10 Nov 2026 pukul 15:06 WIB. Amarisoft tidak dipakai.
5. Lisensi untuk kode baru?

Dampak penundaan ada di [timeline](DELIVERY-TIMELINE.md). Keadaan lab5g-dev pada 10 Nov 2026 ada di [inventaris](../lab/LAB5G-DEV-INVENTORY-20261110.md).
