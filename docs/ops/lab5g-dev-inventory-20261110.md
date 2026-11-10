# Inventaris lab5g-dev — 10 Nov 2026

Dokumen ini merangkum inventaris lab5g-dev (hanya lab tersebut; lab5g-vm di luar cakupan) menurut repo branch `master` (commit `3af0834`) dan pemeriksaan langsung di guest. Setiap temuan ditandai sumbernya: **dicek di lab**, **menurut repo**, atau keduanya.

Tidak ada alamat internal, secret, kunci, token, IMSI, Ki, atau OPc di dokumen ini. Nama yang dipakai adalah nama jaringan Docker, nama kontainer, atau variabel logis (contoh: `lab5g-dev_s11`, `core.server`).

Status lab setelah pemulihan ke baseline `master` pada 10 Nov 2026 15:31 WIB terdokumentasi di [runbook pemulihan](runbook-lab5g-dev-restore.md) dan [hasil smoke test](../evidence/lab5g-dev-restore-20261110/SUMMARY.md).

## 1. Perbandingan repo `master` vs kondisi live

| Aspek | Menurut repo (`master` / `3af0834`) | Dicek di lab |
|---|---|---|
| Stack core | Proyek Compose `lab5g-dev`: `l5gd-mongo` (`mongo:7.0`), `hss`, `pcrf`, `mme`, `sgwc`, `sgwu`, `smf`, `upf` (`gradiant/open5gs:2.8.0`), `server` (`netshoot`) | Sama, versi Open5GS **v2.8.0**, mongod **7.0.45** |
| RAN | Proyek `lab5g-dev-ran`: `l5gd-enb`, `l5gd-ue` (`gradiant/srsran-4g:25_10`, ZMQ) | Kontainer `enb` dan `ue` ada dan, setelah pemulihan, berstatus Up |
| Jaringan | Jaringan Docker internal (di antaranya `s1mme`, `s1u`, `s11`, `s5s8`, `pfcp`, `s6a`, `gx`, `sgi`, `mgmt`, plus jaringan UU RAN). Tidak ada port yang dipublish ke host | Dikonfirmasi: tidak ada port kontainer yang dipublish ke host |
| WebUI Open5GS | Tidak ada layanan WebUI di Compose lab | Tidak ada WebUI |
| Metrics Prometheus | Tidak ada blok `metrics` pada conf NF (terkait PRD R-11) | Tidak ada blok `metrics` di conf yang terpasang |
| PCRF admin-RAR | `lab/patches/pcrf-admin-rar*` berstatus DRAFT, belum di-compile, belum diuji; PCRF memakai image stok | PCRF memakai image stok + bind conf saja; patch **tidak terpasang** |
| Dashboard (FastAPI / Postgres / Next.js) | Tidak ada service Compose, role Ansible, atau Postgres di stack lab | Belum pernah jalan di lab5g-dev; rencana penempatan di host/Compose/role belum ada di `infra/` |
| Alat orkestrasi | `infra/`: `make up\|down\|verify\|lint\|render\|check\|secrets-check`; `site.yml` hanya mengizinkan lab5g-dev | Binary `docker-compose` v2.29.7 dipakai di guest; plugin `docker compose` tidak ada. Ansible tidak terpasang di laptop operator |
| Snapshot / rollback VM | Tidak ada mekanisme snapshot VM di repo; yang ada `lte-only-restore.sh` (RAN) dan `make down` | Dikonfirmasi: tidak ada mekanisme snapshot VM |

Pada 10 Nov 2026 15:10 WIB (pemeriksaan read-only, sebelum pemulihan), kondisi live **menyimpang** dari baseline `master`: lab berada di state PoC slicing (`upf-a`, `upf-b`, `cgnat`, override PoC). SMF mati sejak 6 Nov 21:12 WIB. Setelah pemulihan 10 Nov 15:15–15:31 WIB, lab kembali ke baseline (tanpa node PoC tersebut). Rincian ada di runbook.

## 2. Jawaban lima pertanyaan integrasi dashboard

Sumber: pemeriksaan langsung di lab pada 10 Nov 2026, dicocokkan dengan `lab/` dan `infra/` di `master`.

1. **Versi yang terpasang.** Open5GS **v2.8.0** EPC CUPS (image `gradiant/open5gs:2.8.0`). MongoDB: proses `mongod` **7.0.45** (image `mongo:7.0`). WebUI Open5GS **tidak aktif** (tidak ada di stack).
2. **Cara akses yang tersedia untuk dashboard.**
   - **MongoDB subscriber DB:** tanpa autentikasi, hanya terjangkau dari jaringan Docker internal `mgmt`. Tidak ada port yang dipublish ke host. Basis data logis: `open5gs` (variabel host logis `core.mongo`).
   - **WebUI API:** tidak ada.
   - **Endpoint metrics Prometheus per NF** (MME, HSS, PCRF, SGW-C, SGW-U, SMF, UPF): tidak dikonfigurasi.
   - **Log:** keluaran stdout kontainer (`docker logs` pada `l5gd-*`). Berkas pcap/CSV RAN berada di direktori temporer dalam kontainer `enb`/`ue`.
3. **Patch PCRF admin-RAR di lab:** **tidak terpasang**. Image PCRF stok; berkas patch di repo masih draft, belum di-compile, dan belum diuji.
4. **Apakah dashboard sudah pernah jalan di lab5g-dev:** **belum.** Tidak ada service Compose, role Ansible, atau basis data Postgres untuk dashboard di stack lab. Penempatan (host, Compose, atau role Ansible) belum dirinci di `infra/`.
5. **Kendala akses / jendela waktu.** Jalur operasi yang dipakai: laptop operator → host agen → guest (user lab). Plugin `docker compose` tidak ada di guest (pakai binary `docker-compose`). Ansible tidak terpasang di laptop operator. `infra/site.yml` tidak memuat `vault.yml`, dan `ansible.cfg` tidak mengatur vault password. Tidak ada mekanisme snapshot VM. Jendela maintenance tidak terdokumentasi di repo. Config contoh di repo tersanitasi, sehingga baseline `master` diterapkan memakai config guest yang terverifikasi sama dengan kondisi pra-PoC (bukan menempel mentah berkas contoh repo).

Untuk merancang jalur dashboard ke Mongo/metrics di jaringan `mgmt` yang internal, diperlukan keputusan dan persetujuan terpisah (perubahan jaringan atau publish port tidak termasuk dokumen ini).

## 3. Kapasitas guest untuk uji Gate B

Diukur langsung di guest lab5g-dev pada 10 Nov 2026 (read-only).

| Sumber daya | Nilai terukur |
|---|---|
| CPU | 8 vCPU, Xeon Gold 6140 |
| RAM | 15 GiB |
| Disk | 38G total, 22G kosong |
| Kernel | 6.8.0-136-generic, `PREEMPT_DYNAMIC`, **bukan** lowlatency |
| Docker | 27.5.1 |
| Compose | docker-compose v2.29.7 (binary `docker-compose`, bukan plugin) |
| SDR / GPSDO / UE COTS EN-DC | Tidak ada yang terpasang di guest |

**Subnet Docker untuk jaringan X2 baru:** pakai blok /24 berikutnya yang belum dipakai skema lab (lihat `lab/compose`). Jangan memakai kembali jaringan yang sudah didefinisikan di skema tersebut (termasuk `ran_uu` dan `mgmt`).

## 4. Catatan sisa setelah pemulihan (tidak diubah pada 10 Nov 2026)

Temuan ini dicatat agar tidak dianggap sudah dibereskan:

- UPF masih punya default route ke node `cgnat` yang sudah dihapus (sisa egress internet). Tidak memengaruhi SGi lokal (`core.server`).
- `docker-compose.override.dev.yml` (di repo dan di guest) me-mount `bin/open5gs-upfd` yang tidak ada di guest.

## 5. Rekomendasi operasional

- Role `verify` / `lab-up` harus selalu menjalankan `lab-routes.sh` setelah recreate NF mana pun (lihat runbook: rute `lab5g-dev_s11` hilang setelah SMF dibuat ulang).
- Ubah override PoC agar tidak mem-bind satu berkas ke dalam direktori yang di-mount read-only.
