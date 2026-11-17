# Phase 1: dummy VPN "examine" di emulator → lab5g-vm → Zeek

Status (2026-11-17 14:48 WIB): SUKSES end-to-end dengan v0.6-poc (run-20261117-144129). Riwayat kegagalan sebelumnya di bawah.
[Riwayat 14:02] End-to-end ke l5g-server/Zeek GAGAL karena UE srsUE lab5g-vm DETACH (bukan karena app): setelah idle sejak 11:54 WIB,
trafik 14:02 WIB memicu service request -> `service reject EMM cause=0x9` -> re-attach gagal 5/5 (MME/SGW-C "No Context") -> UE RRC IDLE, menyerah.
Perlu keputusan user: restart/re-attach l5g-ue (di luar batas "jangan ubah lab").

## Hasil run-20261117-140216 (results/)
- tun0 10.111.0.2/32 MTU 1400, route 10.99.9.0/24 (table 1018), uidrange 10174 (app), VpnTransportInfo session=magnon-poc-examine, Underlying [104]=eth0.
- v0.2: TCP gagal `protect() failed` (Socket() Android belum punya fd) -> diperbaiki v0.3 (SocketChannel). UDP keluar: pcap magen 172.26.0.2 -> 10.99.9.20:9000 `MAGNON-POC seq=1..5`.
- Echo server l5g-server InDatagrams=0; UE netns -> 10.99.9.20 juga tidak sampai; Zeek conn.log jendela 07:00Z tidak memuat 10.45.0.38.
- Skew: emulator ~3.9 s di belakang magen (paket UDP sama: logcat 1794898940.839 vs tcpdump 14:02:24.725 WIB); VM ~8.5 s di belakang magen (magen-date.txt).
- v0.4: stop via poll() (fd ditutup). Stop via intent tetap tidak efektif -> script memakai `am force-stop` (terverifikasi tun0 hilang).

## Perubahan AKTIF
- emulator: paket id.magnon.poc.examine v0.4 terpasang, appop ACTIVATE_VPN allow, /tmp/magnon-poc-examine.apk di container. VPN TIDAK aktif.
- lab5g-vm: UDP echo :9000 (python3 via nsenter ke netns l5g-server, pid file /tmp/poc-phase1-udp-echo.pid, log /tmp/poc-phase1-udp-echo.log, script /tmp/poc-phase1-udp-echo.py) — DIBIARKAN aktif atas permintaan user. Rollback: `bash ~/poc-latency/phase1/scripts/38-udp-echo-stop.sh`.
- magen: ~/poc-latency/phase1/, phase1-bundle5.tgz, phase1-results.tgz.
- Rollback app: `bash ~/poc-latency/phase1/scripts/39-rollback.sh`.


## App `id.magnon.poc.examine` (Java, tanpa NDK/Gradle, minSdk 29 / target 33)
- MainActivity: VpnService.prepare() → start ExamineVpnService (`--es cmd stop` untuk stop).
- ExamineVpnService: tun 10.111.0.2/32, route HANYA 10.99.9.0/24, MTU 1400, addAllowedApplication(paket sendiri).
  Forwarder userspace level koneksi (meniru examine magnon-app: socket baru + protect() + Network.bindSocket(underlying non-VPN)):
  - UDP: DatagramSocket per flow, balasan dibungkus ulang IPv4/UDP ke TUN.
  - TCP: state machine kecil (SYN→connect protected Socket→SYN-ACK MSS 1360; data→write+ACK; FIN/RST; socket→segmen PSH/ACK ke TUN).
  - ICMP/lainnya: drop + log.
  - Log tiap paket: tag `MAGNON_EXAMINE` `ts=<epoch ms> mono_ns=<elapsedRealtimeNanos> dir=app->net|net->app proto src dst len flags seq ack plen`.
- GenActivity (app target, uid sama, socket TIDAK di-protect → masuk tun0): TCP 3x ke 10.99.9.20:5201 (cookie 37 B `magnonpocexamine…`, baca 1 byte balasan iperf3), UDP 5x ke :9000 (`MAGNON-POC seq=N ts=…`). Tag `MAGNON_GEN`.
- Build: `app/build.sh` (JDK17 + build-tools 33.0.2 di box ~/tools). APK: `magnon-poc-examine.apk` (29065 B, sha256 1b36fe87…c97087). Checksum IPv4/TCP/UDP diverifikasi di JVM.

## Menjalankan (di magen, setelah bundle disalin ke ~/poc-latency/phase1)
1. `bash scripts/30-install.sh`  — docker cp APK ke b0-agen-emu:/tmp, `adb install -r -g`, `appops set … ACTIVATE_VPN allow`.
2. `bash scripts/31-test.sh`     — start VPN, cek tun0/dumpsys, generator, logcat, screenshot, pcap bridge emulator (payload marker), stop VPN, tunggu rotasi Zeek 320 s, ekstrak conn/tunnel netprobe-zeek-live (read-only) → `run-*/` + tgz. Juga mencatat jam magen/emulator/VM (offset ~7–8 s).
3. Rollback: `bash scripts/39-rollback.sh` (stop VPN, uninstall, hapus /tmp APK). Jalur phase0 tidak disentuh.

Transfer: CopyFromBox `phase1-bundle.tgz` → laptop, lalu dari WSL:
`scp -o ClearAllForwardings=yes /mnt/c/.../phase1-bundle.tgz magen:~/poc-latency/` lalu `ssh -o ClearAllForwardings=yes magen 'mkdir -p ~/poc-latency/phase1 && tar xzf ~/poc-latency/phase1-bundle.tgz -C ~/poc-latency/phase1'`.

## Perubahan yang AKAN dibuat (semua di emulator b0-agen-emu)
- file /tmp/magnon-poc-examine.apk di container; paket Android id.magnon.poc.examine; appop ACTIVATE_VPN; tun0 sementara (di-stop di akhir 31-test).
- magen: direktori ~/poc-latency/phase1, tcpdump sementara di br-cc78098cfad4 (timeout 120 s).
- lab5g-vm: hanya baca (+ `ip route replace 10.99.9.0/24 dev tun_srsue` di l5g-ue, sama seperti runbook phase0).

## Re-attach UE (2026-11-17 14:18 WIB) — GAGAL, berhenti sesuai instruksi
- `scripts/34-reattach-ue.sh`: `docker restart -t 10 l5g-ue` 07:18:21Z (14:18:21 WIB). srsUE start OK (ZMQ tx :2001, rx 10.99.11.20:2000),
  log berhenti di `Attaching UE...` (14:18:43 WIB); 3 menit tanpa `Network attach successful`, eNB tidak melihat RACH sejak 14:05 WIB.
- Diagnosis: link ZMQ srsRAN. Runbook open5g lab/README.md: "ZMQ order matters ... After any RAN restart, prefer UE then eNB" —
  restart UE saja tidak cukup; eNB (l5g-enb) perlu di-restart setelah UE. Itu di luar izin (eNB) -> menunggu keputusan user.
- Efek samping restart: aturan phase0 di DALAM netns l5g-ue (route 172.22.10.1/32, MASQUERADE poc-phase0, route D5) hilang bersama netns lama;
  setelah UE attach jalankan `bash ~/poc-latency/phase0/20-setup-vm.sh` (idempoten, tidak bergantung IP UE). Aturan magen/VM (rule 2099, DOCKER-USER) tetap.
- Keepalive (`scripts/35-keepalive.sh start|stop`) BELUM dijalankan. tun0 emulator tidak aktif.
- Langkah lanjut yang diusulkan: `sudo docker restart l5g-enb` (sesudah UE sudah listen), tunggu attach, 20-setup-vm.sh, 35-keepalive.sh start, 31-test.sh, 35-keepalive.sh stop.


## SUKSES — run-20261117-144129 (v0.6-poc, 14:41 WIB)
Pemulihan UE (izin user "perbaiki jika diperlukan"):
1. 14:18 WIB restart l5g-ue saja -> macet "Attaching UE..." (34-reattach.out)
2. 14:24 WIB restart l5g-enb -> S1 up, UE tetap tanpa sel (36-restart-enb.out)
3. 14:29 WIB restart l5g-ue lagi -> tetap macet (34-reattach-2.out)
4. 14:33 WIB siklus RAN bersih sesuai /home/lab/lab5g/lab-up.sh (stop ue+enb, start enb, sleep 8, start ue) -> 14:33:54 WIB
   "Network attach successful. IP: 10.45.0.39" (37-ran-cycle.out). Catatan: urutan lab5g-vm = eNB dulu lalu UE (beda dgn README lab5g-dev).
   Core (MME/SGW/SMF/UPF), probe, l5g-syn-* tidak disentuh.
5. 20-setup-vm.sh dijalankan ulang (20-setup-rerun.out): route/MASQ/D5 di netns l5g-ue baru; ping l5g-ue->server 3/3 (~40 ms).
6. Keepalive PERMANEN (35-keepalive.sh start): /tmp/poc-phase1-ka.sh di host VM, ping 1x/3 s dari netns l5g-ue, resolve PID tiap loop, pasang ulang D5 bila hilang.
   pid file /tmp/poc-phase1-ka.pid, log /tmp/poc-phase1-ka.log. Stop: `bash ~/poc-latency/phase1/scripts/35-keepalive.sh stop` (atau di VM `sudo kill $(cat /tmp/poc-phase1-ka.pid)`).

Perbaikan app:
- v0.5: bindSocket(underlying) -> EPERM di run 14:34 -> dibuat best-effort (protect() saja cukup). Stop VPN via `am broadcast -n id.magnon.poc.examine/.StopReceiver` (instance statis) -> terverifikasi tun0 hilang.
- v0.6: TCP macet 10 s: stream adaptor SocketChannel berbagi blockingLock (read rx-thread menahan write byte ke-37 cookie, tun-loop ikut tertahan,
  iperf3 "unable to receive cookie") -> pakai ch.read/ch.write langsung. Generator jeda 1,5 s antar sesi iperf3.

Bukti (results/run-20261117-144129):
- MAGNON_GEN: tcp#1..3 connect 41–54 ms firstbyte=9 (state PARAM_EXCHANGE iperf3); udp#1..5 echo_from=/10.99.9.20:9000 rtt 32–41 ms match=true.
- tun0 10.111.0.2/32, route 10.99.9.0/24 table 1022, 59 baris log per paket (dir=app->net/net->app).
- pcap magen: 172.26.0.2.45596 > 10.99.9.20.5201 SYN 14:41:36.236 WIB, payload `magnonpocexamine…`.
- Zeek netprobe-zeek-live conn.2026-11-17-07-40-00.log: 10.45.0.39 -> 10.99.9.20:5201 tcp SF x3 (orig 37 B/resp 10 B, history ShADXTadtFf);
  10.45.0.39:52057 -> :9000 udp SF orig 15 pkt/495 B, resp 15 pkt/495 B. tunnel_parents -> GTPv1 s1u (VLAN 102) 10.99.2.20<->10.99.2.12,
  10.99.5.13->10.99.2.20; s5s8 (VLAN 105).
- Echo server log (/tmp/poc-phase1-udp-echo.log): 5x echo 10.45.0.39:52057 len=33.
- Skew (dari SYN tcp#1 yang sama): emulator = magen − 3,91 s; lab5g-vm/Zeek = magen − 8,94 s. Zeek ts 14:41:27.297 (jam VM) = 14:41:36.235 WIB terkoreksi.
- Screenshot: screen-vpn.png, screen-gen.png.
