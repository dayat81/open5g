# RISKS.md — Risk register

Sumber: PRD v0.6 §8 + plan NA + `sgnb-feasibility.md`. Likelihood/Impact numerik n/a di PRD.

| ID | Description | Likelihood | Impact | Mitigation | Status | Source |
|---|---|---|---|---|---|---|
| R-01 | Native Gx Usage-Monitoring butuh patch; stock URR → Gy | n/a | Blokir klaim Gx usage | eBPF/out-of-band; Gate F | FACT / PLANNED | plan NA; PRD |
| R-02 | URR per-PDR bukan per-app | n/a | n/a | eBPF counters; SDF bridge later | FACT | plan NA; PRD |
| R-03 | Tidak ada mongo→RAR; rekomendasi PCRF admin-trigger; gaps QCI/ARP-on-existing & APN-AMBR | n/a | Tinggi untuk D1 | UI reject unsupported; evidence-chain | FACT + PROPOSAL; untested | plan NA §4; PRD |
| R-04 | Hostname/SNI bukan IPFilterRule native | n/a | n/a | eBPF + SDF bridge | FACT | PRD |
| R-05 | ECH/QUIC/DoH | n/a | Misclassification | Fail-open | Known limit | PRD |
| R-06 | Multi-APN / srsUE multi-PDN UNKNOWN | n/a | Delay Gate A | PoC lab5g-dev | PLANNED / UNKNOWN | PRD |
| R-07 | Resource / agen disk | n/a | Capacity | Kuota; lab5g-dev | RUNNING | PRD |
| R-08 | Kernel/BTF / UE attach UNKNOWN | n/a | Blokir eBPF | Tunggu Gate A | UNKNOWN / BUILD | PRD |
| R-09 | 5GC Opt 7/4 tidak ada di OSS | n/a | Stretch | MVP EPC + Opt 3x | FACT / stretch | PRD |
| R-10 | SGi egress kebijakan UNKNOWN | n/a | Internet path | Test server internal | UNKNOWN | PRD |
| R-11 | Prometheus/Grafana belum ada | n/a | Observability | docker logs + API | UNKNOWN | PRD |
| R-12 | Gate B D3: SgNB terpisah wajib. **REKOMENDASI NA (pending approval Hidayat via PM):** OAI eNB + separate OAI en-gNB over X2AP tag **2026.w43** on lab5g-dev; X2AP SCTP **36422**; S1-U SGW-U→en-gNB after E-RAB Modification. Open5GS 2.8.0 core OK, no patch expected. **Risk:** OAI EN-DC UE over rfsim UNKNOWN — **5–8 day spike = go/no-go**. Fallback Amarisoft Callbox+UEsim. Jangan rebuild sebelum approval | n/a | Tinggi untuk Gate B / jadwal | UE spike dulu; approval Hidayat via PM; bukti X2 SgNB Addition + E-RAB ModInd/Confirm + TEID baru | PLANNED / recommendation pending approval | D3; sgnb-feasibility.md NA 6 Nov 2026; PRD v0.6 |
