# PRD Lab 5G NSA — Dashboard Slicing Core (v0.6)

| Field | Value |
|---|---|
| Source Page | https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/a248bcce-b7e8-40aa-ad8e-839a25cab7a8 |
| Version | v0.6 (current) |
| Baseline | v0.2 Disetujui sebagai baseline |
| Date | 6 Nov 2026 (Asia/Bangkok, UTC+7) |
| Language | Bahasa Indonesia (istilah teknis tetap EN) |

**Status:** Baseline v0.2 + D1–D3 tetap. **v0.6** mengklarifikasi D3: keputusan produk Hidayat — berkata **harus sgnb** langsung ke Project Manager bot (6 Nov 2026) setelah laporan bahwa Gate B lulus kecuali S1AP E-RAB Modification karena eNB dan NR cell integrated dalam satu proses; di-relay PM → Network Architect (20:13 WIB); dikonfirmasi Network Architect → PM (20:22 WIB). Perubahan berikutnya = v0.7+.

---

## Konteks lab

| Label | Value |
|---|---|
| Host | agen (10.17.7.160) |
| Lab live | lab5g-vm — READ-ONLY |
| Lab dev | lab5g-dev (172.22.20.21) — satu-satunya target tulis |
| EN-DC | WAJIB. Integrated srsENB LTE+NR = achieved-but-not-accepted untuk Gate B. Target: SgNB/en-gNB terpisah + X2 SgNB Addition. Stack TBD |
| Stack dashboard | Next.js + FastAPI + PostgreSQL |
| Repo | github.com/dayat81/open5g |

## 1–3. Masalah, persona, scope

Sama v0.5: dashboard multi-user self-service PCRF/IMSI + observability core EPC CUPS di lab5g-dev; EN-DC option 3x dengan **SgNB terpisah** (D3); non-goals termasuk write ke lab5g-vm dan klaim Gate B dari integrated cell.

Persona: Admin / Instructor (edit+apply dalam grup, D2) / Student.

## 4. User stories

US-01…US-09 sama v0.5 (immediate apply via Gx RAR; instructor in-group; 403 lintas grup).

## 5. Functional requirements (ringkas perubahan)

FR-01…FR-14, FR-16, FR-17 sama v0.5.

**FR-15 (D3):** EN-DC option 3x di lab5g-dev. Acceptance Gate B: en-gNB/SgNB **TERPISAH**; X2 SgNB Addition; S1AP E-RAB Modification Indication/Confirm; S1-U ke gNB dengan TEID baru. Integrated srsENB LTE+NR (attach + NR SCG + data NR + S1-U verified) = **achieved-but-not-accepted** karena tidak menghasilkan E-RAB Modification (eNB+NR satu proses). Sumber: keputusan produk Hidayat "harus sgnb" langsung ke PM bot; relay/confirm NA.

**FR-16:** Immediate apply via Gx RAR; active ≠ RAA 2001 saja; QCI/ARP-on-existing & APN-AMBR stock unsupported → UI reject sampai patch.

## 6–8. NFR, metrics, risks

NFR-LAB-01..03: lab5g-dev only. Lihat [RISKS.md](./RISKS.md) — R-12 mencakup stack TBD / X2AP / MME E-RAB Mod / rebuild.

## 9. Milestones

Lihat [ROADMAP.md](./ROADMAP.md). Gate B exit = SgNB terpisah (D3).

## 10–11. Backlog & open questions

**Gate B stack (D3) — REKOMENDASI NA (bukan keputusan; menunggu approval Hidayat via PM):** OAI eNB + separate OAI en-gNB over X2AP (tag **2026.w43**) di lab5g-dev; X2AP over SCTP **36422**; S1-U SGW-U → en-gNB after E-RAB Modification. Open5GS 2.8.0 core side OK, no patch expected. Go/no-go: OAI EN-DC UE over rfsim spike **5–8 hari** (UNKNOWN). Fallback: Amarisoft Callbox + UEsim. Sumber: `sgnb-feasibility.md`, NA 6 Nov 2026.


## 12. Decisions log

Lihat [DECISIONS.md](./DECISIONS.md).

| ID | Inti | Sumber |
|---|---|---|
| D0 | Baseline v0.2 approved | Hidayat via PM 19:40 WIB |
| D1 | Immediate Gx RAR apply | Hidayat "rar, seperti standart telco" via PM 19:40 WIB |
| D2 | Instructor in-group edit+apply | Hidayat "bole" via PM 19:41 WIB |
| D3 | Gate B wajib SgNB terpisah; integrated = achieved-but-not-accepted | **Hidayat "harus sgnb" langsung ke PM bot** (menanggapi laporan Gate B minus E-RAB Mod karena cell integrated); relay PM→NA 20:13 WIB; NA→PM confirm 20:22 WIB |

## 13. Changelog

| Versi | Perubahan |
|---|---|
| v0.6 | Klarifikasi D3 + (catatan lanjut) rekomendasi stack Gate B NA OAI eNB+en-gNB X2AP 2026.w43 pending approval Hidayat via PM; UE rfsim spike 5–8 hari go/no-go; fallback Amarisoft |
| v0.5 | D3 dikunci; FR-15/Gate B/R-12 |
| v0.4 | Plan NA final; gates A–F |
| v0.3 | D1+D2 |
| v0.2 | Baseline approved |
| v0.1 | Draf pertama |
