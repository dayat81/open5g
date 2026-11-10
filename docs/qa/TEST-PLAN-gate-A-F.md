# Open5G QA — Test Plan Gate A–F (draf)

Dokumen ini merangkum draf rencana uji Gate A–F untuk repositori [dayat81/open5g](https://github.com/dayat81/open5g). Bahasa: Indonesia. Semua cap waktu memakai zona **WIB (Asia/Bangkok, UTC+7)**.

**Status:** draf QA, read-only terhadap kode produk. **Semua hasil lab: belum dijalankan.** Kriteria penerimaan tidak dikarang: hanya yang tercatat di paket PRD v0.6 (termasuk ROADMAP, DECISIONS, RISKS) atau tes T1–T10 yang merujuk `docs/plan-poc-slicing-core.md` sebagai sumber ROADMAP. Pemeriksaan scaffold yang bukan exit criteria ditandai eksplisit.

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
| Cabang yang dipetakan | `main`, `master` | `main` = `d0d4bc4b68a79862ff0b15b3e30190ce460c514b` (merge PR #4, 6 Nov 2026, 20:48:55 WIB) tanpa `infra/`. `master` = `3af083492de01f3baa0c2b8851cbf11157d7b7c4` — cabang integrasi plus IaC. Basis draf ini: **master**. |

Tautan: [commit PRD v0.6](https://github.com/dayat81/open5g/commit/d13050f4e6082709a69e8bdf4c586908726f5e22), [ujung master](https://github.com/dayat81/open5g/commit/3af083492de01f3baa0c2b8851cbf11157d7b7c4).

`docs/BOOTSTRAP.md` masih menulis bahwa `main` hanya initial commit. Itu sudah usang: PR #4 menggabungkan `master` ke `main`, lalu PR #5 menambahkan IaC hanya ke `master`. `PRD-v0.5.md` dan `PRD-v0.4.md` tidak ada di `docs/prd/`. Snapshot v0.4 bersifat historis dan **bukan** sumber kriteria v0.6.

### Status gate di dokumen (bukan hasil uji ulang QA)

Semua baris di bawah adalah status yang tercatat di repo, bukan hasil lab yang dijalankan untuk draf ini.

| Gate | ROADMAP v0.6 | DELIVERABLES / evidence (laporan NA di repo; tidak di-rerun) |
| --- | --- | --- |
| A | PLANNED / BUILD | Tabel status VERIFIED; heading evidence ACCEPTED untuk baseline VM + LTE attach + ping SGi. Evidence secara eksplisit: slicing / eBPF / RAR tidak termasuk Gate A; APN-per-slice belum dikonfigurasi di snapshot itu. |
| B | Integrated RUNNING (not accepted); separate-SgNB PLANNED; rekomendasi stack di dokumen lama masih pending approval | Integrated NR cell NOT ACCEPTED (tidak ada E-RAB Modification / S1-U ke SgNB). **Keputusan Netdrive 10 Nov 2026, 15:10 WIB: stack Gate B adalah OAI (eNB + en-gNB terpisah).** Lihat catatan di bawah. |
| C–E | PLANNED (C: BTF UNKNOWN) | Tidak ada ringkasan evidence lab. Scaffold (eBPF compile, pytest, UI demo) bukan exit gate. |
| F | Later | Belum dimulai. Gate PoC slicing 1–4 di `docs/evidence/gate-poc-slicing/` adalah daftar berbeda, bukan C–F. |

### Catatan Gate B (keputusan Netdrive, 10 Nov 2026)

Mulai arahan Netdrive (10 Nov 2026, 15:10 WIB), **Gate B memakai OAI dengan eNB dan en-gNB terpisah**. Ini menggantikan ketidakpastian “stack masih menunggu approval” di draf QA sebelumnya, dan tetap selaras dengan D3 / FR-15: srsENB LTE+NR terintegrasi = *achieved-but-not-accepted*, bukan exit Gate B.

Rencana uji formal **T-B1..T-Bn akan disusun Architect di PR terpisah**. Kasus B di dokumen ini **tidak merancang prosedur lab sendiri** dan **ditandai menunggu dokumen Architect**. Jangan memakai prosedur T9 di `docs/plan-poc-slicing-core.md` (masih mendeskripsikan srsENB terintegrasi) atau skrip `endc-up.sh` sebagai bukti lulus Gate B. Kriteria penerimaan yang sudah tertulis di ROADMAP / FR-15 / D3 tetap berlaku: X2 SgNB Addition; S1AP E-RAB Modification Indication/Confirm; S1-U berpindah ke gNB dengan TEID baru.

## 2. Struktur repo dan cara verifikasi sintetis

Pemetaan memakai ujung `master` `3af083492de0…` karena itu satu-satunya ref yang memuat IaC pada saat draf ini disusun. Ujung `main` sama untuk dashboard, eBPF, PRD, dan lab, tetapi tidak punya `infra/`. Perintah di kolom kanan adalah pemeriksaan lokal/sintetis; **bukan hasil lab**.

| Area | Lokasi | Yang ada sekarang | Cara verifikasi (lokal / sintetis) |
| --- | --- | --- | --- |
| Backend | `dashboard/backend/` | FastAPI, modul kebijakan, migrasi PostgreSQL `migrations/001_init.sql`. Tes: `test_domain.py`, `test_api.py`. Dokumentasi repo: `pytest -q` menghasilkan 19 passed (12 domain + HTTP). Tes HTTP menerapkan migrasi ke PostgreSQL lokal lalu rollback. Adapter stock menolak *immediate apply*. | `cd dashboard/backend; python3 -m venv .venv; .venv/bin/pip install -r requirements.lock; .venv/bin/pytest -q` |
| Frontend | `dashboard/frontend/` | Next.js 15, Vitest, ESLint, `tsc --noEmit`, `next build`. Tes: `EvidenceBadge.test.tsx`, `ProfileEditor.test.tsx`. Dokumentasi: `npm test` menghasilkan 4 passed; lint, typecheck, dan build dilaporkan bersih di PR #3. Mode demo default (`NEXT_PUBLIC_API_BASE` kosong). Hasil apply ditampilkan *rejected*; tidak memakai badge *lifecycle-active*. | `cd dashboard/frontend; npm ci; npm test; npm run lint; npm run typecheck; npm run build` |
| Kontrak eBPF | `ebpf/` | Skeleton `classifier/app_classifier.bpf.c` (tidak parsing DNS/TLS/QUIC, tidak attach). Kontrak `exporter/contract.py`. Tes: `test_contract.py` (dokumen PR: 2 passed). `scripts/check_build.py` mengompilasi objek lalu membuangnya; `loaded=false`. | `cd ebpf; python3 scripts/check_build.py; python3 -m pytest tests` (exit 2 = toolchain tidak ada, bukan kegagalan kontrak) |
| IaC (dry-run) | `infra/` (hanya `master` / PR #5) | Ansible site/teardown, inventory dry-run lokal, renderer, secret-scan, skema Compose. Validasi independen (bukan apply) tercatat PASS di `infra/docs/iac-independent-validation.md`. `ansible-playbook --check/--diff` dan `make up/verify/down/render/check` **tidak** termasuk set validasi independen (bisa menyentuh modul/host). | Dari `infra/`, inventory dry-run lokal, perintah di `infra/docs/iac-independent-validation.md`. Jangan `make up`. |
| Lab reference | `lab/` | Compose, contoh konfigurasi, skrip, patch PCRF DRAFT / tidak dikompilasi. Bukan deploy dari checkout ini. Target tulis satu-satunya: lab5g-dev. lab5g-vm bersifat read-only. | Hanya setelah otorisasi Lab Ops. Perintah di `lab/README.md` dan plan-poc bagian 8. **Belum dijalankan untuk draf ini.** |
| CI GitHub Actions | `.github/workflows` | Tidak ada. `list_workflows` = 0, `list_workflow_runs` = 0, check runs pada SHA `master` = 0. “CI” di dokumen ini berarti perintah lokal/sintetis yang tercatat di README dan isi PR. | Tidak ada status CI otomatis untuk PR. Verifikasi manual di SHA persis (bagian 5). |

## 3. Tabel kasus uji per gate

Total **30 kasus**: 11 sintetis/review, 19 lab. Rincian: Gate A 5 (1 sintetis + 4 lab), B 5 (2 sintetis + 3 lab), C 4 (2 sintetis + 2 lab), D 7 (2 sintetis + 5 lab), E 6 (3 sintetis + 3 lab), F 3 (1 sintetis + 2 lab).

Kolom *Status lab* untuk setiap kasus lab adalah **belum dijalankan**. Kasus sintetis tidak menghasilkan bukti lab. Semua kasus lab membutuhkan otorisasi Lab Ops ke **lab5g-dev saja**; lab5g-vm tidak boleh diubah.

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

Goal: dual connectivity dengan en-gNB terpisah. Exit ROADMAP/FR-15/D3: X2 SgNB Addition; S1AP E-RAB Modification Indication/Confirm; S1-U berpindah ke gNB dengan TEID baru. **Stack yang diputuskan Netdrive (10 Nov 2026): OAI, eNB + en-gNB terpisah.** Integrated srsENB LTE+NR tetap *achieved-but-not-accepted*. Dependensi: Gate A, plus **dokumen uji T-B1..T-Bn dari Architect (PR terpisah)** sebelum lab dijalankan.

| ID | Kriteria dari PRD / sumber | Kasus uji | Tipe | Perintah / cara verifikasi | Lab Ops | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B-S1 | D3 / FR-15: integrated srsENB LTE+NR = *achieved-but-not-accepted*, bukan exit Gate B. | Review evidence/konfigurasi: `endc-up.sh` atau throughput NR integrated tidak boleh dinyatakan ACCEPTED. | Sintetis / review | Baca `docs/evidence/gate-b-endc-integrated/SUMMARY.md` dan diff PR. Tolak klaim Gate B tanpa X2 + E-RAB Mod + TEID baru ke gNB. | Tidak | P1 | tidak berlaku (sintetis) |
| B-S2 | Sama D3, plus keputusan OAI terpisah. Teks `nr_cell_list` atau Compose OAI kosong di hasil render IaC bukan penerimaan EN-DC. | Jika SHA memuat `infra/`, pastikan artefak ter-render tidak diartikan sebagai SgNB hidup. | Sintetis/CI | Tinjau hasil render + `infra/docs/iac-independent-validation.md`. Tidak ada apply. | Tidak | P2 | tidak berlaku (sintetis) |
| B-L1 | Exit ROADMAP/FR-15/D3: X2 SgNB Addition; S1AP E-RAB Modification Indication/Confirm; S1-U switched ke gNB dengan TEID baru. Stack: OAI eNB + en-gNB terpisah (keputusan Netdrive). | EN-DC Option 3x di lab5g-dev dengan eNB dan en-gNB OAI terpisah. **Menunggu dokumen Architect (T-B1..T-Bn).** | Lab nyata (RAN/UE) | Jangan merancang prosedur informal. Setelah T-B* terbit: ikuti perintah Architect; bukti minimum tetap pcap X2AP, S1AP, GTPv2 Modify Bearer, dan GTP-U ke endpoint gNB (`` `<IP-gNB>` ``) — bukan hanya eNB (`` `<IP-eNB>` ``). | Ya | P1 | belum dijalankan (menunggu dokumen Architect) |
| B-L2 | ROADMAP merujuk T9. Plan-poc T9 masih mendeskripsikan jalur integrated, yang D3 tolak. Prosedur resmi pengganti adalah T-B1..T-Bn (Architect, PR terpisah). | Korelasi bukti EN-DC terpisah menurut T-B*, bukan cell terintegrasi. **Menunggu dokumen Architect.** | Lab nyata (RAN/UE) | Jangan pakai `endc-up.sh` atau T9 integrated sebagai bukti lulus. Hanya LTE-leg/attach = belum selesai. | Ya | P1 | belum dijalankan (menunggu dokumen Architect) |
| B-L3 | Pelengkap kesiapan lab/UE untuk jalur OAI terpisah. Isi langkah resmi ada di T-B1..T-Bn, bukan di draf ini. | Kasus lab pelengkap (misalnya kesiapan UE pada stack OAI yang sudah diputuskan). **Menunggu dokumen Architect;** jangan menambah prosedur sendiri yang bisa bertentangan dengan PR Architect. | Lab nyata | Ikuti T-B* begitu terbit. Draf ini tidak mengunci langkah spike atau rebuild. | Ya | P1 | belum dijalankan (menunggu dokumen Architect) |

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

Kelima skenario ini adalah uji ujung-ke-ujung di lab nyata (RAN/UE). Semuanya butuh Lab Ops. **Status seluruhnya: belum dijalankan.** Capture kontrol mengikuti plan-poc bagian 8 (Gx, GTPv2, PFCP, S1AP, GTP-U), disimpan dengan stempel waktu WIB, tanpa material kunci subscriber dan tanpa identitas mentah (pakai `` `<IMSI-UE-1>` `` dan sejenisnya).

| ID | Skenario | Kriteria / PASS (sumber) | Cara verifikasi ringkas | Kasus terkait | Pri. | Status lab |
| --- | --- | --- | --- | --- | --- | --- |
| E2E-01 | UE attach (LTE) | LTE attach sukses + jalur SGi (ROADMAP Gate A; prosedur verifikasi di `lab/README.md`). | Setelah otorisasi: `lab-up.sh` (UE lalu eNB). Cek S1 ESTAB di MME (port S1AP), log UE attach successful, alamat antarmuka UE, ping `` `<IP-SGi>` ``. | A-L1 | P1 | belum dijalankan |
| E2E-02 | LTE + SgNB EN-DC (OAI eNB + en-gNB terpisah) | X2 SgNB Addition; S1AP E-RAB Modification Indication/Confirm; S1-U ke gNB dengan TEID baru (FR-15/D3/ROADMAP). Bukan `endc-up.sh` integrated cell — itu sudah NOT ACCEPTED. Stack: OAI terpisah per keputusan Netdrive 10 Nov 2026. | **Menunggu T-B1..T-Bn dari Architect (PR terpisah).** Jangan jalankan prosedur informal. Bukti minimum setelah T-B* terbit: pcap S1AP ModInd/Confirm, GTPv2 Modify Bearer, GTP-U TEID baru ke `` `<IP-gNB>` ``. | B-L1, B-L2 | P1 | belum dijalankan (menunggu dokumen Architect) |
| E2E-03 | Bearer per APN | Dua APN ke UPF (plus SGW-U); SDF; PDR/FAR dan pool sesuai; GTP-U TEID berbeda; CCA benar (T1 / exit Gate A). | Attach/reconnect dua APN, traffic 5-tuple, pcap Sx/SGi. Evidence Gate A saat ini menyatakan APN-per-slice belum dikonfigurasi — kasus ini masih terbuka. | A-L2, A-L4 | P1 | belum dijalankan |
| E2E-04 | PCC / Gx RAR | FR-16 + T4–T8: RAR + RAA 2001 dan PFCP Mod accepted + Create/Update/Delete Bearer S5/S11 + E-RAB Setup/Modify/deaktif. Tanpa sesi atau gagal prosedur menghasilkan *no-active-session* / *failed* / *degraded*, bukan *active*. | tcpdump/tshark Gx, PFCP, GTPv2, S1AP sesuai plan-poc bagian 8. Patch PCRF di repo masih draft — jangan klaim live RAR sebelum patch terverifikasi. | D-L1…D-L5 | P1 | belum dijalankan |
| E2E-05 | Aksi dashboard | T10 + FR-16/17: validate/apply/status terhadap core hidup; 403 lintas grup; audit actor+owner; hasil apply mengikuti evidence-chain (bukan badge *active* dari demo). | API mode butuh profil, If-Match, CSRF; UI tidak membuat login. Jalankan aksi di lab, bandingkan audit + pcap. Demo mode (`data_origin` demo) bukan bukti lab. | E-L1, E-L2, E-L3 | P1 | belum dijalankan |

NO-GO (plan-poc bagian 9): slicing APN/UPF GO hanya jika T1 lulus; EN-DC jika prosedur resmi Gate B (T-B* setelah terbit; bukan T9 integrated) lulus; app detection jika T3 lulus; live PCC jika T4/T6 lulus dan T5 dibatasi hasil; self-service jika T10 lulus; Sx URR jika T2 lulus. NO-GO bila hanya basis data inti berubah, hanya RAA 2001, atau hanya UE attach.

## 5. Checklist verifikasi PR Dev pada SHA persis

Pakai checklist ini untuk setiap PR pengembangan. Semua perintah dijalankan pada commit yang sama (catat hasil `git rev-parse HEAD`). Jangan mencampur hasil dari SHA lain. Tidak ada GitHub Actions; lulus/gagal adalah hasil perintah di bawah plus review diff.

1. **Identitas SHA.** Catat SHA penuh, cabang head/base, dan apakah `infra/` ada di pohon itu. Ujung `main` (`d0d4bc4b68a7…`) tidak memuat IaC; ujung `master` (`3af083492de0…`) memuatnya.
2. **Backend** (jika menyentuh `dashboard/backend` atau dependensi). `cd dashboard/backend; python3 -m venv .venv; .venv/bin/pip install -r requirements.lock; .venv/bin/pytest -q`. Baseline dokumen: 19 passed, termasuk apply migrasi `001_init.sql` dan authz objek. Tes HTTP memakai PostgreSQL lokal lalu rollback. Immediate apply tetap *rejected*, `executed=false`, `core_restart=false` selama adapter stock. RAA 2001 saja bukan *active*.
3. **Frontend** (jika menyentuh `dashboard/frontend`). `cd dashboard/frontend; npm ci; npm test; npm run lint; npm run typecheck; npm run build`. Baseline dokumen: 4 tes Vitest lulus; lint/typecheck/build bersih. Cek: mode demo default; hasil apply bukan badge *lifecycle-active*; tidak ada login buatan; klien API hanya memanggil validate/apply jika id, If-Match, dan CSRF sudah ada.
4. **Kontrak eBPF** (jika menyentuh `ebpf/`). `cd ebpf; python3 scripts/check_build.py; python3 -m pytest tests`. Objek boleh terbangun, tetapi loader/attach tidak boleh terjadi di pemeriksaan ini. Exit 2 (toolchain hilang) berarti *untested*, bukan lulus compile. Exporter menolak label IMSI/SNI/hostname/flow; stub wajib `data_origin=stub`.
5. **IaC dry-run** (jika `infra/` ada di SHA itu). Dari direktori `infra/`, hanya set validasi independen di `infra/docs/iac-independent-validation.md`: yamllint; `ansible-playbook` dengan inventory dry-run lokal untuk `site.yml --syntax-check` (dan `teardown.yml`); `ansible-lint --offline`; `python3 scripts/render-compose.py`; `python3 tests/validate_rendered.py`; `python3 tests/validate_compose_schema.py`; `docker-compose config --quiet` untuk core dan RAN; `bash scripts/secret-scan.sh`. Jangan menjalankan `make up/down/verify/render/check`, atau `ansible-playbook --check/--diff`, tanpa otorisasi — dokumen IaC menyatakan check-mode masih bisa menulis atau menyentuh host. Teks `nr_cell_list` ter-render atau Compose OAI kosong bukan penerimaan Gate B.
6. **Hygiene PR.** Tidak ada material kunci subscriber, kata sandi, atau token; placeholder tetap placeholder. Jangan klaim Gate A–F, live RAR, atau klasifikasi eBPF tanpa evidence baru di SHA itu. Prototype `docs/ux/prototype/` bukan aplikasi. Jangan memasukkan IP privat/internal, hostname internal sensitif, atau IMSI/MSISDN mentah ke dalam bukti atau dokumen.
7. **Lab** (hanya jika PR mengklaim hasil lab, dan hanya setelah otorisasi). Ulangi kasus terkait di lab5g-dev pada artefak yang dibangun dari SHA yang sama. lab5g-vm tidak diubah. Stempel bukti: WIB, SHA, serta identifikasi yang sudah disanitasi (`` `<IMSI-UE-1>` ``, APN/EBI/rule/revision). **Untuk draf test plan ini, lab belum dijalankan.**

## 6. Pertanyaan terbuka

Tiga pertanyaan berikut perlu jawaban Architect (atau keputusan produk) sebelum test plan ini dianggap lengkap. Pertanyaan lama tentang “stack Gate B mana yang disetujui” **sudah terjawab** oleh Netdrive (OAI eNB + en-gNB terpisah) dan tidak diulang di sini.

1. **Gate A — apakah T1+T2 masih wajib?** ROADMAP v0.6 masih PLANNED / BUILD, sementara evidence NA bertuliskan VERIFIED/ACCEPTED untuk attach + ping SGi saja, dan secara eksplisit bukan APN-per-slice / SDF+URR / pcap T1–T2. Apakah exit Gate A sudah dianggap selesai, atau T1 dan T2 masih wajib dibuktikan di lab5g-dev?
2. **Gate B — kapan dan di PR mana Architect merilis T-B1..T-Bn?** Stack sudah diputuskan (OAI, eNB + en-gNB terpisah). Kasus B-L1..B-L3 dan E2E-02 menunggu dokumen prosedur resmi itu. Plan-poc T9 masih mendeskripsikan srsENB integrated, yang D3 tolak, jadi tidak dipakai sebagai prosedur lab.
3. **Di mana teks lengkap US/FR yang berlaku?** `PRD-v0.6.md` menulis US-01…US-09 dan FR-01…FR-14, FR-16, FR-17 “sama v0.5”, tetapi `PRD-v0.5.md` tidak ada di repo dan `docs/SOURCE-OF-TRUTH.md` menyatakan v0.5 tidak pernah menjadi body kanonik. FR-15/16/17 hanya diringkas. QA tidak memakai snapshot v0.4 sebagai pengganti. Mohon ekspor teks lengkap US/FR yang berlaku.

Draf disusun 10 Nov 2026, 15:13 WIB (Asia/Bangkok, UTC+7) oleh Open5G QA. Uji lab belum dijalankan. Revisi berikutnya menunggu jawaban di atas, dokumen T-B* dari Architect, dan/atau PR Dev baru pada SHA persis.
