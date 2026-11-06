# Memo kelayakan dashboard lab 5G (parsial)

> **WIP / interim export from Cursor Canvas TSX source (string-literal digest).**
> Exported: 2026-11-06 20:22:08 +0700 · timezone: Asia/Bangkok (UTC+7)
> Canvas URL: https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/464ec2f8-0481-469e-82d4-9c8aca720dcb
> canvas_id: `464ec2f8-0481-469e-82d4-9c8aca720dcb`
> **Method:** regex extraction of JSX text / string props — not a browser-rendered DOM dump; Status/Diagram/interactive widgets partially flattened.
> **Not** a product approval, API contract, or new decision. Phrases below are as written in the Canvas source.
> Soft Arch feasibility memo (design/architecture narrative). Not the PRD. Not API final.

**Summary (from Page):** Verifikasi sisi CORE + self-service editor profil PCRF untuk IMSI milik sendiri (usulan, belum disetujui). Observability tetap wajib. Bukan slicing E2E RAN/UE. Tidak ada kode.

**Page `sources` prop:**
- https://open5gs.org/open5gs/docs/guide/01-quickstart/
- https://open5gs.org/open5gs/docs/tutorial/04-metrics-prometheus/
- https://www.etsi.org/deliver/etsi_TS/129200_129299/129281/18.04.00_60/ts_129281v180400p.pdf
- https://etsi.org/deliver/etsi_ts/129200_129299/129212/19.00.00_60/ts_129212v190000p.pdf
- https://www.etsi.org/deliver/etsi_TS/123500_123599/123501/18.11.00_60/ts_123501v181100p.pdf
- https://www.etsi.org/deliver/etsi_TS/123500_123599/123503/19.08.00_60/ts_123503v190800p.pdf
- https://developer.android.com/studio/run/emulator-networking-address
- https://docs.srsran.com/projects/4g/en/latest/app_notes/source/zeromq/source/index.html

---

> **Lingkup: core + self-service profil (usulan):** Kebutuhan baru: setiap user bebas mengatur profil PCRF untuk IMSI miliknya agar mendapat slicing/policy yang diinginkan. MVP = observability + editor self-service terikat kepemilikan server-side — bukan baca-saja murni, dan belum disetujui untuk kode. URSP/Opt 7/4 bukan prasyarat. Segmentasi core ≠ bukti NSA+5GC E2E.

## Status dan batasan klaim {#status}

- **Tujuan dashboard (klarifikasi):** Verifikasi sisi core (S1-U, UPF, SMF, PCRF) + user mengedit profil PCRF IMSI sendiri â bukan E2E RAN/UE slicing
- **Lab terverifikasi (Net Arch):** Open5GS 2.8 EPC CUPS + srsRAN 4G eNB/srsUE; dukungan tiap adapter dashboard = unknown hingga divalidasi
- **Kandidat Net Arch (proposal PoC):** Emulasi berbasis APN + UPF per APN (opsional SGW-U); PCC per-app / dedicated bearer via PCRF â belum PoC
- **Bukan prasyarat eksperimen core:** URSP native Android/UE; Option 7/4 NSA+5GC E2E

> **Jangan overclaim:** Segmentasi APN/DNN, UPF terpisah, atau PCC di core membuktikan perilaku gateway/policy di lab — bukan bahwa perangkat melakukan seleksi slice 3GPP (S-NSSAI/URSP) atau bahwa jalur adalah NSA+5GC end-to-end. Label UI memisahkan: kelas eksperimen logis, segmentasi APN/DNN, QoS/bearer, dan S-NSSAI standar (hanya jika benar-benar ada di 5GC).


## Alur eksperimen sisi core [A] {#alur}

1. **Definisi eksperimen** — Kelas logis + pemilik user/grup + kuota
2. **Klasifikasi aplikasi** — Aturan IP / hostname / SNI â app_id (bukti + confidence)
3. **APN / DNN** — Segmentasi yang dipilih eksperimen
4. **SMF / PGW-C** — Kontrol sesi; minta kebijakan PCRF; laporkan usage jika adapter mendukung
5. **UPF / PGW-U (+ SGW-U bila ada)** — User plane; deteksi/counter di titik tangkap yang benar
6. **Observed** — Sesi/bearer, PCC terpasang, TEID, throughput per antarmuka

Empat keadaan terpisah (jangan digabung di UI): (1) detection — app dikenali dari bukti; (2) policy decision — PCRF memutuskan; (3) installed enforcement — rule/bearer terpasang di PCEF/UP; (4) observed traffic — paket/counter benar-benar terlihat.


## EPC vs 5GC — label antarmuka [F] {#iface}

| Konsep | EPC (tipikal lab sekarang) | 5GC (hanya jika SA/5GC nyata) | Larangan label |
| --- | --- | --- | --- |
| Akses â gateway UP | S1-U: eNB â SGW-U (GTP-U) | N3: gNB â UPF (GTP-U) | Jangan sebut counter UPF sebagai S1-U kecuali titik tangkap = S1-U |
| Antar-gateway UP | S5/S8-U: SGW-U â PGW-U | N9: UPF â UPF (jika ada) | Jangan samakan S5-U dengan N3 |
| Kontrol UP | Sxa/Sxb / PFCP ke SGW-U dan PGW-U | N4: SMF â UPF (PFCP) | Adapter wajib menyatakan antarmuka yang dibaca |
| Policy | PCRF â PCEF (Gx Diameter); PCRF = NF EPC | PCF (SBI) â bukan PCRF | Jangan panggil PCRF sebagai NF 5GC native |
| Ke DN / internet | SGi di PGW-U | N6 di UPF | Pakai label SGi kecuali jalur benar-benar 5GC N6 |
| SMF / UPF dual-role | Open5GS: SMF dapat berperan PGW-C; UPF sebagai PGW-U (quickstart) | SMF/UPF 5GC | Klaim peran PGW-C/U hanya jika konfigurasi lab diverifikasi |

[F] GTP-U/TEID: TS 29.281. [F] Gx PCRF→PCEF install/aktivasi PCC: TS 29.212. [F] Open5GS quickstart memisahkan 4G/5G NSA Core (PCRF, SGW-U, PGW-C/SMF, PGW-U/UPF) dari 5G SA Core (AMF/SMF/UPF/PCF, tanpa PCRF).


## Usulan arsitektur dashboard [A] {#arsitektur}

- **Frontend:** Next.js â view bukti, RBAC UI
- **Backend:** FastAPI â sesi auth, RBAC, orkestrasi baca, audit
- **Metadata:** PostgreSQL â user/grup, eksperimen, aturan klasifikasi, audit
- **Adapter lab:** ( Least-privilege per instance; tiap kapabilitas unknown / perlu validasi — jangan klaim dukungan stock Open5GS )

- Browser tidak memegang Docker socket / root SSH
- Restart / ubah shared core: admin-only + tampilkan blast radius
- Mahasiswa hanya data eksperimen miliknya


## View bukti yang diusulkan [A] {#views}

1. Intended vs observed mapping
  - Eksperimen â app_id â APN/DNN â (opsional) kelas slice logis
  - Observed: sesi/bearer aktual, APN terpakai, UPF/SGW yang melayani
2. PCC policy vs install status
  - Keputusan PCRF (rule name, SDF, gate, QCI)
  - Status terpasang di PCEF/SMF binding
  - Terpisah dari trafik sudah sesuai
3. Lifecycle bearer / sesi
  - Create / modify / release timestamps; penyebab bila diketahui
4. Korelasi TEID dan tunnel endpoints
  - Pasangan TEID + IP endpoint per antarmuka (S1-U, S5/S8-U, atau N3 bila 5GC)
  - Sumber: signaling GTPv2-C / PFCP â bukan tebakan
5. Throughput GTP-U per antarmuka
  - Titik tangkap eksplisit; jangan campur S1-U dengan SGi
6. KPI per UPF / eksperimen / app
  - Wajib: origin data, waktu, capture point
  - Unknown jika adapter tidak mendukung
7. Per sesi: nilai observed + versi profil + status apply
  - Tampilkan stale data dan kapabilitas unavailable secara eksplisit
  - Jangan samakan draft tersimpan dengan kebijakan aktif di PCRF


## Deteksi app di UPF (IP / hostname / SNI) [A] {#detect}

> **Bukan dekripsi payload:** Usulan deteksi (laporan kebutuhan): collector eBPF membaca IP, hostname via DNS snooping, dan TLS SNI plaintext; counter per-app di BPF map, diekspor misalnya ke Prometheus. Tidak ada janji dekripsi konten. eBPF tidak menggantikan PCC/Gx dan bukan implementasi kebijakan PCRF.

| Sinyal | Kapan berguna | Kapan gagal / ambigu |
| --- | --- | --- |
| IP tujuan | Endpoint stabil milik app uji | CDN/shared IP; IP berubah; banyak app satu IP |
| Hostname (DNS snooping) | Query DNS plaintext terlihat di jalur yang di-hook | DoH/DoT; cache; spoof; jeda waktu DNS versus flow |
| TLS SNI plaintext | ClientHello tidak terenkripsi | ECH; beberapa stack QUIC/TLS menyembunyikan SNI; parsing gagal |

[A] eBPF exporter = sumber provenance first-class (di samping Gx dan Sx/N4), belum di-deploy/diverifikasi. Privilege eBPF hanya di collector — bukan di web backend. Kompatibilitas kernel/BTF/helper di VM target dicek Network Architect; kapabilitas host CentOS 7 tidak diasumsikan.

| Field bukti (usulan) | Isi |
| --- | --- |
| exporter / instance | Identitas collector yang mengekspor |
| attach hook / interface | Titik pasang eBPF dan antarmuka jaringan |
| timestamp / freshness | Waktu sampel dan usia data |
| rule version | Versi peta klasifikasi yang dipakai |
| mapping | flow â app_id â eksperimen (di API/storage berotorisasi) |
| bytes / packets | Counter per-app dari BPF map; dokumentasikan reset semantics |
| loss / unknown | Hanya jika diinstrumentasi â jangan mengarang metrik |

> **Kardinalitas Prometheus:** Jangan taruh IMSI, SNI, atau flow ID mentah sebagai label Prometheus tanpa batas. Label metrik agregat dibatasi (mis. app_id, eksperimen, antarmuka). Drill-down detail lewat API + penyimpanan berotorisasi.

Setiap hasil deteksi tetap menyimpan evidence type, nilai, confidence, collision/precedence. Klaim kuat: flow terkontrol atau instrumentasi sumber. Status dukungan: unknown — Net Arch.


## Self-service profil PCRF [A] {#profile}

> **Kebutuhan user (belum approval desain/kode):** Setiap user bebas mengatur profil PCRF untuk IMSI yang menjadi miliknya agar mendapatkan slicing/policy yang diinginkan — dalam katalog, kuota, dan validasi yang ditetapkan admin.

Field yang boleh diedit (intent pengguna, dalam batas katalog): APN / kelas slice logis yang diizinkan; QCI/ARP; AMBR / MBR / GBR; intent PCC per-app (IP / hostname / SNI); ambang usage. Bukan field rahasia auth.

| Lapisan | Arti | Jangan dicampur |
| --- | --- | --- |
| User policy intent | Draft/profil yang user tulis di GUI | Belum berarti aktif di jaringan |
| Subscriber DB (HSS/Mongo) | Data langganan jika adapter provision terverifikasi | Bukan tempat menyimpan Ki/OPc lewat GUI user |
| PCRF decision | Keputusan/rule yang PCRF kirim ke PCEF (Gx) | Hostname/SNI bukan AVP Gx native otomatis |
| eBPF detection / counters | Klasifikasi & metrik di collector | Bukan enforcement PCC; BPF rule tidak terpasang otomatis dari HSS |

1. Kepemilikan & otorisasi
  - IMSI hanya dari assignment admin di server â bukan IMSI yang diketik user atau klaim token tidak terverifikasi
  - Otorisasi ulang per request/stream; tidak ada edit Ki/OPc/secret auth atau pengaturan shared core
2. Katalog, kuota, validasi
  - Admin mendefinisikan template/katalog dan kuota
  - Validasi silang: GBR â¤ MBR; agregat reservasi resource; implikasi QCI/ARP/preemption
  - Fleksibilitas user hanya dalam ownership + resource terikat â UI tidak boleh diam-diam mengklaim limit yang belum disetujui
  - Jika angka limit lab belum ditetapkan: design choice pending (jangan mengisi default seolah approved)
3. Versi, apply, audit
  - Audit immutable; profil ber-versi; optimistic concurrency
  - Apply = job idempotent; rollback = versi baru (tidak menjamin undo paket/sesi aktif)
  - State: saved â validated â queued â pushed â active | failed | drift â tiap target dengan evidence
  - Simpan draft â  apply produksi/live; apply butuh konfirmasi eksplisit + peringatan disrupsi (reattach/reconnect)
4. Sinkron live (unknown)
  - HSS/subscriber provision vs update PCRF butuh adapter terverifikasi
  - Live sync / Gx RAR vs efek hanya setelah attach berikutnya: unknown â Net Arch; jangan diklaim tersedia

| Provenance usage | Arti | Jika tidak ada |
| --- | --- | --- |
| Gx usage monitoring | Laporan PCEFâPCRF bila adapter mendukung â bukan eBPF | unknown / not validated |
| Sx / N4 (PFCP) reports | Usage report SMFâUP dari PFCP | unknown / not validated |
| eBPF exporter (usulan) | Counter/klasifikasi per-app; terpisah dari Gx/PCC | not deployed / not verified |
| Passive capture | Mirror pada antarmuka bernama (S1-U / S5-U / SGi) | unsupported |

> **Kandidat PoC Net Arch:** Emulasi APN + UPF per APN + PCC/dedicated bearer via PCRF — pending PoC. Egress dilabeli SGi selama EPC.


## MVP self-service + observability [A] {#mvp}

| Fase | Isi | Syarat |
| --- | --- | --- |
| MVP | Observability (intended vs observed, TEID, PCC decision vs install, counters ber-provenance) + editor profil PCRF self-service untuk IMSI assigned | Ownership server-side; validasi katalog/kuota; apply terkonfirmasi; audit/versi; unknown jujur |
| Di luar MVP / admin | Assignment IMSI; katalog/template/kuota; restart shared core; secret auth | Admin-only; adapter terverifikasi sebelum sync live |

**Pros**
- Hanya IMSI yang di-assign admin
- Authz per request; audit immutable semua apply
- Tidak ada akses Ki/OPc atau shared core dari role mahasiswa

**Cons**
- User mengetik IMSI sendiri
- Draft tersimpan dianggap sudah slicing aktif
- WebUI/Mongo mentah bersama


## Go/no-go dan keputusan pengguna {#poc}

| ID | Uji | Go | No-go |
| --- | --- | --- | --- |
| C1 | Path core | TEID + counter di antarmuka yang dilabeli benar | Counter dicap S1-U padahal di SGi |
| C2 | Klasifikasi app | Flow terkontrol cocok aturan; confidence + evidence ada | Tebakan port / klaim SNI saat ECH |
| C3 | Policy vs enforce vs traffic | State terpisah di UI tanpa dipaksa sama | Satu badge OK untuk semua |
| C4 | Usage provenance | Gx / PFCP / capture terpisah atau unknown | Angka usage tanpa sumber |
| C5 | Isolasi + ownership | User hanya edit IMSI assigned; tidak lihat/ubah profil orang lain | IMSI bebas diketik / PCC orang lain terlihat |
| C6 | Apply vs draft | Konfirmasi apply + peringatan reattach; state/versi/evidence jelas | Save draft dianggap live; tanpa audit/versi |
| C7 | Klaim arsitektur | UI tidak mengklaim NSA+5GC E2E atau hostname sebagai AVP Gx native | SNI/hostname disamakan dengan PCC terpasang tanpa bukti |

- [ ] KEPUTUSAN UTAMA: setujui lingkup core-side + MVP = self-service profil PCRF (IMSI assigned) + observability, stack Next.js/FastAPI/PostgreSQL
- [ ] Tetapkan katalog/template, kuota resource, dan apakah GBR/MBR/AMBR aggregate sudah punya angka approved
- [ ] Setujui kandidat PoC APN + UPF per APN + PCC; Net Arch validasi adapter HSS vs PCRF dan perilaku RAR/reattach
- [ ] Pilih jalur deteksi MVP eBPF vs alternatif; cek kernel/BTF di VM target


## Sumber primer {#sumber}

Tidak ada counter, snippet implementasi, atau dukungan lab yang dikarang. Kapabilitas apply PCRF/HSS, Gx RAR vs reattach, Gx usage, PFCP, eBPF exporter, UPF per APN menunggu validasi Network Architect atau PoC.
