# DECISIONS.md — Decision log

Tanggal zona Asia/Bangkok (WIB / UTC+7). Sumber: PRD v0.6 Page.

| ID | Keputusan | Sumber | Tanggal | Status di PRD Page | Implikasi |
|---|---|---|---|---|---|
| D0 | PRD v0.2 Disetujui sebagai baseline | Hidayat "prd approved" via Project Manager bot | 6 Nov 2026 19:40 WIB | Ya | Perubahan lewat versi baru |
| D1 | Profile apply segera via PCRF-initiated Gx RAR ("seperti standar telco"). Re-attach hanya fallback | Hidayat: "rar, seperti standart telco", via PM; refinement Software Architect | 6 Nov 2026 19:40 WIB | Ya (v0.3+) — FR-16 | R-03 = delivery risk mekanisme |
| D2 | Instructor boleh edit DAN apply IMSI student dalam grup sendiri saja; audit actor+owner; lintas grup = 403 | Hidayat: "bole", via PM | 6 Nov 2026 19:41 WIB | Ya (v0.3+) — FR-17 | Model grup |
| D3 | Gate B EN-DC: wajib **SgNB / en-gNB TERPISAH** (X2 SgNB Addition + S1AP E-RAB Modification Indication/Confirm + S1-U TEID baru di gNB). Hasil **integrated srsENB LTE+NR** = **achieved-but-not-accepted** | **Keputusan produk Hidayat:** berkata "harus sgnb" **langsung** ke Project Manager bot pada 6 Nov 2026, menjawab laporan PM bahwa Gate B lulus kecuali S1AP E-RAB Modification karena eNB dan NR cell berjalan integrated dalam satu proses. Di-relay PM → Network Architect 20:13 WIB; dikonfirmasi Network Architect → PM 20:22 WIB | 6 Nov 2026 | Ya (v0.5; konteks diklarifikasi v0.6) — FR-15, Gate B, R-12 | Bentuk stack diisi D4. Integrated tetap achieved-but-not-accepted |
| D4 | Stack RAN Gate B = **OAI eNB** (`lte-softmodem`) + **OAI en-gNB** (`nr-softmodem --nsa`) sebagai proses terpisah, tag **`2026.w43`**, X2AP SCTP **36422**, hanya di lab5g-dev. Core tetap Open5GS v2.8.0 EPC CUPS tanpa patch (asumsi; titik gagal diuji). Fallback Amarisoft tetap tercatat di PRD; biaya fallback bukan bagian dari keputusan ini | **Keputusan Netdrive**, 10 Nov 2026 WIB. Menutup rekomendasi NA 6 Nov 2026 yang sebelumnya menunggu approval | 10 Nov 2026 | Belum masuk badan PRD v0.6 (teks v0.6 dibekukan 6 Nov dan masih menulis "rekomendasi") | Rencana uji: [gate-b/OAI-GO-NOGO-TEST-PLAN.md](./gate-b/OAI-GO-NOGO-TEST-PLAN.md). Bukan gate baru. Tidak ada rebuild sebelum PR rencana itu di-approve. `lab5g-vm` tidak disentuh |


## Open items (not decisions)

Butir stack Gate B yang dulu berstatus rekomendasi NA ditutup oleh D4.

Pertanyaan yang masih terbuka (ukuran guest, snapshot, subnet rfsim, biaya OTA, patch bila hipotesis MME gagal) ada di rencana uji §8. Itu belum menjadi keputusan.

| Item | Status | Sumber |
|---|---|---|
| Gate B RAN stack: OAI eNB + OAI en-gNB terpisah, X2AP, tag 2026.w43 | **Diputuskan (D4).** Bukan lagi rekomendasi | Netdrive, 10 Nov 2026 WIB |
