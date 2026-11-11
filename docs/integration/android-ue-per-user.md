# One Android emulator per dashboard user

Status: design and lab overlay only. Nothing in this change was started on lab5g-dev, and it does not deploy. The request is the Netdrive goal of 10 Nov 2026 20:00 WIB: each dashboard user's traffic is one UE through srsUE, srsENB, SGW/PGW-U, then CGNAT on SGi.

The running stack stays the sanitized lab5g-dev EPC: Open5GS `gradiant/open5gs:2.8.0` CUPS, srsRAN 4G `gradiant/srsran-4g:25_10` over ZMQ, and Mongo. The dashboard that assigns a student to an IMSI is PR #7 (`cursor/dashboard-lab5g-dev-phase1-a70b`). That PR is not merged. This overlay does not read it and does not need it for an attach. The IMSI string in the gitignored env file is what both sides must share.

Bring-up steps are in [`docs/deploy/android-ue-lab5g-dev.md`](../deploy/android-ue-lab5g-dev.md).

## Topology

```
student assignment (dashboard, when PR #7 is in use)
        |
        | one test IMSI, Ki/OPc from the existing subscriber seed
        v
+--------------------------- shared network namespace ---------------------------+
|  docker-android (SLIRP)                                                        |
|       |  process uses this netns default route                                 |
|       v                                                                        |
|  tun_srsue  <---- srsUE (its own container, this netns)                        |
|  uu eth0    <---- ZMQ TCP only, toward this user's srsENB                      |
+--------------------------------------------------------------------------------+
        | GTP user plane is not on this netns
        v
srsENB  -- S1-MME --> MME ---- S6a ---- HSS (Mongo)
        -- S1-U   --> SGW-U -- S5/S8-U --> UPF (PGW-U, ogstun, UE pool)
                                              |
                                              | SGi
                          +-------------------+------------------+
                          |                                      |
                    SGi iperf server                         cgnat
                    (already in the lab)         nftables, then tun0
                                                     |
                                              tun2socks in the cgnat netns
                                                     |
                                              SOCKS on <GW_IP>:1080
                                                     |
                                              ssh -R from the laptop
                                                     |
                                                  internet
```

Control-plane ADB does not follow that path. It is published on the guest loopback into the shared netns. The reply stays on the uu interface because the peer is the bridge gateway, which is a connected route. New destinations that are not the eNB use `tun_srsue`.

The UE pool, SGi subnet, and the planned CGNAT hop are the ones already written in `lab/compose/docker-compose.yml` and `infra/group_vars/all/lab.yml` (`ue_sessions`, `cgnat_ip`). The overlay does not repeat them as literals. The env file supplies them.

## One student, one IMSI, one srsUE, one emulator

| Piece | What it is |
|---|---|
| Dashboard user | A student. PR #7 binds that user to an assignment. Ki and OPc are not profile fields. |
| Test IMSI | One IMSI in the lab PLMN (MCC/MNC from the existing plan). Seeded with the existing subscriber mechanism: `infra/roles/subscribers/templates/seed-subscriber.js.j2`, which is a Mongo `replaceOne`. The dashboard, once merged, can later edit QoS on that document. This overlay does not write Mongo. |
| srsUE | Container `l5gd-ueN`. USIM comes from `lab/config/ran/android-ue.conf.template` after `envsubst`. Placeholders are `UE_IMSI`, `UE_KI`, `UE_OPC`, `UE_IMEI`. |
| srsENB | Container `l5gd-enbN`. One eNB per UE. See the multi-UE decision below. eNB ID and S1 addresses are not the stock pair. |
| Emulator | Container `l5gd-androidN`, image `halimqarroum/docker-android:api-33`, `network_mode: service:ueN`. |

`ue1` and `ue2` are the template. The up script starts `ue1` only. `ue2` requires `ANDROID_UE_ALLOW_SECOND=1` because the current guest cannot honestly run two emulators. The generator refuses a count above 2.

QoS: MME/SGW/PCRF install the subscriber document at attach (QCI, ARP, AMBR, and any PCC rules already stored for that IMSI). PR #7 still rejects a live Gx RAR, so a profile edit applies on the next attach, not on the live bearer. Restarting that user's srsUE is the apply step. This overlay does not change PCRF and does not claim Gate D.

The Gradiant srsRAN image ships default `KEY` and `OPC` environment values. The UE service overrides both from the gitignored env. Do not copy those image defaults into git or into a ticket.

## Default route through tun_srsue

The emulator uses `network_mode: service:ueN`. Compose ignores any network or port setting on that service. It shares the srsUE network namespace, so it sees `tun_srsue` and the uu interface, and it cannot be given a second docker network that bypasses the EPC.

`srsUE` is not started with `gw.netns`. The upstream ZMQ note uses a netns because the UE and a same-host EPC would otherwise short-circuit. Here the EPC is already a different container netns. A `gw.netns` would create `tun_srsue` where the emulator cannot see it.

After attach, `l5gd-ueN-route` (same netns, `NET_ADMIN`) does four things and then exits. The rules remain in the netns:

1. Wait until `tun_srsue` has an IPv4 address from the PGW pool.
2. Pin the eNB address as a `/32` on the uu interface. That keeps ZMQ off the tun. The ZMQ ports are the lab's existing pair (TCP 2000/2001 and 2100/2101) and they are inside this netns, so they do not collide with `l5gd-enb` / `l5gd-ue`.
3. Replace the default route with `default dev tun_srsue`. Linux then sources off-net packets from the tun address, which is the UE address the PGW and the PCRF session know.
4. iptables OUTPUT: accept loopback, accept TCP to the eNB (ZMQ), accept output via `tun_srsue`, accept established replies (ADB), drop the rest. ip6tables OUTPUT drops everything except loopback, so IPv6 is not a second path.

The Android guest does not see `tun_srsue`. QEMU user-mode networking (SLIRP) inside the emulator process is NATed by that process. The process's own packets use the container routing table. `adb shell ip route` shows the SLIRP network. The check that matters is `ip route get` in the shared netns, plus a ping from the Android shell to a literal SGi address.

The uu network is the core compose network marked `internal: true`, so even a packet that escaped the OUTPUT filter still cannot be routed to the internet by Docker. The filter is there so a later non-internal network on this netns would not become a bypass. The emulator is not given `NET_ADMIN` or `/dev/net/tun`, so it cannot undo the route.

The emulator does not use Docker's embedded resolver at `127.0.0.11`. Compose sets `dns:` on the UE service, and the emulator is started with `-dns-server` set to `ANDROID_UE_PGW_DNS`, the address the SMF/PGW gives the UE. That is what keeps the query off Docker's resolver: Docker rewrites `127.0.0.11:53` in nat OUTPUT before the filter guard runs, so a reject of destination port 53 never sees those packets. A query that uses the PGW resolver has to leave on `tun_srsue`.

Policy routing (`ip rule`) was the other option. It is the wrong default here: one netns and one default route is the thing an operator can read. A second table would only be needed if srsUE itself had to keep a different default, and it does not.

## CGNAT on SGi

The approved internet path is CGNAT plus a SOCKS tunnel to the operator laptop. It stays off until `android-ue-up.sh --with-socks-egress`. The egress docker network stays `--internal`.

`l5gd-cgnat` sits on SGi. `l5gd-egress` (tun2socks) and `l5gd-egress-dns` (CoreDNS) use `network_mode: service:cgnat`, so they share that netns. Images are `ANDROID_UE_TUN2SOCKS_IMAGE` and `ANDROID_UE_DNS_IMAGE`. Both are `REPLACE_` placeholders until Lab Ops names the mirror. `ANDROID_UE_SOCKS_ADDR` is `<GW_IP>:1080`, also a placeholder. `CGNAT_EGRESS_ADDR` is cgnat's static address on the egress network. The guest accepts TCP 1080 only from that address on the egress bridge, then drops every other packet to 1080.

After tun0 exists, the only default route in that netns is `dev tun0`. A host route to the SOCKS address lets tun2socks reach the tunnel. nft drops every other packet that does not leave via tun0.

`lab/config/cgnat/cgnat.nft.template` is the policy. It accepts new forwards only from `UE_POOL`, drops bogons plus `ANDROID_UE_LAB_SUBNET`, allows TCP 80 and 443 only, DNATs UDP and TCP 53 to `127.0.0.1:53`, and rejects other UDP. Each UE address is limited to about 10 Mbit/s (`1250 kbytes/second`) and `CGNAT_CT_LIMIT` connections (200 in the example). Logs are a rate-limited prefix. DNS queries are not logged. The Corefile is rendered from `ANDROID_UE_DNS_UPSTREAM` (default `1.1.1.1`) as `forward . tcp://<upstream> { force_tcp }` with no log plugin.

The UPF default route toward cgnat is still opt-in (`--install-upf-route` and `ANDROID_UE_INSTALL_UPF_ROUTE=1`), only together with the SOCKS flag, and only for that test window. That flag adds `ip rule from <UE_ADDR>/32 lookup 1080` and a default route only in table 1080. The main default route is not saved or replaced. `android-ue-down.sh` deletes that policy rule and the table 1080 default. HSS, PCRF, and SMF configuration are not changed. The SGi server stays on the connected route.

`infra/roles/internet_egress` is not what this flag turns on. The guest reaches the internet only through the ssh reverse forward from the laptop.

## Multi-UE on srsRAN ZMQ

**Decision: one srsENB per srsUE, each with its own ZMQ pair.** That is the simplest option that matches a shape this lab already runs. A shared eNB is not what this overlay starts.

What the sources actually say:

- The srsRAN 4G ZeroMQ application note shows one eNB and one UE, and its known issues say: "We currently only support a single eNB and a single UE." The direct ZMQ arguments are one IQ stream per antenna port (`tx_port`/`rx_port`, or `tx_port0`/`tx_port1` for a second antenna). A second UE cannot share that socket pair. The note's GNU Radio section is a broker between one UE and one eNB, and the broker has to be running before the UE attaches.  
  https://docs.srsran.com/projects/4g/en/latest/app_notes/source/zeromq/source/index.html
- The eNB itself can serve more than one UE. Andre Puschmann wrote on srsRAN_4G issue 818 (2022-03-03) that a GNU Radio flowgraph which fans downlink samples out and sums uplink samples back is the right approach, that srsRAN had tested it with many UEs, and that the reporter's failure was a subscriber mismatch. That flowgraph is not in the Gradiant image and has not been run in this lab.  
  https://github.com/srsran/srsRAN_4G/issues/818
- The OAIC multi-UE example is the same pattern: one `srsenb`, several `srsue` processes, one netns each, and a separate GNU Radio broker.  
  https://openaicellular.github.io/oaic/multi_ue_example.html
- srsRAN Project (the 5G gNB) has its own multi-UE ZMQ section. This lab runs srsRAN 4G `release_25_10` in `gradiant/srsran-4g:25_10`. This change does not switch the RAN.

`tx_port1` in the current lab compose is a second antenna port, not a second UE. Copying the verified pair onto a new pair of addresses is smaller than adding GNU Radio. The cost is an extra eNB (2 CPU, 2048 MiB in this overlay) per concurrent emulator. That is why the cap is one running user on the current guest, with a second user only described.

Known ZMQ behavior from the same app note still applies: stop the UE before the eNB, and after a detach the eNB needs a restart. The eNB wrapper waits until the UE accepts TCP 2001, which is the lab's existing "UE first" rule.

## docker-android

Source: https://github.com/HQarroum/docker-android (image `halimqarroum/docker-android`, current project version 1.1.0).

| Item | Value |
|---|---|
| Tag | `api-33` (Android 13, Google APIs, x86_64). `api-33-playstore` is not the default: it needs a matching adb key and Google egress. |
| KVM | `--device /dev/kvm`. The image is built around hardware virtualization. |
| Upstream size | At least 4 GiB RAM and 8 GiB disk for API 33. Image defaults are `MEMORY=8192` and `CORES=4`. Docker Hub lists `api-33` as linux/amd64, about 2.54 GB compressed. |
| This overlay | `MEMORY=2048`, `CORES=2`, container limit 2 CPU and 2560 MiB, `shm_size` 1 GiB. That is below the upstream 4 GiB note. If the emulator does not boot, the guest has to grow. Do not quietly raise the limit on the 16 GiB guest. |
| Screen | The image is headless. It has no web VNC. ADB listens in the container; this overlay publishes it on `127.0.0.1` of the guest (example ports 15551 and 15552). The operator SSHes to the guest and runs `adb connect` and `scrcpy`. `SKIP_AUTH=true` matches the image default and is acceptable only because the port is not on a routed address. |
| Data | The upstream image wipes the AVD on restart. This overlay does not add a data volume. |

How many instances: the guest in the lab notes is 8 vCPU, 16 GiB RAM, and 40 GiB disk, and it already runs the EPC. The stock srsRAN pair is requested at 2.5 CPU and 2048 MiB each. One extra eNB, one srsUE, and one emulator at the caps above is the realistic first run, and only if the stock `l5gd-enb` / `l5gd-ue` are stopped so they are not also holding CPU, RAM, and an IMSI. Two emulators plus two eNB/UE pairs do not fit that guest. The compose file defines two users so the mapping is concrete. It is not a claim that both boot.

`adb` and `scrcpy` on the guest are also packages. They have to come from the mirror.

## Risks to the EPC and to subscribers

| Risk | What limits it |
|---|---|
| A normal core `up` starts the emulators | Separate compose file, profile `android-ue`. Do not add this file to the core `-f` list. |
| A second eNB disturbs the stock eNB | Different eNB IDs (`0x1A1`, `0x1A2` in the example, not `0x19B`) and different S1 and ZMQ addresses. Stop the stock UE if it uses the same IMSI. |
| Subscriber collection is rewritten | No Mongo client in this overlay. Extra IMSIs are a `replaceOne` through the existing seed, one test IMSI at a time. Rollback does not delete subscribers. |
| Open5GS YAML or freeDiameter changes | None. The only core data change is the test subscriber document. |
| UPF default route blackholes SGi | The change is opt-in, only with `--with-socks-egress`, and restored by the down script. Connected routes, including the iperf server, stay. |
| Emulator reaches the internet without the EPC | Shared netns, default route via `tun_srsue`, OUTPUT drop, IPv6 drop, uu network internal, no `NET_ADMIN` on the emulator. |
| ADB exposed on the lab network | Published on `127.0.0.1` only. |
| Image USIM defaults or logs leak Ki | Env overrides `KEY` and `OPC`. Do not paste `docker logs` or `docker inspect` of the UE into a ticket. `docker inspect` will show the USIM to anyone who already has Docker on the guest. |
| lab5g-vm | Out of scope. The up script talks only to the networks named in the env file. |

## Prerequisites and blockers

Netdrive and Lab Ops have to clear these before the internet path, or before more than a dry description, is real:

1. **Egress.** Internet for this profile is the SOCKS tunnel. The egress docker network stays `--internal`. The guest sshd needs `GatewayPorts clientspecified`, and INPUT on TCP 1080 is allowed only from the cgnat address. The laptop opens `ssh -N -J agen -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -R <GW_IP>:1080 guest`.
2. **Mirrors.** The guest cannot pull. Mirror `halimqarroum/docker-android:api-33`, a cgnat image with `nft`, `ip`, `awk`, and `sh`, a tun2socks image with `tun2socks`, `ip`, and `sh`, and a CoreDNS image that reads `-conf`. The example leaves those names as `REPLACE_`. Also mirror `adb` and `scrcpy`. Do not `docker pull` from this overlay.
3. **KVM.** `/dev/kvm` must exist inside the lab guest. The guest is itself a libvirt VM, so this is nested virtualization on the host. The up script stops if the device is missing.
4. **Test IMSIs.** Seed one new test IMSI for ue1. Seed a second only if a larger guest is approved for ue2. Use the existing `replaceOne` seed, the lab PLMN, and Ki/OPc only in the gitignored env and the vault. Do not reuse the IMSI the stock srsUE is using. Point the student's dashboard assignment at that same IMSI once PR #7 is the tool operators use. This change does not merge that PR.
5. **Guest size.** One user first. Two concurrent emulators need more vCPU and RAM than 8 / 16 GiB.
6. **Compose on the guest.** Standalone `docker-compose` v2.29.7, same pin as the dashboard runbook. Root via `sudo` is how the guest runs Docker today.

## Phase 2

- A GNU Radio (or other) IQ broker so one srsENB can serve several srsUEs, after a lab5g-dev spike. Not this overlay.
- A dashboard control to start and stop the emulator for an assignment.
- A screen path that is not scrcpy-over-SSH. This image does not provide web VNC. A different image would be a separate choice.
- Show the UE address, the port block, and a byte counter on the dashboard.
- Live Gx RAR (Gate D) so a student profile edit hits the existing bearer without a reattach.
- Resize the guest, and confirm nested KVM, before a second emulator.
- Play Store image only if `api-33` has no browser the test needs, and only with a mirrored adb key and approved Google egress.
- autossh for the laptop tunnel, full UDP through the filter, and IPv6. The cgnat netns drops IPv6 until then.
