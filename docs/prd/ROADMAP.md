# ROADMAP — Lab 5G NSA / Dashboard Slicing Core

Sumber: PRD v0.6 + Network Architect `plan-poc-slicing-core.md` §9 + D3 + `sgnb-feasibility.md`.  
Semua gate hanya di **lab5g-dev**. **lab5g-vm tidak diubah.**

| ID | Name | Goal | Exit criteria | Dependencies | Status | Date assumption? |
|---|---|---|---|---|---|---|
| M0 | PRD & desain | Mengunci lingkup | Baseline v0.2 + D1–D3 + plan NA | — | Done through v0.6 docs | No — 6 Nov 2026 |
| Gate A | Baseline LTE + multi-APN/SDF/URR | EPC CUPS hidup | LTE attach; dua APN→UPF(+SGW-U); SDF+URR; pcap T1–T2 | lab5g-dev | PLANNED / BUILD | Yes |
| Gate B | EN-DC Option 3x (**SgNB terpisah, D3**) | Dual connectivity dengan en-gNB terpisah | **X2 SgNB Addition**; S1AP E-RAB Modification Indication/Confirm; S1-U switched ke gNB dengan **TEID baru**. Integrated srsENB LTE+NR = **achieved-but-not-accepted** (tidak ada E-RAB Mod karena eNB+NR satu proses; D3 = keputusan produk Hidayat "harus sgnb" langsung ke PM) | Gate A; **stack approval**; UE spike go/no-go | Integrated RUNNING (not accepted); separate-SgNB PLANNED; **stack recommendation pending approval** | Yes |
| Gate C | eBPF app detection | IP/DNS/SNI + counters | T3; BTF verified | Gate A | PLANNED; BTF UNKNOWN | Yes |
| Gate D | Live RAR | Immediate apply | PCRF admin-trigger; T4–T8; FR-16 evidence-chain | Gate A; R-03 | PLANNED | Yes |
| Gate E | Self-service dashboard | Multi-user GUI | API/RBAC/grup/audit; FR-16/17; T10 | M0 | PLANNED | Yes |
| Gate F | Usage lanjut | Per-app usage | SDF bridge; Gx usage hanya dengan patch R-01 | Gate C/D | Later | Yes |
| Stretch | 5GC / Option 7/4 | Bila tersedia | AMF/gNB terverifikasi | Verified stack | Stretch | Yes |

## Gate B — stack recommendation & go/no-go (NA, not decided)

Sumber: `/workspace/sgnb-feasibility.md`, Network Architect, 6 Nov 2026. **Bukan keputusan produk** — menunggu approval Hidayat via Project Manager bot. Jangan rebuild sebelum approval.

| Item | Isi |
|---|---|
| Recommendation | **OAI eNB (`lte-softmodem`) + separate OAI en-gNB (`nr-softmodem --nsa`)** over **X2AP**, tag **`2026.w43`**, on lab5g-dev |
| X2AP | SCTP port **36422** |
| User plane | S1-U **SGW-U → en-gNB** after E-RAB Modification |
| Core | Open5GS **2.8.0** supports path; **no patch expected** |
| Go/no-go step | Limited **OAI EN-DC UE over rfsim spike, 5–8 working days** (status UNKNOWN in docs/CI). If EPC-anchored sim path fails, stop before full RAN rebuild |
| Fallback | **Amarisoft Callbox + UEsim** (procurement/license; not free) |
| Not recommended | srsENB+OAI gNB X2 bridge (srsENB X2AP is dummy/direct calls) |
