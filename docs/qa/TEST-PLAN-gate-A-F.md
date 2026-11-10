# Open5G QA — Test Plan Gate A–F (draf)

Dokumen ini merangkum draf rencana uji Gate A–F untuk repositori [dayat81/open5g](https://github.com/dayat81/open5g). Bahasa: Indonesia. Semua cap waktu memakai zona **WIB (Asia/Bangkok, UTC+7)**.

**Status:** draf QA, read-only terhadap kode produk. Kriteria penerimaan tidak dikarang: hanya yang tercatat di paket PRD v0.6 (termasuk ROADMAP, DECISIONS, RISKS) atau tes T1–T10 yang merujuk `docs/plan-poc-slicing-core.md` sebagai sumber ROADMAP. Pemeriksaan scaffold yang bukan exit criteria ditandai eksplisit. Hasil lab Gate A dan Gate C–F untuk draf ini **belum dijalankan**. Untuk Gate B, T-B0..T-B2 dikumpulkan sebagai bukti parsial (evidence Lab Ops di [PR #8](https://github.com/dayat81/open5g/pull/8)); T-B3..T-B12 tidak dijalankan di fase ini (lihat catatan Gate B).

**Cakupan fase 1.** Gerbang rilis fase ini: dashboard hidup, `/api/core/status`, dan provision dengan readback pada IMSI uji (`` `<IMSI-UE-1>` ``). Temuan yang tidak menghentikan dashboard atau merusak EPC adalah fase 2 dan tidak memblokir (non-blocking).

Dokumen ini tidak memuat alamat IP privat/internal, hostname internal sensitif, token, kata sandi, atau identitas pelanggan (IMSI/MSISDN). Nilai lab ditulis sebagai placeholder, misalnya `` `<IMSI-UE-1>` `` dan `` `<IP-SGi>` ``.

## 1. Ringkasan sumber

Paket kanonik Product Manager adalah `docs/prd/`. Isi Gate A–F yang operasional ada di `docs/prd/ROADMAP.md`, bukan hanya di tubuh singkat `PRD-v0.6.md`. Rincian tes T1–T10 dan rantai bukti RAR merujuk `docs/plan-poc-slicing-core.md`, yang disebut sebagai sumber ROADMAP.

| Artefak | Path | SHA / konteks yang dibaca |
| --- | --- | --- |
| PRD v0.6 (ditemukan) | `docs/prd/PRD-v0.6.md` | Terakhir diubah di `d13050f4e6082709a69e8bdf4c586908726f5e22` (6 Nov 2026, 20:30 WIB). Byte yang sama masih ada di ujung `main` dan `master`. |
| Roadmap Gate A–F | `docs/prd/ROADMAP.md` | Sama, commit `d13050f4e608…`; dibaca bersama ujung `master`. |
| Keputusan dan risiko | `docs/prd/DECISIONS.md`, `docs/prd/RISKS.md` | D0–D3 dan R-01…R-12. |
| Rencana uji T1–T10 | `docs/plan-poc-slicing-core.md` | Snapshot dokumen 6 Nov 2026, 20:17:38 WIB; dibaca di ujung `master`. |
| Status deliverable / evidence | `docs/DELIVERABLES.md`, `docs/evidence/` | Ujung `master` `3af083492de01f3baa0c2b8851cbf11157d7b7c4` (merge PR #5, 6 Nov 2026, 20:59:30 WIB). |
| Rencana uji Gate B OAI (belum di-merge) | `docs/prd/gate-b/OAI-GO-NOGO-TEST-PLAN.md` | [PR #8](https://github.com/dayat81/open5g/pull/8), head `d544e133217fa17bf77beb51729a7d2cae2c88bd` (10 Nov 2026). Prosedur T-B0..T-B12. Evidence Lab Ops (bukti parsial T-B0..T-B2) dan keputusan OAI NO-GO (16:16 WIB) ada di komentar PR itu. |
| Cabang yang dipetakan | `main`, `master` | `main` = `d0d4bc4b68a79862ff0b15b3e30190ce460c514b` (merge PR #4, 6 Nov 2026, 20:48:55 WIB) tanpa `infra/`. `master` = `3af083492de01f3baa0c2b8851cbf11157d7b7c4` — cabang integrasi plus IaC. Basis draf ini: **master**. |

Tautan: [commit PRD v0.6](https://github.com/dayat81/open5g/commit/d13050f4e6082709a69e8bdf4c586908726f5e22), [ujung master](https://github.com/dayat81/open5g/commit/3af083492de01f3baa0c2b8851cbf11157d7b7c4).

`docs/BOOTSTRAP.md` masih menulis bahwa `main` hanya initial commit. Itu sudah usang: PR #4 menggabungkan `master` ke `main`, lalu PR #5 menambahkan IaC hanya ke `master`. `PRD-v0.5.md` dan `PRD-v0.4.md` tidak ada di `docs/prd/`. Snapshot v0.4 bersifat historis dan **bukan** sumber kriteria v0.6.

### Status gate di dokumen (bukan hasil uji ulang QA)

Semua baris di bawah adalah status yang tercatat di repo atau keputusan Netdrive, bukan hasil lab yang diulang untuk draf ini. Bukti parsial Gate B dirujuk dari PR #8.

| Gate | ROADMAP v0.6 | DELIVERABLES / evidence (laporan NA di repo; tidak di-rerun) |
| --- | --- | --- |
| A | PLANNED / BUILD | Tabel status VERIFIED; heading evidence ACCEPTED untuk baseline VM + LTE attach + ping SGi. Evidence secara eksplisit: slicing / eBPF / RAR tidak termasuk Gate A; APN-per-slice belum dikonfigurasi di snapshot itu. |
| B | Integrated RUNNING (not accepted); separate-SgNB PLANNED. **Fase 2 (ditunda, keputusan Netdrive 10 Nov 2026 16:16 WIB; OAI NO-GO).** Bukan release blocker fase ini. | Integrated NR cell NOT ACCEPTED. Arahan 15:10 WIB memilih OAI (eNB + en-gNB terpisah); keputusan 16:16 WIB = OAI NO-GO, Gate B ditunda. T-B0..T-B2 = bukti parsial ([PR #8](https://github.com/dayat81/open5g/pull/8)); T-B3..T-B12, termasuk T-B10, = Fase 2 – tidak dijalankan di fase ini. |
| C–E | PLANNED (C: BTF UNKNOWN) | Tidak ada ringkasan evidence lab. Scaffold (eBPF compile, pytest, UI demo) bukan exit gate. |
| F | Later | Belum dimulai. Gate PoC slicing 1–4 di `docs/evidence/gate-poc-slicing/` adalah daftar berbeda, bukan C–F. |

### Catatan Gate B (keputusan Netdrive)

**Status Gate B:** Fase 2 (ditunda, keputusan Netdrive 10 Nov 2026 16:16 WIB; OAI NO-GO). Gate B bukan release blocker fase ini.

Arahan Netdrive 10 Nov 2026, 15:10 WIB memilih stack OAI (eNB + en-gNB terpisah) dan tetap selaras dengan D3 / FR-15: srsENB LTE+NR terintegrasi = *achieved-but-not-accepted*, bukan exit Gate B. Keputusan Netdrive 10 Nov 2026 16:16 WIB menutup jalur itu untuk fase ini: **OAI NO-GO**, dan Gate B ditunda ke fase 2. Exit E1–E7 (SgNB Addition, E-RAB Modification Indication/Confirm, dan S1-U pindah ke en-gNB dengan TEID baru) tidak dibuktikan di fase ini dan tidak menjadi syarat rilis fase 1.

Prosedur resmi tetap di [PR #8](https://github.com/dayat81/open5g/pull/8) (head `d544e13`, `docs/prd/gate-b/OAI-GO-NOGO-TEST-PLAN.md`): kasus **T-B0..T-B12**. Dokumen QA ini tidak merancang prosedur lab sendiri. Evidence Lab Ops untuk bukti parsial ada di komentar PR #8. T9 di `docs/plan-poc-slicing-core.md` dan `lab/scripts/endc-up.sh` (srsENB terintegrasi) tidak dipakai sebagai prosedur atau bukti lulus (PR #8 §3 dan §6).

**Jejak T-B* pada fase ini:**

| ID | Nama | Status fase ini |
| --- | --- | --- |
| T-B0 | baseline | bukti parsial. Evidence Lab Ops: [PR #8](https://github.com/dayat81/open5g/pull/8). Bukan penutupan Gate A (T1/T2 tetap terbuka) dan bukan exit Gate B. |
| T-B1 | S1 Setup | bukti parsial. Evidence Lab Ops: [PR #8](https://github.com/dayat81/open5g/pull/8). Bukan exit Gate B. |
| T-B2 | X2 Setup | bukti parsial. Evidence Lab Ops: [PR #8](https://github.com/dayat81/open5g/pull/8). Bukan exit Gate B. |
| T-B3 .. T-B12 | termasuk T-B10 | Fase 2 – tidak dijalankan di fase ini. |

T-B0 (baseline), T-B1 (S1 Setup), dan T-B2 (X2 Setup) dikumpulkan di fase ini sebagai bukti parsial saja. T-B3 sampai T-B12, termasuk T-B10, bertanda **Fase 2 – tidak dijalankan di fase ini**.

Exit yang tetap berlaku bila Gate B dilanjutkan di fase 2 (FR-15 / D3 / ROADMAP, di PR #8 sebagai **E1–E7**): dua proses OAI terpisah; X2 Setup + SgNB Addition; RRC NR; S1AP E-RAB Modification Indication/Confirm (batas 10 detik); S1-U pindah ke en-gNB dengan TEID baru, dibuktikan S11 Modify Bearer **dan** PFCP Session Modification **serta** GTP-U; data DL/UL sampai SGi. Option 3x di rencana itu = **SCG split bearer, S1-U terminated di en-gNB**; sisa DL di eNB atau X2-U bersifat informatif, bukan syarat gagal. Kriteria itu bukan gerbang rilis fase 1.

Tanda tangan Gate B, saat fase 2 dibuka kembali: QA menyusun evidence; Architect merekomendasikan GO/NO-GO; Netdrive memutuskan dan menandatangani. Untuk fase ini keputusan sudah ada: OAI NO-GO, Gate B ditunda. Status evidence **ACCEPTED** / **NOT ACCEPTED** untuk exit E1–E7 tidak dikeluarkan di fase ini. Hasil harian di rencana Architect adalah LANJUT/STOP, bukan GO/NO-GO. Label T-B0..T-B2 adalah **bukti parsial**, bukan ACCEPTED.

**Pemetaan ID** (PR #8 §6.1, head `d544e13`), disesuaikan keputusan 16:16 WIB:

| ID draf QA ini | ID / bagian di PR #8 | Status fase ini |
| --- | --- | --- |
| B-S1 | §1, exit **E1–E7**, plus alasan integrated srsENB *achieved-but-not-accepted* (standar review; bukan langkah lab) | Review tetap berlaku. Exit E1–E7 tidak ditutup; OAI NO-GO untuk fase ini. |
| B-S2 | Tidak ada langkah lab di PR #8 (tetap review render IaC di draf ini) | tidak berlaku (sintetis) |
| B-L1 | **T-B1 .. T-B9** (prasyarat **T-B0**; kasus negatif **T-B10..T-B12** ada di rencana, tidak dijalankan sekarang) | T-B0..T-B2 bukti parsial ([PR #8](https://github.com/dayat81/open5g/pull/8)). T-B3..T-B9 Fase 2 – tidak dijalankan di fase ini. |
| B-L2 | Larangan T9 / `endc-up.sh`; bukti harus terkorelasi menurut T-B* (bukan prosedur integrated) | T-B4..T-B9 Fase 2 – tidak dijalankan di fase ini. |
| B-L3 | Hari 1 (`hari-1-keluaran.md`: topologi rfsim dan nama field HSS/DCNR) **dan T-B3** | T-B3 Fase 2 – tidak dijalankan di fase ini. |
| E2E-02 | **T-B4 .. T-B9** pada **satu** sesi UE (Hari 5, dilanjutkan Hari 6 hanya bila ID tidak berubah) | Fase 2 – tidak dijalankan di fase ini. Bukan release blocker. |

T-B0 adalah subset attach LTE + ping `` `<IP-SGi>` ``, **bukan** penutupan Gate A; T1/T2 tetap terbuka. Bukti parsial T-B0..T-B2 tidak menutup T1/T2 dan tidak menutup exit Gate B.

## 2. Struktur repo dan cara verifikasi sintetis

Pemetaan memakai ujung `master` `3af083492de0…` karena itu satu-satunya ref yang memuat IaC pada saat draf ini disusun. Ujung `main` sama untuk dashboard, eBPF, PRD, dan lab, tetapi tidak punya `infra/`. Perintah di kolom kanan adalah pemeriksaan lokal/sintetis; **bukan hasil lab**.

| Area | Lokasi | Yang ada sekarang | Cara verifikasi (lokal / sintetis) |
| --- | --- | --- | --- |
| Backend | `dashboard/backend/` | FastAPI, modul kebijakan, migrasi PostgreSQL `migrations/001_init.sql`. Tes: `test_domain.py`, `test_api.py`. Dokumentasi repo: `pytest -q` menghasilkan 19 passed (12 domain + HTTP). Tes HTTP menerapkan migrasi ke PostgreSQL lokal lalu rollback. Adapter stock menolak *immediate apply*. | `cd dashboard/backend; python3 -m venv .venv; .venv/bin/pip install -r requirements.lock; .venv/bin/pytest -q` |
| Frontend | `dashboard/frontend/` | Next.js 15, Vitest, ESLint, `tsc --noEmit`, `next build`. Tes: `EvidenceBadge.test.tsx`, `ProfileEditor.test.tsx`. Dokumentasi: `npm test` menghasilkan 4 passed; lint, typecheck, dan build dilaporkan bersih di PR #3. Mode demo default (`NEXT_PUBLIC_API_BASE` kosong). Hasil apply ditampilkan *rejected*; tidak memakai badge *lifecycle-active*. | `cd dashboard/frontend; npm ci; npm test; npm run lint; npm run typecheck; npm run build` |
| Kontrak eBPF | `ebpf/` | Skeleton `classifier/app_classifier.bpf.c` (tidak parsing DNS/TLS/QUIC, tidak attach). Kontrak `exporter/contract.py`. Tes: `test_contract.py` (dokumen PR: 2 passed). `scripts/check_build.py` mengompilasi objek lalu membuangnya; `loaded=false`. | `cd ebpf; python3 scripts/check_build.py; python3 -m pytest tests` (exit 2 = toolchain tidak ada, bukan kegagalan kontrak) |
| IaC (dry-run) | `infra/` (hanya `master` / PR #5) | Ansible site/teardown, inventory dry-run lokal, renderer, secret-scan, skema Compose. Validasi independen (bukan apply) tercatat PASS di `infra/docs/iac-independent-validation.md`. `ansible-playbook --check/--diff` dan `make up/verify/down/render/check` **tidak** termasuk set validasi independen (bisa menyentuh modul/host). | Dari `infra/`, inventory dry-run lokal, perintah di `infra/docs/iac-independent-validation.md`. Jangan `make up`. |
| Lab reference | `lab/` | Compose, contoh konfigurasi, skrip, patch PCRF DRAFT / tidak dikompilasi. Bukan deploy dari checkout ini. Target tulis satu-satunya: lab5g-dev. lab5g-vm bersifat read-only. | Hanya setelah otorisasi Lab Ops. Perintah di `lab/README.md` dan plan-poc bagian 8. **Belum dijalankan untuk draf ini**, kecuali bukti parsial Gate B (T-B0..T-B2) yang dirujuk dari evidence Lab Ops di PR #8. |
| CI GitHub Actions | `.github/workflows` | Tidak ada. `list_workflows` = 0, `list_workflow_runs` = 0, check runs pada SHA `master` = 0. “CI” di dokumen ini berarti perintah lokal/sintetis yang tercatat di README dan isi PR. | Tidak ada status CI otomatis untuk PR. Verifikasi manual di SHA persis (bagian 5). |

## 3. Tabel kasus uji per gate

Total **30 kasus**: 11 sintetis/review, 19 lab. Rincian: Gate A 5 (1 sintetis + 4 lab), B 5 (2 sintetis + 3 lab), C 4 (2 sintetis + 2 lab), D 7 (2 sintetis + 5 lab), E 6 (3 sintetis + 3 lab), F 3 (1 sintetis + 2 lab).

Kolom *Status lab* untuk kasus lab Gate A dan Gate C–F adalah **belum dijalankan**. Kasus Gate B yang menyentuh T-B3..T-B12 berstatus **Fase 2 – tidak dijalankan di fase ini** dan bukan release blocker. T-B0 (baseline), T-B1 (S1 Setup), dan T-B2 (X2 Setup) hanya **bukti parsial** di [PR #8](https://github.com/dayat81/open5g/pull/8). Kasus sintetis tidak menghasilkan bukti lab. Kasus lab yang masih akan dijalankan membutuhkan otorisasi Lab Ops ke **lab5g-dev saja**; lab5g-vm tidak boleh diubah.

### Gate A — Baseline LTE + multi-APN/SDF/URR

Goal: EPC CUPS hidup di lab5g-dev. Exit ROADMAP: LTE attach; dua APN ke UPF (plus SGW-U); SDF+URR; pcap T1–T2.

| ID | Kriteria dari PRD / sumber | Kasus uji | Tipe | Perintah / cara verifikasi | Lab Ops | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A-S1 | Bukan exit gate. Pra-cek sintetis terhadap template dua UPF slice yang disebut ROADMAP (dua APN ke UPF). | Render dan validasi skema Compose core/RAN termasuk layanan upf-slice-a/b (hanya di SHA yang memuat `infra/`). | Sintetis/CI | Perintah dry-run di `infra/docs/iac-independent-validation.md`. Lulus render bukan bukti T1 di lab. | Tidak | P2 | tidak berlaku (sintetis) |
| A-L1 | ROADMAP: LTE attach. Evidence / lab README: S1 Associated, attach sukses, ping SGi ke `` `<IP-SGi>` ``. | UE attach LTE + jangkauan SGi di lab5g-dev (ulang pada SHA yang diklaim; jangan andalkan snapshot 6 Nov tanpa rerun). | Lab nyata (RAN/UE) | `lab/README.md`: `lab-up.sh` atau compose + `lab-routes.sh`; UE lalu eNB. Cek S1 di port S1AP; log attach; alamat antarmuka UE; `ping -c 3` `` `<IP-SGi>` ``. | Ya | P1 | belum dijalankan |
| A-L2 | Exit ROADMAP + T1: dua APN ke UPF (plus SGW-U); SDF; PDR/FAR/pool sesuai; GTP-U TEID berbeda; CCA benar; pcap T1. | Baseline multi-APN/SDF. Evidence Gate A menyatakan APN-per-slice belum dikonfigurasi — kasus ini belum tertutup oleh ACCEPTED attach. | Lab nyata (RAN/UE) | Plan-poc bagian 8 T1 + tcpdump/tshark PFCP, GTP-U, Gx CCR/CCA. Gagal jika APN/UPF salah atau rule tidak match. | Ya | P1 | belum dijalankan |
| A-L3 | Exit ROADMAP + T2: SDF+URR; Session Report Request/Response; counter dalam toleransi pcap. Jangan labeli Gx usage (R-01/R-02). | Melewati ambang volume/waktu URR di UPF, bukti Sx/N4. | Lab nyata | Plan-poc T2; pcap PFCP. Tidak ada report = gagal. Stock report ke Gy bukan klaim Gx. | Ya | P1 | belum dijalankan |
| A-L4 | R-06 (PRD/RISKS): multi-APN / srsUE multi-PDN = UNKNOWN, risiko delay Gate A. | Uji kemampuan UE/lab untuk dua PDN/APN secara aktual (pelengkap T1, bukan kriteria exit terpisah di ROADMAP). | Lab nyata (RAN/UE) | Dokumentasikan apakah UE uji menahan dua PDN; jika tidak, catat blocker T1 dan opsi reconnect per APN. Identitas uji: `` `<IMSI-UE-1>` ``. | Ya | P2 | belum dijalankan |

### Gate B — EN-DC Option 3x (OAI eNB + en-gNB terpisah)

**Status:** Fase 2 (ditunda, keputusan Netdrive 10 Nov 2026 16:16 WIB; OAI NO-GO). Gate B bukan release blocker fase ini.

Goal (fase 2): dual connectivity dengan en-gNB terpisah. Exit ROADMAP/FR-15/D3: X2 SgNB Addition; S1AP E-RAB Modification Indication/Confirm; S1-U berpindah ke gNB dengan TEID baru. Arahan 15:10 WIB memilih OAI (eNB + en-gNB terpisah); keputusan 16:16 WIB menyatakan OAI NO-GO dan menunda gate ini. Integrated srsENB LTE+NR tetap *achieved-but-not-accepted*. Prosedur tetap T-B0..T-B12 di [PR #8](https://github.com/dayat81/open5g/pull/8) head `d544e13`. Di fase ini hanya T-B0 (baseline), T-B1 (S1 Setup), dan T-B2 (X2 Setup) dikumpulkan sebagai bukti parsial (evidence Lab Ops di PR #8). T-B3..T-B12, termasuk T-B10, bertanda Fase 2 – tidak dijalankan di fase ini.

| ID | Kriteria dari PRD / sumber | Kasus uji | Tipe | Perintah / cara verifikasi | Lab Ops | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B-S1 | D3 / FR-15, plus exit **E1–E7** di PR #8 §1: integrated srsENB LTE+NR = *achieved-but-not-accepted*, bukan exit Gate B. Keputusan 16:16 WIB: OAI NO-GO untuk fase ini. | Review evidence/konfigurasi terhadap E1–E7: `endc-up.sh`, throughput NR integrated, atau bukti parsial T-B0..T-B2 tidak boleh dinyatakan ACCEPTED. | Sintetis / review | Baca `docs/evidence/gate-b-endc-integrated/SUMMARY.md` dan bandingkan dengan E1–E7 (PR #8 §1). Tolak klaim Gate B tanpa dua proses OAI terpisah, X2 Setup + SgNB Addition, E-RAB Modification Indication/Confirm, dan TEID baru ke gNB. Bukti parsial S1/X2 di PR #8 bukan exit. | Tidak | P1 | tidak berlaku (sintetis) |
| B-S2 | Sama D3. Keputusan 16:16 WIB: OAI NO-GO untuk fase ini. Teks `nr_cell_list` atau Compose OAI di hasil render IaC bukan penerimaan EN-DC. PR #8 tidak memuat langkah lab untuk kasus ini. | Jika SHA memuat `infra/`, pastikan artefak ter-render tidak diartikan sebagai SgNB hidup atau sebagai GO Gate B. | Sintetis/CI | Tinjau hasil render + `infra/docs/iac-independent-validation.md`. Tidak ada apply. Di luar bukti parsial T-B0..T-B2. | Tidak | P2 | tidak berlaku (sintetis) |
| B-L1 | Exit ROADMAP/FR-15/D3 = E1–E7 (fase 2). Stack yang diuji: OAI eNB + en-gNB terpisah (D4), lalu OAI NO-GO (16:16 WIB). Option 3x = SCG split bearer, S1-U terminated di en-gNB. | EN-DC Option 3x ditunda. Fase ini: T-B0 (baseline), T-B1 (S1 Setup), T-B2 (X2 Setup) = bukti parsial di PR #8. T-B3..T-B9 dan negatif T-B10..T-B12 = Fase 2 – tidak dijalankan di fase ini. | Lab nyata (RAN/UE, rfsim) | Prosedur fase 2 tetap PR #8, bukan prosedur informal. Exit (tidak dijalankan di fase ini): pcap X2-C (Setup + SgNB Addition Request/Acknowledge/Reconfiguration Complete), S1AP Indication/Confirm (≤ 10 detik), S11 Modify Bearer **dan** PFCP Session Modification, GTP-U ke `` `<IP-gNB>` `` dengan TEID baru (beda dari TEID di `` `<IP-eNB>` ``), lembar korelasi satu sesi (E-RAB ID, TEID lama/baru, ID X2AP/S1AP). T-B8: ≥ 100 paket DL pada TEID baru selama iperf3 30 detik; sisa DL di eNB atau X2-U informatif. T-B9: `ping -c 5` 100% ke `` `<IP-SGi>` `` dan iperf3 DL 30 detik utuh (throughput rfsim bukan syarat lulus). Bukti parsial fase ini hanya T-B0..T-B2 di PR #8. | Ya | P1 | T-B0..T-B2 bukti parsial (PR #8); T-B3..T-B9 Fase 2 – tidak dijalankan di fase ini; bukan release blocker |
| B-L2 | ROADMAP merujuk T9. Plan-poc T9 dan `endc-up.sh` tetap jalur integrated, yang D3 tolak. PR #8 §3 dan §6: keduanya **tidak dipakai**. | Korelasi bukti EN-DC terpisah menurut T-B4..T-B9, bukan cell terintegrasi. Kasus ini Fase 2 – tidak dijalankan di fase ini. | Lab nyata (RAN/UE) | Jangan pakai `endc-up.sh` atau T9 sebagai bukti lulus. Hanya LTE-leg/attach atau bukti parsial T-B0..T-B2 = belum selesai. Bila fase 2 dibuka: bukti T-B4..T-B9 harus satu sesi UE (CSV korelasi, nama pcap `hari-N-*` sesuai PR #8 §6.0); jangan menggabungkan ID dari dua attach. | Ya | P1 | Fase 2 – tidak dijalankan di fase ini (T-B4..T-B9); bukan release blocker |
| B-L3 | Kesiapan UE/lab OAI: Hari 1 dan T-B3 di PR #8. Keputusan 16:16 WIB menunda T-B3 dan sesudahnya, termasuk T-B10. | T-B3 (RRC Connection Reconfiguration memuat konfigurasi NR) = Fase 2 – tidak dijalankan di fase ini. Catatan lapangan, bila ada, tetap tanpa nilai rahasia; identitas ringkasan `` `<IMSI-UE-1>` ``. | Lab nyata (RAN/UE, rfsim) | Tidak dijalankan di fase ini. Prosedur fase 2 tetap PR #8 (Hari 1 dan T-B3). Jangan menambah prosedur sendiri. Identitas di ringkasan: `` `<IMSI-UE-1>` `` (placeholder saja). | Ya | P1 | Fase 2 – tidak dijalankan di fase ini (T-B3, termasuk rangkaian sampai T-B12 / T-B10); bukan release blocker |

### Gate C — eBPF app detection

Goal: IP/DNS/SNI + counters. Exit ROADMAP: T3; BTF verified. Status: PLANNED; BTF UNKNOWN.

| ID | Kriteria dari PRD / sumber | Kasus uji | Tipe | Perintah / cara verifikasi | Lab Ops | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C-S1 | Bukan exit gate. Skeleton boleh dikompilasi; ROADMAP mensyaratkan T3 + BTF verified di lab. | Compile check `app_classifier.bpf.c` tanpa load/attach. | Sintetis/CI | `cd ebpf; python3 scripts/check_build.py` — objek dibuang; `loaded=false`. Exit 2 = toolchain missing. | Tidak | P2 | tidak berlaku (sintetis) |
| C-S2 | Bukan exit gate. Kontrak label exporter (bukan traffic terukur). | pytest kontrak: label set tetap; tolak IMSI/SNI/hostname/flow; stub `data_origin=stub`. | Sintetis/CI | `cd ebpf; python3 -m pytest tests` (baseline dokumen: 2 passed). | Tidak | P2 | tidak berlaku (sintetis) |
| C-L1 | Exit ROADMAP: BTF verified. R-08: kernel/BTF di lab5g-dev = UNKNOWN. | Uji kompatibilitas kernel, BTF, dan hook pada lab5g-dev. | Lab nyata | Belum ada prosedur rinci di PRD v0.6 selain “BTF verified”. Minta rincian ke Architect sebelum merancang perintah attach. | Ya | P1 | belum dijalankan |
| C-L2 | Exit ROADMAP + T3: dua hostname pada VIP sama, DNS unik, `curl --resolve`; app_id/counter terpisah; DNS TTL expire; ECH/DoH fail-open (R-05). | Klasifikasi IP/DNS/SNI + counters di UPF lab. Parsing belum ada di skeleton saat ini — kasus ini gagal sampai implementasi ada. | Lab nyata | Plan-poc T3. Counter eBPF bukan keputusan PCRF dan bukan PCC terpasang (README eBPF / PRD). | Ya | P1 | belum dijalankan |

### Gate D — Live RAR

Goal: *Immediate apply* via Gx RAR (D1 / FR-16). Exit ROADMAP: PCRF admin-trigger; T4–T8; evidence-chain FR-16. *Active* bukan RAA 2001 saja. QCI/ARP-on-existing dan APN-AMBR stock *unsupported*: UI reject sampai patch.

| ID | Kriteria dari PRD / sumber | Kasus uji | Tipe | Perintah / cara verifikasi | Lab Ops | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D-S1 | FR-16: QCI/ARP-on-existing dan APN-AMBR stock unsupported menghasilkan reject sampai patch; *active* bukan RAA 2001 saja. | Tes unit/API: `stock_immediate_apply` menyimpan *rejected*; RAA 2001 paling jauh *pushed* pada helper murni. | Sintetis/CI | `dashboard/backend`: `pytest -q`. Ini regresi keamanan klaim, bukan bukti live RAR. | Tidak | P1 | tidak berlaku (sintetis) |
| D-S2 | ROADMAP: PCRF admin-trigger masih PLANNED. DELIVERABLES: patch draft, not compiled, not tested. | Review PR: `lab/patches/pcrf-admin-rar` tidak boleh diklaim teruji hanya karena file ada di pohon. | Sintetis / review | Diff + `lab/patches/README.md`. Kompilasi/apply hanya setelah otorisasi lab. | Tidak | P2 | tidak berlaku (sintetis) |
| D-L1 | T4 + FR-16 evidence-chain: RAR + RAA 2001; PFCP Mod accepted; Create Bearer S5/S11; E-RAB Setup; traffic di bearer baru. | Install PCC baru (5-tuple, QCI/ARP/MBR baru) via trigger, bukan ganti basis data inti saja. Identitas: `` `<IMSI-UE-1>` ``. | Lab nyata | Plan-poc T4 / bagian 4.3. RAA sukses tetapi N4/GTP/S1AP gagal = *failed/degraded*, bukan *active*. | Ya | P1 | belum dijalankan |
| D-L2 | T5: ubah MBR dedicated (Update Bearer+PFCP+E-RAB Modify). QCI/ARP existing hanya lulus jika nilai aktual berubah (FR-16 / matriks plan-poc bagian 4.4). | RAR modify MBR, lalu percobaan QCI/ARP on-existing. | Lab nyata | Plan-poc T5. Jika QoS tidak berubah, fallback remove+install/reconnect; jangan anggap stock mendukung. | Ya | P1 | belum dijalankan |
| D-L3 | T6: hapus rule; Delete Bearer S5/S11; E-RAB deactivate; PDR dihapus. | RAR Remove. | Lab nyata | Plan-poc T6. Gagal jika bearer/trafik masih aktif. | Ya | P1 | belum dijalankan |
| D-L4 | T7: `` `<IMSI-UE-1>` `` tanpa sesi, RAN tolak, atau timeout menghasilkan *no-active-session*/*failed*; reconnect later memungut intent. UI tidak boleh *active* tanpa evidence. | Failed apply / no session. | Lab nyata | Plan-poc T7 + status API/dashboard. | Ya | P1 | belum dijalankan |
| D-L5 | T8 + matriks FR-16: edit APN / default bearer QCI / static IP tidak boleh diklaim live; reconnect lalu CCR-I/CCA-I + PDN baru benar. | Fallback APN/default QoS. | Lab nyata | Plan-poc T8. Gagal jika hanya nama di UI berubah pada sesi lama. | Ya | P1 | belum dijalankan |

### Gate E — Self-service dashboard

Goal: GUI multi-user. Exit ROADMAP: API/RBAC/grup/audit; FR-16/17; T10. FR-17 (D2): instructor edit+apply hanya dalam grup; lintas grup = 403; audit actor+owner.

| ID | Kriteria dari PRD / sumber | Kasus uji | Tipe | Perintah / cara verifikasi | Lab Ops | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E-S1 | FR-17/D2: instructor hanya in-group; 403 lintas grup; audit actor+owner. Bukan exit T10 lab, tetapi regresi kanonik di scaffold. | pytest API + migrasi PostgreSQL + batas grup. | Sintetis/CI | `cd dashboard/backend; .venv/bin/pytest -q` (termasuk tes authz yang disebut DELIVERABLES). | Tidak | P1 | tidak berlaku (sintetis) |
| E-S2 | Bukan exit gate. ROADMAP mensyaratkan GUI multi-user + T10. Ini gerbang kualitas UI scaffold. | Vitest, lint, typecheck, build; apply UI = *rejected*; tanpa badge *lifecycle-active*. | Sintetis/CI | `dashboard/frontend`: `npm ci; npm test; npm run lint; npm run typecheck; npm run build`. | Tidak | P1 | tidak berlaku (sintetis) |
| E-S3 | DELIVERABLES: UI tidak membuat login; API mode butuh profile id, If-Match, CSRF. Plan-poc bagian 7 punya bentuk API berbeda (celah). | Review kontrak klien vs backend pada SHA PR. | Sintetis / review | Bandingkan `dashboard/frontend/src/lib/api.ts` dengan rute FastAPI dan plan-poc bagian 7. Catat deviasi, jangan anggap T10 lulus. | Tidak | P2 | tidak berlaku (sintetis) |
| E-L1 | Exit ROADMAP + T10: user A edit `` `<IMSI-UE-B>` `` / over-cap / wildcard menghasilkan HTTP 403/422; audit; tidak ada tulis DB/RAR. | Isolasi multi-user terhadap API hidup (bukan demo localStorage). | Lab nyata (aksi dashboard + core) | Plan-poc T10 pada lab5g-dev. Prototype `docs/ux/prototype/` tidak dihitung. | Ya | P1 | belum dijalankan |
| E-L2 | FR-16/17 + ROADMAP: apply in-group via jalur Gx RAR dengan evidence-chain; lintas grup 403. | Instructor/student apply `` `<IMSI-UE-1>` `` yang sah vs tidak sah, dikorelasikan ke pcap RAR. | Lab nyata | Bergantung Gate D. Status *active* hanya dengan bukti prosedur, bukan demo banner. | Ya | P1 | belum dijalankan |
| E-L3 | Goal Gate E: self-service GUI. Aksi dashboard (validate/apply/status) harus mengenai core, bukan `data_origin=demo`. | Alur operator di Overview / editor profil / audit terhadap sesi lab hidup. | Lab nyata (aksi dashboard) | `NEXT_PUBLIC_API_BASE` menunjuk API lab; bukti If-Match/CSRF; audit trail cocok dengan apply. Login produksi belum ada di tree — dokumentasikan blocker. | Ya | P1 | belum dijalankan |

### Gate F — Usage lanjut

Goal: usage per-app. Exit ROADMAP: SDF bridge; Gx usage hanya dengan patch R-01. Status: Later. Stock URR mengarah ke Gy, bukan Gx usage.

| ID | Kriteria dari PRD / sumber | Kasus uji | Tipe | Perintah / cara verifikasi | Lab Ops | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F-S1 | R-01/R-02 + ROADMAP: native Gx usage butuh patch; URR per-PDR bukan per-app; stock Session Report ke Gy. | Hygiene klaim: tolak laporan Gx usage atau per-app usage yang hanya berdasar eBPF stub atau URR stock. | Sintetis / review | Review PR/docs/metrics stub (`/api/metrics/drilldown` kosong menurut dashboard README). | Tidak | P1 | tidak berlaku (sintetis) |
| F-L1 | Exit ROADMAP (Later): SDF bridge — hasil DNS/SNI menjadi flow 5-tuple PCC, dipasang RAR, diukur URR. | Jembatan deteksi ke PCC stock, setelah Gate C/D. | Lab nyata | Plan-poc bagian 5.3. Belum ada prosedur perintah terperinci di PRD v0.6 selain nama deliverable. | Ya | P3 | belum dijalankan |
| F-L2 | Exit ROADMAP: Gx usage hanya dengan patch R-01 (Usage-Monitoring AVP + CCR-U USAGE_REPORT). | Native Gx per-app usage, hanya jika patch disetujui. | Lab nyata | Jangan mulai sebelum keputusan patch. Pcap Gx harus menampilkan AVP runtime, bukan dictionary saja. | Ya | P3 | belum dijalankan |

## 4. Daftar kasus E2E lab (lab5g-dev)

Kelima skenario ini adalah uji ujung-ke-ujung di lab nyata (RAN/UE). Semuanya butuh Lab Ops bila dijalankan. **E2E-01 dan E2E-03..E2E-05: belum dijalankan.** **E2E-02:** Fase 2 – tidak dijalankan di fase ini; bukan release blocker. T-B0..T-B2 hanya bukti parsial di [PR #8](https://github.com/dayat81/open5g/pull/8). Capture kontrol mengikuti plan-poc bagian 8 (Gx, GTPv2, PFCP, S1AP, GTP-U), disimpan dengan stempel waktu WIB, tanpa material kunci subscriber dan tanpa identitas mentah (pakai `` `<IMSI-UE-1>` `` dan sejenisnya).

| ID | Skenario | Kriteria / PASS (sumber) | Cara verifikasi ringkas | Kasus terkait | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- |
| E2E-01 | UE attach (LTE) | LTE attach sukses + jalur SGi (ROADMAP Gate A; prosedur verifikasi di `lab/README.md`). | Setelah otorisasi: `lab-up.sh` (UE lalu eNB). Cek S1 ESTAB di MME (port S1AP), log UE attach successful, alamat antarmuka UE, ping `` `<IP-SGi>` ``. | A-L1 | P1 | belum dijalankan |
| E2E-02 | LTE + SgNB EN-DC (OAI eNB + en-gNB terpisah) | E1–E7 / FR-15/D3, ditunda ke fase 2 (OAI NO-GO, 16:16 WIB): X2 SgNB Addition; S1AP E-RAB Modification Indication/Confirm (≤ 10 detik); S1-U ke gNB dengan TEID baru, dibuktikan S11 Modify Bearer **dan** PFCP Session Modification **serta** GTP-U. Option 3x = SCG split bearer, S1-U terminated di en-gNB; X2-U informatif. Bukan `endc-up.sh` / T9. Bukan release blocker fase ini. | Tidak dijalankan di fase ini. Prosedur fase 2: **T-B4..T-B9 pada satu sesi UE** (Hari 5, Hari 6 hanya jika ID sama; jika sesi putus, ulangi T-B4..T-B9 sebagai satu larian baru). Bukti: pcap X2-C, S1AP, S11, PFCP, S1-U, SGi; CSV korelasi (E-RAB ID, TEID lama/baru). T-B8 ≥ 100 paket DL pada TEID `` `<IP-gNB>` ``; T-B9 `ping -c 5` 100% + iperf3 30 detik ke `` `<IP-SGi>` ``. T-B10..T-B12 = Fase 2 – tidak dijalankan di fase ini, jangan dicampur ke larian emas. T-B0..T-B2 hanya bukti parsial di PR #8. | B-L1, B-L2 | P1 | Fase 2 – tidak dijalankan di fase ini; bukan release blocker. T-B0..T-B2 bukti parsial di PR #8. |
| E2E-03 | Bearer per APN | Dua APN ke UPF (plus SGW-U); SDF; PDR/FAR dan pool sesuai; GTP-U TEID berbeda; CCA benar (T1 / exit Gate A). | Attach/reconnect dua APN, traffic 5-tuple, pcap Sx/SGi. Evidence Gate A saat ini menyatakan APN-per-slice belum dikonfigurasi — kasus ini masih terbuka. | A-L2, A-L4 | P1 | belum dijalankan |
| E2E-04 | PCC / Gx RAR | FR-16 + T4–T8: RAR + RAA 2001 dan PFCP Mod accepted + Create/Update/Delete Bearer S5/S11 + E-RAB Setup/Modify/deaktif. Tanpa sesi atau gagal prosedur menghasilkan *no-active-session* / *failed* / *degraded*, bukan *active*. | tcpdump/tshark Gx, PFCP, GTPv2, S1AP sesuai plan-poc bagian 8. Patch PCRF di repo masih draft — jangan klaim live RAR sebelum patch terverifikasi. | D-L1…D-L5 | P1 | belum dijalankan |
| E2E-05 | Aksi dashboard | T10 + FR-16/17: validate/apply/status terhadap core hidup; 403 lintas grup; audit actor+owner; hasil apply mengikuti evidence-chain (bukan badge *active* dari demo). | API mode butuh profil, If-Match, CSRF; UI tidak membuat login. Jalankan aksi di lab, bandingkan audit + pcap. Demo mode (`data_origin` demo) bukan bukti lab. | E-L1, E-L2, E-L3 | P1 | belum dijalankan |

NO-GO (plan-poc bagian 9, diselaraskan PR #8 dan keputusan Netdrive 10 Nov 2026 16:16 WIB): slicing APN/UPF GO hanya jika T1 lulus; app detection jika T3 lulus; live PCC jika T4/T6 lulus dan T5 dibatasi hasil; self-service jika T10 lulus; Sx URR jika T2 lulus. NO-GO bila hanya basis data inti berubah, hanya RAA 2001, atau hanya UE attach.

**Gate B / OAI.** Keputusan Netdrive 10 Nov 2026 16:16 WIB: **OAI NO-GO**. Gate B ditunda ke fase 2 dan bukan release blocker fase ini. T-B0 (baseline), T-B1 (S1 Setup), dan T-B2 (X2 Setup) adalah bukti parsial (evidence Lab Ops di [PR #8](https://github.com/dayat81/open5g/pull/8)), bukan GO dan bukan syarat rilis. T-B3 sampai T-B12, termasuk T-B10, bertanda Fase 2 – tidak dijalankan di fase ini. Bukti parsial S1/X2 atau attach saja tidak membuka exit E1–E7 dan tidak memblokir rilis fase 1. T9 / `endc-up.sh` tetap tidak dipakai. Bila fase 2 dibuka, EN-DC GO hanya jika E1–E7 / T-B4..T-B9 lulus pada satu sesi dan T-B0 sesudah rollback lulus; QA menyusun evidence, Architect merekomendasikan, Netdrive memutuskan dan menandatangani.

**Gerbang rilis fase 1:** dashboard hidup, `/api/core/status`, dan provision dengan readback pada IMSI uji (`` `<IMSI-UE-1>` ``). Temuan yang tidak menghentikan dashboard atau merusak EPC adalah fase 2 dan non-blocking.

## 5. Checklist verifikasi PR Dev pada SHA persis

Pakai checklist ini untuk setiap PR pengembangan. Semua perintah dijalankan pada commit yang sama (catat hasil `git rev-parse HEAD`). Jangan mencampur hasil dari SHA lain. Tidak ada GitHub Actions; lulus/gagal adalah hasil perintah di bawah plus review diff.

1. **Identitas SHA.** Catat SHA penuh, cabang head/base, dan apakah `infra/` ada di pohon itu. Ujung `main` (`d0d4bc4b68a7…`) tidak memuat IaC; ujung `master` (`3af083492de0…`) memuatnya.
2. **Backend** (jika menyentuh `dashboard/backend` atau dependensi). `cd dashboard/backend; python3 -m venv .venv; .venv/bin/pip install -r requirements.lock; .venv/bin/pytest -q`. Baseline dokumen: 19 passed, termasuk apply migrasi `001_init.sql` dan authz objek. Tes HTTP memakai PostgreSQL lokal lalu rollback. Immediate apply tetap *rejected*, `executed=false`, `core_restart=false` selama adapter stock. RAA 2001 saja bukan *active*.
3. **Frontend** (jika menyentuh `dashboard/frontend`). `cd dashboard/frontend; npm ci; npm test; npm run lint; npm run typecheck; npm run build`. Baseline dokumen: 4 tes Vitest lulus; lint/typecheck/build bersih. Cek: mode demo default; hasil apply bukan badge *lifecycle-active*; tidak ada login buatan; klien API hanya memanggil validate/apply jika id, If-Match, dan CSRF sudah ada.
4. **Kontrak eBPF** (jika menyentuh `ebpf/`). `cd ebpf; python3 scripts/check_build.py; python3 -m pytest tests`. Objek boleh terbangun, tetapi loader/attach tidak boleh terjadi di pemeriksaan ini. Exit 2 (toolchain hilang) berarti *untested*, bukan lulus compile. Exporter menolak label IMSI/SNI/hostname/flow; stub wajib `data_origin=stub`.
5. **IaC dry-run** (jika `infra/` ada di SHA itu). Dari direktori `infra/`, hanya set validasi independen di `infra/docs/iac-independent-validation.md`: yamllint; `ansible-playbook` dengan inventory dry-run lokal untuk `site.yml --syntax-check` (dan `teardown.yml`); `ansible-lint --offline`; `python3 scripts/render-compose.py`; `python3 tests/validate_rendered.py`; `python3 tests/validate_compose_schema.py`; `docker-compose config --quiet` untuk core dan RAN; `bash scripts/secret-scan.sh`. Jangan menjalankan `make up/down/verify/render/check`, atau `ansible-playbook --check/--diff`, tanpa otorisasi — dokumen IaC menyatakan check-mode masih bisa menulis atau menyentuh host. Teks `nr_cell_list` ter-render atau Compose OAI kosong bukan penerimaan Gate B.
6. **Hygiene PR.** Tidak ada material kunci subscriber, kata sandi, atau token; placeholder tetap placeholder. Jangan klaim Gate A–F, live RAR, atau klasifikasi eBPF tanpa evidence baru di SHA itu. Prototype `docs/ux/prototype/` bukan aplikasi. Jangan memasukkan IP privat/internal, hostname internal sensitif, atau IMSI/MSISDN mentah ke dalam bukti atau dokumen.
7. **Lab** (hanya jika PR mengklaim hasil lab, dan hanya setelah otorisasi). Ulangi kasus terkait di lab5g-dev pada artefak yang dibangun dari SHA yang sama. lab5g-vm tidak diubah. Stempel bukti: WIB, SHA, serta identifikasi yang sudah disanitasi (`` `<IMSI-UE-1>` ``, APN/EBI/rule/revision). Untuk draf ini, lab Gate A dan Gate C–F belum dijalankan. Bukti parsial Gate B (T-B0 baseline, T-B1 S1 Setup, T-B2 X2 Setup) merujuk evidence Lab Ops di PR #8 dan tidak menutup exit Gate B. T-B3..T-B12, termasuk T-B10, berstatus Fase 2 – tidak dijalankan di fase ini. Gate B bukan release blocker fase ini.

## 6. Pertanyaan terbuka

Pertanyaan “stack Gate B mana yang disetujui” sempat dijawab pada 15:10 WIB (OAI eNB + en-gNB terpisah). Keputusan berikutnya, **10 Nov 2026 16:16 WIB**, menyatakan **OAI NO-GO** dan menunda Gate B ke fase 2. Prosedur T-B* tetap di [PR #8](https://github.com/dayat81/open5g/pull/8) head `d544e13` (pemetaan di bagian 1 dan 3). T-B0..T-B2 = bukti parsial di PR #8; T-B3..T-B12, termasuk T-B10, = Fase 2 – tidak dijalankan di fase ini. Gate B bukan release blocker fase ini. T9 / `endc-up.sh` tidak dipakai.

Yang masih terbuka:

1. **Gate A — apakah T1+T2 masih wajib?** ROADMAP v0.6 masih PLANNED / BUILD, sementara evidence NA bertuliskan VERIFIED/ACCEPTED untuk attach + ping SGi saja, dan secara eksplisit bukan APN-per-slice / SDF+URR / pcap T1–T2. PR #8 menegaskan T-B0 hanya subset attach + ping dan **tidak** menutup T1/T2. Apakah exit Gate A sudah dianggap selesai, atau T1 dan T2 masih wajib dibuktikan di lab5g-dev?
2. **Di mana teks lengkap US/FR yang berlaku?** `PRD-v0.6.md` menulis US-01…US-09 dan FR-01…FR-14, FR-16, FR-17 “sama v0.5”, tetapi `PRD-v0.5.md` tidak ada di repo dan `docs/SOURCE-OF-TRUTH.md` menyatakan v0.5 tidak pernah menjadi body kanonik. FR-15/16/17 hanya diringkas. QA tidak memakai snapshot v0.4 sebagai pengganti. Mohon ekspor teks lengkap US/FR yang berlaku.

Draf awal: 10 Nov 2026, 15:13 WIB (Asia/Bangkok, UTC+7). Revisi pemetaan T-B*: 10 Nov 2026, 15:40 WIB, terhadap PR #8 head `d544e133217fa17bf77beb51729a7d2cae2c88bd`. Revisi keputusan OAI NO-GO dan penundaan Gate B ke fase 2: 10 Nov 2026, 16:16 WIB. Uji lab Gate A dan Gate C–F belum dijalankan. Exit Gate B tidak dijalankan di fase ini. Revisi berikutnya menunggu jawaban T1/T2, teks US/FR, dan/atau PR Dev baru pada SHA persis. Perubahan status Gate B di PRD/ROADMAP, bila diperlukan, masuk lewat PR terpisah.
