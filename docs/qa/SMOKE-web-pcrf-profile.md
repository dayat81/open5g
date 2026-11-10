# Smoke — profil PCRF lewat web (W0–W8)

Dokumen ini adalah prosedur smoke untuk mengubah profil PCRF dari dashboard web, lalu membaca kembali nilai itu di basis data dan, pada jalur radio, di sinyal. Bahasa: Indonesia. Semua cap waktu memakai zona **WIB (Asia/Bangkok, UTC+7)**.

**Keputusan:** Netdrive, 10 Nov 2026, 17:21 WIB — profil PCRF diuji lewat web.

**Status:** prosedur QA. Prasyarat W0, termasuk baseline iperf3, sudah dicatat Lab Ops (10 Nov 2026, 17:38 WIB); lihat W0. W1–W8 **belum dijalankan**. Dev sedang membangun form login dan editor profil. Dokumen ini tidak mengubah kode produk dan tidak menyatakan GO.

**Identitas yang boleh tertulis di dokumen dan di bukti:** placeholder saja.

| Peran | Placeholder |
| --- | --- |
| IMSI UE srsRAN | `` `<IMSI-UE-SRS>` `` |
| Server iperf3 di sisi SGi | `` `<IP-SGi>` `` |
| Akun student uji | `` `<akun-student-uji>` `` |

Dokumen ini tidak memuat alamat IP privat/internal, hostname internal, token, kata sandi, Ki, OPc, atau IMSI/MSISDN mentah. Jangan mengganti placeholder dengan nilai lab di repo, tiket, atau komentar PR.

## 1. Label hasil

Setiap hasil memakai **tepat satu** dari tiga level berikut. Kasus yang dijalankan pada dua level menghasilkan dua baris bukti, masing-masing dengan satu label. Jangan menggabung mock dan lab ke dalam satu status.

| Level | Arti |
| --- | --- |
| SINTETIS | Unit atau CI, dengan mock. Tanpa Mongo nyata, tanpa EPC, tanpa RAN. |
| LAB-CORE | Mongo dan EPC nyata. Tanpa RAN dan tanpa UE. |
| RAN/UE NYATA | srsRAN + srsUE. |

Baris bukti memuat: ID kasus, level, PASS / FAIL / BLOCKED, cap waktu WIB, dan SHA penuh PR Dev. Nama berkas bukti memakai ID kasus, bukan IMSI atau alamat IP.

## 2. Ringkasan kasus

| ID | Kasus | Level | Blocking |
| --- | --- | --- | --- |
| W0 | Prasyarat | LAB-CORE (throughput baseline: RAN/UE NYATA) | blocking (fase 1) |
| W1 | Login web sebagai student | SINTETIS dan LAB-CORE | blocking (fase 1) |
| W2 | Editor profil | SINTETIS dan LAB-CORE | blocking (fase 1) untuk ubah nilai dan validasi; 403 lintas grup = fase 2 jika tidak memblokir |
| W3 | Provision | LAB-CORE | blocking (fase 1) |
| W4 | Readback | LAB-CORE | blocking (fase 1) |
| W5 | UE re-attach | RAN/UE NYATA | blocking untuk objektif PCRF (fase 1) |
| W6 | iperf3 AMBR | RAN/UE NYATA | fase 2 bila tidak ada enforcement dan W5 benar |
| W7 | Kembalikan profil | LAB-CORE | blocking (fase 1) |
| W8 | Regresi | LAB-CORE | blocking fase 1 bila dashboard atau EPC rusak; bukan klausul GO |

Urutan jalannya: W0, lalu W1–W4 pada IMSI yang sama, lalu W5–W6, lalu W7, lalu W8. Nilai yang diubah pada W2 tetap terpasang sampai W7 mengembalikannya lewat web.

## 3. Kasus

### W0 — Prasyarat

- **Level:** LAB-CORE. Pengukuran iperf3 baseline memakai srsRAN + srsUE, jadi baris throughput itu berlabel **RAN/UE NYATA**. Baris SHA, akun, `attach_ready`, cadangan, dan hash tetap **LAB-CORE**.
- **Blocking:** blocking (fase 1).

**Langkah**

1. Catat SHA penuh PR Dev (keluaran `git rev-parse HEAD` pada commit yang di-deploy) dan digest image yang benar-benar berjalan. Keduanya harus merujuk artefak yang sama.
2. Pastikan akun student uji `` `<akun-student-uji>` `` ada dan masuk grup yang memiliki `` `<IMSI-UE-SRS>` ``. Kata sandi tetap di luar repo dan di luar bukti.
3. Pastikan Lab Ops sudah mengisi data keamanan (Ki/OPc) untuk `` `<IMSI-UE-SRS>` `` **di luar dashboard**, dan `attach_ready=true`. Dashboard tidak dipakai untuk menulis Ki/OPc.
4. Ambil cadangan Mongo **sebelum** uji. Hitung hash sub-dokumen keamanan subscriber itu hanya atas bidang `k`, `opc`, dan `amf`; kecualikan `sqn`. Simpan hanya algoritma dan digest. `sqn` dikecualikan karena nilainya naik pada setiap autentikasi, sehingga digest ikut berubah walaupun `k`, `opc`, dan `amf` tidak ditulis ulang (temuan Lab Ops, 10 Nov 2026, 17:38 WIB).
5. Ukur baseline iperf3 **sebelum** perubahan profil, ke server di `` `<IP-SGi>` ``: arah DL (`iperf3 -R`) dan UL, masing-masing 3 kali 30 detik. Catat ketiga angka per arah.
6. Pilih nilai APN-AMBR untuk W2 yang jauh di bawah kapasitas radio dan di bawah baseline W0, misalnya DL 5 Mbps dan UL 2 Mbps. Jika baseline sudah di bawah contoh itu, catat angkanya dan sepakati nilai yang lebih rendah dengan Lab Ops sebelum W2, supaya W6 masih bisa dibandingkan.

**Hasil yang diharapkan**

- SHA dan digest image tercatat dan saling cocok.
- Akun uji bisa dipakai. IMSI uji `attach_ready=true` tanpa menulis ulang data keamanan dari web.
- Cadangan Mongo ada di lokasi lab di luar repo. Digest sub-dokumen keamanan tercatat, dihitung hanya atas `k`, `opc`, dan `amf`.
- Enam angka baseline (3 DL, 3 UL) tercatat, masing-masing 30 detik.

**Bukti yang wajib**

- SHA penuh dan digest image.
- Konfirmasi akun `` `<akun-student-uji>` `` dan `attach_ready=true` untuk `` `<IMSI-UE-SRS>` ``, tanpa Ki/OPc dan tanpa kata sandi.
- Waktu cadangan (WIB) dan hash sub-dokumen keamanan (algoritma + digest atas `k`, `opc`, dan `amf` saja).
- Tabel iperf3 baseline, berlabel RAN/UE NYATA, dengan placeholder `` `<IP-SGi>` `` saja.

**Catatan hasil (Lab Ops, 10 Nov 2026, 17:38 WIB).** Bukti W0 ada di komentar Lab Ops: https://github.com/dayat81/open5g/pull/7#issuecomment-6765184449

Baseline iperf3 yang tercatat (QCI 9, AMBR 1 Gbps, 3 kali 30 detik, server `` `<IP-SGi>` ``):

| Arah | Ulangan 1 | Ulangan 2 | Ulangan 3 |
| --- | --- | --- | --- |
| DL | 17,6 Mbit/s | 17,6 Mbit/s | 17,9 Mbit/s |
| UL | 17,4 Mbit/s | 17,6 Mbit/s | 17,3 Mbit/s |

Sekitar 17 Mbit/s kemungkinan besar batas link ZMQ.

### W1 — Login web sebagai student

- **Level:** SINTETIS dan LAB-CORE. Dua hasil terpisah.
- **Blocking:** blocking (fase 1). Kedua level harus PASS.

**Langkah**

1. **SINTETIS.** Pada SHA yang sama, jalankan uji unit/CI login dengan mock: kata sandi benar, kata sandi salah, permintaan tanpa cookie, dan logout. Tanpa Mongo atau EPC nyata.
2. **LAB-CORE.** Buka form login web. Masuk sebagai `` `<akun-student-uji>` `` dengan kata sandi yang benar.
3. Ulangi login dengan kata sandi yang salah.
4. Baca atribut cookie sesi pada respons login yang berhasil.
5. Panggil `/api/core/status` tanpa cookie.
6. Logout, lalu panggil `/api/core/status` lagi dengan cookie sesi yang tadi.

**Hasil yang diharapkan**

- Login benar membuka dashboard.
- Kata sandi salah menghasilkan 401 atau pesan galat. Pesan itu tidak membocorkan keberadaan akun lain, data profil, IMSI, Ki, OPc, atau jejak stack.
- Cookie sesi membawa atribut HttpOnly dan SameSite. Nilai SameSite dicatat apa adanya.
- `/api/core/status` tanpa cookie menghasilkan 401.
- Setelah logout, sesi itu tidak berlaku: `/api/core/status` dengan cookie lama menghasilkan 401.

**Bukti yang wajib**

- Keluaran uji SINTETIS pada SHA persis (lulus/gagal per skenario), tanpa fixture yang memuat rahasia.
- Tangkapan LAB-CORE yang sudah disunting: halaman dashboard setelah login benar; status 401 atau pesan galat untuk kata sandi salah; header `Set-Cookie` yang menunjukkan HttpOnly dan SameSite; 401 tanpa cookie; 401 setelah logout.
- Cookie, token, dan kata sandi tidak ikut tersimpan di bukti.

### W2 — Editor profil

- **Level:** SINTETIS dan LAB-CORE. Dua hasil terpisah.
- **Blocking:** perubahan QCI dan APN-AMBR, serta penolakan input yang tidak sah, adalah **blocking (fase 1)**. Akses IMSI di luar grup (403) adalah **fase 2** jika student tetap bisa mengedit IMSI di grupnya sendiri dan penolakan lain tidak menulis ke Mongo.

**Langkah**

1. **SINTETIS.** Pada SHA yang sama, uji editor dan validasi dengan mock. Pastikan penolakan tidak menambah penulisan ke penyimpanan mock.
2. **LAB-CORE.** Sebagai `` `<akun-student-uji>` ``, buka profil `` `<IMSI-UE-SRS>` ``.
3. Kirim, satu per satu, input yang harus ditolak, sebelum nilai sah di-provision:
   - QCI di luar rentang yang diizinkan form dan API pada SHA itu;
   - ARP di luar 1–15 (contoh: 0 dan 16);
   - APN-AMBR negatif;
   - APN-AMBR 0;
   - satuan atau nilai non-numerik.
4. Setelah setiap penolakan, baca dokumen subscriber di Mongo dan bandingkan dengan salinan sebelum percobaan (bidang profil saja).
5. Ubah QCI, misalnya dari 9 menjadi 8. Ubah APN-AMBR UL/DL ke nilai yang jauh di bawah kapasitas radio, misalnya DL 5 Mbps dan UL 2 Mbps. Provision menyusul di W3. Catat nilai yang akan dikirim.
6. Minta ubah IMSI yang berada di grup lain. IMSI itu tidak ditulis di bukti; cukup identitas “grup lain”.

**Hasil yang diharapkan**

- Nilai QCI dan APN-AMBR yang sah tertampung di editor, siap di-provision pada W3.
- Setiap input tidak sah ditolak. Mongo tidak berubah karena penolakan itu.
- IMSI di grup lain menghasilkan 403. Jika 403 belum ada tetapi edit IMSI sendiri tetap berjalan dan tidak ada tulis ke IMSI orang lain, catat 403 sebagai fase 2 dan lanjutkan jalur IMSI uji.

**Bukti yang wajib**

- Keluaran SINTETIS: kasus valid dan kasus ditolak, plus hitungan tulis mock yang tetap nol pada penolakan.
- Cuplikan LAB-CORE nilai yang akan di-provision (QCI, APN-AMBR UL, APN-AMBR DL).
- Untuk tiap penolakan: kode atau pesan tolak, dan perbandingan Mongo yang menunjukkan tidak ada tulis.
- Untuk grup lain: status 403, atau catatan fase 2 bila belum memblokir jalur IMSI sendiri.
- Bukti tanpa Ki, OPc, atau IMSI mentah.

### W3 — Provision

- **Level:** LAB-CORE.
- **Blocking:** blocking (fase 1).

**Langkah**

1. Dari sesi `` `<akun-student-uji>` ``, provision profil `` `<IMSI-UE-SRS>` `` yang diubah pada W2.
2. Baca badan respons.
3. Baca jejak audit untuk aksi itu.

**Hasil yang diharapkan**

- Respons provision bertanda `written`.
- Ada entri audit untuk penulisan itu (aktor akun uji dan IMSI placeholder).

**Bukti yang wajib**

- Respons yang memuat `written`, dengan identitas tersunting menjadi `` `<akun-student-uji>` `` dan `` `<IMSI-UE-SRS>` ``.
- Entri audit yang cocok dengan aksi provision tersebut.

### W4 — Readback

- **Level:** LAB-CORE.
- **Blocking:** blocking (fase 1).

**Langkah**

1. Baca profil lewat API untuk `` `<IMSI-UE-SRS>` ``.
2. Baca dokumen subscriber yang sama di Mongo (bidang profil).
3. Bandingkan keduanya dengan nilai yang di-provision pada W3, termasuk tanda drift.
4. Periksa seluruh badan respons API: tidak ada bidang keamanan.
5. Hitung ulang hash sub-dokumen keamanan dengan algoritma yang sama seperti W0, hanya atas bidang `k`, `opc`, dan `amf`. Kecualikan `sqn`. Alasan pengecualian ada di W0.

**Hasil yang diharapkan**

- Nilai di API dan di Mongo sama dengan input W2/W3. `drift=false`.
- Respons tidak memuat bidang keamanan, Ki, atau OPc.
- Hash atas `k`, `opc`, dan `amf` identik dengan hash W0.

**Bukti yang wajib**

- Kutipan API dan kutipan bidang profil Mongo, keduanya tersunting, yang menunjukkan QCI dan APN-AMBR serta `drift=false`.
- Pernyataan pemeriksa bahwa respons tidak memuat bidang keamanan, Ki, atau OPc. Jangan menempelkan respons mentah jika masih ada kemungkinan bidang itu muncul; sunting dulu.
- Digest W4 di samping digest W0, keduanya atas `k`, `opc`, dan `amf` saja. Keduanya sama.

### W5 — UE re-attach

- **Level:** RAN/UE NYATA.
- **Blocking:** blocking untuk objektif PCRF (fase 1). PASS pada W0–W4 tanpa W5 belum menutup objektif ini.

**Langkah**

1. Lab Ops melepas (detach) srsUE `` `<IMSI-UE-SRS>` ``, lalu memasangkannya kembali (attach).
2. Kumpulkan sinyal pada sesi attach yang baru:
   - S6a ULA: AMBR serta QCI/ARP dari HSS;
   - S11 Create Session Request dan Create Session Response: QoS bearer (QCI/ARP) dan APN-AMBR;
   - Gx CCR/CCA-I bila PCRF ikut (port 3868);
   - S1AP Initial Context Setup: UE-AMBR dan QCI E-RAB.
3. Sumber: log MME, log SMF, log PCRF, dan pcap yang sudah disunting.

**Hasil yang diharapkan**

- Nilai baru dari W2/W3 muncul di sinyal (AMBR, QCI/ARP, APN-AMBR, UE-AMBR, QCI E-RAB, sesuai pesan yang memang memuat bidang itu).
- Bila PCRF ikut pada attach, CCR/CCA-I di port 3868 memuat nilai yang sama. Bila PCRF tidak ikut, catat bahwa Gx tidak muncul dan nilai yang terlihat berasal dari jalur HSS/MME/SMF; jangan mengarang pesan Gx.

**Bukti yang wajib**

- Kutipan log MME, SMF, dan PCRF (PCRF bila pesan Gx ada) dengan cap waktu WIB.
- Pcap tersunting yang memperlihatkan ULA, Create Session Request/Response, Initial Context Setup, dan CCR/CCA-I bila ada.
- IMSI dan alamat IP di log serta pcap diganti placeholder sebelum bukti meninggalkan lab.

### W6 — iperf3 AMBR

- **Level:** RAN/UE NYATA.
- **Blocking:** bukan NO-GO bila throughput tidak ter-cap **dan** sinyal W5 benar. Catat sebagai keterbatasan enforcement EPC (fase 2), bukan bug dashboard. Konfirmasi ke Lab Ops dan Architect apakah UPF Open5GS v2.8 atau eNB yang menegakkan batas laju AMBR.

**Peringatan:** server iperf3 berjalan di port 5201 sebagai proses utama container server. Jangan mematikannya dan jangan me-restart-nya.

**Langkah**

1. Setelah attach W5, jalankan iperf3 ke `` `<IP-SGi>` ``: DL (`iperf3 -R`) dan UL, masing-masing 3 kali 30 detik. Prosedur dan server sama dengan baseline W0.
2. Bandingkan tiap ulangan dengan AMBR yang di-provision dan dengan tiga angka baseline W0 pada arah yang sama.
3. Bila angka tidak turun mengikuti AMBR, periksa ulang bahwa W5 memuat nilai baru. Lalu tanyakan ke Lab Ops/Architect titik enforcement (UPF Open5GS v2.8 atau eNB).

**Hasil yang diharapkan**

- Throughput tiap arah ≤ AMBR arah itu ditambah 10%, dan jelas lebih rendah daripada baseline W0 pada arah yang sama.
- Untuk contoh DL 5 Mbps / UL 2 Mbps, batas 10% adalah DL 5,5 Mbps dan UL 2,2 Mbps. Batas dihitung dari AMBR yang benar-benar di-provision, bukan dari contoh bila nilainya berbeda.
- Bila throughput tidak ter-cap tetapi W5 benar, hasil W6 = keterbatasan enforcement EPC (fase 2). Dashboard dan provision tidak ditandai gagal karena hal itu.

**Bukti yang wajib**

- Enam angka (3 DL, 3 UL), durasi 30 detik, label RAN/UE NYATA, dibandingkan dengan baseline W0 dan dengan AMBR.
- Catatan jawaban Lab Ops/Architect tentang titik enforcement, bila cap tidak terjadi.
- Server hanya tertulis sebagai `` `<IP-SGi>` ``.

### W7 — Kembalikan profil

- **Level:** LAB-CORE.
- **Blocking:** blocking (fase 1).

**Langkah**

1. Lewat web, sebagai `` `<akun-student-uji>` ``, kembalikan profil `` `<IMSI-UE-SRS>` `` ke nilai semula (nilai sebelum W2).
2. Provision perubahan balik itu.
3. Ulangi readback seperti W4: API, Mongo, `drift`, dan hash sub-dokumen keamanan hanya atas `k`, `opc`, dan `amf` (`sqn` dikecualikan; alasan di W0).

**Hasil yang diharapkan**

- API dan Mongo memuat nilai semula. `drift=false`.
- Hash atas `k`, `opc`, dan `amf` tetap identik dengan W0.
- Respons readback tetap tanpa bidang keamanan, Ki, atau OPc.

**Bukti yang wajib**

- Respons provision balik dan readback tersunting.
- Digest W7 di samping digest W0, keduanya atas `k`, `opc`, dan `amf` saja. Keduanya sama.
- Tidak ada pemulihan lewat pengembalian dump basis data pada kasus ini.

### W8 — Regresi

- **Level:** LAB-CORE.
- **Blocking:** lulus W8 tidak menambah klausul GO. FAIL adalah **blocking fase 1** bila `/api/core/status` bukan 200 dengan cookie yang sah, atau bila MME, SMF, atau UPF restart: itu menghentikan dashboard atau merusak EPC, sehingga bukan catatan fase 2.

**Langkah**

1. Dengan cookie sesi yang masih sah, panggil `/api/core/status`.
2. Catat apakah proses MME, SMF, dan UPF tetap berjalan sejak awal W3, tanpa restart.

**Hasil yang diharapkan**

- `/api/core/status` menghasilkan 200 bila cookie ada.
- EPC tetap naik. MME, SMF, dan UPF tidak restart selama smoke ini.

**Bukti yang wajib**

- Status HTTP 200 beserta cap waktu WIB, tanpa badan yang memuat rahasia.
- Catatan waktu proses atau log yang menunjukkan MME, SMF, dan UPF tidak restart. Identitas host disunting.

## 4. Kriteria GO / NO-GO

Hanya status **PASS** yang masuk hitungan. BLOCKED dan FAIL bukan PASS.

| Keputusan | Syarat |
| --- | --- |
| GO | W0, W1, W2 (ubah nilai dan validasi), W3, W4, W5, dan W7 PASS. |
| GO dengan catatan fase 2 | Syarat GO terpenuhi, dan W6 gagal hanya karena tidak ada enforcement laju sementara sinyal W5 benar. Ini keterbatasan EPC, bukan bug dashboard. |
| NO-GO | Salah satu dari W0, W1, W2 (ubah nilai atau validasi yang sampai menulis ke Mongo), W3, W4, W5, atau W7 bukan PASS. |

403 lintas grup yang belum tersedia, sementara IMSI di grup sendiri tetap terisolasi dari tulis yang salah, tidak membatalkan GO. Catat sebagai fase 2.

W8 tidak termasuk syarat GO di atas. Kegagalan W8 yang membuat dashboard berhenti atau EPC restart tetap blocking fase 1 dan dilaporkan bersama keputusan, karena gerbang rilis fase 1 di [TEST-PLAN-gate-A-F.md](TEST-PLAN-gate-A-F.md) mencakup dashboard hidup dan `/api/core/status`.

Baseline iperf3 W0 sudah tercatat (10 Nov 2026, 17:38 WIB). W1–W8 belum dijalankan. Jangan mengisi GO sebelum bukti W0–W7 lengkap.

## 5. Aturan keselamatan

- Yang diubah hanya IMSI uji `` `<IMSI-UE-SRS>` `` lewat akun `` `<akun-student-uji>` ``.
- Data keamanan (Ki/OPc) diisi Lab Ops di luar dashboard. Uji web tidak menulis ulang sub-dokumen itu. Hash W0, W4, dan W7 dihitung hanya atas `k`, `opc`, dan `amf` (`sqn` dikecualikan) dan harus sama.
- Cadangan Mongo sebelum uji disimpan di luar repo. Pemulihan profil pada smoke ini dilakukan lewat web (W7).
- Jangan menjalankan `mongorestore --drop`.
- Jangan mengubah indeks Mongo secara manual.
- Sunting IMSI dan alamat IP pada setiap bukti (log, pcap, tangkapan layar, komentar) sebelum bukti dibagikan. Di teks yang dibagikan, pakai `` `<IMSI-UE-SRS>` ``, `` `<IP-SGi>` ``, dan `` `<akun-student-uji>` ``.
- Jangan menaruh kata sandi, cookie, token, Ki, atau OPc di repo atau di komentar PR.
- Perubahan di lab hanya atas arahan Lab Ops, dan hanya pada IMSI uji.

## 6. Jejak

Disusun mengikuti keputusan Netdrive 10 Nov 2026, 17:21 WIB. Hash sub-dokumen keamanan (hanya `k`, `opc`, dan `amf`) serta angka baseline iperf3 W0 mengikuti temuan Lab Ops 10 Nov 2026, 17:38 WIB. Ditautkan dari cakupan fase 1 di [TEST-PLAN-gate-A-F.md](TEST-PLAN-gate-A-F.md). W1–W8 belum dijalankan. Keputusan GO/NO-GO menunggu bukti dan keputusan Netdrive. Dokumen ini tidak di-merge sebagai pernyataan lulus.
