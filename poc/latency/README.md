# PoC latency per paket — fase 0, 1, 2, dan inet (termasuk CGNAT UDP)

Tujuan: membuktikan jalur dari aplikasi di emulator Android sampai server di SGi lab (`l5g-server`, `10.99.9.20`), lewat UE srsRAN di **lab5g-vm**, bahwa Zeek (`netprobe-zeek-live`) mencatat flow tersebut (termasuk parent GTP-U), lalu mengukur latency one-way per flow dengan penanda MGLT, dan memberi UE/emulator akses internet lewat proxy SGi.

Lokasi di repo: `poc/latency/`. Skrip operasional ditulis untuk dijalankan di host lab (hypervisor emulator) dengan salinan tree di `~/poc-latency/` (fase 1–2 mensource `~/poc-latency/phase0/common-vm.sh`, dengan fallback ke `phase0/scripts/common-vm.sh`). Set `LAB_USER` (atau `LAB_SSH_KEY` / `LAB_SSH_KNOWN_HOSTS` / `LAB_SSH_KEY_DEV`) sebelum SSH ke VM; path kunci di skrip memakai placeholder, bukan username personal. Untuk tunnel internet dari laptop, set juga `MAGEN_HOST` dan `MAGEN_USER` (lihat `inet/README.md`).

## Status

| Fase | Hasil | Waktu (Asia/Bangkok, WIB) | Keterangan |
|---|---|---|---|
| 0 | **PASS** | 11:53, 17 Nov 2026 | Emulator (tanpa VPN dummy) → UE `10.45.0.38` → GTP-U → `10.99.9.20`. Bukti: `phase0/lab5g-vm/vm-run-20261117-115354/` |
| 1 | **PASS** | run `run-20261117-144129` (14:41, 17 Nov 2026) | App VPN dummy **v0.6-poc** (`id.magnon.poc.examine`). UDP echo `:9000` 5/5 (RTT 32–40 ms, payload cocok). TCP `:5201` 3/3 (connect 41–54 ms). Zeek `conn.log`/`tunnel.log` mencatat flow dari `10.45.0.39` dengan parent GTPv1 S1-U (VLAN 102). |
| inet (TCP+DNS) | **PASS** | 15:07, 17 Nov 2026 | UE/emulator → SGi → SOCKS → laptop. `curl https://example.com` dari netns UE http=200 dalam 0,28 s; Zeek `conn`/`dns`/`ssl` mencatat flow `10.45.0.39` (SNI example.com, www.google.com) dengan parent GTP. |
| inet CGNAT UDP | **PASS** | 17:28, 17 Nov 2026 | NAT44 SNAT `10.45/16` → `100.64.0.1` (RFC 6598, port-block per UE) + TPROXY ke gost UDP-over-TCP (`ssh -R 11081` ke relay laptop). DNS UDP `@8.8.8.8` NOERROR 70–92 ms; QUIC UDP 443 Google/YouTube membalas ~97 ms; Cloudflare timeout untuk probe minimal (belum diselidiki). ICMP tetap tidak lewat. |
| 2 | **PASS** | run acuan `run-20261117-154824` (15:48, 17 Nov 2026) | Chrome 109 di emulator lewat VPN dummy **v0.7-poc** + penanda MGLT per flow. 36/36 marker echo, CRC cocok. Zeek instance terpisah `poc-phase2-zeek-mglt` menulis `mglt.log` (S1-U, S5/S8, SGi). |

Run fase 1 yang gagal (UE RRC IDLE, EMM cause `0x9`, `No Context in TEID` / GTP Cause 64) **tidak** dilampirkan; diringkas di `phase1/README.md`. Akar masalahnya status UE di core, bukan aplikasi atau jalur emulator.

## Hasil latency fase 2 (fakta hasil ukur)

Run acuan `phase2/results/run-20261117-154824/` (p50, ms, skew sudah dikoreksi):

| Segmen | p50 | min–max |
|---|---|---|
| RTT marker di app (UE → reflector `:9000` → UE) | **33,0** | 17,5–55,3 |
| One-way app → S1-U (UL) | **24,0** | 6,5–39,7 |
| di dalamnya: app → bridge emulator | 2,4 | 2,1–3,1 |
| di dalamnya: bridge → S1-U (radio srsUE/ZMQ + VM) | 21,6 | 4,1–37,4 |
| Core S1-U → SGi | **0,33** | max 0,66 |
| Reflector turnaround di SGi | 0,12 | max 1,14 |
| Downlink S1-U → bridge emulator | **8,8** | 6,6–11,8 |

Dengan beban lebih berat (run 2, tidak dilampirkan): RTT p50 66 ms, p90 264 ms. Dugaan: overhead forwarder Java + logcat; belum diuji terpisah.

**De-proxy.** Emulator punya `settings global http_proxy = 172.26.0.1:8080` (socat di host lab, bukan jalur lab). Setting itu **tidak diubah**. App v0.7 men-terminasi `CONNECT` ke proxy tersebut, resolve + connect ke tujuan asli lewat jalur UE, lalu relay TLS Chrome utuh. Dimatikan dengan `--es deproxy off`.

**Skew dan akurasi.** Chrony belum dipasang (jam tidak diubah). Offset terukur vs host lab pada run acuan: VM/Zeek −8,9967 s (±2,2 ms), emulator −3,9298 s (±6,8 ms). Koreksi one-way = raw + 5,0670 s, dihitung tiap run (`55-skew.sh`). Akurasi absolut one-way sekitar ±7–9 ms; jam VM bergeser ~0,85 ms/menit relatif host lab. Selisih antar tap di dalam VM (S1-U → SGi) akurat di bawah 1 ms. Penanda dikirim **per flow**, bukan per paket TLS (stempel per paket tidak tembus slirp maupun forwarder level koneksi).

## CGNAT UDP (fakta hasil ukur)

Desain lengkap ada di `inet/README.md` (bagian **CGNAT UDP**). Ringkasannya: UDP dari UE `10.45.0.0/16` ke tujuan non-privat di-SNAT di netns `l5g-server` ke `100.64.0.1` (RFC 6598) dengan port-block 240 port per UE (untuk `10.45.0.39`: `10144–10383`), lalu di-TPROXY di host VM ke gost `redu://:12346` → `relay://127.0.0.1:11081` → `ssh -R` dari host lab ke gost relay UDP-over-TCP di laptop. Mapping tercatat di `/home/lab/poc-inet/cgnat-map.log` (log mentah tidak dilampirkan). DNS UDP ke 8.8.8.8 melewati CGNAT hanya jika relay `:11081` hidup. TCP tetap lewat SOCKS.

Tes 17:28 WIB (Asia/Bangkok), 17 Nov 2026, dari netns UE `10.45.0.39`:

- DNS UDP `@8.8.8.8`: NOERROR 70–92 ms (`www.google.com`, `www.youtube.com`, `cloudflare-quic.com`).
- QUIC UDP 443: Google dan YouTube membalas (~97 ms); Cloudflare timeout untuk probe minimal, belum diselidiki.
- Contoh mapping: `{"ev":"NEW","ue":"10.45.0.39:51901","pub":"100.64.0.1:10169","dst":"142.251.154.119:443"}`.

Keterbatasan: bergantung laptop online + WSL berjalan; trafik keluar memakai IP laptop; ICMP tidak didukung. Rollback: `49-inet-rollback.sh` (memanggil `cgnat.sh remove`) dan di WSL `poc-inet-laptop.sh udp-stop`. Sementara, `touch /home/lab/poc-inet/cgnat_off` di VM menonaktifkan CGNAT tanpa memutus jalur TCP.

## Fakta vs usulan

Ditandai di `ARCHITECTURE.md` dan di bawah.

**Fakta (sudah diuji di lab):**

- Jalur emulator → policy routing/SNAT di host lab → `lab5g-vm` → netns `l5g-ue` (`tun_srsue`) → S1-U → `l5g-server`.
- VpnService dummy mode examine (v0.6) meneruskan TCP dan UDP, mencatat timestamp per paket di logcat (`ts=`, `mono_ns=`), dan berhenti lewat broadcast `StopReceiver` (`tun0` hilang). v0.7 menambah allowed Chrome, marker MGLT per flow, dan de-proxy CONNECT.
- Zeek yang aktif di lab ini adalah `netprobe-zeek-live` (bukan kontainer `l5g-probe-zeek-*`, yang lognya kosong sejak 3 Nov 2026). Fase 2 memakai instance terpisah `poc-phase2-zeek-mglt` (~90 MiB) di `mirror0` (libpcap, bukan af_packet) agar probe live tidak di-restart.
- **UE tidak boleh idle.** Setelah attach, pasang keepalive permanen (`phase1/scripts/35-keepalive.sh start`: ping 1×/3 s dari netns `l5g-ue` ke `10.99.9.20`). Kalau UE idle lama, service request bisa ditolak dan attach ulang gagal.
- **Urutan RAN:** siklus bersih sesuai `lab-up.sh` lab5g-vm — **eNB dulu, UE 8 detik kemudian**. Restart UE atau eNB saja sering tidak cukup untuk memulihkan konteks.
- **Clock skew terukur** (vs jam host lab): pada fase 1 (run 14:41) VM/Zeek **−8,94 s**, emulator **−3,91 s**; pada fase 2 (15:48) VM **−8,9967 s**, emulator **−3,9298 s**. Akurasi target adalah milidetik, jadi chrony cukup (PTP tidak diperlukan), tetapi **belum dipasang**.
- Internet UE lewat SGi → gost redirect/DNS → SOCKS di host lab → reverse SSH ke laptop (script `inet/` + `lab-up-poc.sh`). Guard di VM memasang ulang aturan tiap 10 s.
- UDP dari UE ke internet lewat CGNAT (NAT44 `100.64.0.1` + gost UDP-over-TCP ke laptop, `ssh -R 11081`). Teruji 17:28 WIB.

**Usulan (belum dikerjakan, menunggu persetujuan):**

- Sinkronisasi jam dengan chrony di lab5g-vm (dan sumber NTP di host lab).

## Cara pakai skrip

Di host lab, setelah `LAB_USER` (atau path kunci SSH) diset, dan tree ada di `~/poc-latency/`:

```bash
# All-in-one: UE (siklus RAN bila perlu), keepalive, jalur emulator, echo UDP, inet
# Prasyarat inet: tunnel laptop sudah start, dan inet/bin/gost sudah dipasang (lihat inet/README.md)
bash ~/poc-latency/lab-up-poc.sh            # atau --no-inet
bash ~/poc-latency/lab-down-poc.sh          # atau --inet-only

# Fase 0 — jalur emulator ke lab5g-vm (tanpa app VPN)
bash ~/poc-latency/phase0/scripts/10-inspect-vm.sh
bash ~/poc-latency/phase0/scripts/20-setup-vm.sh    # policy rule 2099, SNAT, tag poc-phase0
bash ~/poc-latency/phase0/scripts/21-test-vm.sh
bash ~/poc-latency/phase0/scripts/22-collect-zeek-vm.sh

# RAN: jika UE tidak attach, siklus bersih (eNB dulu, UE +8 s)
bash ~/poc-latency/phase1/scripts/37-ran-cycle.sh

# Keepalive permanen — pasang segera setelah attach, jangan biarkan UE idle
bash ~/poc-latency/phase1/scripts/35-keepalive.sh start   # status | stop

# Fase 1 — app VPN dummy v0.6 (APK dibangun dari phase1/app/, tidak dilampirkan di git)
bash ~/poc-latency/phase1/app/build.sh
bash ~/poc-latency/phase1/scripts/30-install.sh
bash ~/poc-latency/phase1/scripts/32-udp-echo-start.sh    # echo UDP :9000 di l5g-server
bash ~/poc-latency/phase1/scripts/31-test.sh

# Inet — setelah gost ada di inet/bin/gost dan tunnel laptop aktif
bash ~/poc-latency/inet/40-inet-setup.sh
bash ~/poc-latency/inet/41-inet-status.sh
bash ~/poc-latency/inet/42-inet-test.sh
# CGNAT UDP — di WSL juga: poc-inet-laptop.sh udp-start (perlu ~/poc-inet/gost)
bash ~/poc-latency/inet/44-cgnat-test.sh

# Fase 2 — Chrome + marker MGLT (APK dibangun dari phase2/app/)
bash ~/poc-latency/phase2/scripts/52-zeek-selftest.sh
bash ~/poc-latency/phase2/scripts/53-zeek-start.sh
bash ~/poc-latency/phase2/app/build.sh
bash ~/poc-latency/phase2/scripts/54-install-app.sh
bash ~/poc-latency/phase2/scripts/56-test.sh              # lalu 58-analyze.py <run-dir>
```

Di laptop (WSL), setelah `MAGEN_HOST` / `MAGEN_USER` diset (atau alias SSH `magen` di `~/.ssh/config`):

```bash
# salin inet/laptop/poc-inet-laptop.sh ke ~/poc-inet/ lalu:
bash ~/poc-inet/poc-inet-laptop.sh start     # atau up-all (start + udp-start + lab-up-poc.sh)
# untuk CGNAT UDP (setelah gost ada di ~/poc-inet/gost):
bash ~/poc-inet/poc-inet-laptop.sh udp-start
```

Skrip `phase0/scripts/01–06` dan `99-rollback.sh` adalah jalur **lab5g-dev** (inspeksi awal; VM itu kemudian di-shutdown). Jalur yang lulus tes adalah **lab5g-vm**.

## Rollback

```bash
bash ~/poc-latency/phase2/scripts/59-rollback.sh     # app v0.7 / Zeek MGLT (KEEP_APP=1, PURGE=1)
bash ~/poc-latency/lab-down-poc.sh                   # inet + echo + keepalive + jalur emulator
# atau manual:
# bash ~/poc-latency/inet/49-inet-rollback.sh
# bash ~/poc-latency/phase1/scripts/35-keepalive.sh stop
# bash ~/poc-latency/phase1/scripts/38-udp-echo-stop.sh
# bash ~/poc-latency/phase1/scripts/39-rollback.sh
# bash ~/poc-latency/phase0/scripts/29-rollback-vm.sh
# Jalur lab5g-dev (jika pernah dipasang): bash ~/poc-latency/phase0/scripts/99-rollback.sh
# Tunnel laptop: di WSL  bash ~/poc-inet/poc-inet-laptop.sh down-all   # atau udp-stop; stop
```

## Isi folder

| Path | Isi |
|---|---|
| `ARCHITECTURE.md` | Desain PoC (fakta repo vs usulan), termasuk format MGLT |
| `lab-up-poc.sh` / `lab-down-poc.sh` | Bring-up / rollback all-in-one (UE, keepalive, emulator, echo, inet) |
| `phase0/` | README, skrip, bukti run 11:53 (`zeek-extract.txt`, `android-traffic.txt`, `zeek-live/*.log`) |
| `phase1/app/` | Sumber app Java v0.6-poc + `build.sh` (bukan APK/keystore) |
| `phase1/scripts/` | Install, tes, echo UDP, keepalive, siklus RAN, rollback |
| `phase1/results/run-20261117-144129/` | Bukti run lulus (teks, `screen-gen.png`, `screen-vpn.png`; tanpa pcap) |
| `inet/` | Script 40–49 (termasuk `44-cgnat-test.sh`), `vm/` (apply/guard/remove + `cgnat.sh`, `cgnat-map.py`, `udp-check.py`), `laptop/` (SOCKS + relay UDP gost), README (termasuk unduh gost dan CGNAT UDP), hasil Zeek teks |
| `phase2/app/` | Sumber app Java v0.7-poc + `build.sh` (bukan APK/keystore) |
| `phase2/zeek/` | `mglt.zeek`, run scripts, pcap selftest kecil |
| `phase2/scripts/` | 50–59, termasuk `58-analyze.py` dan rollback; `45-inet-install.sh` (pasang script inet yang di-stage) |
| `phase2/results/run-20261117-154824/` | `summary.txt`, `mglt-joined.csv`, `screen-chrome-2.png` |

Yang **tidak** masuk: APK, `debug.keystore`, pcap besar, logcat penuh, arsip `.tgz`, binary `gost` (unduh terpisah; lihat `inet/README.md`), output inspeksi mentah `*.out`, salinan repo lain, dan folder `lab5g-dev` (selain skrip di `phase0/scripts/`).
