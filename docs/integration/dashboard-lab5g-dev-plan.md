# Rencana integrasi dashboard ↔ lab5g-dev

Dokumen ini menyertai kode Phase 1 di cabang yang sama. Ini bukan bukti sesi UE, bukan hasil deploy, dan bukan izin menulis ke lab. Target tulis tetap lab5g-dev. lab5g-vm tetap read-only (`infra/site.yml` menolak host live).

Agen yang menulis dokumen ini tidak membuka SSH ke lab. Fakta yang disebut **live-verified** datang dari operator (10 Nov 2026) setelah inspeksi read-only. Fakta **repo** dicek di pohon `master`. Enum Open5GS dicek ke tag upstream `v2.8.0` lewat berkas publik; pohon ini tidak mengompilasi Open5GS.

## 1. Apa yang ada di kode

| Klaim | Sumber | Status |
|---|---|---|
| Dashboard menyimpan intent APN, QCI, ARP, AMBR, MBR/GBR, app rule di PostgreSQL | `dashboard/backend/src/open5g_dashboard/domain.py`, `dashboard/backend/migrations/001_init.sql` | Repo |
| Apply Gx langsung ditolak; RAA 2001 bukan Active | `domain.py` (`stock_immediate_apply`, `raa_ack_status`, `active_allowed`) | Repo |
| Seed subscriber Open5GS: `imsi`, `security.k/opc`, `ambr`, `slice[].session[]` (name, type 3, qos.index, arp, ambr), `schema_version` | `infra/roles/subscribers/templates/seed-subscriber.js.j2` | Repo |
| Image `gradiant/open5gs:2.8.0`, `mongo:7.0`; layanan mongo/hss/pcrf/mme/sgwc/sgwu/smf/upf; tidak ada service WebUI | `lab/compose/docker-compose.yml`, `infra/group_vars/all/versions.yml`, `infra/roles/open5gs_epc_cups/templates/docker-compose.yml.j2` | Repo |
| Mongo tanpa auth (`mongod --bind_ip_all`), hanya jaringan Compose `mgmt`, tidak di-publish | `lab/compose/docker-compose.yml` service `mongo` | Repo |
| Tidak ada blok `metrics` pada NF | `infra/roles/open5gs_epc_cups/templates/pcrf.yaml.j2` (dan template NF lain: hanya `db_uri` / freeDiameter) | Repo |
| Patch PCRF admin-RAR **DRAFT, NOT COMPILED, NOT TESTED** | `lab/patches/README.md`, `lab/patches/pcrf-admin-rar/README.md` | Repo |
| PCC dibaca dari Mongo pada CCR-I/U; Mongo tidak memicu RAR; APN-AMBR dan QCI/ARP default bearer tidak lewat RAR stock | `docs/capabilities.md` | Ekstrak upstream, tidak diuji ulang di lab pada run ini |
| Open5GS 2.8.0 dan MongoDB 7.0.45 hidup; jaringan Mongo live bernama `lab5g-dev_mgmt` (internal, tidak dipublish); tidak ada WebUI; tidak ada metrik NF; PCRF image stock | Laporan operator | **Live-verified. Agen ini tidak mengulang probe.** |
| Binary guest `docker-compose` v2.29.7 (standalone) | Laporan operator | **Live-verified** |
| Lab sedang menjalankan PoC slicing dua UPF (UPF-A / UPF-B) yang tidak sama dengan Compose `master` (satu `upf` + slice UPF Ansible `slice-a`/`slice-b`) | Laporan operator vs `lab/compose/docker-compose.yml` dan `infra/roles/open5gs_epc_cups/templates/docker-compose.yml.j2` | **Live drift. Nama persis kontainer tidak disalin ke kode.** |
| SMF sedang down | Laporan operator | **Live-verified. Bukan sesuatu yang dashboard hardcode.** |
| Dashboard belum pernah jalan di lab: tidak ada service Compose, role Ansible, atau Postgres di stack default | `infra/site.yml` (tidak memuat role dashboard), `lab/compose/docker-compose.yml` | Repo, konsisten dengan laporan operator |

Bitrate Open5GS: `unit` adalah pangkat 1000 (`lib/dbi/session.c` pada tag v2.8.0). Decoder hanya membaca BSON int32. ARP di dokumen subscriber memakai konstanta 5GC: disabled `1`, enabled `2` (`lib/proto/types.h`). HSS dan PCRF baru mengirim EPC enabled bila nilai tersimpan adalah `2` (`src/hss/hss-s6a-path.c`, `src/pcrf/pcrf-gx-path.c`). Seed lab memakai `1`/`1`, jadi stock memetakan keduanya ke disabled. `open5gs-dbctl` v2.8.0 tidak konsisten (add memakai vulnerability `2`, `update_apn` memakai `1`). Adapter menulis `2` hanya untuk `may_preempt` / `preemptable`.

Flow direction `3` = bidirectional pada header yang sama. Satu rule IP dashboard menjadi satu `pcc_rule.flow`. Apakah UPF lab memasang direction `3` tanpa filter lawan **belum diuji**.

Tutorial metrik upstream (dibaca 2026-11-10) menyebut exporter untuk AMF, MME, dan SMF. Lab ini EPC, tanpa AMF. HSS, PCRF, SGW, dan UPF **tidak diklaim** punya `/metrics`.

## 2. Divergensi `main` / `master`

- `master` pada penulisan ini: `3af083492de01f3baa0c2b8851cbf11157d7b7c4` (merge PR infra). Pohon ini punya `infra/`.
- `main` (`origin/main`): `d0d4bc4b68a79862ff0b15b3e30190ce460c514b`. Tidak punya `infra/`. GitHub default tetap `main`.
- `git diff --stat origin/main...master`: 64 berkas, seluruhnya penambahan IaC di bawah `infra/`.
- Integrasi ini bercabang dari `master` karena seed subscriber, Compose, dan vars lab ada di sana. Port ke `main` tanpa `infra/` akan kehilangan jalur provision Ansible.

## 3. Phase 1 — bisa disambungkan ke stock Open5GS 2.8

Tidak lewat WebUI. Compose dan role EPC tidak mendefinisikan WebUI, jadi tidak ada klien WebUI.

Adapter: `SubscriberPort` di `dashboard/backend/src/open5g_dashboard/subscriber_port.py`, pemetaan di `open5gs_schema.py`.

| Operasi | Perilaku |
|---|---|
| Baca | `GET /api/assignments/{id}/subscriber`. Proyeksi tanpa `security` / Ki / OPc. Semua session dikembalikan, termasuk APN UPF lain. |
| Tulis | `POST /api/profiles/{id}/provision` setelah draft `validated`, dengan CSRF dan `If-Match`. `$set` atomik hanya pada session yang namanya sama persis: QCI/ARP, AMBR session, dan `pcc_rule` yang menggabungkan flow IP. UE-AMBR dan `security` tidak ditulis. Hostname/SNI dan usage monitoring tidak ditulis. Dokumen baru tanpa seed ditolak. |
| Buat dokumen | Ditolak. Subscriber harus sudah di-seed (Ki/OPc tidak ditulis oleh dashboard). |
| Update | `$set` pada path session yang cocok, plus `open5g_dashboard.generation`. Filter generasi lama menghasilkan 409. Session lain dan `pcc_rule` asing tidak dihapus. Tidak ada rename diam-diam. Batas Open5GS 2.8.0: 8 PCC rule, 4 session per slice, 3 dedicated bearer. |
| Efek sesi | `live_gx_rar=false`, `session_effect=not_pushed_to_active_session`. Perubahan baru terbaca HSS/PCRF pada attach atau PDN reconnect berikutnya (`docs/capabilities.md`). Bukan sesi aktif. |
| Rollback | Lewat validasi, cap, dan audit yang sama dengan provision. Replay atau konflik idempotensi tidak menulis Mongo. Jika store down, respons 503 dan versi Postgres tidak berubah. |
| Konsistensi | Baris `subscriber_sync` mencatat pending lalu written/conflict/unavailable. `GET` subscriber membandingkan intent dengan session APN yang sama (`drift`). Seed Ansible `replaceOne` menimpa seluruh dokumen, termasuk QoS dashboard. |
| Authz | Sama dengan apply: student pemilik, instructor satu grup, admin ditolak (`domain.authorize`). |

NF: `GET /api/core/status` (`telemetry.py`). Butuh sesi. Tidak memakai Docker socket.

- `OPEN5G_METRICS_ENDPOINTS` dan `OPEN5G_HEALTH_ENDPOINTS` kosong → setiap NF `not_configured` (bukan error). Daftar statis memuat `upf`, `upf-a`, dan `upf-b` supaya dua UPF tidak diasumsikan hilang.
- URL terpasang dan scrape gagal (timeout, connect, HTTP non-200) → target itu `down`, target lain tetap. HTTP respons tetap 200.
- Probe Mongo terpisah (`mongo-subscriber`). Gagal = `down`, bukan 500.
- Nama metrik saja yang dikembalikan. Label, termasuk IMSI, dibuang.
- Timeout scrape default 2 detik, batas 0,2–10 detik. Timeout Mongo default 2000 ms, batas 200–10000.
- UI: `dashboard/frontend/src/components/CoreStatusPanel.tsx` di Overview. Demo tidak memanggil API. Mode API menampilkan `down` tanpa menggagalkan panel.

Contoh blok metrik yang **belum** dipasang di lab: `lab/config/examples/open5gs/metrics.yaml.example`. Memasangnya butuh perubahan lab terpisah dan persetujuan owner. Selama SMF down, verifikasi sesi end-to-end ditunda. Menyalakan SMF adalah perbaikan lab, bukan bagian PR ini.

### Kriteria terima Phase 1

1. Provision menulis QCI/APN/AMBR ke koleksi `subscribers` dan baca-balik sama, tanpa mengembalikan Ki/OPc.
2. Session kedua (UPF lain) tetap ada.
3. Apply Gx dan flag RAR tidak menghasilkan `pushed` atau `active`.
4. Status NF dengan SMF down dan UPF lain hidup mengembalikan 200 dan kedua keadaan itu.
5. URI/driver error tidak disalin ke respons.
6. `infra/site.yml` dan `lab/compose/docker-compose.yml` tidak berubah perilakunya. Role `infra/roles/dashboard_optional/` tidak dipanggil site.yml. Compose opsional hanya lewat berkas terpisah dan profile `dashboard`.

### Tes Phase 1

Dari `dashboard/backend` (Postgres lokal `open5g_test`, mongomock, HTTP metrik di-mock; tidak ada lab):

```bash
.venv/bin/pytest -q
```

Dari `dashboard/frontend`:

```bash
npm test
npm run lint
npm run typecheck
npm run build
```

eBPF tidak diubah, jadi `ebpf/scripts/check_build.py` tidak dijalankan.

## 4. Phase 2 — tertahan patch PCRF

Interface: `dashboard/backend/src/open5g_dashboard/policy_port.py`.

- Default `OPEN5G_ENABLE_GX_RAR=0` → `StockPolicyPort` → `stock_immediate_apply` (`rejected`, `executed=false`, path `gx_rar_immediate`).
- `=1` → `DraftAdminRarPort`. Tetap `rejected`, `executed=false`, path `gx_rar_admin_draft`, capability `draft_not_available`. `gx_rar_effective` di status selalu `false`.
- Tidak ada klien Unix socket `/run/open5gs-pcrf-admin.sock`. Patch di `lab/patches/pcrf-admin-rar/` tidak dikompilasi di sini. PCRF lab menjalankan image stock.

Yang tetap butuh patch plus bukti RAR/RAA dan bukti bearer/PFCP sebelum boleh disebut `pushed` atau `active`:

- push PCC ke sesi yang sudah ada
- ubah QCI/ARP bearer yang sudah ada
- APN-AMBR pada sesi aktif

MBR/GBR pada dedicated bearer disebut `unverified` di `domain.diff_operations`. Adapter Phase 1 hanya menyimpannya di `pcc_rule` untuk CCR berikutnya.

### Kriteria terima Phase 2 (nanti, bukan PR ini)

1. Patch terkompilasi, terpasang hanya di lab5g-dev, dan diuji.
2. Flag tetap default mati sampai bukti itu ada.
3. RAA 2001 saja tetap bukan Active (`domain.active_allowed`).
4. Tes menolak respons `pushed`/`active` bila bukti sesi tidak ada.

## 5. Konfigurasi — nama saja

Kosong = mati. Jangan mengisi host lab, Ki, OPc, IMSI, atau IMEI sungguhan.

| Nama | Fungsi | Tempat |
|---|---|---|
| `OPEN5G_DATABASE_URL` | Postgres dashboard | `.env.example` |
| `OPEN5G_SESSION_PEPPER` | Hash cookie sesi | `.env.example` |
| `OPEN5G_COOKIE_SECURE` | Flag cookie Secure | `.env.example` |
| `OPEN5G_ENABLE_DEMO_ROUTES` | Route sampel | `.env.example` |
| `OPEN5G_BOOTSTRAP_PASSWORD` / `OPEN5G_BOOTSTRAP_EMAIL` | Bootstrap admin satu kali | `.env.example` |
| `OPEN5G_MONGO_URI` | URI subscriber store; boleh userinfo dan `tls` | `.env.example`, `infra/.env.example`, `vault_open5gs_mongo_uri` |
| `OPEN5G_MONGO_DATABASE` | Default nama DB `open5gs` | env + `dashboard_mongo_database` |
| `OPEN5G_MONGO_COLLECTION` | Default `subscribers` | env + `dashboard_mongo_collection` |
| `OPEN5G_MONGO_TIMEOUT_MS` | Batas waktu driver | env + `dashboard_mongo_timeout_ms` |
| `OPEN5G_ENABLE_GX_RAR` | Flag Phase 2, default mati | env + `dashboard_enable_gx_rar` |
| `OPEN5G_METRICS_ENDPOINTS` | `nama=url` scrape Prometheus | env + `dashboard_metrics_endpoints` |
| `OPEN5G_HEALTH_ENDPOINTS` | `nama=url` health, digabung dengan metrik | env + `dashboard_health_endpoints` |
| `OPEN5G_METRICS_TIMEOUT_S` | Timeout scrape | env + `dashboard_metrics_timeout_s` |
| `dashboard_enabled` | Role opsional, default false | `infra/group_vars/all/lab.yml`, `infra/roles/dashboard_optional/defaults/main.yml` |
| `vault_ue_ki` / `vault_ue_opc` | Seed HSS saja, bukan field profil | `infra/vault.yml.example` |
| `vault_open5gs_mongo_uri` | URI Mongo untuk template role | `infra/vault.yml.example` |

Template Compose opsional: `lab/compose/docker-compose.dashboard.optional.yml`. Profile `dashboard`, jaringan eksternal `lab5g-dev_mgmt`, tidak di-merge ke `docker-compose.yml`. `infra/scripts/render-compose.py` melewatkan `dashboard.env.j2` supaya render offline tidak menulis URI. `infra/site.yml` tidak memanggil role ini.

Placeholder di contoh env sengaja bukan alamat lab. Inventaris alamat tetap di `infra/group_vars/all/lab.yml` yang sudah ada; dokumen ini tidak menyalinnya.

## 6. Risiko dan pertanyaan terbuka

1. **Mongo tanpa auth di `lab5g-dev_mgmt`.** Siapa pun yang join jaringan itu bisa mengubah subscriber, termasuk Ki/OPc. Adapter mendukung URI ber-auth dan TLS, tetapi lab hari ini tidak memakainya. Jangan publish port Mongo ke host. Dashboard harus join jaringan itu hanya setelah persetujuan; berkas Compose opsional tidak melakukan join pada `up` default.
2. **Dua sumber kebenaran.** Postgres menyimpan intent dan versi. Mongo menyimpan dokumen yang dibaca HSS/PCRF. Provision tidak mengubah `applied_content` dan tidak menyebut sesi aktif. Rollback Postgres menulis ulang Mongo hanya bila URI terpasang; kalau tidak, dokumen core bisa lebih baru daripada intent.
3. **SMF down.** Baca/tulis subscriber dan status NF tidak membutuhkan SMF. Attach, CCR, dan bukti sesi membutuhkan SMF. Verifikasi end-to-end menunggu SMF pulih. Itu perbaikan lab terpisah dan butuh persetujuan owner. PR ini tidak me-restart apa pun.
4. **Drift UPF.** Kode tidak menganggap satu UPF. Daftar metrik dikonfigurasi per nama (`upf-a`, `upf-b`, atau nama lain). PoC live tidak sama dengan Compose `master`.
5. **Metrik belum ada.** Status `not_configured` bukan berarti NF mati. Setelah URL dipasang, NF yang tidak mendukung exporter akan tampil `down`. Contoh YAML tidak dipasang otomatis.
6. **Int32 dan ARP.** Nilai di luar int32 ditolak. ARP `0` (EPC enabled di Diameter) **tidak** dianggap enabled, karena HSS/PCRF stock hanya membandingkan dengan `2`. Perlu dikonfirmasi pada satu subscriber lab sebelum produksi kelas.
7. **Direction flow `3` dan penggantian `pcc_rule`.** Rule IP mengganti `pcc_rule` session yang dipilih. Rule IMS/manual yang sudah ada di session itu hilang. Session lain tidak diubah.
8. **Tidak ada snapshot VM.** `infra/docs` dan inventaris operator: rollback VM tidak ada. Rollback produk adalah versi profil + tulis ulang dokumen, bukan snapshot.
9. **Egress.** Jaringan lab internal tanpa egress. Image dashboard/Postgres harus dari mirror. Template Compose memakai nama `REPLACE_WITH_LOCAL_MIRROR/...` dan tidak di-build di run ini.
10. **Tool Compose.** Guest memakai `docker-compose` v2.29.7. Role EPC yang ada memanggil `docker compose` dan `community.docker.docker_compose_v2` (`infra/roles/open5gs_epc_cups/tasks/main.yml`). Perbedaan itu tidak diubah di PR ini supaya stack default tidak bergeser. Perlu dikonfirmasi binary mana yang ada di PATH guest.
11. **Vault Ansible.** `vault.yml` tidak di-load otomatis oleh `site.yml` (lihat inventaris operator). `vault_open5gs_mongo_uri` hanya terpakai bila role opsional dijalankan dengan vault.
12. **Yang masih belum diverifikasi agen ini:** auth Mongo live (hanya laporan tanpa auth), port metrik setelah diaktifkan, DNS service `mongo` dari kontainer dashboard, dan apakah SMF/MME lab benar-benar mengekspor metrik pada build `gradiant/open5gs:2.8.0`.

## 7. Cara menguji tanpa lab

1. Postgres lokal + `pytest` (mongomock untuk koleksi subscriber, `httpx.MockTransport` untuk metrik).
2. Jangan mengarahkan `OPEN5G_MONGO_URI` ke lab dari lingkungan ini.
3. Jangan menjalankan `docker-compose.dashboard.optional.yml` terhadap proyek `lab5g-dev` sebelum review jaringan dan mirror image.
4. Setelah SMF pulih dan metrik disetujui: baca `GET /api/core/status`, provision satu IMSI uji, lalu attach/reconnect. Bukti Active tetap butuh sesi/PGW-C/PFCP, bukan hanya dokumen Mongo atau RAA.
