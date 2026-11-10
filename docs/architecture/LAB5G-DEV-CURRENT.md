# Arsitektur lab5g-dev saat ini — 10 Nov 2026 17:25 WIB

Sumber: inventori Lab Ops (read-only, 15:10 WIB), evidence PR #7 (deploy dashboard @ d74db7c, 17:05 WIB) dan PR #8 (Gate B fase 1, 17:01–17:09 WIB). Tanpa secret; IP yang tidak terverifikasi tidak dicantumkan.

```mermaid
flowchart LR
  subgraph RAN["RAN: srsRAN 4G 25_10 (ZMQ, tanpa SDR)"]
    UE["l5gd-ue<br/>srsUE (LTE + NR)"]
    ENB["l5gd-enb<br/>srsENB + NR terintegrasi<br/>(EN-DC dalam satu proses)"]
    UE -- "ZMQ (Uu)" --- ENB
  end

  subgraph EPC["Core Open5GS 2.8.0 EPC CUPS"]
    MME["MME"]
    HSS["HSS"]
    PCRF["PCRF<br/>(image stok, tanpa patch RAR)"]
    SGWC["SGW-C"]
    SGWU["SGW-U"]
    SMF["SMF / PGW-C"]
    UPF["UPF / PGW-U<br/>+ UPF-A, UPF-B (PoC slicing)"]
    MONGO[("MongoDB 7.0<br/>tanpa auth (risiko diterima)")]
  end

  subgraph DASH["Dashboard (PR #7 @ d74db7c, deploy 17:05 WIB)"]
    WEB["dashboard-web (Next.js)<br/>127.0.0.1:3000"]
    API["dashboard-api (FastAPI)<br/>tidak dipublish"]
    PG[("Postgres<br/>intent / audit")]
  end

  SRV["server SGi (netshoot)<br/>+ cgnat / internet-up"]

  ENB -- "S1-MME SCTP 36412" --> MME
  ENB -- "S1-U GTP-U 2152" --> SGWU
  MME -- "S6a Diameter" --> HSS
  MME -- "S11 GTPv2-C 2123" --> SGWC
  SGWC -- "Sxa PFCP" --> SGWU
  SGWC -- "S5/S8-C" --> SMF
  SGWU -- "S5/S8-U" --> UPF
  SMF -- "Sxb PFCP" --> UPF
  SMF -- "Gx Diameter" --> PCRF
  HSS --- MONGO
  PCRF --- MONGO
  UPF -- "SGi" --> SRV

  WEB -- "network web + dashboard" --> API
  API --- PG
  API -- "network mgmt<br/>(akun dan IMSI uji saja)" --> MONGO
```

## Catatan
- **Status:** semua NF berjalan. SMF sempat mati sejak 6 Nov dan pulih di Day 0. Setelah srsRAN dipulihkan (17:09 WIB): attach berhasil, RRC NR reconfiguration berhasil, ping ke SGi 4/5.
- **Slicing:** berbasis APN/PCC lewat dashboard yang menulis ke Mongo, bukan S-NSSAI. Gx RAR masih dimatikan (`OPEN5G_ENABLE_GX_RAR=0`), jadi perubahan berlaku saat attach ulang.
- **Mongo:** risiko tanpa auth diterima Netdrive (10 Nov 15:49 WIB) selama jendela uji. Dashboard hanya memakai akun student dan IMSI uji, tanpa instructor dan tanpa seed.
- **Gate B:** OAI eNB/en-gNB 2026.w43 sempat diuji di rfsim (`10.99.13.0/24`) dan lulus S1 Setup serta EN-DC X2 Setup. Setelah itu dibongkar. OAI NO-GO; EN-DC penuh (X2 SgNB Addition, E-RAB Modification) masuk Fase 2.
- **Akses:** komputer Netdrive, lalu host agen, lalu guest lab5g-dev. Tidak ada port yang dipublish ke luar guest; lab5g-vm hanya baca.
- **Subnet yang tercatat:** s1mme `10.99.1.0/24`, s1u `10.99.2.0/24`, x2 `10.99.12.0/24`, rfsim `10.99.13.0/24` (tidak aktif). Subnet lain belum tercatat lengkap di inventori.
