# PoC latency per paket — fase 0 & 1

Tujuan: membuktikan jalur dari aplikasi di emulator Android sampai server di SGi lab (`l5g-server`, `10.99.9.20`), lewat UE srsRAN di **lab5g-vm**, dan bahwa Zeek (`netprobe-zeek-live`) mencatat flow tersebut (termasuk parent GTP-U). Pengukuran latency **per paket** (sisipan timestamp MGLT) belum diimplementasikan.

Lokasi di repo: `poc/latency/`. Skrip operasional ditulis untuk dijalankan di host lab (hypervisor emulator) dengan salinan tree di `~/poc-latency/` (fase 1 mensource `~/poc-latency/phase0/common-vm.sh`). Set `LAB_USER` (atau `LAB_SSH_KEY` / `LAB_SSH_KNOWN_HOSTS` / `LAB_SSH_KEY_DEV`) sebelum SSH ke VM; path kunci di skrip memakai placeholder, bukan username personal.

## Status

| Fase | Hasil | Waktu (Asia/Bangkok, WIB) | Keterangan |
|---|---|---|---|
| 0 | **PASS** | 11:53, 17 Nov 2026 | Emulator (tanpa VPN dummy) → UE `10.45.0.38` → GTP-U → `10.99.9.20`. Bukti: `phase0/lab5g-vm/vm-run-20261117-115354/` |
| 1 | **PASS** | run `run-20261117-144129` (14:41, 17 Nov 2026) | App VPN dummy **v0.6-poc** (`id.magnon.poc.examine`). UDP echo `:9000` 5/5 (RTT 32–40 ms, payload cocok). TCP `:5201` 3/3 (connect 41–54 ms). Zeek `conn.log`/`tunnel.log` mencatat flow dari `10.45.0.39` dengan parent GTPv1 S1-U (VLAN 102). |

Run fase 1 yang gagal (UE RRC IDLE, EMM cause `0x9`, `No Context in TEID` / GTP Cause 64) **tidak** dilampirkan; diringkas di `phase1/README.md`. Akar masalahnya status UE di core, bukan aplikasi atau jalur emulator.

## Fakta vs usulan

Ditandai di `ARCHITECTURE.md` dan di bawah.

**Fakta (sudah diuji di lab):**

- Jalur emulator → policy routing/SNAT di host lab → `lab5g-vm` → netns `l5g-ue` (`tun_srsue`) → S1-U → `l5g-server`.
- VpnService dummy mode examine (v0.6) meneruskan TCP dan UDP, mencatat timestamp per paket di logcat (`ts=`, `mono_ns=`), dan berhenti lewat broadcast `StopReceiver` (`tun0` hilang).
- Zeek yang aktif di lab ini adalah `netprobe-zeek-live` (bukan kontainer `l5g-probe-zeek-*`, yang lognya kosong sejak 3 Nov 2026).
- **UE tidak boleh idle.** Setelah attach, pasang keepalive permanen (`phase1/scripts/35-keepalive.sh start`: ping 1×/3 s dari netns `l5g-ue` ke `10.99.9.20`). Kalau UE idle lama, service request bisa ditolak dan attach ulang gagal.
- **Urutan RAN:** siklus bersih sesuai `lab-up.sh` lab5g-vm — **eNB dulu, UE 8 detik kemudian**. Restart UE atau eNB saja sering tidak cukup untuk memulihkan konteks.
- **Clock skew terukur** (vs jam host lab, dari SYN TCP yang sama pada run 14:41): lab5g-vm/Zeek **−8,94 s**; emulator **−3,91 s**. Akurasi target adalah milidetik, jadi chrony cukup (PTP tidak diperlukan), tetapi **belum dipasang**.

**Usulan (belum dikerjakan, menunggu persetujuan):**

- Sinkronisasi jam dengan chrony di lab5g-vm (dan sumber NTP di host lab).
- Sisipan timestamp MGLT di payload probe (lihat `ARCHITECTURE.md`).
- Egress internet UE lewat proxy SGi (script `lab-up-poc.sh` / `lab-down-poc.sh` dan `inet/` belum final; tidak masuk PR ini).

## Cara pakai skrip

Di host lab, setelah `LAB_USER` (atau path kunci SSH) diset, dan tree ada di `~/poc-latency/`:

```bash
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
```

Skrip `phase0/scripts/01–06` dan `99-rollback.sh` adalah jalur **lab5g-dev** (inspeksi awal; VM itu kemudian di-shutdown). Jalur yang lulus tes adalah **lab5g-vm**.

## Rollback

```bash
bash ~/poc-latency/phase1/scripts/35-keepalive.sh stop
bash ~/poc-latency/phase1/scripts/38-udp-echo-stop.sh
bash ~/poc-latency/phase1/scripts/39-rollback.sh      # app / sisa tes fase 1
bash ~/poc-latency/phase0/scripts/29-rollback-vm.sh   # rule 2099, SNAT, tag poc-phase0
# Jalur lab5g-dev (jika pernah dipasang): bash ~/poc-latency/phase0/scripts/99-rollback.sh
```

## Isi folder

| Path | Isi |
|---|---|
| `ARCHITECTURE.md` | Desain PoC (fakta repo vs usulan), termasuk format MGLT |
| `phase0/` | README, skrip, bukti run 11:53 (`zeek-extract.txt`, `android-traffic.txt`, `zeek-live/*.log`) |
| `phase1/app/` | Sumber app Java v0.6-poc + `build.sh` (bukan APK/keystore) |
| `phase1/scripts/` | Install, tes, echo UDP, keepalive, siklus RAN, rollback |
| `phase1/results/run-20261117-144129/` | Bukti run lulus (teks, `screen-gen.png`, `screen-vpn.png`; tanpa pcap) |

Yang **tidak** masuk: APK, `debug.keystore`, pcap, arsip `.tgz`, output inspeksi mentah `*.out`, salinan repo lain, folder `lab5g-dev` (selain skrip di `phase0/scripts/`), dan script inet yang belum final.
