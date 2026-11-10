# Deploy dashboard ke lab5g-dev

Runbook operator. Lab Ops yang menjalankan ini setelah review arsitek dan QA. Jangan merge dari dokumen ini. Jangan menulis ke lab5g-vm.

Guest memakai binary standalone `docker-compose` v2.29.7. Jaringan lab tidak punya egress: image harus sudah ada di mirror lokal sebelum `up`.

UI hanya lewat tunnel SSH ke port web. API tidak dipublish.

`OPEN5G_ENABLE_GX_RAR` tetap `0`. `OPEN5G_MONGO_URI` mengarah ke service `mongo` di jaringan `lab5g-dev_mgmt` (bukan alamat yang di-commit).

## Yang harus ada di mirror

Catat digest saat menarik image, lalu simpan digest itu di catatan deploy:

- `python:3.12-slim-bookworm` (build API)
- `node:22-bookworm-slim` (build web)
- `postgres:16` (runtime; tag ulang ke `postgres:16` atau set `DASHBOARD_POSTGRES_IMAGE`)
- wheel untuk setiap distribusi di `dashboard/backend/requirements.lock`
- paket npm sesuai `dashboard/frontend/package-lock.json`, atau cache `npm ci`

`mongomock` tidak masuk image API.

Build arg bila base image atau indeks tidak memakai nama upstream:

- `PYTHON_IMAGE`, `PIP_FIND_LINKS`
- `NODE_IMAGE`, `NPM_CONFIG_REGISTRY`, `NEXT_PUBLIC_API_BASE` (default `/`)

## 1. Build di host yang punya egress

Dari root repositori, pada commit yang sudah di-review:

```bash
docker build -f dashboard/backend/Dockerfile -t open5g-dashboard-api:local dashboard/backend
docker build -f dashboard/frontend/Dockerfile -t open5g-dashboard-web:local dashboard/frontend
```

`NEXT_PUBLIC_API_BASE=/` dibakar ke bundle browser. Browser memanggil `/api` pada origin web. `proxy.mjs` meneruskan `/api` dan `/health` ke `OPEN5G_API_INTERNAL_URL` (runtime, default `http://dashboard-api:8000`). Mengganti URL publik berarti build ulang web.

## 2. Pindahkan image ke guest

Di host build:

```bash
docker save open5g-dashboard-api:local open5g-dashboard-web:local | gzip > dashboard-images.tar.gz
```

Pindahkan arsip ke guest lewat jalur yang sudah disetujui. Di guest:

```bash
docker load < dashboard-images.tar.gz
```

Atau dorong kedua tag ke mirror lokal, lalu tarik di guest. Jangan tarik dari internet di dalam guest.

Image Postgres yang sama harus sudah ter-load. Kalau namanya berbeda, export `DASHBOARD_POSTGRES_IMAGE` sebelum `up`.

## 3. Isi env dari vault

```bash
cd lab/compose
cp dashboard.env.example dashboard.env
chmod 600 dashboard.env
```

`dashboard.env` dan `lab/compose/.env` tidak di-commit. Ganti setiap nilai yang mengandung `REPLACE_`. Proses API menolak nilai kosong dan nilai yang masih berisi `REPLACE_` atau `CHANGEME`.

Isi minimal:

- `OPEN5G_SESSION_PEPPER` — minimal 32 karakter, unik
- `POSTGRES_PASSWORD` dan password yang sama di `OPEN5G_DATABASE_URL`
- `OPEN5G_ENABLE_GX_RAR=0`
- `OPEN5G_MONGO_URI=mongodb://mongo:27017/open5gs` hanya setelah backup di langkah 5. Kosongkan dulu bila tulis subscriber belum diizinkan pada jendela ini.
- `OPEN5G_BIND_HOST=0.0.0.0` dan `OPEN5G_BIND_PORT=8000` (hanya di dalam container; port ini tidak dipublish)

Opsional di shell, bukan di file yang di-commit:

```bash
export DASHBOARD_WEB_BIND=127.0.0.1
export DASHBOARD_WEB_PORT=3000
```

Default bind web sudah `127.0.0.1:3000`.

## 4. Cek file Compose

Dari root repositori, di guest atau di host build:

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard config
```

Binary harus v2.29.7. Periksa bahwa hanya `dashboard-web` punya `ports`, dan binding-nya `127.0.0.1:3000:3000` kecuali variabel di atas diubah. `dashboard-api` tidak punya port publish.

## 5. Backup subscriber Mongo sebelum up

Lakukan ini pada container Mongo yang sudah jalan (`l5gd-mongo`), sebelum URI dashboard diisi.

```bash
docker exec l5gd-mongo mongodump --db open5gs --collection subscribers --archive=/tmp/subscribers.archive
docker cp l5gd-mongo:/tmp/subscribers.archive ./subscribers-before-dashboard.archive
docker exec l5gd-mongo rm -f /tmp/subscribers.archive
```

Arsip itu berisi data subscriber, termasuk material autentikasi. Simpan di luar git, izin terbatas, dan jangan salin ke chat. Pola `subscriber-dump/` sudah di-ignore.

Koleksi lab yang sudah di-seed Open5GS memakai indeks unik `imsi_1`. Dashboard tidak membuat dan tidak mengubah indeks. Jika status API memperingatkan `no_unique_imsi_index`, Lab Ops yang menjalankan ini sekali:

```bash
docker exec l5gd-mongo mongosh open5gs --eval 'db.subscribers.createIndex({imsi:1},{unique:true,name:"imsi_1"})'
```

Jangan membuat indeks kedua dengan nama lain pada field yang sama. MongoDB 7 menolaknya dengan IndexOptionsConflict (kode 85).

## 6. Naikkan dashboard

Dari root repositori di guest:

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard up -d
```

Perintah ini tidak mengubah proyek Compose inti `lab5g-dev`. Service dashboard bergabung ke jaringan eksternal `lab5g-dev_mgmt` hanya untuk API, supaya bisa mencapai `mongo`. Web hanya di jaringan `dashboard`.

Kalau API langsung keluar, baca log. Penyebab yang diharapkan bila env belum diganti: penolakan placeholder.

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard logs dashboard-api
```

## 7. Sampai ke UI

Di workstation yang men-SSH ke guest:

```bash
ssh -L 3000:127.0.0.1:3000 <user-guest>
```

Buka `http://127.0.0.1:3000`. Jangan mem-publish port web ke alamat selain loopback guest.

## 8. Smoke test

Ganti port bila `DASHBOARD_WEB_PORT` bukan 3000. Jangan memakai IMSI pelanggan sungguhan. Satu subscriber uji yang sudah di-seed cukup.

```bash
curl -fsS http://127.0.0.1:3000/health
```

Harapan: JSON `status` ok. `core` boleh `not_checked`.

Login lewat UI atau cookie sesi yang sudah ada, lalu:

```bash
curl -fsS -b cookies.txt http://127.0.0.1:3000/api/core/status
```

Harapan: HTTP 200. NF tanpa URL metrik berstatus `not_configured`, bukan gagal sehalaman. `gx_rar_effective` false.

Baca satu subscriber uji yang memang ada di Mongo:

```bash
curl -fsS -b cookies.txt http://127.0.0.1:3000/api/assignments/<assignment-id-uji>/subscriber
```

Harapan: tidak ada field `security`, Ki, atau OPc di badan respons.

Provision hanya untuk subscriber uji yang sudah di-seed, lewat tombol **Tulis subscriber** atau:

```bash
curl -fsS -b cookies.txt -H "x-csrf-token: <csrf>" -H "if-match: <etag>" \
  -X POST http://127.0.0.1:3000/api/profiles/<profile-id-uji>/provision
```

Harapan: `status` written, `live_gx_rar` false. Sesi UE yang sedang aktif tidak berubah.

Rollback profil uji yang sama dengan `Idempotency-Key` baru. Ulangi kunci yang sama: tidak ada tulis Mongo kedua. `OPEN5G_ENABLE_GX_RAR` tetap 0.

## 9. Stop

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard stop
```

`stop` mempertahankan volume Postgres dashboard. Core lab tidak dihentikan.

Untuk melepas container dashboard tanpa menghapus volume:

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard down
```

`down -v` menghapus volume Postgres dashboard (pengguna UI), bukan koleksi Mongo.

## 10. Rollback deploy

1. `down` seperti di atas.
2. Bila smoke test sudah menulis subscriber uji, pulihkan arsip langkah 5:

```bash
docker cp ./subscribers-before-dashboard.archive l5gd-mongo:/tmp/subscribers.archive
docker exec l5gd-mongo mongorestore --archive=/tmp/subscribers.archive --nsInclude=open5gs.subscribers --drop
docker exec l5gd-mongo rm -f /tmp/subscribers.archive
```

`--drop` hanya menyentuh koleksi di dalam arsip (`open5gs.subscribers`). Jangan menjalankan ini tanpa arsip langkah 5.

3. Hapus image lokal bila perlu: `docker image rm open5g-dashboard-api:local open5g-dashboard-web:local`.
4. Core Open5GS, RAN, dan jaringan `lab5g-dev_mgmt` tetap seperti sebelum dashboard naik.
