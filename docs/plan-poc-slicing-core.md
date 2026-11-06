<!-- Sanitized reference copy. Snapshot 2026-11-06 20:17:38 +07 (Asia/Bangkok). Not a deployable mirror. -->

# FINAL — Rencana PoC core-side slicing, live policy, dan EN-DC

**Target:** `lab5g-dev` (`172.22.20.21`) saja. **`lab5g-vm` live tidak pernah diubah.**  
**Baseline:** Open5GS `v2.8.0`, commit `157f611a530e292e40ec50f9d23f0ef5d4fcd6a6`; EPC CUPS; srsRAN 4G.  
**Status dokumen:** perencanaan; belum ada perubahan slicing/eBPF/RAR. EN-DC sedang diimplementasikan terpisah, hasil menunggu.  
**Legenda:** **FACT** = dibuktikan pada source yang dirujuk; **UNKNOWN** = perlu uji; **PROPOSAL** = desain, belum berjalan.

## 1. Sasaran dan batasan

Satu **slice = satu APN**, dengan UPF (PGW-U) khusus dan, bila diperlukan isolasi S1-U/S5-U lebih awal, SGW-U khusus. SMF/PGW-C memilih jalur berdasarkan APN/DNN; PCRF memberi PCC rule per aplikasi. App detection oleh **eBPF** terhadap IP, hostname dari DNS, dan TLS SNI. Setiap pengguna hanya boleh mengubah profil IMSI miliknya.

PoC memverifikasi S1-U → SGW-U → UPF/SMF/PGW-C → PCRF, bukan native S-NSSAI/URSP. EN-DC Option 3x tetap memakai EPC sehingga slicing di sini adalah emulasi berbasis APN/PCC, bukan slicing 5GS. Pemilihan APN baru membutuhkan PDN reconnect; perubahan PCC yang didukung harus diterapkan **live melalui Gx RAR**, dengan bukti bearer aktual, bukan sekadar tersimpan di MongoDB.

## 2. Topologi dan alur

```text
srsUE (NSA LTE+NR via ZMQ)
          | LTE eNB MN + NR SCG, satu EPS bearer
          v
srsENB --S1-MME(MME)--S1AP; S1-U GTP-U--> SGW-U(slice-A/B)
                                             ^
                                        Sxa  | SGW-C --S11(2123)-- MME
                                             v
                                          S5-U GTP-U
                                             |
                                      UPF-A / UPF-B (ogstun + eBPF)
                                      Sxb PFCP |       | SGi/N6
                                               v
                                       SMF/PGW-C ---- Gx(3868) ---- PCRF
                                          |                              |
                                         URR                         MongoDB
                                          |                              ^
                                  usage (stock -> Gy;          Dashboard + ACL
                                  Gx perlu patch)                per-IMSI + trigger
```

Alur sesi: CCR-I/CCA-I memberi PCC; SMF membentuk PDR/FAR/QER/URR pada UPF; PFCP accepted kemudian Create/Update Bearer melalui SGW-C ke MME. Untuk UE dengan EN-DC, bearer dan TEID EPC yang sama digunakan; arsitektur ini tidak menambah gNB→5GC dan tidak mengklaim NGEN-DC/NE-DC.

Sumber IP pool per APN harus dipetakan ke UPF/ogstun dan N6 berbeda atau setidaknya routing/counter berbeda. Binding APN↔UPF/SGW-U dibuat sebagai template admin; pengguna tidak menulis YAML, Docker, atau membuat UPF sendiri. Nama APN/IP/interface final adalah **UNKNOWN** sampai inventaris konfigurasi dev divalidasi.

## 3. Fakta kemampuan stock v2.8.0

| Kemampuan | Status | Bukti source |
|---|---|---|
| Gx CCR-I/CCA-I dan Charging-Rule Install/Remove; Flow-Description | **FACT: ada** | `src/pcrf/pcrf-gx-path.c:614-652,1669-1716`; `src/smf/gx-path.c:1034-1102` |
| IP 5-tuple SDF di UPF; URR volume/time dan threshold-report | **FACT: ada** | `lib/pfcp/handler.c:507-564`; `src/upf/n4-handler.c:25-41,339-352`; `src/upf/context.c:709-720,771-890` |
| Native UPF hostname/SNI, PDI Application-ID matching/PFD | **FACT: tidak ada** | TLV decode ada di `lib/pfcp/message.h:1278,1287`; `src/upf/pfcp-sm.c:118-283` tidak mendispatch PFD |
| SGW-U URR | **FACT: tidak ada** | `src/sgwu/sxa-handler.c`, `sxa-build.c` tidak punya jalur URR |
| UPF URR Session Report → SMF | **FACT: ada**, sekarang diarahkan ke **Gy**, bukan Gx usage | `src/smf/n4-handler.c:1728-1762` |
| Gx Usage-Monitoring AVP runtime dan CCR-U `USAGE_REPORT` | **FACT: tidak ada**; dictionary saja | `lib/diameter/gx/dict.c:172,240,270`; `src/smf/gsm-sm.c:108-110,148-150` hanya INITIAL/TERMINATION |
| PCC dari Mongo saat CCR-I/U | **FACT: database dibaca ulang** | `src/pcrf/pcrf-gx-path.c:614-628`; `src/pcrf/pcrf-context.c:388-420` |

**Konsekuensi go/no-go:** R1 IP/PCC dan policy query = **GO**; hostname/SNI = **GO hanya melalui eBPF, belum dibangun**; native Gx per-app usage = **NO-GO stock**, perlu integrasi/patch dan tidak boleh diklaim dari counter eBPF saja.

## 4. Live policy melalui Gx RAR — temuan source

### 4.1 Apakah perubahan Mongo otomatis memicu RAR?

**Tidak (FACT).** `pcrf_gx_send_rar()` didefinisikan di `src/pcrf/pcrf-gx-path.c:1033-1055`, dan seluruh call site hanya dari Rx AAR/STR di `src/pcrf/pcrf-rx-path.c:450-452,946-952`. Tidak ada call site Mongo-trigger/REST/admin di PCRF. HSS memang punya Mongo change stream (`lib/dbi/ogs-mongoc.c:200-203`; `src/hss/hss-context.c:1411-1429`) lalu IDR untuk UE-AMBR/APN (`src/hss/hss-context.c:1509-1522,1535-1537`), tetapi itu S6a ke MME, **bukan** PCC RAR ke SMF.

### 4.2 Kemampuan SMF menerima RAR

- **FACT:** SMF mendaftarkan callback RAR (`src/smf/gx-path.c:1493-1519`), decode `Charging-Rule-Install` dan `Remove` (`:1301-1408`) lalu memanggil bearer binding (`src/smf/gx-handler.c:259-270`). AVP top-level selain kedua itu dan header umum hanya menghasilkan `Not supported` (`src/smf/gx-path.c:1404-1406`); jadi jangan berasumsi top-level APN-AMBR ikut diproses.
- **FACT:** install baru → PFCP bearer modification (`src/smf/binding.c:140-223,335-344`). Setelah PFCP accepted → Create Bearer (`src/smf/n4-handler.c:1340-1355`); update flow/MBR/GBR → Update Bearer; deaktivasi → Delete Bearer (`src/smf/n4-handler.c:1357-1384,1434,1455`). SGW-C meneruskan respons/prosedur S11 (`src/sgwc/sgwc-sm.c:193-204`; `src/sgwc/s5c-handler.c:625,750,861`).
- **FACT penting:** RAA `2001` dikirim setelah event dimasukkan queue (`src/smf/gx-path.c:1411-1456`), tetapi bearer binding berjalan pada state machine (`src/smf/gx-handler.c:259-270`). RAA saja **bukan bukti policy aktif**.
- **UNKNOWN:** keberhasilan end-to-end srsRAN untuk dedicated bearer serta remove/partial flow update harus dibuktikan dengan pcap.

### 4.3 Tiga opsi trigger RAR

| Opsi | Kelayakan dan batas FACT | Effort | Risiko | Putusan |
|---|---|---:|---|---|
| **(1) Rx AF shim**: client Diameter Rx Python/freeDiameter, AAR → PCRF | **FACT:** UE dipetakan melalui `Framed-IP-Address` (atau IPv6 prefix) ke Gx session (`pcrf-rx-path.c:216-253`), bukan sekadar IMSI. AAR memicu RAR `:450-452`. Rx menerima Media-Component, Media-Sub-Component Flow-Description dan bandwidth (`:288-410`). Media-Type hanya audio/video/control → QCI **1/2/5** dari template DB (`pcrf-gx-path.c:1123-1205`). ARP berasal dari template DB. Flow 5-tuple dapat disalin ke PCC (`lib/proto/types.c:1139-1179`), Max/Min-Requested-BW menjadi MBR/GBR (`:1184-1207,1212-1247,1249+`). Secara syntax 5-tuple arbitrer dan MBR/GBR dapat dibawa, tetapi QCI/ARP tidak arbitrer: harus template media DB. Rx rule bersifat IMS/dinamis dan harus hidup berdampingan/terpisah jelas dari intent Mongo. | 2–4 hari | Semantik media yang dipaksakan, AF session state, Rx terbatas QCI, update/remove harus memakai Rx session yang sama; sulit menjadi editor profil umum | **Baik untuk spike/validasi cepat RAR**, tidak rekomendasi final |
| **(2) PCRF patch admin-trigger/change-stream + diff → Gx RAR** | **FACT:** dapat memakai state Gx yang sudah menyimpan IMSI/APN dan helper DB/RAR (`pcrf-gx-path.c:1073-1101,1112-1121`). Namun generator RAR sekarang **Rx-centric**, mengharuskan `rx_sid`/`rx_message` (`:1033-1053`), dan meng-encode rule dari media, jadi perlu fungsi baru untuk bulk install/remove dari DB. | 5–10 hari | Diff state, full replace/partial removal, concurrency, session lookup, ketergantungan internal, regresi PCRF | **REKOMENDASI final** |
| **(3) External Gx RAR injector** | Harus berperan sebagai peer PCRF, memakai Gx `Session-Id` aktif, Destination-Host/Realm, AVP yang tepat dan koneksi Diameter yang dipercaya SMF. SMF mampu memproses AVP-nya secara FACT seperti §4.2. | 3–7 hari | Session-id/peer spoof operational coupling; radius perubahan sulit dibatasi; duplikasi PCRF state; TLS/identity/trust; raw injector tidak bisa mempertahankan data tetap PCRF | Hanya alat uji darurat, **bukan rekomendasi produksi lab** |

**Rekomendasi implementasi (PROPOSAL):** dashboard menyimpan intent dan memanggil **authenticated admin trigger pada PCRF**, dengan IMSI+APN+revision. Mulai dengan explicit trigger (lebih terukur daripada Mongo watch); tambahkan change-stream kemudian bila konsistensi writer selain dashboard dibutuhkan. PCRF mencari seluruh Gx session IMSI+APN aktif, membaca profil tervalidasi, menghasilkan **Charging-Rule-Install** dan **Charging-Rule-Remove** dari diff nama rule, lalu mengirim RAR. Jika tidak ada sesi aktif, hasil = pushed/pending reconnect. Hindari reuse fungsi Rx semu tanpa refactor: buat encoder `pcrf_gx_send_pcc_rar(gx_sid, diff)` berbagi encoder existing di `pcrf-gx-path.c:1669-1800`.
Acceptance harus membuktikan RAR, RAA `Result-Code=2001`, PCC tersimpan/berubah di PGW-C/SMF, PFCP Session Modification accepted, lalu Create/Update/Delete Bearer pada S5-C dan S11 serta E-RAB Setup/Modify pada S1AP. Jika RAA sukses tetapi prosedur selanjutnya gagal → status **failed/degraded**, bukan active.

### 4.4 Matriks perubahan profil

| Perubahan | Live melalui RAR? | Klasifikasi dan catatan/fallback |
|---|---|---|
| PCC rule Install (5-tuple, QCI/ARP/MBR baru) | **Ya, setelah trigger tersedia** | **FACT:** decode+bearer binding/PFCP di atas; **UNKNOWN:** test E2E |
| PCC rule Remove | **Ya** | **FACT:** decode Remove dan deactivate→Delete Bearer (`gx-path.c:1361-1403`; `binding.c:363-387`); **UNKNOWN** E2E |
| MBR/GBR dedicated bearer yang sudah ada | **Ya** | **FACT:** perubahan dibandingkan dan `qos_presence` → PFCP+Update Bearer (`binding.c:228-241,352-360`) |
| QCI/ARP dedicated bearer yang sudah ada | **Jangan diasumsikan** | **FACT:** comparison `qos_presence` hanya MBR/GBR (`binding.c:228-241`); fallback remove+install/reconnect, **UNKNOWN** mana yang diterima RAN |
| Flow 5-tuple ditambah | **Ya** | **FACT:** add-only TFT dibentuk (`binding.c:244-323`); flow removal individual di luar Remove rule perlu test/patch |
| APN-AMBR | **Tidak melalui RAR stock** | **FACT:** RAR top-level `QoS-Information` tidak diterima (`gx-path.c:1404-1406`); fallback PDN reconnect (keputusan desain; bukan sekadar rule PCC) |
| APN/slice/IP pool/static UE IPv4 | **Tidak; PDN reconnect/re-attach** | PAA/APN sudah terikat sesi; **UNKNOWN** untuk tiap variasi HSS IDR, uji fallback |
| Default bearer QCI/ARP | **Tidak; PDN reconnect/re-attach** | RAR callback tidak menangani Default-EPS-Bearer-QoS; **FACT** handler APN/default QoS berada di initial CCA (`gx-handler.c:64-106`) |
| UE-AMBR dari HSS | **Bukan Gx RAR; IDR bila change-stream enabled** | **FACT:** `ambr`→S6a IDR (`hss-context.c:1509-1512,1535-1537`); hasil MME/eNB **UNKNOWN**, verifikasi pcap |
| Usage-monitoring key/threshold | **Tidak stock** | AVP runtime absent (FACT §3); perlu patch PCRF+SMF+URR mapping |
| eBPF classifier map | **Live out-of-band** | Bukan Diameter/policy EPS. SDF mirror menunggu PCC RAR/reconnect |

## 5. Usage reporting Sx/N4 dan eBPF

### 5.1 Desain usage

1. **Stock per-PDR/session:** SMF membuat URR dengan volume threshold; UPF menghitung dan mengirim PFCP Session Report. Gunakan untuk membuktikan N4 terlebih dahulu. Karena satu PDR dapat membawa beberapa app, ini **bukan** otomatis per-app.
2. **eBPF per-app:** TC clsact di `ogstun` dalam network namespace UPF. UL pada TC egress dan DL pada TC ingress; optional TC N6 untuk cross-check. Map LPM IP→app, DNS response A/AAAA→IP+TTL, parser TLS ClientHello SNI→app, flow table dan per-CPU counter `(ue_ip,app_id,direction)`. Agent membaca stats → dashboard. Ini custom/out-of-band.
3. **SDF bridge:** hasil DNS/SNI divalidasi lalu dijadikan flow 5-tuple pada template PCC; RAR memasang PDR sehingga URR dapat mengukur flow tersebut. Ini jembatan terdekat ke stock tetapi TTL/shared-CDN harus dijaga.
4. **Native Gx usage (fase lanjut):** tambahkan Usage-Monitoring AVP, URR per monitoring-key, dan CCR-U `USAGE_REPORT`; tidak termasuk keberhasilan PoC awal. Stock Session Report menuju Gy (`smf/n4-handler.c:1728-1762`).

Batas: ECH, QUIC/HTTP3, DoH/DoT, TCP ClientHello fragment/multi-packet, IPv6, shared CDN; default **fail-open** ke app unknown/default slice, jangan steer berdasarkan tebakan. IP-only berbahaya pada shared VIP. BPF perlu kernel/BTF/toolchain yang sesuai (**UNKNOWN** pada dev) dan agent privilege ketat.

## 6. EN-DC NSA Option 3x — **in progress, results pending**

Desain: srsENB menjalankan LTE master + NR secondary cell dan srsUE menjalankan NSA melalui ZMQ. Subscriber/HSS dan MME harus mengizinkan EN-DC/DCNR serta capability NR pada UE; keberhasilan current implementation **belum diverifikasi**.

- Setelah SCG/NR ditambahkan, eNB mengirim **S1AP E-RAB Modification Indication** dengan alamat/TEID downlink leg yang baru. Open5GS MME memproses IE dan memperbarui TEID/IP (`src/mme/s1ap-handler.c:2346-2386,2434-2517`), lalu meminta Modify Bearer dan E-RAB Modification Confirm (`:2524`; `src/mme/s1ap-build.c:1771-1847`).
- Core-side slicing **transparan** terhadap EN-DC: APN/PDN/EBI/PCC/QER sama; RAN yang memindahkan aktual S1-U leg. Tidak ada UPF baru khusus NR.
- QCI/ARP/GBR berlaku pada EPS bearer, sementara UE/APN-AMBR tetap membatasi aggregate LTE+NR; throughput radio per leg tidak dibuktikan oleh GTP counter sendiri. Ambil UE/eNB RRC/NR log dan throughput kedua leg.
- **Pcap wajib:** S1AP `E_RABModificationIndication` dan Confirm pada SCTP/36412; GTPv2 Modify Bearer terkait; GTP-U TEID baru pada 2152. Hasil implementasi dan kemampuan dedicated bearer EN-DC = **UNKNOWN/pending**.

## 7. Dashboard self-service dan model status

API awal:

```text
GET  /api/imsi/{imsi}/profile
PUT  /api/imsi/{imsi}/profile             # intent tervalidasi
POST /api/imsi/{imsi}/apply               # -> PCRF admin trigger, revision
POST /api/imsi/{imsi}/reconnect           # hanya fallback APN/default bearer
GET  /api/imsi/{imsi}/status              # revision, timestamp, evidence
GET  /api/imsi/{imsi}/usage?source=ebpf|urr
GET  /api/templates/apn                   # admin-owned allowlist
```

Body mengandung `sessions[].apn/default_qos/apn_ambr/pcc_rules[]` dan `ebpf_apps[]` (`cidr`, `hostnames`, `snis`). Security key admin-only; template APN/UPF read-only. Backend adalah satu-satunya writer Mongo; RBAC daftar IMSI, batas QCI/MBR/GBR, maksimal 8 PCC rules/15 flows, larang wildcard flow berbahaya, audit diff, rate-limit apply, idempotency revision.

Status:
**intent** (draft) → **pushed** (Mongo/map write acknowledged, revision tercatat) → **apply-in-progress** (RAR terkirim) → **active** hanya bila RAA 2001 **dan** prosedur N4/GTP/S1AP yang diharapkan sukses dan rule/QoS cocok. eBPF-only aktif bila map revision cocok dan counter uji bertambah. `pushed`, `no-active-session`, `failed`, atau `degraded` bila tahapan gagal. Timeout tanpa evidence tidak dibulatkan menjadi sukses.

## 8. Rencana uji dan pcap (dijalankan hanya setelah approval)

Semua perintah dijalankan di **lab5g-dev**, mengganti `${IF}` dengan interface lab atau `any`; simpan waktu/IMSI/APN/EBI/rule-name/revision. Contoh capture kontrol, dipisah agar file kecil:

```bash
sudo tcpdump -i "${IF:-any}" -s 0 -U -w /tmp/t-gx.pcap '(tcp or sctp) and port 3868'
sudo tcpdump -i "${IF:-any}" -s 0 -U -w /tmp/t-gtpc.pcap 'udp port 2123'
sudo tcpdump -i "${IF:-any}" -s 0 -U -w /tmp/t-pfcp.pcap 'udp port 8805'
sudo tcpdump -i "${IF:-any}" -s 0 -U -w /tmp/t-s1ap.pcap 'sctp port 36412'
sudo tcpdump -i "${IF:-any}" -s 0 -U -w /tmp/t-up.pcap 'udp port 2152 or host 10.99.9.20'
```

Inspeksi:

```bash
tshark -r /tmp/t-gx.pcap -Y 'diameter' -V            # RAR/RAA code, Session-Id, Result-Code=2001
tshark -r /tmp/t-gtpc.pcap -Y 'gtpv2' -V             # Create/Update/Delete Bearer Request/Response, Cause
tshark -r /tmp/t-pfcp.pcap -Y 'pfcp' -V               # Session Modification Request/Response, Cause accepted
tshark -r /tmp/t-s1ap.pcap -Y 's1ap' -V               # E-RAB Setup/Modify + EN-DC ModInd/Confirm
tshark -r /tmp/t-up.pcap -Y 'gtp or icmp or tcp or udp' -V
```

| Test | Prosedur | PASS | FAIL/interpretasi |
|---|---|---|---|
| T1 APN slice/SDF baseline | Dua APN, attach/reconnect, traffic 5-tuple | PDR/FAR dan pool/UPF sesuai; GTP-U TEID berbeda; CCA rule benar | APN/UPF salah atau rule tidak match |
| T2 Sx URR | Melewati volume/time threshold | Session Report Request/Response diterima, counter ± toleransi pcap | Tidak ada report; jangan labeli Gx usage |
| T3 eBPF DNS/SNI | Dua hostname pada VIP sama, DNS unik, `curl --resolve` | app_id/counter terpisah; DNS TTL expire; negative ECH/DoH fail-open | SNI sama atau counter salah/blank |
| T4 RAR Install | Simpan PCC baru → apply | RAR + RAA 2001; PFCP Mod accepted; Create Bearer req/resp sukses S5/S11; E-RAB Setup sukses; traffic memakai bearer | RAA bukan pass bila N4/GTP/S1AP gagal |
| T5 RAR Modify | Ubah MBR dedicated, lalu QCI/ARP | MBR: Update Bearer+PFCP+E-RAB Modify; QCI/ARP: hanya pass bila aktual berubah | QoS tidak berubah → gunakan remove+install/reconnect |
| T6 RAR Remove | Hapus rule | Delete Bearer S5/S11 sukses, E-RAB deactivate, PDR dihapus | Bearer/trafik masih aktif |
| T7 Failed apply/no session | Trigger IMSI tanpa sesi, RAN tolak, timeout | `no-active-session`/`failed` tepat; reconnect later picks intent | UI menunjukkan active tanpa evidence |
| T8 APN/default QoS fallback | Edit APN/default bearer QCI/static IP | Tidak mengaku live; reconnect lalu CCR-I/CCA-I+PDN baru benar | Sesi lama tetap berubah nama UI saja |
| T9 EN-DC | Attach DCNR, tambah SCG, generate UL/DL | NR SCG log; S1AP ModInd/Confirm; data TEID baru, SGW-U path terbukti | hanya LTE-leg/attach = belum EN-DC selesai |
| T10 isolation | User A edit IMSI B/over-cap/wildcard | HTTP 403/422; audit; tidak ada DB/RAR | Perubahan terjadi |

Pcap dan log diberi nama per-test, disertai timestamp dalam zona **Asia/Bangkok**, tanpa secret key/subscriber auth material pada laporan publik.

## 9. Fase, risiko, dan kriteria go/no-go akhir

| Fase | Deliverable/gate |
|---|---|
| A — baseline | LTE attach, dua APN→UPF(+SGW-U), SDF+URR, pcap T1–T2 |
| B — EN-DC (sedang berjalan) | T9 lulus sebelum klaim EN-DC dan sebelum QoS dedicated dianggap valid |
| C — eBPF | klasifikasi IP/DNS/SNI + counter T3 |
| D — live RAR | rekomendasi PCRF admin trigger; T4–T8 |
| E — self-service | API/RBAC/audit/status; T10 |
| F — usage lanjut | SDF bridge; native Gx usage hanya bila patch disetujui |

Risiko utama: RAA false confidence, update QCI/ARP yang bukan compare-aware, SGW-U tidak menghitung, shared-CDN/ECH/QUIC, dedicated bearer srsRAN tidak stabil, RAR storm, resource multi-user belum diuji, eBPF privilege, dan student cross-IMSI writes. Mitigasi: evidence-chain status, caps/rate-limit, satu writer, allowlist template, dev-only snapshots/backups, fail-open detection.

**GO akhir per requirement:** slicing APN/UPF bila T1 lulus; EN-DC bila T9 lulus; app detection bila T3 lulus; live PCC bila T4/T6 lulus dan T5 dibatasi hasil; self-service bila T10 lulus; Sx URR bila T2 lulus. **NO-GO bila hanya Mongo berubah, hanya RAA 2001, atau hanya UE attach.** Native SMF→PCRF per-app Gx usage monitoring tetap pekerjaan lanjutan sampai AVP CCR-U/CCA-U benar-benar terlihat.

## 10. Referensi desain

Dokumen asal: `/workspace/epc-cups-app-detection-feasibility.md` dan `/workspace/nsa-5gc-feasibility-report.md`. Semua referensi file:line di atas menggunakan tag Open5GS `v2.8.0` dan dapat dibuka sebagai `https://github.com/open5gs/open5gs/blob/v2.8.0/<path>#L<line>`.
