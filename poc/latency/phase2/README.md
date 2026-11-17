# Phase 2: Chrome lewat VPN dummy examine + timestamp MGLT terbaca Zeek

Status (2026-11-17 15:50 WIB): **SUKSES**. Run acuan `results/run-20261117-154824` (app v0.7-poc, APK sha256 a4f6e067…).
Tag semua perubahan: `poc-phase2`. Rollback: `bash ~/poc-latency/phase2/scripts/59-rollback.sh` (magen). APK tidak dilampirkan di git; bangun dengan `bash ~/poc-latency/phase2/app/build.sh` (sha256 lab: a4f6e067…).

## Alur
Chrome (uid 10126) -> tun0 (VPN v0.7, route 0/0, DNS 10.99.9.20) -> forwarder examine (socket protect) -> slirp emulator
-> magen br-emu -> (poc-phase0 / poc-inet) -> l5g-ue SNAT 10.45.0.39 -> srsUE/eNB -> S1-U GTP-U -> SGW-U -> S5/S8 -> UPF -> SGi
-> l5g-server (poc-inet: SOCKS -> laptop -> internet).
Untuk tiap flow Chrome forwarder mengirim **marker UDP MGLT** ke reflector 10.99.9.20:9000 (echo yang sudah ada) lewat jalur yang sama.

## Temuan penting: proxy global emulator
Emulator punya `settings global http_proxy = 172.26.0.1:8080` (socat di magen sejak 12 Nov -> 127.0.0.1:8080 magen; BUKAN jalur lab,
bukan poc-inet). Tanpa penanganan, Chrome tidak lewat UE. Setting ini **tidak diubah**. Sebagai gantinya forwarder v0.7
men-terminasi `CONNECT host:443` ke proxy itu ("de-proxy"): resolve host lewat DNS VPN (jalur UE), sambung langsung ke IP tujuan
lewat jalur UE, balas `200 Connection established`, lalu relay byte TLS Chrome apa adanya. Non-CONNECT diteruskan ke proxy asli.
Matikan dengan `--es deproxy off`.

## App v0.7 (app/)
- allowed: `id.magnon.poc.examine` + `com.android.chrome` (extra `--es apps`), route 0.0.0.0/0, `addDnsServer(10.99.9.20)` (UDP DNS lewat forwarder, poc-inet me-redirect ke resolver).
- QUIC (UDP/443 ke publik) di-drop -> Chrome fallback TCP/TLS (jalur internet lab TCP-only).
- Flow control net->app (menunggu ACK/window Chrome) — perlu untuk halaman besar.
- `Mglt.java`: marker 60 B = inti MGLT v1 32 B (magic, ver=1, flags=0x20, hdr_len=60, flow_id, seq, t_ue_ns, t_ue_mono_us, CRC32C byte 0–27)
  + ekstensi flow 28 B (proto, event syn/est/data/fin/udp, 5-tuple asli di tun0 = src ip:port + dst ip:port tujuan asli, segs, bytes, uid).
  Event: SYN/CONNECT (sebelum connect upstream), EST, segmen data app->net ke-1 dan tiap 10, FIN; UDP flow open (DNS).
  t_ue_ns = basis epoch (diselaraskan ke pergantian ms) + elapsedRealtimeNanos -> resolusi sub-ms.
  Echo balik -> RTT di logcat (`mglt echo ... rtt_ms=`).
- getConnectionOwnerUid -> logcat menampilkan `pkg=com.android.chrome` per flow.

## Zeek (zeek/)
- `mglt.zeek` (script murni, tanpa plugin): `udp_contents` port 9000 (UL + echo DL), validasi CRC32C, baca frame mentah per paket
  (`get_current_packet`) untuk VLAN tap (102 s1u, 105 s5s8, 109 sgi), IP luar & TEID GTP-U. Tulis `mglt.log`:
  ts (ts_zeek), t_ue, one_way_raw = ts - t_ue, flow_id, seq, evt, orig_dst/orig_dport (tujuan Chrome), vlan/seg, teid, tunnel_outer, tunnel_uid, crc_ok.
- Dipasang sebagai **instance terpisah** container `poc-phase2-zeek-mglt` (image sama `netprobe/zeek-live:9.0.1-lte1.1-slim`, host network,
  libpcap `-i mirror0`, 512 MiB/1 CPU, ~90 MiB terpakai). Log: VM `/dev/shm/poc-phase2-zeek/mglt.log` (rotasi 5 mnt; conn.log hanya flow marker).
  Alasan tidak memasang ke `netprobe-zeek-live`: entrypoint `exec zeek` tanpa hot-reload + mount script tetap -> perlu recreate container
  (jeda semua log produksi). Sengaja libpcap, bukan af_packet, agar tidak ikut fanout group netprobe (fanout akan membagi paket).
- `run-local.zeek` memuat `vlan_fivetuple` (inner GTP S1-U vs salinan SGi 5-tuple sama dipisah). `52-zeek-selftest.sh` = uji pcap sintetis.

## Script (scripts/, dijalankan di magen)
50-inspect, 51-inspect-zeek, 51b-status, 52-zeek-selftest, 53-zeek-start [stop], 54-install-app, 55-skew (ukur offset jam read-only,
coproc bracket, sampel RTT terkecil), 56-test [URL1] [URL2], 57-inspect-proxy, 58-analyze.py <run-dir>, 59-rollback (KEEP_APP=1, PURGE=1).
Helper laptop: `laptop-run.sh` (WSL: salin + jalankan di magen).

## Hasil run-20261117-154824 (Chrome: example.com + www.wikipedia.org)
Lihat `results/run-20261117-154824/summary.txt`, `mglt-joined.csv`, `screen-chrome-2.png` (Wikipedia termuat lewat VPN).
- Flow Chrome (logcat): CONNECT example.com, www/en.wikipedia.org, upload.wikimedia.org, www.google.com, accounts.google.com, … semua `pkg=com.android.chrome`.
- Marker: tx 36 / echo 36, crc_ok 216/216 baris mglt.log; tiap marker terlihat 6x (UL+DL × S1-U GTP, S5/S8 GTP, SGi).
- Zeek-live: ssl.log `server_name` example.com / www.wikipedia.org / en.wikipedia.org dari 10.45.0.39 tap s1u, conn tunnel_parents GTP.
  Korelasi marker.orig_dst == conn.resp_h (mis. 104.20.23.154:443 = example.com, 103.102.166.224:443 = wikipedia).
- Skew (55-skew, sebelum/sesudah): VM−magen −8.9967 s (±2.2 ms), EMU−magen −3.9298 s (±6.8 ms). Koreksi: one_way = raw − off_vm + off_emu = raw + 5.0670 s.
- Latensi (ms, p50 [min–max], n=36):
  - RTT marker di app (UE->reflector->UE): 33.0 [17.5–55.3]
  - one-way app -> S1-U (UL, terkoreksi): 24.0 [6.5–39.7]; -> SGi: 24.3
  - dekomposisi via pcap br-emu magen: app->br-emu 2.4 [2.1–3.1] | br-emu->S1-U 21.6 [4.1–37.4] (porsi radio srsUE/ZMQ UL + VM)
    | core S1-U->SGi 0.33 | reflector 0.12 | DL S1-U->br-emu 8.8 [6.6–11.8]
- Run 2 (run-20261117-154220, beban lebih besar): RTT p50 66 ms p90 264 ms (forwarder Java + logcat per paket saat Chrome memuat banyak flow).

## Trade-off / keterbatasan
- Marker **per flow** (SYN/EST/tiap 10 segmen/FIN), bukan per paket TLS. Paket TLS Chrome tidak diubah; header IP asli tidak sampai jaringan
  (forwarder level koneksi + slirp NAT), jadi stempel per paket butuh enkapsulasi/IP option yang tidak tembus slirp/forwarder.
  Marker menumpang jalur & bearer yang sama sehingga latensinya representatif untuk paket flow itu pada saat itu, tapi tidak identik per segmen.
- Akurasi absolut one-way dibatasi skew terukur (EMU ±~7 ms, VM ±~2 ms) tanpa chrony; jam tidak diubah. VM drift ~ −1 ms/menit relatif magen
  (−8.94 -> −8.997 s dalam ~1 jam) -> ukur skew tiap run (56-test sudah melakukannya sebelum & sesudah).
- Selisih antar titik tap di VM (S1-U->S5/S8->SGi) akurat sub-ms karena satu jam.
- De-proxy hanya untuk CONNECT; resolusi DNS oleh forwarder (bukan Chrome). sport tidak bisa dikorelasikan (slirp + SNAT), korelasi pakai dst ip:port + waktu.
- pkg uid: Android 11+ package visibility -> manifest `<queries>` com.android.chrome.
