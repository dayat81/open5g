# ROADMAP — Lab 5G NSA / Dashboard Slicing Core

Sumber: PRD v0.6 + Network Architect `plan-poc-slicing-core.md` §9 + D3 + `sgnb-feasibility.md`.  
Semua gate hanya di **lab5g-dev**. **lab5g-vm tidak diubah.**

| ID | Name | Goal | Exit criteria | Dependencies | Status | Date assumption? |
|---|---|---|---|---|---|---|
| M0 | PRD & desain | Mengunci lingkup | Baseline v0.2 + D1–D3 + plan NA | — | Done through v0.6 docs | No — 6 Nov 2026 |
| Gate A | Baseline LTE + multi-APN/SDF/URR | EPC CUPS hidup | LTE attach; dua APN→UPF(+SGW-U); SDF+URR; pcap T1–T2 | lab5g-dev | PLANNED / BUILD | Yes |
| Gate B | EN-DC Option 3x (**SgNB terpisah, D3**) | Dual connectivity dengan en-gNB terpisah | **X2 SgNB Addition**; S1AP E-RAB Modification Indication/Confirm; S1-U switched ke gNB dengan **TEID baru**. Integrated srsENB LTE+NR = **achieved-but-not-accepted** (tidak ada E-RAB Mod karena eNB+NR satu proses; D3 = keputusan produk Hidayat "harus sgnb" langsung ke PM) | Gate A; **D4**; rencana uji di-approve sebelum eksekusi | Integrated achieved-but-not-accepted; stack OAI **diputuskan D4** (10 Nov 2026); eksekusi menunggu approval [rencana uji](./gate-b/OAI-GO-NOGO-TEST-PLAN.md) | Yes |
| Gate C | eBPF app detection | IP/DNS/SNI + counters | T3; BTF verified | Gate A | PLANNED; BTF UNKNOWN | Yes |
| Gate D | Live RAR | Immediate apply | PCRF admin-trigger; T4–T8; FR-16 evidence-chain | Gate A; R-03 | PLANNED | Yes |
| Gate E | Self-service dashboard | Multi-user GUI | API/RBAC/grup/audit; FR-16/17; T10 | M0 | PLANNED | Yes |
| Gate F | Usage lanjut | Per-app usage | SDF bridge; Gx usage hanya dengan patch R-01 | Gate C/D | Later | Yes |
| Stretch | 5GC / Option 7/4 | Bila tersedia | AMF/gNB terverifikasi | Verified stack | Stretch | Yes |

## Gate B — stack decision & go/no-go

**Keputusan Netdrive, 10 Nov 2026 WIB (D4).** Bukan lagi rekomendasi yang menunggu approval. Badan PRD v0.6 (6 Nov) masih menulis "rekomendasi"; keputusan ada di [DECISIONS.md](./DECISIONS.md). Rencana uji: [gate-b/OAI-GO-NOGO-TEST-PLAN.md](./gate-b/OAI-GO-NOGO-TEST-PLAN.md). Jangan rebuild sebelum PR rencana itu di-approve. Bukan gate baru.

| Item | Isi |
|---|---|
| Keputusan | **OAI eNB (`lte-softmodem`) + OAI en-gNB terpisah (`nr-softmodem --nsa`)** over **X2AP**, tag **`2026.w43`**, commit `cfee4c20b45ac1cf6d455d3f01bb3e00200438b0`, di lab5g-dev |
| X2AP | SCTP port **36422**, jaringan baru `10.99.12.0/24` |
| User plane | S1-U **SGW-U → en-gNB** after E-RAB Modification, TEID baru |
| Core | Open5GS **2.8.0** tanpa patch (asumsi). Dukungan E-RAB Modification Indication, PFCP modify SGW-U, dan DCNR/HSS adalah hipotesis yang diuji |
| Go/no-go | Rfsim saja, Hari 0 (baseline Gate A) lalu maksimum 8 hari kerja. UE OAI mode EN-DC rfsim = **UNKNOWN** di dokumen tag. Henti dini sebelum rebuild RAN bila jalur itu gagal |
| Fallback | **Amarisoft Callbox + UEsim** tetap tercatat di PRD. Pemicu rekomendasi ada di rencana uji. Biaya = keputusan Netdrive, terpisah |
| Tidak dianjurkan | srsENB+OAI gNB sebagai jembatan X2 |
