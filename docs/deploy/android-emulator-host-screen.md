# Layar emulator di host Docker

Demo kecil. Emulator sudah jalan di host Docker, di container `b0-agen-emu`, pada bridge miliknya sendiri. Dashboard tetap di guest. File ini tidak menyalakan core, tidak mengubah HSS, PCRF, SGW, atau PGW, dan tidak men-deploy apa pun.

Jalur tamu di [`android-emulator-dashboard.md`](android-emulator-dashboard.md) tetap default. Mode `host-agen` mati sampai dihidupkan dengan sengaja.

## Pilihan

Image emulator tidak memuat scrcpy, gRPC 8554, atau VNC. Layar memakai image ws-scrcpy yang sama dengan sidecar tamu, termasuk `scrcpy-server.jar` yang di-push lewat adb. Service `screen` memakai `network_mode: container:b0-agen-emu` supaya adb di `127.0.0.1:5555` di dalam netns emulator tercapai.

adb yang dipakai streamer adalah `127.0.0.1:5555` di dalam netns itu. Compose ini tidak menambah publish 5037, 5554, 5555, 8554, atau VNC.

ws-scrcpy 0.8.1 tidak punya opsi bind. Prosesnya mendengar di setiap interface netns emulator. Itu bukan publish host. Satu-satunya port yang di-publish file ini adalah `127.0.0.1:3301`, pada service `screen-publish`. Docker menolak `ports` pada `network_mode: container`, jadi publish tidak bisa menempel pada service yang sama.

Container screen tidak memasang `/dev/kvm` dan tidak mengatur group id. GID kvm milik emulator dideteksi di host dengan `stat -c %g /dev/kvm`. Jangan salin angkanya ke git.

## Image, tanpa jaringan di host

Host Docker tidak punya egress. Jangan `docker pull` dan jangan build di sana. Compose tidak punya kunci build.

Di mesin yang bisa menjangkau mirror dan GitHub:

```bash
docker build -f lab/images/ws-scrcpy/Dockerfile -t open5g-ws-scrcpy:local lab/images/ws-scrcpy
id=$(docker image inspect --format '{{.Id}}' open5g-ws-scrcpy:local)
docker save open5g-ws-scrcpy:local | ssh <SSH_TARGET> docker load
```

`<SSH_TARGET>` adalah target SSH operator. Jangan tulis hostname ke git. Setelah `docker load`, id image tetap sama. Di env yang di-gitignore, set `ANDROID_UE_SCREEN_IMAGE` ke id `sha256:...` itu, atau ke digest `nama@sha256:...` kalau image ada di mirror privat. Tag tanpa pin ditolak.

Build itu menjalankan `npm run dist`. Hasilnya, termasuk `scrcpy-server.jar`, ada di dalam image. Startup di host menjalankan `node dist/index.js` dan tidak mengulang build.

## Aktifkan

1. Pastikan `b0-agen-emu` sudah jalan. Compose ini tidak membuatnya dan tidak menghentikannya.
2. Salin nama bridge ke env lokal. Jangan commit hasilnya:

   ```bash
   docker inspect -f '{{range $name, $net := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' b0-agen-emu
   cp lab/compose/screen-standalone.env.example lab/compose/screen-standalone.env
   ```

   Isi `ANDROID_EMULATOR_NETWORK` dan `ANDROID_UE_SCREEN_IMAGE`. `ANDROID_EMULATOR_CONTAINER` pada contoh adalah `b0-agen-emu`.

3. Periksa, lalu naikkan:

   ```bash
   lab/scripts/android-ue-screen-standalone.sh --print
   lab/scripts/android-ue-screen-standalone.sh up
   ```

## Tunnel

Pakai `ssh -L` dari guest atau dari laptop. Jangan pakai `ssh -R`: forward remote bisa mendengar di interface lain kalau konfigurasi SSH keliru. Kedua ujung tetap `127.0.0.1`. Kunci SSH tidak masuk repo.

Laptop, untuk melihat UI langsung:

```bash
ANDROID_EMULATOR_SSH_TARGET=<SSH_TARGET> SCREEN_TUNNEL_LOCAL_PORT=3301 \
  lab/scripts/android-ue-screen-tunnel.sh
```

Guest, supaya tidak bentrok dengan listener dashboard di port 3301:

```bash
ANDROID_EMULATOR_SSH_TARGET=<SSH_TARGET> \
  lab/scripts/android-ue-screen-tunnel.sh
```

Perintah itu mendengar di `127.0.0.1:3302` dan meneruskan ke `127.0.0.1:3301` di host Docker.

## Verifikasi

Dari ujung tunnel laptop:

```bash
curl -sS -D- -o /dev/null --max-time 5 http://127.0.0.1:3301/
curl -sS -D- -o /dev/null --max-time 5 \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  http://127.0.0.1:3301/
```

Respons pertama dari UI. Respons kedua memuat `101 Switching Protocols`. Browser di `http://127.0.0.1:3301/` menampilkan frame. `ss -ltn` di host harus menunjukkan `127.0.0.1:3301`, bukan setiap interface.

UI ws-scrcpy 0.8.1 ada di `/`. Variabel pathname tidak dipakai oleh commit yang di-pin. Demo langsung tidak lewat dashboard, jadi tidak ada login pada streamer. Pagarnya adalah bind loopback dan SSH.

## Dashboard, default mati

`OPEN5G_EMULATOR_SCREEN_MODE` kosong atau `guest` mempertahankan perilaku sidecar tamu. `SCREEN_UPSTREAM_URL` diabaikan.

Untuk mode host, di env dashboard yang di-gitignore:

```bash
OPEN5G_EMULATOR_SCREEN_MODE=host-agen
SCREEN_UPSTREAM_URL=http://127.0.0.1:3302
```

`3302` adalah ujung tunnel di guest. Auth, peran, dan audit tetap: user, instructor, dan admin seperti baca profil; satu pemegang kontrol; pengguna kedua mendapat 409 `emulator_control_busy`. Cek sebelum restart API:

```bash
OPEN5G_EMULATOR_SCREEN_MODE=host-agen SCREEN_UPSTREAM_URL=http://127.0.0.1:3302 \
  lab/scripts/android-ue-screen-mode.sh
```

Skrip itu hanya mencetak `mode=host-agen upstream=loopback`. URL kosong membuat mode ini mati: proxy tidak men-dial. Frame dashboard masih meminta `/emulator/<ue_id>/`, sementara server yang di-pin melayani `/`. Menyambungkan keduanya adalah tindak lanjut, bukan bagian dari demo ini.

## Rollback

```bash
lab/scripts/android-ue-screen-standalone.sh down
```

Itu `docker compose -f lab/compose/compose.screen-standalone.yml --env-file lab/compose/screen-standalone.env down`. Container emulator tidak ikut berhenti. Hentikan proses `ssh -L`. Kembalikan env dashboard: hapus `OPEN5G_EMULATOR_SCREEN_MODE` dan `SCREEN_UPSTREAM_URL`, lalu restart API hanya kalau keduanya sempat di-set. Core tidak diubah.
