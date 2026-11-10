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
| R-12 | Gate B D3: SgNB terpisah wajib. **Update 10 Nov 2026:** stack OAI eNB + OAI en-gNB terpisah, tag 2026.w43, adalah **keputusan Netdrive (D4)**, bukan lagi rekomendasi yang menunggu approval. X2AP SCTP 36422; S1-U SGW-U→en-gNB setelah E-RAB Modification. Core Open5GS 2.8.0 tanpa patch = asumsi. Sisa risiko teknis di R-13–R-22. Jangan rebuild sebelum PR rencana uji di-approve | n/a | Tinggi untuk Gate B / jadwal | Rencana uji go/no-go; bukti X2 SgNB Addition + E-RAB ModInd/Confirm + TEID baru | Stack DECIDED (D4); eksekusi belum | D3; D4; rencana uji 10 Nov 2026; PRD v0.6 |
| R-13 | EN-DC rfsim OAI belum stabil. FEATURE_SET pada commit `cfee4c20` (`2026.w43`): NSA gNB "unstable", satu UE. Jalur nrUE/lteUE EN-DC rfsim tidak tertulis = UNKNOWN | n/a | NO-GO Gate B | Spike terbatas; henti dini; tidak ada OTA sebelum GO rfsim | OPEN / UNKNOWN | Rencana uji §2.4 |
| R-14 | Versi eNB, en-gNB, dan UE tidak satu commit (`develop`, `latest`, `2026.w44`, atau `v3.0.0` tercampur) | n/a | X2/RRC gagal karena skew | Pin commit `cfee4c20` dan digest amd64 di rencana uji | OPEN | Rencana uji §2.4 |
| R-15 | MME pada image lab `gradiant/open5gs:2.8.0` tidak menangani E-RAB Modification Indication dari OAI (tidak ada Confirm, atau TEID tidak ke en-gNB). Sumber v2.8.0 punya handler; perilaku image belum diuji | n/a | NO-GO tanpa patch | T-B5. Jangan menambal diam-diam | HIPOTESIS | Rencana uji H1 |
| R-16 | PFCP Session Modification SGW-C→SGW-U tidak memindahkan F-TEID downlink ke en-gNB | n/a | S1-U tetap di eNB; Option 3x gagal | T-B6 dan T-B7 | HIPOTESIS | Rencana uji H2 |
| R-17 | Rekonsiliasi capability UE EN-DC/DCNR di HSS/MME menolak NR sebagai secondary RAT | n/a | Attach LTE tanpa SgNB Addition | Subscriber uji di lab. Nilai `access_restriction_data=32` dari uji integrated bukan bukti | HIPOTESIS | Rencana uji H3 |
| R-18 | 8 vCPU non-RT (Xeon Gold 6140, 1 thread/core), RAM 15 GiB, kernel generic: eNB + en-gNB + UE rfsim berjalan di atas EPC yang sudah resident | n/a | Spike tidak konklusif | Bandwidth LTE 5/10 MHz dan NR 20/40 MHz; srsRAN mati; pinning; resize 16 vCPU / 32 GiB hanya bila Netdrive setuju | OPEN | Inventori Lab Ops 10 Nov 2026 15:12 WIB |
| R-19 | Disk `/` 38 GiB dengan 22 GiB kosong; `/var/lib/docker` satu partisi dengan root. Build source OAI tidak diukur | n/a | Pull/build menggeser stack yang jalan | Utamakan image terpin (~571 MiB size API). Stop bila sisa akan turun di bawah 8 GiB | OPEN | Inventori Lab Ops 10 Nov 2026 |
| R-20 | Drift `main` (`d0d4bc4`, tanpa `infra/`) dan `master` (`3af0834`, dengan `infra/`, PR #5) | n/a | Eksekusi dari pohon yang salah | PR rencana uji dan eksekusi menyasar `master` | FACT | Inventori Lab Ops 10 Nov 2026 |
| R-21 | Spike Gate B menggeser prioritas tim #1: integrasi dashboard ↔ lab5g-dev, yang tetap didahulukan | n/a | Dashboard tertunda | Dashboard mengambil jendela lebih dulu. Spike hanya di sisa jendela. Bukan gate baru | CONSTRAINT | Arahan rencana uji 10 Nov 2026 |
| R-22 | Baseline live bukan Gate A: `l5gd-smf` EXITED sejak 6 Nov 2026 21:12 WIB, state PoC slicing, UE hanya siklus RRC | n/a | Uji OAI tidak sah | Hari 0 memulihkan attach + ping SGi sebelum OAI start | FACT | Inventori live Lab Ops 10 Nov 2026 15:10 WIB |
