# Layar emulator di host Docker

Demo kecil. Emulator sudah jalan di host Docker, di container `b0-agen-emu`, pada bridge miliknya sendiri. Dashboard tetap di guest. File ini tidak menyalakan core, tidak mengubah HSS, PCRF, SGW, atau PGW, dan tidak men-deploy apa pun.

Jalur tamu di [`android-emulator-dashboard.md`](android-emulator-dashboard.md) tetap default. Mode `host-agen` mati sampai dihidupkan dengan sengaja.

## Pilihan

Image emulator tidak memuat scrcpy, gRPC 8554, atau VNC. Layar memakai entrypoint sidecar yang sama, `lab/scripts/android-ue-screen.sh`, dengan `ANDROID_UE_SCREEN_MODE=standalone`. Service `screen` memakai `network_mode: container:b0-agen-emu` supaya adb di dalam netns tercapai. Pathname-nya `/emulator/ue1`. Batas default adalah 800, 2 Mbit/s, dan 15 fps.

Sidecar hanya mendengar di `ANDROID_UE_SCREEN_BIND`, yaitu alamat emulator pada bridge-nya. Loopback ditolak: DNAT Docker tidak mencapai bind `127.0.0.1` di dalam netns. Satu-satunya port host adalah `127.0.0.1:3301` pada `screen-publish`. Docker menolak `ports` pada `network_mode: container`, jadi publish tidak menempel pada sidecar. Compose ini tidak menambah publish 5037, 5554, 5555, 8554, atau VNC, dan tidak menyalin jaringan `o5g-screen`.

Container screen tidak memasang `/dev/kvm` dan tidak mengatur group id. GID kvm milik emulator dideteksi di host dengan `stat -c %g /dev/kvm`. Jangan salin angkanya ke git.

## Image, tanpa jaringan di host

Host Docker tidak punya egress. Jangan `docker pull` dan jangan build di sana. Compose tidak punya kunci build.

Di mesin yang bisa menjangkau mirror dan GitHub:

```bash
docker build -f lab/images/ws-scrcpy/Dockerfile -t open5g-ws-scrcpy:local lab/images/ws-scrcpy
docker save open5g-ws-scrcpy:local | ssh <SSH_TARGET> docker load
```

`<SSH_TARGET>` adalah target SSH operator. Jangan tulis hostname ke git. `ANDROID_UE_SCREEN_IMAGE` harus `nama@sha256:` diikuti 64 digit hex. Tanpa digest, skrip berhenti. Tag dan id tanpa `@sha256` ditolak.

## Aktifkan

1. Pastikan `b0-agen-emu` sudah jalan. Compose ini tidak membuatnya dan tidak menghentikannya.
2. Salin nama bridge ke env lokal. Jangan commit hasilnya:

   ```bash
   docker inspect -f '{{range $name, $net := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' b0-agen-emu
   docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}' b0-agen-emu
   cp lab/compose/screen-standalone.env.example lab/compose/screen-standalone.env
   ```

   Isi `ANDROID_EMULATOR_NETWORK`, `ANDROID_UE_SCREEN_IMAGE` (`nama@sha256:`), dan `ANDROID_UE_SCREEN_BIND` dari alamat bridge container itu. `ANDROID_EMULATOR_CONTAINER` pada contoh adalah `b0-agen-emu`.

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
curl -sS -D- -o /dev/null --max-time 5 http://127.0.0.1:3301/emulator/ue1/
curl -sS -D- -o /dev/null --max-time 5 \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  http://127.0.0.1:3301/emulator/ue1/
```

Respons pertama dari UI di `/emulator/ue1/`. Respons kedua memuat `101 Switching Protocols`. Browser di alamat itu menampilkan frame. `ss -ltn` di host harus menunjukkan `127.0.0.1:3301`, bukan setiap interface.

Demo langsung tidak lewat dashboard, jadi tidak ada login pada streamer. Pagarnya adalah publish loopback dan SSH.

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

Skrip itu hanya mencetak `mode=host-agen upstream=loopback`. URL kosong membuat mode ini mati: proxy tidak men-dial. Path upstream tetap `/emulator/<ue_id>/`, sama dengan sidecar.

## Rollback

```bash
lab/scripts/android-ue-screen-standalone.sh down
```

Itu `docker compose -f lab/compose/compose.screen-standalone.yml --env-file lab/compose/screen-standalone.env down`. Container emulator tidak ikut berhenti. Hentikan proses `ssh -L`. Kembalikan env dashboard: hapus `OPEN5G_EMULATOR_SCREEN_MODE` dan `SCREEN_UPSTREAM_URL`, lalu restart API hanya kalau keduanya sempat di-set. Core tidak diubah.
