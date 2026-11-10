# Runbook: pemulihan lab5g-dev dari state PoC slicing ke baseline `master`

Runbook ini mencatat pemulihan yang dijalankan pada **10 Nov 2026 15:15–15:31 WIB**. Cakupan hanya lab5g-dev. lab5g-vm tidak disentuh. Tidak ada alamat internal, secret, kunci, token, IMSI, Ki, atau OPc di dokumen ini.

Akses yang dipakai: laptop operator → host agen → guest (user lab).

Baseline target: branch `master` commit `3af0834` (`lab/` + `infra/`). Config contoh di repo tersanitasi, sehingga yang diterapkan adalah config guest yang terverifikasi sama dengan kondisi pra-PoC.

Hasil smoke test ada di [`docs/evidence/lab5g-dev-restore-20261110/SUMMARY.md`](../evidence/lab5g-dev-restore-20261110/SUMMARY.md).

## Kronologi dan akar masalah

Pada **6 Nov 21:05–21:12 WIB**, percobaan PoC slicing menerapkan `docker-compose.override.poc.yml` (kontainer `UPF-A` / `UPF-B`, plus `cgnat`). Override itu mem-bind satu berkas `poc-conf/smf.yaml` ke `/etc/o5/smf.yaml` di dalam bind directory read-only `conf` (yang juga di-mount ke `/etc/o5`).

Akibatnya proses SMF gagal dengan `FATAL cannot open file /etc/o5/smf.yaml` dan exit **255**. SMF (`l5gd-smf`) tetap mati sejak **6 Nov 21:12 WIB**. UPF kehilangan asosiasi PFCP (sekitar 6 Nov 21:05 WIB). Tidak ada sesi data selama sekitar 3,5 hari. UE hanya berputar pada siklus RRC connect/release.

Akar masalah utama: bind satu berkas ke dalam direktori yang sudah di-mount read-only, sehingga SMF tidak dapat membuka conf-nya. Binary SMF sendiri tidak rusak (lihat verifikasi di bawah).

Penyebab tambahan yang baru terlihat setelah SMF dibuat ulang pada 10 Nov 2026: rute subnet jaringan `lab5g-dev_s11` di netns SMF hilang, sehingga Create Session Request dari SGW-C (sumber: alamat S11) tidak dijawab. Gejala: SGW-C mencatat `No Create Session Response`, MME mencatat `GTP Timeout Message-Type[32]`. Ini terbukti lewat tcpdump di bridge `s5s8`. Perbaikannya adalah menjalankan kembali `lab-routes.sh` (bukan mengganti conf SMF).

## Prasyarat dan tindakan yang tidak boleh dilupakan

- Backup dulu, baru ubah kontainer.
- Jangan commit config guest ke repo; jika config repo yang salah/kurang, buat PR terpisah.
- Plugin `docker compose` mungkin tidak ada di guest; pakai binary `docker-compose`.
- Setelah recreate NF mana pun, jalankan `lab-routes.sh` (sebelum dan sesudah RAN up, agar rute UE D5 ikut terpasang).
- Tidak ada mekanisme snapshot VM; satu-satunya titik kembali yang disiapkan adalah arsip backup di guest.

## Langkah yang dijalankan (10 Nov 2026 15:15–15:31 WIB)

### a. Backup state PoC

Lokasi di guest: `~/backups/poc-20261110-1515` (mode `600`).

Isi yang diarsipkan:

- Berkas lab (tgz), **tanpa** `mongo-data` dan `open5gs-src`
- `docker inspect` semua kontainer
- keluaran `docker ps`
- `mongodump` basis data `open5gs` dalam bentuk archive

Jumlah dokumen subscriber pada dump: **5**. Isi dump tidak disalin ke repo.

### b. Verifikasi baseline masih utuh

Sebelum menghapus node PoC:

- `conf/smf.yaml` identik dengan `smf.yaml.bak-poc` (baseline conf SMF utuh)
- `bin/open5gs-smfd` identik dengan binary stok image `gradiant/open5gs:2.8.0` (sha256 sama)
- `docker-compose.yml` di guest identik dengan salinan `.bak-poc`

Kesimpulan: cukup kembali ke compose baseline; tidak perlu mengganti binary SMF atau menempel conf dari contoh repo.

### c. Hapus node PoC dan buat ulang SMF dari baseline

Kontainer khusus PoC dihapus:

```bash
docker rm -f l5gd-upf-a l5gd-upf-b l5gd-cgnat
```

SMF dibuat ulang hanya dari `docker-compose.yml` baseline (tanpa override PoC), tanpa menyentuh NF lain:

```bash
docker-compose -p lab5g-dev -f docker-compose.yml up -d --no-deps --force-recreate smf
```

Setelah SMF naik: PFCP associated ke UPF, dan Gx **CONNECTED** ke PCRF.

### d. Pulihkan rute `lab5g-dev_s11` (wajib setelah recreate SMF)

Setelah langkah (c), rute subnet `lab5g-dev_s11` di netns SMF hilang. Create Session Request dari SGW-C tidak dijawab sampai rute dipasang kembali:

```bash
sudo bash lab-routes.sh
```

Jalankan skrip ini **sebelum dan sesudah** RAN up agar rute UE D5 juga terpasang.

### e. Restart terkendali RAN

```bash
docker-compose -p lab5g-dev-ran -f docker-compose-ran.yml stop enb ue
docker-compose -p lab5g-dev-ran -f docker-compose-ran.yml up -d ue
# sleep 5
docker-compose -p lab5g-dev-ran -f docker-compose-ran.yml up -d enb
```

Kemudian jalankan lagi `sudo bash lab-routes.sh` (lihat langkah d).

## Rollback ke state PoC

State PoC itu sendiri **sudah rusak** (SMF tidak dapat membuka conf karena bind satu berkas ke direktori read-only). Rollback ini hanya mengembalikan susunan kontainer dan berkas, bukan layanan data yang sehat.

1. Kembalikan arsip tgz dari `~/backups/poc-20261110-1515`.
2. Naikkan kembali stack dengan override PoC:

```bash
docker-compose -f docker-compose.yml -f docker-compose.override.dev.yml -f docker-compose.override.poc.yml -f docker-compose.cgnat.yml up -d
```

Dump Mongo di backup dapat dipakai jika data subscriber perlu dikembalikan; jangan menuliskan isinya ke repo atau ke log.

## Temuan sisa (tidak diubah pada pemulihan ini)

- UPF masih punya default route ke node `cgnat` yang sudah dihapus (sisa egress internet). Tidak memengaruhi SGi lokal.
- `docker-compose.override.dev.yml` (repo dan guest) me-mount `bin/open5gs-upfd` yang tidak ada di guest.
- Plugin `docker compose` tidak ada; pakai binary `docker-compose`.
- `infra/site.yml` tidak memuat `vault.yml`, dan `ansible.cfg` tidak mengatur vault password.
- Ansible tidak terpasang di laptop operator.
- Tidak ada mekanisme snapshot VM.
- Config contoh repo tersanitasi, sehingga baseline `master` diterapkan memakai config guest yang terverifikasi sama dengan pra-PoC.

## Rekomendasi

- Role `verify` / `lab-up` harus selalu menjalankan `lab-routes.sh` setelah recreate NF mana pun.
- Ubah override PoC agar tidak mem-bind satu berkas ke dalam direktori yang di-mount read-only.
- Pertimbangkan mekanisme snapshot atau rollback VM; saat ini satu-satunya titik kembali adalah arsip di `~/backups/`.
