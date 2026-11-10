# Smoke test pemulihan lab5g-dev — 10 Nov 2026 15:31 WIB

Ringkasan hasil setelah lab5g-dev dipulihkan ke baseline `master` (`3af0834`). Langkah pemulihan ada di [`docs/ops/runbook-lab5g-dev-restore.md`](../../ops/runbook-lab5g-dev-restore.md). Inventaris ada di [`docs/ops/lab5g-dev-inventory-20261110.md`](../../ops/lab5g-dev-inventory-20261110.md).

Cakupan: lab5g-dev saja. Tidak ada alamat internal, secret, kunci, token, IMSI, Ki, atau OPc di dokumen ini. Tidak ada pcap yang diarsipkan (tcpdump hanya dipakai untuk diagnosis rute S11, tidak disimpan).

**Waktu:** 10 Nov 2026 15:31 WIB (Asia/Bangkok).

## Status fungsi jaringan

Semua NF berikut berstatus **Up**: `mongo`, `hss`, `pcrf`, `mme`, `sgwc`, `sgwu`, `smf`, `upf`, `server`, `enb`, `ue`.

| Pemeriksaan | Hasil |
|---|---|
| S1 Setup | Diterima MME (`eNBs=1`) |
| Sx (PFCP) | SMF associated dengan UPF; SGW-C associated dengan SGW-U |
| Gx | SMF–PCRF **CONNECTED** |
| Attach UE | `Network attach successful` |
| EN-DC | `RRC NR reconfiguration successful` |
| Sesi aktif | SMF=1, SGW-U=1, UPF=1 |

## Uji ping SGi

Arah: UE → `core.server` melalui `tun_srsue`.

- 5/5 balasan, 0% loss
- RTT rata-rata 45,3 ms (min 32,2 ms, max 67,3 ms)

## Catatan

- CCR Gx tidak tercatat pada log level info, sehingga tidak dipakai sebagai bukti sesi kebijakan.
- Pcap tidak diarsipkan; diagnosis rute memakai tcpdump di bridge `s5s8` tanpa menyimpan berkas.
- Temuan sisa yang tidak diubah (rute default UPF ke node `cgnat` yang sudah dihapus, mount `bin/open5gs-upfd` yang tidak ada di guest) dicatat di runbook dan tidak memengaruhi hasil SGi lokal di atas.
