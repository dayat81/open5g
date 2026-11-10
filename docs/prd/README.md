# docs/prd — Product requirements export

Export Markdown dari PRD Page **v0.6** untuk repo [dayat81/open5g](https://github.com/dayat81/open5g).

| File | Isi |
|---|---|
| [PRD-v0.6.md](./PRD-v0.6.md) | PRD current (D3 konteks diklarifikasi) |
| [ROADMAP.md](./ROADMAP.md) | Gates A–F; Gate B = SgNB terpisah |
| [DECISIONS.md](./DECISIONS.md) | D0–D3 (D3 = keputusan produk Hidayat langsung ke PM) |
| [RISKS.md](./RISKS.md) | Risk register |
| [gate-b/OAI-GO-NOGO-TEST-PLAN.md](./gate-b/OAI-GO-NOGO-TEST-PLAN.md) | Rencana uji go/no-go Gate B. Keputusan stack OAI (D4, 10 Nov 2026). Bukan hasil lab |

**Source Page:** https://cursor.com/canvas/store-e072d755-cec8-43ee-b21b-75b859f13c7c/a248bcce-b7e8-40aa-ad8e-839a25cab7a8  

**Baseline:** v0.2 approved · **Current:** v0.6 · **Date:** 6 Nov 2026 (Asia/Bangkok)

Gate B stack: **keputusan Netdrive 10 Nov 2026 WIB (D4)** — OAI eNB + OAI en-gNB terpisah, tag `2026.w43`. Badan PRD v0.6 masih menulis "rekomendasi" karena dibekukan 6 Nov. Lihat [DECISIONS.md](./DECISIONS.md), [ROADMAP.md](./ROADMAP.md), dan [rencana uji](./gate-b/OAI-GO-NOGO-TEST-PLAN.md). Bukan gate baru.

`PRD-v0.5.md` / `PRD-v0.4.md` dihapus (digantikan).

**Sanitasi:** tidak memuat password, token, private key, material autentikasi subscriber aktual, atau IMSI penuh. IP lab internal boleh ada di Page; export ringkas v0.6 mungkin tidak mengulang semua IP.
