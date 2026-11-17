# poc-inet: internet untuk UE/emulator lab5g-vm lewat SGi → SOCKS → laptop (tag: poc-inet)

Status: AKTIF dan teruji 2026-11-17 15:07 WIB (UE 10.45.0.39).

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

Juga pasang binary `gost` (lihat [di bawah](#gost)).

## Arsitektur

UE srsUE (l5g-ue, default dev tun_srsue) / emulator (jalur fase 0, di-MASQ ke IP UE)
 → eNB → S1-U GTP-U → SGW-U → S5/S8 → UPF (ip rule 2100: from 10.45/16 iif ogstun ke non-privat → 10.99.9.20)
 → l5g-server netns: iptables nat POC_INET: DNS (udp/tcp 53, tujuan apa pun) → gost dns :10053 (upstream tcp://1.1.1.1:53);
    TCP ke non-privat → gost red :12345   (UDP/ICMP non-DNS TIDAK didukung)
 → socks5 10.99.9.254:11080 (gost tcp fwd di host VM, bind bridge SGi saja) → VM 127.0.0.1:11080
 → ssh -R dari host lab (loop run/vm-tunnel.sh) → host lab 127.0.0.1:11080
 → ssh reverse dynamic SOCKS dari laptop WSL (RemoteForward 127.0.0.1:11080) → internet via laptop.

Emulator: host lab ip rule 2100 (iif br-cc78098cfad4 → VM untuk non-privat), VM ip rule 2100 (iif ens3 from 172.22.10.1 → l5g-ue),
DOCKER-USER poc-inet. DNS emulator: slirp 10.0.2.3 → docker DNS container → 8.8.8.8 (resolv host lab) → ikut jalur lab → di-redirect ke gost dns.
SMF dns = 10.99.9.20 (tidak diubah; core Open5GS config TIDAK disentuh).

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
```

Checksum:

| Artefak | SHA-256 |
|---|---|
| `gost_3.3.3_linux_amd64.tar.gz` (resmi) | `f4c1255dc892a7014c0ad6e5f1c3573108f7bea4403f04f21873406ab58aa666` |
| binary `gost` hasil extract (teruji di lab) | `a60f87707d679d154fad93d05313284baf3dea71fdb9ec18afecaac35db946dd` |

`40-inet-setup.sh` menolak jalan jika `inet/bin/gost` belum ada.

## Script

Host lab `~/poc-latency/inet/` (salinan di sini):

- `40-inet-setup.sh`  setup idempoten (salin gost ke VM `/home/lab/poc-inet`, vm-tunnel loop, apply.sh + guard.sh di VM, rule host lab)
- `41-inet-status.sh` status
- `42-inet-test.sh [wait_zeek]` tes UE+emulator+Zeek → `run/test-*/`
- `43-emu-chrome.sh [url]`
- `49-inet-rollback.sh` rollback semua sisi host lab + VM
- `vm/apply.sh` (idempoten, dijalankan guard tiap 10 s: tahan restart l5g-server/upf/ue), `vm/remove.sh`, `vm/guard.sh`

Laptop WSL `~/poc-inet/poc-inet-laptop.sh` (salinan `laptop/`): `start|stop|status|up-all|down-all`
  (config khusus `~/.ssh/poc-inet.conf` tanpa LocalForward alias lain; loop di wsl.exe tersembunyi; pid `~/poc-inet/tunnel.pid`)

All-in-one host lab: `~/poc-latency/lab-up-poc.sh [--no-inet]`, `~/poc-latency/lab-down-poc.sh [--inet-only]`

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

## Keterbatasan

Bergantung laptop online + WSL berjalan; hanya TCP + DNS (QUIC/UDP lain & ICMP gagal; browser fallback ke TCP);
throughput dibatasi ssh 2 hop + uplink laptop; RTT internet tidak representatif untuk latency radio; trafik keluar dari IP laptop.
