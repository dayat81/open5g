# Arsitektur lab5g-dev saat ini — 11 Nov 2026 16:20 WIB

Status dokumen: 11 Nov 2026 16:20 WIB. Diagram pertama tetap topologi 10 Nov 2026 17:25 WIB; port dashboard di kedua diagram adalah `127.0.0.1:3300`.

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
    WEB["dashboard-web (Next.js)<br/>127.0.0.1:3300"]
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
- **Dashboard:** web di `127.0.0.1:3300` (PR #7 @ 519cd61). `127.0.0.1:3000` adalah Grafana.
- **Subnet yang tercatat:** s1mme `10.99.1.0/24`, s1u `10.99.2.0/24`, x2 `10.99.12.0/24`, rfsim `10.99.13.0/24` (tidak aktif). Subnet lain belum tercatat lengkap di inventori.

## Android UE emulator dan egress SOCKS (PR #12 @ c8d3455)

```mermaid
flowchart LR
  subgraph LAPTOP["Laptop operator (WSL, internet, tanpa VPN kantor)"]
    SOCKS["ssh client<br/>reverse dynamic SOCKS"]
  end
  AGEN["host agen<br/>(SSH jump saja)"]
  subgraph GUEST["Guest lab5g-dev (tanpa internet langsung)"]
    subgraph RAN["RAN srsRAN 4G (ZMQ)"]
      ENB["srsENB stok l5gd-enb"]
      UE["srsUE stok l5gd-ue"]
      ENB1["srsENB l5gd-enb1"]
      subgraph NS["netns bersama ue1"]
        UE1["srsUE ue1<br/>tun_srsue = UE1_ADDR/32"]
        AND["Android emulator api-33<br/>DNS = PGW DNS<br/>adb connect UE1_UU:5555"]
      end
    end
    subgraph EPC["Open5GS v2.8.0 EPC CUPS"]
      MME["MME"]
      HSS["HSS"]
      PCRF["PCRF"]
      SGWC["SGW-C"]
      SMF["SMF/PGW-C"]
      SGWU["SGW-U"]
      UPF["UPF/PGW-U<br/>ip rule hanya UE1/32<br/>tanpa route /32 di netns"]
      MDB[("MongoDB<br/>index imsi_1")]
    end
    subgraph DASH["Dashboard (PR #7 @ 519cd61)"]
      WEB["web 127.0.0.1:3300<br/>login/profil, RBAC, CSRF"]
      API["backend<br/>slicing APN/PCC"]
      PG[("Postgres<br/>users, assignment, audit")]
      GUI["PR #13 GUI emulator (rencana)<br/>ws-scrcpy di alamat uu<br/>127.0.0.1:3301, flag OFF"]
    end
    subgraph EGR["Network egress --internal"]
      CGNAT["cgnat<br/>/opt/cgnat + /etc/cgnat (ro)<br/>nft: src pool UE, TCP 80/443<br/>bogon drop, rate limit, DNAT DNS"]
      SIDE["sidecar egress<br/>tun2socks + CoreDNS (TCP)"]
      GW["GW_IP:1080<br/>hanya dari CGNAT_IP"]
    end
  end
  INET(("Internet<br/>IP publik = laptop"))

  UE <-->|Uu ZMQ| ENB
  UE1 <-->|Uu ZMQ| ENB1
  AND -.- UE1
  ENB -->|S1-MME| MME
  ENB1 -->|S1-MME| MME
  ENB -->|S1-U| SGWU
  ENB1 -->|S1-U via up.sh| SGWU
  MME -->|S6a| HSS
  MME -->|S11| SGWC
  SGWC -->|S5-C| SMF
  SGWC -->|Sxa| SGWU
  SMF -->|Sxb| UPF
  SMF -->|Gx| PCRF
  SGWU -->|S5-U| UPF
  HSS --- MDB
  PCRF --- MDB
  WEB --> API
  WEB -.->|flag OFF| GUI
  API --> PG
  API -->|provision/rollback IMSI uji| MDB
  UPF -.->|SGi UE1| CGNAT
  CGNAT -.-> SIDE
  SIDE -.-> GW
  GW -.->|ssh -R| AGEN
  AGEN -.-> SOCKS
  SOCKS -.-> INET
```

- Core tidak berubah. Dashboard web sudah ter-deploy di `127.0.0.1:3300` (PR #7 @ 519cd61). `127.0.0.1:3000` adalah Grafana.
- Emulator memakai netns bersama ue1, sehingga semua trafik termasuk DNS lewat tun_srsue lalu EPC.
- adb tidak lagi dipublish di port host 15551. Dari guest: `adb connect <UE1_UU>:5555`. Dari luar guest: `ssh -L`, karena `uu` adalah jaringan internal.
- Route S1-U enb1 menuju SGW-U GTP-U dipasang oleh `up.sh` di netns enb1, pola yang sama dengan lab-routes untuk l5gd-enb. Tidak ada route /32 di netns UPF.
- Skrip cgnat ada di `/opt/cgnat` (ro), konfig di `/etc/cgnat` (ro).
- Jalur internet hanya untuk UE1 /32 lewat ip rule di UPF, lalu cgnat, tun2socks, dan tunnel SOCKS ke laptop operator. Jalur ini fail-closed dan hanya aktif dalam jendela uji yang disetujui Netdrive.
- PR #12 belum di-merge.
- PR #13 (rencana, flag OFF, belum aktif): GUI emulator di dashboard. Sidecar ws-scrcpy di alamat `uu`. Proxy WebSocket di belakang login dan RBAC: user = UE sendiri, instructor = grupnya, admin = semua. Origin layar terpisah `127.0.0.1:3301`.
