# poc-inet: internet untuk UE/emulator lab5g-vm lewat SGi → SOCKS → laptop (tag: poc-inet)

Status: AKTIF dan teruji 2026-11-17 15:07 WIB (TCP+DNS, UE 10.45.0.39). CGNAT UDP teruji 17:28 WIB (Asia/Bangkok).

## Prasyarat

Di **host lab**, set `LAB_USER` (atau `LAB_SSH_KEY` / `LAB_SSH_KNOWN_HOSTS`) sebelum SSH ke VM — sama seperti fase 0/1. Path kunci memakai placeholder, bukan username personal.

Di **laptop (WSL)**, sebelum `poc-inet-laptop.sh`:

```bash
export MAGEN_HOST=<IP atau hostname hypervisor lab>
export MAGEN_USER=<user SSH>          # atau LAB_USER
# opsional:
export MAGEN_SSH_KEY=/path/ke/kunci
```

Jika alias SSH `Host magen` sudah ada di `~/.ssh/config` (berisi `HostName` dan `User`), variabel itu bisa diisi otomatis dari sana. Nilai host/user **tidak** di-hardcode di skrip.

Juga pasang binary `gost` (lihat [di bawah](#gost)): di host lab `inet/bin/gost`, dan untuk CGNAT UDP salin binary yang sama ke `~/poc-inet/gost` di WSL.

## Arsitektur

UE srsUE (l5g-ue, default dev tun_srsue) / emulator (jalur fase 0, di-MASQ ke IP UE)
 → eNB → S1-U GTP-U → SGW-U → S5/S8 → UPF (ip rule 2100: from 10.45/16 iif ogstun ke non-privat → 10.99.9.20)
 → l5g-server netns: iptables nat POC_INET: DNS (udp/tcp 53, tujuan apa pun) → gost dns :10053 (upstream tcp://1.1.1.1:53);
    TCP ke non-privat → gost red :12345   (ICMP tetap tidak didukung)
 → socks5 10.99.9.254:11080 (gost tcp fwd di host VM, bind bridge SGi saja) → VM 127.0.0.1:11080
 → ssh -R dari host lab (loop run/vm-tunnel.sh) → host lab 127.0.0.1:11080
 → ssh reverse dynamic SOCKS dari laptop WSL (RemoteForward 127.0.0.1:11080) → internet via laptop.

Emulator: host lab ip rule 2100 (iif br-cc78098cfad4 → VM untuk non-privat), VM ip rule 2100 (iif ens3 from 172.22.10.1 → l5g-ue),
DOCKER-USER poc-inet. DNS emulator: slirp 10.0.2.3 → docker DNS container → 8.8.8.8 (resolv host lab) → ikut jalur lab → di-redirect ke gost dns.
SMF dns = 10.99.9.20 (tidak diubah; core Open5GS config TIDAK disentuh).

## CGNAT UDP

UDP dari UE `10.45.0.0/16` ke tujuan non-privat tidak lewat SOCKS. Jalurnya NAT44 + relay UDP-over-TCP:

1. **NAT44 di l5g-server (RFC 6598):** ip rule 2101 from 10.45/16, table 2101 default via 10.99.9.254 (throw prefix privat). iptables nat `POC_CGNAT`: SNAT UDP `10.45.0.N` → `100.64.0.1` dengan port-block 240 port per UE (basis 1024; untuk UE `10.45.0.39` bloknya `10144–10383`). Sisa 10.45/16 → `100.64.0.2`. Filter `POC_CGNAT_FWD` hanya meneruskan UDP non-privat.
2. **TPROXY di host VM:** UDP dari pool `100.64.0.0/29` di bridge SGi di-TPROXY ke gost `redu://:12346`, lalu di-forward ke `relay://127.0.0.1:11081`. ip rule 2101 mengembalikan jawaban ke l5g-server; fwmark 0x2101 / table 2102 ke local; DOCKER-USER drop sisa pool agar tidak bocor ke ens3.
3. **Relay ke laptop:** `ssh -R 127.0.0.1:11081` dari host lab (`run/vm-tunnel-udp.sh`) ke gost relay UDP-over-TCP di laptop WSL (`poc-inet-laptop.sh udp-start`). Trafik keluar ke internet memakai IP laptop.
4. **DNS UDP ke 8.8.8.8** (daftar `CGNAT_DNS`, default 8.8.8.8) dikecualikan dari redirect gost dns **hanya** saat relay `:11081` hidup; kalau relay mati, DNS itu kembali ke gost dns (TCP).
5. **Log mapping:** `cgnat-map.py` (ctnetlink, di netns l5g-server) menulis JSON per baris ke `/home/lab/poc-inet/cgnat-map.log` (rotasi 5 MB × 3). Log mentah **tidak** dilampirkan di repo. Contoh (tes 17:28 WIB):

   `{"ev":"NEW","ue":"10.45.0.39:51901","pub":"100.64.0.1:10169","dst":"142.251.154.119:443"}`

Guard `apply.sh` memanggil `cgnat.sh apply` tiap 10 s, kecuali jika file `/home/lab/poc-inet/cgnat_off` ada (TCP/DNS tetap jalan, CGNAT dilewati).

### Hasil tes 17:28 WIB (Asia/Bangkok), 17 Nov 2026 — fakta hasil ukur

Dari netns UE `10.45.0.39` (tanpa gost dns untuk 8.8.8.8):

- **DNS UDP `@8.8.8.8`:** NOERROR dalam 70–92 ms (`www.google.com`, `www.youtube.com`, `cloudflare-quic.com`).
- **QUIC UDP 443** (probe version negotiation minimal):
  - Google dan YouTube membalas (sekitar 97 ms).
  - Cloudflare timeout untuk probe ini. Kemungkinan karena paket uji yang dipakai sangat minimal; belum diselidiki.
- **NAT44:** `10.45.0.39` di-SNAT ke `100.64.0.1` dengan port-block `10144–10383`.

### Rollback CGNAT

```bash
bash ~/poc-latency/inet/49-inet-rollback.sh          # memanggil vm/remove.sh → cgnat.sh remove, plus tunnel TCP/UDP host lab
# atau hanya matikan CGNAT, jalur TCP tetap:
#   touch /home/lab/poc-inet/cgnat_off                # di VM; guard tidak memanggil apply
# Laptop (WSL):
bash ~/poc-inet/poc-inet-laptop.sh udp-stop          # atau down-all (lab-down + udp-stop + stop)
```

## gost

Binary `gost` **tidak** dilampirkan di repo. Dipakai **gost 3.3.3** (linux/amd64) dari rilis resmi [go-gost/gost v3.3.3](https://github.com/go-gost/gost/releases/tag/v3.3.3).

```bash
# di tree poc/latency (atau ~/poc-latency)
mkdir -p inet/bin
curl -fsSL -o /tmp/gost_3.3.3_linux_amd64.tar.gz \
  https://github.com/go-gost/gost/releases/download/v3.3.3/gost_3.3.3_linux_amd64.tar.gz
echo 'f4c1255dc892a7014c0ad6e5f1c3573108f7bea4403f04f21873406ab58aa666  /tmp/gost_3.3.3_linux_amd64.tar.gz' | sha256sum -c
tar -xf /tmp/gost_3.3.3_linux_amd64.tar.gz -C inet/bin gost
chmod +x inet/bin/gost
inet/bin/gost -V    # expect: gost 3.3.3 (go1.27.3 linux/amd64)
sha256sum inet/bin/gost
# untuk CGNAT UDP, salin binary yang sama ke laptop (WSL):
#   cp inet/bin/gost ~/poc-inet/gost && chmod +x ~/poc-inet/gost
```

Checksum:

| Artefak | SHA-256 |
|---|---|
| `gost_3.3.3_linux_amd64.tar.gz` (resmi) | `f4c1255dc892a7014c0ad6e5f1c3573108f7bea4403f04f21873406ab58aa666` |
| binary `gost` hasil extract (teruji di lab) | `a60f87707d679d154fad93d05313284baf3dea71fdb9ec18afecaac35db946dd` |

`40-inet-setup.sh` menolak jalan jika `inet/bin/gost` belum ada. `poc-inet-laptop.sh udp-start` menolak jalan jika `~/poc-inet/gost` belum ada.

## Script

Host lab `~/poc-latency/inet/` (salinan di sini):

- `40-inet-setup.sh`  setup idempoten (salin gost + `cgnat.sh`/`cgnat-map.py`/`udp-check.py` ke VM `/home/lab/poc-inet`, vm-tunnel + vm-tunnel-udp loop, apply.sh + guard.sh di VM, rule host lab)
- `41-inet-status.sh` status (termasuk relay UDP `:11081` dan `cgnat.sh status`)
- `42-inet-test.sh [wait_zeek]` tes UE+emulator+Zeek → `run/test-*/`
- `43-emu-chrome.sh [url]`
- `44-cgnat-test.sh [wait_zeek]` tes DNS UDP @8.8.8.8 dan QUIC UDP 443 dari netns UE → `run/cgnat-*/`
- `44-cgnat-inspect.sh` inspeksi read-only prasyarat CGNAT
- `49-inet-rollback.sh` rollback semua sisi host lab + VM (termasuk CGNAT)
- `vm/apply.sh` (idempoten, dijalankan guard tiap 10 s: tahan restart l5g-server/upf/ue; memanggil `cgnat.sh apply` kecuali `cgnat_off`)
- `vm/remove.sh`, `vm/guard.sh`, `vm/cgnat.sh`, `vm/cgnat-map.py`, `vm/udp-check.py`

Laptop WSL `~/poc-inet/poc-inet-laptop.sh` (salinan `laptop/`): `start|stop|status|udp-start|udp-stop|udp-status|up-all|down-all`
  (config khusus `~/.ssh/poc-inet.conf` / `poc-inet-udp.conf` tanpa LocalForward alias lain; loop di wsl.exe tersembunyi; pid `~/poc-inet/tunnel.pid` dan `udp-tunnel.pid`)

All-in-one host lab: `~/poc-latency/lab-up-poc.sh [--no-inet]`, `~/poc-latency/lab-down-poc.sh [--inet-only]`

Pemutakhiran script inet di lab (backup dulu, lalu setup): `bash ~/poc-latency/phase2/scripts/45-inet-install.sh` (sumber: `phase2/inet-stage/`, tidak dilampirkan di repo).

## Bukti (results/)

Ringkasan teks (screenshot Chrome tidak dilampirkan; halaman still first-run, bukan masalah jaringan):

- UE: `dig @10.99.9.20 example.com` NOERROR 172.66.147.243 (128 ms); `dig @8.8.8.8 google.com` OK;
  `curl --interface tun_srsue https://example.com` http=200 connect 21 ms tls 159 ms total 275 ms `<title>Example Domain`;
  `https://www.google.com` http=200 0.52 s; ping 8.8.8.8 100% loss (sesuai desain, ICMP tidak lewat SOCKS); ping 10.99.9.20 OK.
- Emulator container (172.26.0.2 → jalur lab): `curl https://example.com` http=200 0.31 s; Android: resolve example.com OK, HTTP HEAD :80 via nc
  (Zeek http.log HEAD example.com dari 10.45.0.39).
- Zeek `netprobe-zeek-live` (`results/zeek-20261117-150744.txt`): conn ssl SF 10.45.0.39 → 172.66.147.243:443, 142.251.152.119:443;
  dns.log query example.com/google.com/www.google.com tap s1u/s5s8/sgi; ssl.log server_name example.com, www.google.com (TLSv13, tap s1u);
  tunnel_parents GTPv1 s1u VLAN 102 (10.99.2.20↔10.99.2.12) dan s5s8 VLAN 105. ts Zeek = jam VM (~8,9 s di belakang host lab).
- CGNAT UDP 17:28 WIB: lihat [di atas](#hasil-tes-1728-wib-asiabangkok-17-nov-2026--fakta-hasil-ukur). Log `cgnat-map.log` dan output mentah tes tidak dilampirkan.

## Keterbatasan

Bergantung laptop online + WSL berjalan; trafik keluar memakai IP laptop; throughput dibatasi ssh 2 hop + uplink laptop; RTT internet tidak representatif untuk latency radio.
TCP tetap lewat SOCKS; UDP non-privat lewat CGNAT (DNS UDP ke 8.8.8.8 hanya jika relay `:11081` hidup). ICMP tetap tidak lewat.
Probe QUIC minimal ke Cloudflare masih timeout (belum diselidiki). Chrome HTTP/3 lewat VPN dummy belum menjadi bagian tes 17:28.
