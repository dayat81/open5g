# Phase 0: emulator Android (magen) -> UE lab5g -> GTP-U -> l5g-server, terbukti di Zeek

## Hasil akhir (target: lab5g-vm 172.22.10.32, probe Zeek yang sudah ada)
- Emulator: container `b0-agen-emu` (= e679044a1016, open5g-android-emulator:local, Android 13/API 33), docker net b0-agen-net 172.26.0.2, Android eth0 10.0.2.15 (slirp).
- Jalur: Android -> slirp -> 172.26.0.2 -> magen (policy rule 2099, MASQ docker -> 172.22.10.1) -> VM ens3 (policy rule 2099)
  -> l5g-ue eth0 10.99.11.21 -> MASQUERADE ke IP UE 10.45.0.38 (tun_srsue) -> eNB -> S1-U GTP-U -> SGW-U -> UPF -> SGi -> l5g-server 10.99.9.20.
- Trafik (2026-11-17 11:53:57–11:54:09 WIB): ping 5/5 (RTT 26–334 ms), TCP 3x ke iperf3 :5201 yang sudah ada, UDP :9000 (ICMP unreachable).
- Bukti Zeek: `netprobe-zeek-live` (iface mirror0, VLAN per bridge), log /dev/shm/netprobe-zeek-live, salinan di lab5g-vm/vm-run-20261117-115354/zeek-live/.
  conn.log: 10.45.0.38 -> 10.99.9.20:5201 tcp SF (3 koneksi), icmp, udp 9000; tunnel_parents -> tunnel.log GTPv1 s1u (VLAN 102: 10.99.2.20<->10.99.2.12, 10.99.5.13->10.99.2.20) dan s5s8 (VLAN 105).
- Korelasi emulator: lab5g-vm/vm-run-*/magen-emu-br.pcap (172.26.0.2 <-> 10.99.9.20 sebelum NAT), counter MASQUERADE/DOCKER-USER di zeek-extract.txt.
- Catatan: jam lab5g-vm/lab5g-dev ~7–8 s di belakang magen (Zeek ts 04:53:53Z vs adb 11:54:01 WIB) -> perlu chrony sebelum ukur latency.
- Catatan: l5g-probe-zeek-* (s1u/sgi/…) jalan 2 minggu tapi /home/lab/lab5g/probe/zeek/* kosong sejak 3 Nov; yang aktif hanya netprobe-zeek-live.

## Scripts (dijalankan di magen dari ~/poc-latency/phase0)
- 20-setup-vm.sh (perubahan), 21-test-vm.sh (trafik + ekstrak Zeek), 22-collect-zeek-vm.sh, 29-rollback-vm.sh (rollback).
- lab5g-dev (dibatalkan karena perubahan arah): 05-setup.sh, 06-test.sh, 99-rollback.sh — SUDAH di-rollback.

## Perubahan aktif (lab5g-vm) — rollback: `bash ~/poc-latency/phase0/29-rollback-vm.sh`
magen:  ip rule 2099 `iif br-cc78098cfad4 to 10.99.9.20 lookup 2099`; table 2099 `10.99.9.20 via 172.22.10.32 dev virbr-lab5g`
VM:     ip rule 2099 `iif ens3 from 172.22.10.1 to 10.99.9.20 lookup 2099`; table 2099 `10.99.9.20 via 10.99.11.21 dev br-5bd8dbed8b33`
        DOCKER-USER: 2 ACCEPT (comment poc-phase0)
l5g-ue netns: route `172.22.10.1/32 via 10.99.11.254 dev eth0`; nat POSTROUTING `-s 172.22.10.1 -o tun_srsue -j MASQUERADE` (poc-phase0);
        route D5 `10.99.9.0/24 dev tun_srsue` (runbook lab-routes.sh; dibiarkan)
