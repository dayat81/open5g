# DECISIONS.md — Decision log

Tanggal zona Asia/Bangkok (WIB / UTC+7). Sumber: PRD v0.6 Page.

| ID | Keputusan | Sumber | Tanggal | Status di PRD Page | Implikasi |
|---|---|---|---|---|---|
| D0 | PRD v0.2 Disetujui sebagai baseline | Hidayat "prd approved" via Project Manager bot | 6 Nov 2026 19:40 WIB | Ya | Perubahan lewat versi baru |
| D1 | Profile apply segera via PCRF-initiated Gx RAR ("seperti standar telco"). Re-attach hanya fallback | Hidayat: "rar, seperti standart telco", via PM; refinement Software Architect | 6 Nov 2026 19:40 WIB | Ya (v0.3+) — FR-16 | R-03 = delivery risk mekanisme |
| D2 | Instructor boleh edit DAN apply IMSI student dalam grup sendiri saja; audit actor+owner; lintas grup = 403 | Hidayat: "bole", via PM | 6 Nov 2026 19:41 WIB | Ya (v0.3+) — FR-17 | Model grup |
| D3 | Gate B EN-DC: wajib **SgNB / en-gNB TERPISAH** (X2 SgNB Addition + S1AP E-RAB Modification Indication/Confirm + S1-U TEID baru di gNB). Hasil **integrated srsENB LTE+NR** = **achieved-but-not-accepted** | **Keputusan produk Hidayat:** berkata "harus sgnb" **langsung** ke Project Manager bot pada 6 Nov 2026, menjawab laporan PM bahwa Gate B lulus kecuali S1AP E-RAB Modification karena eNB dan NR cell berjalan integrated dalam satu proses. Di-relay PM → Network Architect 20:13 WIB; dikonfirmasi Network Architect → PM 20:22 WIB | 6 Nov 2026 | Ya (v0.5; konteks diklarifikasi v0.6) — FR-15, Gate B, R-12 | Stack TBD; NA feasibility read-only; rekomendasi sebelum rebuild |


## Open items (not decisions)

| Item | Status | Sumber |
|---|---|---|
| Gate B RAN stack: OAI eNB + separate OAI en-gNB X2AP (2026.w43); UE rfsim spike 5–8 hari go/no-go; fallback Amarisoft | **Recommendation by Network Architect — pending approval by Hidayat via Project Manager** | `/workspace/sgnb-feasibility.md`, NA 6 Nov 2026 |
