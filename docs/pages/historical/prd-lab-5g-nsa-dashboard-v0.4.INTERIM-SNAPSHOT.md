# PRD Lab 5G NSA — Dashboard Slicing Core (v0.4)

> **WIP / interim export from Cursor Canvas TSX source (string-literal digest).**
> Exported: 2026-11-06 20:22:08 +0700 · timezone: Asia/Bangkok (UTC+7)
> Canvas URL: https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/a248bcce-b7e8-40aa-ad8e-839a25cab7a8
> canvas_id: `a248bcce-b7e8-40aa-ad8e-839a25cab7a8`
> **Method:** regex extraction of JSX text / string props — not a browser-rendered DOM dump; Status/Diagram/interactive widgets partially flattened.
> **Not** a product approval, API contract, or new decision. Phrases below are as written in the Canvas source.
> **INTERIM SNAPSHOT ONLY.** Canonical Product Manager pack (PRD v0.4 + roadmap + decision log + risk register) is **pending** under `docs/prd/` — do **not** treat this file as the canonical PRD, and do **not** invent separate roadmap/log/register from this export.
> Included only so cloud WIP has a readable digest of the Soft Arch / Canvas Page until PM lands the canonical pack.
> **SUPERSEDED / PENDING v0.5:** Canonical Product Manager pack is being refreshed to PRD **v0.5**. This file remains a **v0.4 interim Canvas snapshot** for WIP only — not canonical; no invented roadmap / decision log / risk register. Do not re-export while PM update is in flight.

**Summary (from Page):** PRD v0.4: selaras plan PoC final Network Architect (plan-poc-slicing-core.md, lab5g-dev only). D1 immediate Gx RAR + D2 instructor-in-group. R-03 rekomendasi = PCRF admin-trigger patch. FR-16: QCI/ARP-on-existing + APN-AMBR = stock unsupported (reject sampai patch). Gates A–F.

**Page `sources` prop:**
- https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/464ec2f8-0481-469e-82d4-9c8aca720dcb
- https://open5gs.org/open5gs/docs/guide/01-quickstart/
- https://www.etsi.org/deliver/etsi_TS/129200_129299/129212/19.00.00_60/ts_129212v190000p.pdf
- https://www.etsi.org/deliver/etsi_TS/129200_129299/129281/18.04.00_60/ts_129281v180400p.pdf

---

> **Status dokumen v0.4:** Baseline v0.2 tetap berlaku; D1/D2 dikunci di v0.3. v0.4 menyelaraskan lab source ke plan PoC final Network Architect (`/workspace/plan-poc-slicing-core.md`, lab5g-dev only) — plan tidak lagi pending. Temuan RAR/Gx usage = code-level hingga uji lab5g-dev lulus. Perubahan berikutnya = v0.5+.

## Konteks lab yang dikonfirmasi {#konteks}

- **Host:** agen (10.17.7.160) â CentOS 7, KVM/Docker; sumber: Network Architect, 6 Nov 2026
- **Lab live RUNNING:** lab5g-vm â Open5GS 2.8.0 EPC CUPS + srsRAN 4G ZMQ. READ-ONLY: jangan diubah (Hidayat via PM, 6 Nov 2026).
- **Lab dev (satu-satunya target tulis):** lab5g-dev (172.22.20.21) â semua pengembangan EN-DC + slicing PoC hanya di sini. BUILD IN PROGRESS; EN-DC NA belum verified.
- **EN-DC (option 3x):** WAJIB per Hidayat (via PM, 6 Nov 2026). Anchored on EPC (MME/SGW/PGW). Implementasi NA di lab5g-dev: belum diverifikasi.
- **Belum ada / stretch:** 5GC AMF/NR dan NSA Option 7/4 = later/stretch. gNB/X2 EN-DC stack OSS terverifikasi: belum (Asumsi risiko).
- **Stack dashboard:** Next.js + FastAPI + PostgreSQL â Software Architect Page + approval Hidayat
- **Repo:** D:\open5g â origin https://github.com/dayat81/open5g (kosong, siap coding)

Sumber primer lab: Network Architect plan PoC final `/workspace/plan-poc-slicing-core.md` (6 Nov 2026, lab5g-dev only). Desain dashboard: Page Software Architect. Kajian pendukung: `/workspace/epc-cups-app-detection-feasibility.md`.


## 1. Masalah & tujuan {#masalah}

Lab 5G virtual Hidayat dipakai banyak pengguna untuk eksperimen slicing per-aplikasi. Saat ini konfigurasi policy/subscriber tersebar (mongo/WebUI Open5GS) tanpa isolasi multi-user yang aman, dan bukti perilaku core belum tersaji dalam satu dashboard yang jujur terhadap provenance datanya.

Tujuan produk: dashboard multi-user agar student (dan instructor dalam grupnya) dapat mengatur profil PCRF/subscriber untuk IMSI yang diizinkan, menerapkan perubahan segera via Gx RAR seperti standar telco, dan melihat observability sisi core di jalur S1-U / SGW-U / SMF(PGW-C) / UPF(PGW-U) / PCRF — tanpa mengklaim slicing RAN/UE end-to-end.

> **Baseline teknis PoC:** PoC di jalur Open5GS EPC CUPS di lab5g-dev only. EN-DC option 3x wajib. Emulasi slice APN+UPF dedicated + PCC per-app — PLANNED. eBPF — PLANNED. Apply profil = immediate via PCRF Gx RAR (D1); 5GC/Option 7/4 = stretch.


## 2. Persona {#persona}

| Persona | Kebutuhan utama | Batasan |
| --- | --- | --- |
| Admin | Assign IMSI; kelola grup/katalog/kuota; restart shared core; audit global; adapter lab | Satu-satunya role yang boleh menyentuh shared core & secret auth (Ki/OPc) |
| Instructor | Kelola eksperimen grup; assign IMSI ke student di grupnya; edit DAN apply profil IMSI student dalam grup sendiri; pantau observability cohort | Tidak mengubah shared core / Ki/OPc; tidak boleh menyentuh IMSI di luar grupnya (D2) |
| Student | Edit & apply profil PCRF IMSI sendiri; lihat intended vs observed; usage ber-provenance | Hanya IMSI yang di-assign kepadanya; tidak akses mongo/WebUI mentah; tidak restart core |


## 3. Scope & non-goals {#scope}


### In scope (MVP)

- Dashboard web multi-user (RBAC: admin / instructor / student) + model grup (instructorâgrup, studentâgrup)
- Self-service editor profil PCRF/subscriber untuk IMSI assigned
- Immediate apply via PCRF-initiated Gx RAR (D1); re-attach hanya fallback (APN/default bearer) dengan konfirmasi user
- Instructor edit+apply IMSI student dalam grup sendiri, diaudit actor+owner (D2)
- Observability core ber-provenance; isolasi + audit immutable
- PoC EPC CUPS Open5GS 2.8.0 + EN-DC option 3x hanya di lab5g-dev
- Deteksi app eBPF (IP / DNS / TLS SNI) terpisah dari enforcement PCC


### Non-goals

- Slicing E2E RAN/UE (URSP/S-NSSAI di perangkat)
- NSA Option 7/4 via 5GC sebagai prasyarat MVP (stretch)
- Dekripsi TLS/QUIC; klaim deteksi saat ECH/DoH tanpa bukti
- Mahasiswa menulis langsung ke mongo / WebUI Open5GS bersama
- Edit Ki/OPc lewat GUI student/instructor
- Write ke lab5g-vm (live) â development hanya di lab5g-dev
- Mengklaim Gx Usage-Monitoring stock sebelum diverifikasi/dipatch
- Restart core otomatis sebagai jalur apply


## 4. User stories & acceptance criteria {#stories}

| ID | Story | Acceptance (Given / When / Then) |
| --- | --- | --- |
| US-01 | Sebagai student, saya ingin mengedit profil PCRF IMSI saya | Given IMSI di-assign ke saya; When saya ubah field dan Save draft; Then draft tersimpan ber-versi (saved), belum aktif di jaringan, dan saya tidak bisa menyentuh IMSI orang lain |
| US-02 | Sebagai student, saya ingin Apply profil segera ke sesi aktif via Gx RAR seperti standar telco | Given draft tervalidasi dan RAR trigger tersedia; When saya Apply; Then sistem push profil, PCRF kirim Gx RAR, status per IMSI bergerak savedâpushedâactive\|partial\|timeout\|failed dengan freshness; Active hanya jika profile_version+IMSI+session+PCC rule IDs berkorelasi dengan state PGW-C/PFCP dan bearer yang sesuai â RAA 2001 saja BUKAN bukti active |
| US-03 | Sebagai student, saya ingin melihat apakah policy benar-benar terpasang dan trafik sesuai | Given sesi aktif; When saya buka observability; Then UI memisahkan Detected / Decided / Installed / Observed dengan evidence, waktu, dan sumber |
| US-04 | Sebagai instructor, saya ingin assign IMSI ke student di grup saya dan memantau cohort | Given saya instructor grup G; When saya assign IMSI ke student di G; Then student hanya melihat IMSI itu; audit mencatat assignment |
| US-05 | Sebagai admin, saya ingin menetapkan katalog/kuota | Given katalog QCI/MBR/GBR/APN; When submit di luar kuota; Then validasi menolak dan audit mencatat |
| US-06 | Sebagai student, saya ingin usage per-app ber-provenance | Given counter tersedia; When saya lihat KPI; Then setiap angka bertanda eBPF\|PFCP\|Gx\|unsupported; tidak diklaim Gx Usage-Monitoring jika belum didukung |
| US-07 | Sebagai student, jika RAR tidak bisa menerapkan perubahan (mis. ganti APN/default bearer), saya ingin fallback re-attach yang eksplisit | Given operasi = APN/default-bearer change ATAU RAR trigger unsupported di core; When saya Apply; Then UI menolak immediate apply dengan alasan jelas; fallback re-attach hanya setelah konfirmasi user â tidak pernah restart core otomatis |
| US-08 | Sebagai instructor, saya ingin edit DAN apply profil IMSI student dalam grup saya | Given student S di grup G dan saya instructor G; When saya edit+apply profil IMSI S; Then perubahan diterapkan per FR-16 dan audit mencatat actor=instructor, owner=student S |
| US-09 | Sebagai instructor, saya tidak boleh menyentuh IMSI di luar grup saya | Given IMSI milik student di grup lain; When saya GET/PUT/Apply; Then API mengembalikan 403 dan percobaan diaudit |


## 5. Functional requirements {#fr}

| ID | Requirement | Status lab | Sumber |
| --- | --- | --- | --- |
| FR-01 | Auth + RBAC (admin / instructor / student); otorisasi diulang per request. Model keanggotaan: instructorâgrup dan studentâgrup | PLANNED (dashboard) | Software Architect + D2 |
| FR-02 | Ownership IMSI server-side. Student: hanya IMSI assigned. Instructor: edit+apply IMSI student dalam grup sendiri saja. Larangan mengetik IMSI bebas | PLANNED | D2 â Hidayat via PM, 6 Nov 2026 19:41 WIB |
| FR-03 | Editor profil: APN/slice logis, QCI/ARP, AMBR/MBR/GBR, app-rule {IP\|hostname\|SNI}, usage threshold | PLANNED; schema mongo supported untuk field IP/QoS | NA + feasibility v2.8.0 |
| FR-04 | Hostname/SNI tidak diklaim sebagai IPFilterRule Gx native; eBPFâSDF bridge/patch = requires-code | FACT: IPFilterRule = IP/port only | feasibility Open5GS v2.8.0 |
| FR-05 | State per IMSI: saved, pushed, active, partial, timeout, failed + freshness timestamp; desired/applied/observed version terpisah. RAA 2001 saja â  active | PLANNED | Software Architect refinements, 6 Nov 2026 + D1 |
| FR-06 | Apply target = immediate via PCRF-initiated Gx RAR (D1). Save draft â  live. Re-attach hanya fallback (APN/default bearer atau RAR unsupported) dengan konfirmasi user; tidak ada restart core otomatis | Produk decided; mekanisme RAR di core = R-03 delivery risk | D1 â Hidayat via PM, 6 Nov 2026 19:40 WIB |
| FR-07 | Observability: intended vs observed; PCC decision vs install; TEID; throughput per antarmuka berlabel benar (S1-U/S5-U/SGi) | PLANNED; Prometheus/Grafana UNKNOWN | Software Architect + NA |
| FR-08 | Provenance usage wajib: Gx / PFCP(Sx) / eBPF / capture / unsupported | Gx Usage-Monitoring runtime unsupported stock; URRâGy hari ini | feasibility v2.8.0 |
| FR-09 | eBPF collector: IP LPM + DNS snoop + TLS SNI; privilege hanya di collector | PLANNED; kernel/BTF lab5g-dev UNKNOWN | NA + feasibility |
| FR-10 | Emulasi slice: 1 APN per slice, UPF dedicated per APN, pool IP per APN | PLANNED; hari ini single default APN | Network Architect, 6 Nov 2026 |
| FR-11 | Audit immutable: assignment, save, apply, restore. Instructor change wajib actor=instructor + owner=student | PLANNED | Software Architect + D2 |
| FR-12 | Admin: katalog/template/kuota; restart shared core dengan blast-radius warning | PLANNED | Software Architect Page |
| FR-13 | Label EPC vs 5GC tidak dicampur; UI tidak mengklaim NSA+5GC E2E kecuali terverifikasi | FACT: lab = EPC CUPS hari ini | Network Architect, 6 Nov 2026 |
| FR-14 | Adapter lab least-privilege; kapabilitas unknown ditampilkan jujur di UI | PLANNED | Software Architect Page |
| FR-15 | EN-DC NSA option 3x hanya di lab5g-dev; core EPC; UI boleh tampilkan status EN-DC/S1/X2 bila adapter ada | PLANNED â NA implementing; lab5g-vm tidak disentuh | Hidayat via PM, 6 Nov 2026 |
| FR-16 | Immediate apply via Gx RAR per tipe operasi (bukti active = PFCP/GTP/S1AP, BUKAN RAA 2001 saja â RAA dikirim sebelum aktivasi). (a) Add ruleânew bearer: RAR + RAA 2001 + PCC install PGW-C + Create Bearer + E-RAB Setup + PFCP Session Mod accepted. (b) Modify MBR/GBR on existing bearer: Update Bearer / E-RAB Modify + PFCP Mod. (c) Modify QCI/ARP on existing bearer: STOCK UNSUPPORTED (Open5GS hanya bandingkan MBR/GBR) â requires patch; UI reject immediate apply dengan alasan itu sampai patch; fallback remove+install atau reconnect. (d) Remove rule: Delete Bearer bila kosong + PFCP. (e) APN-AMBR via RAR: STOCK UNSUPPORTED (top-level QoS-Information tidak diterima) â requires patch; UI reject immediate apply sampai patch; fallback reconnect. (f) APN/default-bearer QCI/ARP/static IP: re-attach/reconnect fallback, user-confirmed. (g) Jika RAR trigger belum ada di core: UI reject + alasan; jangan auto-restart core | PLANNED produk; RAR trigger + QCI/ARP/APN-AMBR gaps = code-level FACT, untested E2E (plan NA) | D1 + SA + plan-poc-slicing-core.md (NA, 6 Nov 2026) |
| FR-17 | Instructor boleh edit DAN apply profil IMSI student dalam grup sendiri saja. Uji negatif: aksi ke IMSI grup lain â 403 + audit. Student tidak boleh menyentuh IMSI yang tidak di-assign kepadanya | PLANNED (dashboard) | D2 â Hidayat "bole" via PM, 6 Nov 2026 19:41 WIB |


## 6. Non-functional requirements {#nfr}


### Keamanan

- Browser tidak memegang Docker socket / root SSH / kredensial mongo
- Backend dashboard = satu-satunya writer ke subscriber DB untuk peran non-admin
- Ki/OPc tidak diekspos ke student/instructor UI
- Session auth + web hardening (Asumsi: praktik FastAPI/Next.js)


### Isolasi multi-user

- Student: CRUD hanya IMSI assigned kepadanya
- Instructor: CRUD+apply hanya IMSI student dalam grup yang sama; lintas grup = 403
- Uji negatif wajib: student AâB; instructor grup Gâgrup H; semua ditolak + diaudit
- Kuota agregat mencegah satu user menghabiskan shared UPF/core
- Perubahan shared NF = admin-only


### Audit log

- Setiap save/apply/restore/assignment/403 menghasilkan entri immutable
- Instructor change: wajib field actor (instructor) dan owner (student)
- Retention & export: Asumsi â keputusan admin lab


### Performa & ketersediaan

- Dashboard metadata di PostgreSQL terpisah dari mongo Open5GS
- Metrik: jangan taruh IMSI/SNI mentah sebagai label ber-kardinalitas tinggi
- Availability lab: best-effort (Asumsi)
- Batas UPF dedicated / kapasitas lab5g-dev: UNKNOWN


### Batas lab (lab5g-dev only)

- NFR-LAB-01: Tidak ada write/mutasi/restart/config push ke lab5g-vm. Baca-saja diizinkan.
- NFR-LAB-02: Semua development EN-DC, slicing PoC, eBPF, uji adapter, dan uji RAR hanya di lab5g-dev.
- NFR-LAB-03: Milestone/requirement tidak boleh mengimplikasikan perubahan lab5g-vm.


## 7. Success metrics {#metrics}

| Metrik | Target MVP | Cara ukur |
| --- | --- | --- |
| Isolasi ownership + grup | 0 akses silang IMSI / lintas grup pada uji negatif; 403 diaudit | Authz tests US-09 / FR-17 |
| Immediate apply fidelity | Active hanya dengan korelasi profile_version+session+PCC+PFCP/bearer; 0 klaim active dari RAA 2001 saja | FR-16 acceptance / pcap lab5g-dev |
| Kejujuran provenance | 100% angka usage bertanda sumber | Review UI + C4 |
| Pemisahan state | Detected/Decided/Installed/Observed tidak digabung | Review UX + C3 |
| Klasifikasi app terkontrol | Dua SNI beda di VIP sama â app_id beda (saat eBPF siap) | T4 |
| SDF IP stock path | PCC IP flow â dedicated bearer/QER terpasang | T1âT3 |


## 8. Dependencies & risks {#risks}

| ID | Risk / dependency | Status | Mitigasi produk |
| --- | --- | --- | --- |
| R-01 | Native Gx Usage-Monitoring memerlukan patch: stock URR Session Report â Gy (bukan Gx); AVP Usage-Monitoring / CCR-U USAGE_REPORT runtime absent (dictionary saja). Tetap risiko sampai uji lab5g-dev + patch disetujui (plan fase F) | FACT v2.8.0 (plan NA Â§3, Â§5) | MVP: eBPF/out-of-band atau Sx URR berlabel jujur; jangan klaim Gx per-app usage dari eBPF saja |
| R-02 | URR per-PDR, bukan per-app, kecuali eBPFâPDR/SDF | FACT | MVP usage = eBPF counters; bridge SDF later |
| R-03 | DELIVERY RISK: tidak ada mongoâRAR di PCRF stock (pcrf_gx_send_rar hanya dari Rx). REKOMENDASI NA (plan final): small PCRF admin-trigger patch (dashboard â authenticated trigger IMSI+APN+revision â Charging-Rule-Install/Remove diff â Gx RAR). Rx AF shim workable untuk spike tetapi terbatas (UE lookup Framed-IP; QCI hanya 1/2/5; ARP dari template DB). External injector = uji darurat saja. SMF FACT menangani RAR Install/Remove â PFCP Mod + Create/Update/Delete Bearer. Gaps stock: QCI/ARP change on existing bearer tidak dibandingkan (hanya MBR/GBR); APN-AMBR via RAR tidak ditangani. Status: code-level vs v2.8.0, untested sampai pcap T4âT8 lab5g-dev | FACT + PROPOSAL (plan-poc-slicing-core.md Â§4) | Produk tetap D1/FR-16; UI reject operasi stock-unsupported; evidence-chain active; jangan auto-restart core |
| R-04 | Hostname/SNI bukan IPFilterRule native | FACT | eBPF + optional SDF bridge |
| R-05 | ECH/QUIC/DoH mengalahkan SNI/DNS snoop | Known limit | Fail-open; lab hostname/IP terkontrol |
| R-06 | Multi-APN + UPF dedicated belum dijalankan; srsUE multi-PDN UNKNOWN | PLANNED / UNKNOWN | Gate PoC di lab5g-dev |
| R-07 | Resource limit / agen /home 80% full | RUNNING constraint | Kuota admin; kerja di lab5g-dev |
| R-08 | Kernel/BTF lab5g-dev UNKNOWN; UE attach belum verified | UNKNOWN / BUILD | Geser eBPF sampai Gate 0 hijau |
| R-09 | 5GC / Option 7/4 tidak tersedia di OSS terverifikasi | FACT / stretch | MVP EPC CUPS + option 3x |
| R-10 | SGi egress XL UNKNOWN | UNKNOWN | Test server internal dulu |
| R-11 | Prometheus/Grafana belum ada | UNKNOWN | docker logs + API metrics dulu |
| R-12 | EN-DC wajib tapi stack gNB/EN-DC OSS belum terverifikasi di lab | Asumsi / PLANNED | Milestone M2 terpisah; UI jangan klaim EN-DC sebelum bukti |


## 9. Milestones {#milestones}

> **Gates selaras plan NA (fase A–F):** Urutan dari `plan-poc-slicing-core.md` §9. Semua hanya di lab5g-dev. Tanggal fase = Asumsi kecuali M0. EN-DC (fase B) in progress, results pending.

1. **M0 â PRD & desain** — Exit: baseline v0.2 + D1/D2 (v0.3) + plan NA final tercermin (v0.4). Tanggal: sekarang.
2. **Gate A â baseline LTE + multi-APN/SDF/URR** — Exit: LTE attach; dua APNâUPF(+SGW-U); SDF+URR; pcap T1âT2. Dependensi: lab5g-dev. Tanggal: Asumsi. (= ex-M1 + multi-APN awal)
3. **Gate B â EN-DC Option 3x** — Exit: T9 lulus (SCG/NR, S1AP ModInd/Confirm, TEID baru) sebelum klaim EN-DC / dedicated QoS EN-DC. Status NA: in progress, results pending. Tanggal: Asumsi.
4. **Gate C â eBPF app detection** — Exit: IP/DNS/SNI + counters; T3; BTF verified. Tanggal: Asumsi.
5. **Gate D â live RAR (PCRF admin-trigger)** — Exit: patch admin-trigger (R-03 rekomendasi); T4âT8; FR-16 evidence-chain; QCI/ARP-on-existing & APN-AMBR ditolak atau patched. Tanggal: Asumsi.
6. **Gate E â self-service dashboard** — Exit: API/RBAC/grup/audit/status; FR-16/17; T10 isolasi. Boleh paralel UI skeleton sejak M0. Tanggal: Asumsi.
7. **Gate F â usage lanjut** — Exit: SDF bridge; native Gx usage hanya bila patch R-01 disetujui + terlihat di pcap. Bukan keberhasilan PoC awal. Tanggal: Asumsi.
8. **Stretch â 5GC / Option 7/4** — Bukan komitmen MVP. Tanggal: Asumsi.


## 10. Prioritized backlog {#backlog}

| Priority | Item | Horizon | Catatan |
| --- | --- | --- | --- |
| P0 | Auth, RBAC, grup membership, IMSI assignment, audit (actor+owner) | MVP | FR-01/02/11/17 |
| P0 | Profile editor + validasi + immediate apply UX (Gx RAR) + state machine FR-16 | MVP | Target = immediate apply; re-attach = fallback saja |
| P0 | Observability 4-lapisan + provenance usage | MVP | Tanpa klaim palsu |
| P0 | Adapter baca sesi/PCC/TEID/PFCP untuk bukti active | MVP | Korelasi active â  RAA 2001 saja |
| P1 | PCRF admin-trigger patch (R-03 rekomendasi NA) + pcap T4âT8 | MVP lab | Gate D; Rx shim hanya spike |
| P1 | Stock SDF IP PCC path end-to-end di lab5g-dev | MVP lab | T1âT3 |
| P1 | eBPF TC classifier + counter export | MVP lab | Tergantung kernel/BTF |
| P1 | EN-DC NSA option 3x di lab5g-dev | MVP lab | Wajib; NA implementing, belum verified |
| P2 | eBPFâSDF bridge | Later | requires-code agent |
| P2 | Multi-APN + dedicated UPF per slice | Later | PLANNED NA |
| P3 | Native Gx Usage-Monitoring patch (URRâGx CCR-U) | Later / Gate F | R-01; stock feeds Gy |
| P3 | Prometheus/Grafana | Later | UNKNOWN di lab |
| P3 | 5GC AMF / Option 7/4 | Stretch | Bukan option 3x |


## 11. Open questions {#oq}

1. Kapan PCRF admin-trigger patch (R-03 rekomendasi) diimplementasikan dan pcap T4âT8 lab5g-dev lulus? (Plan final sudah ada; mekanisme masih untested.)
2. Angka kuota katalog (max APN/slice per user, max GBR agregat, max PCC rules) â design choice pending.
3. lab5g-dev: uname/BTF, kapan UE attach hijau, berapa UPF paralel yang muat?
4. srsUE multi-PDN (satu UE banyak APN) â didukung atau eksperimen multi-UE per slice?
5. Apakah egress SGi ke internet diizinkan kebijakan XL, atau cukup test server internal?
6. Retention audit & siapa yang boleh export â keputusan admin lab?
7. Target kapan klaim UI boleh menyebut 'slice' vs hanya 'APN/DNN segmentasi'?
8. Asumsi Open5GS tetap 2.8.0 â apakah upgrade versi masuk scope?
9. RAN stack mana untuk EN-DC option 3x di lab5g-dev (srsRAN Project gNB + srsRAN 4G eNB X2, Amarisoft, lain)?


## 12. Decisions log {#decisions}

| ID | Keputusan | Sumber | Implikasi |
| --- | --- | --- | --- |
| D0 | PRD v0.2 Disetujui sebagai baseline | Hidayat "prd approved" via PM, 6 Nov 2026 19:40 WIB | Perubahan lewat versi baru |
| D1 | Profile apply segera via PCRF-initiated Gx RAR (seperti standar telco). Re-attach hanya fallback (APN/default bearer / RAR unsupported), user-confirmed | Hidayat "rar, seperti standart telco" via PM, 6 Nov 2026 19:40 WIB; refinement SA 6 Nov 2026 | FR-16; US-02/US-07; M4 exit; R-03 = delivery risk bukan keputusan produk |
| D2 | Instructor boleh edit DAN apply IMSI student dalam grup sendiri saja; audit actor+owner; lintas grup = 403 | Hidayat "bole" via PM, 6 Nov 2026 19:41 WIB | FR-17; US-08/US-09; FR-01/02/11; NFR isolasi/audit |


## 13. Status / changelog {#changelog}

- **Versi:** v0.4
- **Tanggal:** 6 Nov 2026 (Asia/Bangkok, UTC+7)
- **Status:** ( v0.4 — plan NA final aligned — baseline v0.2 + D1/D2 (v0.3)
- **Keputusan:** D0/D1/D2 tetap. Lab source primer = plan-poc-slicing-core.md (tidak lagi pending). R-03 rekomendasi = PCRF admin-trigger patch (untested). QCI/ARP-on-existing & APN-AMBR stock unsupported hingga patch.

| Versi | Perubahan |
| --- | --- |
| v0.4 | Selaras plan PoC final NA (`plan-poc-slicing-core.md`): plan tidak lagi pending; gates AâF; R-03 rekomendasi = PCRF admin-trigger patch (Rx shim terbatas; injector darurat); FR-16: QCI/ARP-on-existing + APN-AMBR = stock unsupported / UI reject sampai patch; RAA sebelum aktivasi â bukti PFCP/GTP/S1AP; R-01 Gx usage butuh patch (URRâGy). Semua tetap risk sampai uji lab5g-dev. |
| v0.3 | D1+D2 dikunci: FR-16 immediate apply via Gx RAR; FR-17 instructor dalam grup; R-03 delivery risk; Decisions log. |
| v0.2 | EN-DC option 3x; lab5g-dev-only; Disetujui sebagai baseline (Hidayat via PM, 6 Nov 2026 19:40 WIB). |
| v0.1 | Draf pertama PRD. Baseline EPC CUPS; self-service + observability MVP. |

- [x] D1 immediate apply via Gx RAR dikunci
- [x] D2 instructor edit+apply dalam grup dikunci
- [x] Plan PoC final NA tersedia
- [ ] Implementasi PCRF admin-trigger + pcap T4âT8 lab5g-dev
- [ ] Pilih / verifikasi RAN stack EN-DC
- [ ] Gate 0 lab5g-dev hijau â tanpa menyentuh lab5g-vm
- [ ] Mulai coding dashboard di dayat81/open5g
