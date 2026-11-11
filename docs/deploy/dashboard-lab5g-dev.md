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
- `OPEN5G_MONGO_URI=mongodb://mongo:27017/open5gs` hanya setelah backup dan uji pulih di langkah 5 lulus. Kosongkan dulu sampai langkah itu selesai.
- Jendela uji hanya memakai akun uji dan IMSI uji. Jangan memakai IMSI pelanggan atau akun operasional.
- `OPEN5G_BIND_HOST=0.0.0.0` dan `OPEN5G_BIND_PORT=8000` (hanya di dalam container; port ini tidak dipublish)

Opsional di shell, bukan di file yang di-commit:

```bash
export DASHBOARD_WEB_BIND=127.0.0.1
export WEB_PORT=3300
```

Default bind web sudah `127.0.0.1:3300`. Port 3000 tetap untuk Grafana, jadi dashboard tidak memakainya.

## 4. Cek file Compose

Dari root repositori, di guest atau di host build:

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard config
```

Binary harus v2.29.7. Periksa bahwa `dashboard-web` mem-publish `127.0.0.1:3300:3300` kecuali `WEB_PORT` diubah, dan `dashboard-postgres` mem-publish `127.0.0.1:5432:5432` hanya untuk listener layar di host. `dashboard-api` tidak punya port publish.

## 5. Backup subscriber Mongo sebelum up

Lakukan ini pada container Mongo yang sudah jalan (`l5gd-mongo`), sebelum URI dashboard diisi.

```bash
docker exec l5gd-mongo mongodump --db open5gs --collection subscribers --archive=/tmp/subscribers.archive
docker cp l5gd-mongo:/tmp/subscribers.archive ./subscribers-before-dashboard.archive
docker exec l5gd-mongo rm -f /tmp/subscribers.archive
```

Arsip itu berisi data subscriber, termasuk material autentikasi. Simpan di luar git, izin terbatas, dan jangan salin ke chat. Pola `subscriber-dump/` sudah di-ignore.

Sebelum `OPEN5G_MONGO_URI` diisi, uji arsip itu ke namespace lain. Jangan menyentuh koleksi `open5gs.subscribers`.

```bash
docker cp ./subscribers-before-dashboard.archive l5gd-mongo:/tmp/subscribers.archive
docker exec l5gd-mongo mongorestore --archive=/tmp/subscribers.archive --nsFrom='open5gs.*' --nsTo='open5gs_restore_check.*'
docker exec l5gd-mongo mongosh --quiet --eval 'const src = db.getSiblingDB("open5gs").subscribers.countDocuments({}); const dst = db.getSiblingDB("open5gs_restore_check").subscribers.countDocuments({}); if (src !== dst) { print("STOP count " + src + " != " + dst); quit(2); } print("count ok " + src);'
docker exec l5gd-mongo mongosh --quiet --eval 'db.getSiblingDB("open5gs_restore_check").dropDatabase()'
docker exec l5gd-mongo rm -f /tmp/subscribers.archive
```

Berhenti jika jumlah dokumen tidak sama. Jangan lanjut ke isi URI.

Indeks unik pada `imsi` tidak boleh diasumsikan bernama `imsi_1`. Cek dulu, dan jangan buat indeks bila sudah ada.

```bash
docker exec l5gd-mongo mongosh open5gs --quiet --eval 'const dups = db.subscribers.aggregate([{$group:{_id:"$imsi",n:{$sum:1}}},{$match:{n:{$gt:1}}},{$count:"duplicates"}]).toArray(); if (dups.length && dups[0].duplicates > 0) { print("STOP duplicate imsi"); quit(2); } print("no duplicate imsi");'
docker exec l5gd-mongo mongosh open5gs --quiet --eval 'const indexes = db.subscribers.getIndexes(); const uniqueImsi = indexes.some((idx) => idx.unique && idx.key && Object.keys(idx.key).length === 1 && Object.prototype.hasOwnProperty.call(idx.key, "imsi")); print(uniqueImsi ? "unique imsi index present" : "unique imsi index absent"); printjson(indexes.map((idx) => idx.name));'
```

Berhenti jika ada IMSI duplikat. `createIndex` hanya bila pemeriksaan kedua mencetak `unique imsi index absent`, dan hanya setelah pemeriksaan duplikat lulus:

```bash
docker exec l5gd-mongo mongosh open5gs --eval 'db.subscribers.createIndex({imsi:1},{unique:true})'
```

Jangan membuat indeks kedua pada field yang sama dengan nama lain. MongoDB 7 menolaknya dengan IndexOptionsConflict (kode 85). Dashboard tidak membuat indeks.

## 6. Naikkan dashboard

Dari root repositori di guest:

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard up -d
```

Perintah ini tidak mengubah proyek Compose inti `lab5g-dev`.

Jaringan:

- `dashboard` internal. Postgres dan API ada di sini. API tidak dipublish.
- `mgmt` adalah jaringan eksternal `lab5g-dev_mgmt`. Hanya API yang bergabung, supaya mencapai service `mongo`.
- `web` tidak internal. Hanya `dashboard-web` yang ada di sini, plus jaringan `dashboard` agar proxy ke API. Port host `127.0.0.1:3300` menempel di jaringan `web`. Jaringan internal saja tidak meneruskan binding port itu ke host.

Kalau API langsung keluar, baca log. Penyebab yang diharapkan bila env belum diganti: penolakan placeholder.

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard logs dashboard-api
```

## 7. Sampai ke UI

Di workstation yang men-SSH ke guest:

```bash
ssh -L 3300:127.0.0.1:3300 <user-guest>
```

Buka `http://127.0.0.1:3300`. Jangan mem-publish port web ke alamat selain loopback guest. Jangan membuka Grafana dan dashboard di profil browser yang sama: cookie tidak dipisah per port, dan Grafana tetap di port 3000.

## 8. Smoke test

Jendela ini hanya memakai akun uji dan IMSI uji. Bukan akun operasional dan bukan IMSI pelanggan. Prosedur ini tidak mengganti pagar di kode. Ganti port di perintah curl bila `WEB_PORT` bukan 3300.

Permintaan arsitek, wajib selama jendela uji: jangan membuat akun instructor, dan jangan menjalankan seed apa pun (Ansible atau cara lain). Subscriber uji harus sudah ada di Mongo sebelum jendela ini. Dashboard tidak membuat dokumen subscriber baru.

Satu subscriber uji yang sudah ada cukup. Placeholder di bawah bukan rahasia dan bukan IMSI hidup.

```bash
curl -fsS http://127.0.0.1:3300/health
```

Harapan: JSON `status` ok. `core` boleh `not_checked`.

Bootstrap satu admin dari dalam container API. Kata sandi tidak di-commit. Jangan membuat instructor.

```bash
docker-compose -f lab/compose/docker-compose.dashboard.optional.yml --profile dashboard exec \
  -e OPEN5G_BOOTSTRAP_EMAIL=admin@example.test \
  -e OPEN5G_BOOTSTRAP_PASSWORD='<12-characters-minimum>' \
  dashboard-api python /app/scripts/create_user.py
```

Perintah itu mencetak id admin. Buka `http://127.0.0.1:3300/login` lewat tunnel dan masuk dengan email serta kata sandi itu.

Admin lalu membuat grup, satu student uji, dan assignment untuk IMSI uji lewat API origin yang sama. Ganti placeholder. Jangan memakai IMSI pelanggan.

```bash
curl -fsS -c cookies.txt -H 'content-type: application/json' \
  -d '{"email":"admin@example.test","password":"<12-characters-minimum>"}' \
  http://127.0.0.1:3300/api/auth/login
# Simpan csrf_token dari badan JSON. Cookie sesi ada di cookies.txt.

curl -fsS -b cookies.txt -H 'content-type: application/json' -H 'x-csrf-token: <csrf>' \
  -d '{"name":"kelas-uji"}' \
  http://127.0.0.1:3300/api/admin/groups

curl -fsS -b cookies.txt -H 'content-type: application/json' -H 'x-csrf-token: <csrf>' \
  -d '{"email":"student@example.test","display_name":"Student uji","role":"student","group_id":"<group-id>","password":"<12-characters-minimum>"}' \
  http://127.0.0.1:3300/api/admin/users

curl -fsS -b cookies.txt -H 'content-type: application/json' -H 'x-csrf-token: <csrf>' \
  -d '{"imsi":"<IMSI-UJI>","owner_user_id":"<student-id>","group_id":"<group-id>"}' \
  http://127.0.0.1:3300/api/admin/assignments
```

Keluar dari admin (tombol Keluar, atau `POST /api/auth/logout` dengan CSRF). Student masuk lewat form di `/login`. Buka `/profil`, pilih assignment IMSI uji, simpan draf, validasi, lalu tulis subscriber. Tombol Fase 2 tetap nonaktif.

Lalu:

```bash
curl -fsS -b cookies.txt http://127.0.0.1:3300/api/core/status
```

Harapan: HTTP 200. NF tanpa URL metrik berstatus `not_configured`, bukan gagal sehalaman. `gx_rar_effective` false.

Baca satu subscriber uji yang memang ada di Mongo:

```bash
curl -fsS -b cookies.txt http://127.0.0.1:3300/api/assignments/<assignment-id-uji>/subscriber
```

Harapan: tidak ada field `security`, Ki, atau OPc di badan respons.

Provision hanya untuk subscriber uji yang sudah di-seed, lewat tombol **Tulis subscriber** atau:

```bash
curl -fsS -b cookies.txt -H "x-csrf-token: <csrf>" -H "if-match: <etag>" \
  -X POST http://127.0.0.1:3300/api/profiles/<profile-id-uji>/provision
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

Jangan menjalankan `mongorestore --drop` pada koleksi `open5gs.subscribers`.

1. `down` seperti di atas.
2. Bila smoke test sudah menulis subscriber, pulihkan hanya IMSI uji yang disentuh dashboard. Salin dokumen itu dari arsip ke namespace cek, lalu timpa satu dokumen di koleksi hidup. Ulangi untuk setiap IMSI uji. Jangan menyentuh IMSI lain.

```bash
docker cp ./subscribers-before-dashboard.archive l5gd-mongo:/tmp/subscribers.archive
docker exec l5gd-mongo mongorestore --archive=/tmp/subscribers.archive --nsFrom='open5gs.*' --nsTo='open5gs_restore_check.*'
docker exec l5gd-mongo mongosh --quiet --eval 'const imsi = "<IMSI-UJI>"; const src = db.getSiblingDB("open5gs_restore_check").subscribers.findOne({imsi}); if (!src) { print("STOP missing " + imsi); quit(2); } delete src._id; db.getSiblingDB("open5gs").subscribers.replaceOne({imsi}, src);'
docker exec l5gd-mongo mongosh --quiet --eval 'db.getSiblingDB("open5gs_restore_check").dropDatabase()'
docker exec l5gd-mongo rm -f /tmp/subscribers.archive
```

`replaceOne` itu mengganti seluruh dokumen IMSI uji, termasuk `security`. SQN yang lebih lama dapat membuat autentikasi UE uji gagal sampai resync. Untuk jendela ini, IMSI yang dipulihkan harus IMSI uji saja.

3. Hapus image lokal bila perlu: `docker image rm open5g-dashboard-api:local open5g-dashboard-web:local`.
4. Core Open5GS, RAN, dan jaringan `lab5g-dev_mgmt` tetap seperti sebelum dashboard naik.
