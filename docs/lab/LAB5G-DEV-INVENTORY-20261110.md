# Inventaris lab5g-dev (read-only) — 10 Nov 2026 15:04 WIB

Oleh: Lab Ops. Pemeriksaan ini tidak mengubah repo atau lab.

Dokumen ini disanitasi. Tidak ada alamat, hostname internal, pengguna SSH, atau kunci. Nama variabel rahasia dan nilainya tidak dicatat.

## Status akses

- Pada pemeriksaan pertama, lingkungan penyusun tidak menjangkau lab5g-dev: konfigurasi SSH tidak ada, Ansible tidak terpasang, Docker tidak terpasang. Status live pada saat itu belum diketahui.
- Jalur yang sah menurut repo hanya lab5g-dev. Rincian host, akun, berkas kunci, dan alamat tidak ditulis di sini. Tidak ada ProxyJump di inventory Ansible.

## Repo

- `main` berujung `d0d4bc4` dan tidak memuat `infra/`. `master` berujung `3af0834` dan memuat `infra/` (PR #5). Kedua cabang divergen. Pada pemeriksaan awal tidak ada PR terbuka.
- `lab/`: proyek Compose `lab5g-dev`. Layanan: mongo (`mongo:7.0`), hss, pcrf, mme, sgwc, sgwu, smf, upf (image `gradiant/open5gs:2.8.0`), dan server (netshoot). RAN: enb dan ue (`gradiant/srsran-4g:25_10`, transport ZMQ).
- Jaringan Docker internal, alamat disamarkan: s1mme, s1u, s11, s5s8, pfcp, s6a, gx, sgi, mgmt, dan uu. Tidak ada port yang dipublikasikan ke host.
- Skrip naik lab: `lab-up.sh`. Path absolut di tamu disamarkan.
- `infra/`: Ansible. Target Make: `up`, `down`, `verify`, `lint`, `render`, `check`, `secrets-check`. Guard `site.yml` hanya menerima lab5g-dev dan menolak lab5g-vm.
- Rahasia langganan berada di berkas vault yang di-gitignore. Berkas kata sandi vault tidak di-set. `site.yml` tidak memuat vault secara otomatis; pemuatan butuh variabel ekstra dan permintaan kata sandi. Celah ini perlu dirapikan sebelum `make up`.
- Snapshot atau rollback VM: tidak ada. Yang ada hanya `lte-only-restore.sh` (RAN) dan `make down`.
- Kolektor evidence: tidak ada skrip. Role `verify` memeriksa attach, ping SGi, dan log PFCP. Contoh tcpdump ada di [`docs/plan-poc-slicing-core.md`](../plan-poc-slicing-core.md) bagian 8.

## Jawaban untuk Dev

Sumber tiap butir ditandai. Pemeriksaan pertama belum melihat keadaan live.

1. Menurut repo: Open5GS 2.8.0 EPC CUPS (image `gradiant/open5gs:2.8.0`). SMF/UPF dapat bind-mount build lokal `dev-smf-upf`. MongoDB 7.0. WebUI Open5GS tidak ada. Live pada pemeriksaan pertama: belum diketahui.
2. Menurut repo: Mongo tanpa autentikasi, mendengarkan di semua antarmuka di dalam kontainer, hanya di jaringan Docker `mgmt` (internal), tidak dipublikasikan. API WebUI tidak ada. Metrik Prometheus per NF tidak dikonfigurasi (tidak ada blok `metrics`; PRD R-11). Log: stdout ke `docker logs` untuk kontainer `l5gd-*`. Pcap dan CSV RAN ada di `/tmp` kontainer enb/ue.
3. Menurut repo: PCRF admin-RAR di `lab/patches/pcrf-admin-rar*` berstatus DRAFT, NOT COMPILED, NOT TESTED. PCRF memakai image stok. Live pada pemeriksaan pertama: belum diketahui.
4. Menurut repo: dashboard belum pernah jalan di lab5g-dev. Tidak ada service Compose, role Ansible, atau Postgres di stack lab. Penempatan belum dirinci.
5. Kendala: lingkungan penyusun belum punya akses; tulis hanya ke lab5g-dev setelah persetujuan pemilik; jaringan lab internal tanpa egress sehingga image butuh mirror; restart RAN harus dikoordinasikan dengan pekerjaan slicing; jendela maintenance tidak terdokumentasi.

## Yang dibutuhkan dari pemilik

Nilai rahasia tidak diminta di dokumen ini.

1. Pilih jalur akses di luar git: beri jalur SSH yang disetujui kepada operator, atau jalankan perintah read-only dari komputer pemilik yang sudah punya akses. Hostname, akun, dan kunci tidak ditulis di repo.
2. Konfirmasi lab5g-dev menyala, dan sebutkan jendela waktu yang aman untuk inspeksi read-only.
3. Untuk integrasi dashboard nanti, bukan sekarang: putuskan cara dashboard menjangkau Mongo dan metrik di jaringan `mgmt` yang internal. Perubahan itu butuh persetujuan terpisah.

## Update live — 10 Nov 2026 15:10 WIB

Terverifikasi di lab, read-only. Tidak ada yang diubah atau di-restart. Jalur akses adalah komputer pemilik. Hostname, pengguna, berkas kunci, dan alamat tidak dicatat. Penerusan port pada sesi lain sudah terpakai, jadi sesi ini mematikan penerusan. Kontrol hypervisor tidak tersedia karena kebijakan polkit. Disk qcow2 tamu dalam keadaan aktif.

- Tamu sudah menyala 3 hari 20 jam. Docker 27.5.1. docker-compose v2.29.7 (binary `docker-compose`, bukan plugin `docker compose`).
- Open5GS v2.8.0 (`gradiant/open5gs:2.8.0`). mongod 7.0.45 tanpa autentikasi. Tidak ada port yang dipublikasikan. Tidak ada WebUI. Tidak ada blok `metrics` di konfigurasi.
- Kontainer UP: mongo, hss, pcrf, mme, sgwc, sgwu, upf, upf-a, upf-b, cgnat, server, enb, ue.
- **l5gd-smf EXITED (255) sejak 6 Nov 2026 pukul 21:12 WIB.** Pesan fatal: tidak dapat membuka `/etc/o5/smf.yaml`. SMF memakai override PoC (`docker-compose.override.poc.yml` dan `.dev.yml`): bind `poc-conf/smf.yaml` ke `/etc/o5/smf.yaml` di dalam bind read-only `conf` ke `/etc/o5`, plus binary lokal `bin/open5gs-smfd`. Dugaan yang belum diverifikasi: mount bersarang gagal, atau berkas diganti setelah kontainer dibuat.
- Dampak: UPF terlepas dari SMF pada 6 Nov 2026 pukul 21:05 WIB. Sesi SGW-U terakhir dilepas 6 Nov 2026 pukul 21:26 WIB. UE kini hanya berputar antara RRC Connected dan RRC Release. Attach sukses terakhir tercatat di log; alamatnya disamarkan dan waktunya tidak tercatat.
- Drift terhadap `master`: keadaan lab adalah PoC slicing (UPF-A, UPF-B, poc-conf, cgnat, internet-up), bukan baseline `lab/` di repo. Ada banyak berkas `.bak-endc`, `.bak-poc`, dan `.lte-endc`.
- PCRF: image stok ditambah bind konfigurasi. Patch admin-RAR tidak terpasang.
- Pada host tamu ada listener SSH dan satu proses lokal yang mungkin proxy egress. Alamat dan port disamarkan. Dugaan itu belum diverifikasi.

Pemulihan ke baseline `master` disetujui pada 10 Nov 2026 pukul 15:11 WIB. Butir itu adalah M1b di [`docs/pm/DELIVERY-TIMELINE.md`](../pm/DELIVERY-TIMELINE.md) dan menjadi dependensi uji e2e dashboard (M5).
