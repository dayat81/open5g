# android-ue on lab5g-dev

Runbook for one Android emulator as one UE. Design: [`docs/integration/android-ue-per-user.md`](../integration/android-ue-per-user.md).

This was not executed against the lab. Do not point it at lab5g-vm. Do not merge it into the core compose file. Rollback is stopping the `android-ue` profile.

The guest uses standalone Compose **v2.29.7**, the same pin as the dashboard runbook:

```bash
curl -fsSL -o /usr/local/bin/docker-compose \
  https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64
chmod 0755 /usr/local/bin/docker-compose
docker-compose version
```

That binary has to come from the mirror when the guest has no egress. The commands below assume `docker-compose` is that binary and that the checkout is the repo root. The guest's Docker commands run with `sudo`.

## Prerequisites

Stop here until each line is true. The design doc lists the same blockers for Netdrive and Lab Ops.

- Explicit approval to use lab5g-dev. The core is already up from its own compose file (`name: lab5g-dev`). This runbook does not start it and does not edit `lab/config/examples/open5gs/`.
- `/dev/kvm` exists in the guest (nested virtualization). `ls -l /dev/kvm`.
- `ANDROID_UE_MEM_LIMIT` defaults to `4096m`. It must be at least `ANDROID_UE_MEMORY` plus 1536 MiB. A 2560 MiB limit OOM-kills api-33. `up` refuses a smaller limit.
- Images are already loaded: `gradiant/srsran-4g:25_10`, the local emulator image below, and a local cgnat image that contains `nft`, `ip`, `awk`, and `sh`. No pulls from this overlay during `up`.
- `adb` and `scrcpy` are installed on the guest from the mirror.
- One new test IMSI is inserted with `lab/scripts/android-ue-seed.sh`. That script stops if the IMSI is already in Mongo. It does not replace an existing subscriber. Do not run it during the dashboard PR #7 test window. Ki and OPc stay in the gitignored env. Do not reuse the stock srsUE's IMSI. Do not `drop` the subscriber collection.
- Stock `l5gd-enb` and `l5gd-ue` are stopped if the guest cannot spare another eNB and UE (2 CPU and 2048 MiB each in this overlay, plus the emulator).
- The S1-MME, S1-U, uu, and SGi networks already exist (`lab5g-dev_s1mme`, `lab5g-dev_s1u`, `lab5g-dev_uu`, `lab5g-dev_sgi` in the example).
- Egress network: until Netdrive approves a path, create it internal. That is not internet access.

```bash
sudo docker network create --internal lab5g-dev-android-ue-egress
```

Use that name only in the gitignored env. Leave `android-ue.env.example` as it is.

## Emulator image

Build it on a machine that can reach the JDK and Android SDK mirrors, then load the result on the guest:

```bash
sudo bash lab/images/android-emulator/build.sh
sudo docker save open5g-android-emulator:local | gzip > open5g-android-emulator.tar.gz
```

On the guest, `docker load` that archive. `ANDROID_UE_ANDROID_IMAGE` stays `open5g-android-emulator:local`. A registry image is accepted only when its name includes `@sha256`. The build starts from the vendored docker-android tree at commit `f569246983ee994aed06517bf8e06a3f10547b6d`, with the base JDK and the command-line tools zip pinned. No ADB key is stored in the repo or the image; `adb` creates a key on first start, or the lab can mount its own key from outside git.

`BOOT_TIMEOUT` defaults to 600 seconds, the same as `ANDROID_UE_BOOT_TIMEOUT`. Before QEMU starts, the entrypoint checks `getaddrinfo("::1", AI_ADDRCONFIG)`, `::1` on `lo`, and a non-tentative `fe80`. Set `ANDROID_UE_BOOT_GATE=0` to skip the host boot wait for a netns-only run. Optional, and not the default: add `-feature -ModemSimulator` to `ANDROID_UE_EXTRA_FLAGS` only if the Android specialist asks for that fallback.

## Env file

```bash
cp lab/compose/android-ue.env.example lab/compose/android-ue.env
chmod 600 lab/compose/android-ue.env
```

Set `UE1_IMSI`, `UE1_KI`, `UE1_OPC`, and `UE1_IMEI` to the new test subscriber. Set `ANDROID_UE_PGW_DNS` to the DNS address the SMF/PGW gives that UE. It must not be `127.0.0.11`. Set `ANDROID_UE_EGRESS_NETWORK` to the network created above. Set `ANDROID_UE_SGWU_GTPU_ROUTE` to the SGW-U GTP-U address that `lab-routes.sh` installs on the stock eNB, and `ANDROID_UE_SGI_PROBE` to the SGi address used for the ping below. Leave `ANDROID_UE_CGNAT_IMAGE` as a placeholder until the cgnat step, then set it to the mirrored image name. Leave `ANDROID_UE_ALLOW_SECOND=0` and `ANDROID_UE_INSTALL_UPF_ROUTE=0`. Keep `ANDROID_UE_EXTRA_FLAGS` as `-no-metrics -no-audio -partition-size 2048`. The api-33 emulator rejects `-partition-size=2048`.

```bash
sudo bash lab/scripts/android-ue-seed.sh --env-file lab/compose/android-ue.env --user ue1
```

`lab/compose/android-ue.env` is gitignored. Do not commit it. The seed script inserts a new IMSI only. If that IMSI is already present, use the section below instead of deleting the document.

## Existing test IMSI without ue.addr

Leave `android-ue-seed.sh` insert-only. When the test IMSI is already in Mongo and has no `ue.addr`, export that one document and set only the address. The update is `updateOne` with `$set` on `slice.$[sl].session.$[se].ue.addr`, `arrayFilters` for `sst: 1` and the APN, filtered to that IMSI, and `upsert: false`.

```bash
sudo bash lab/scripts/android-ue-set-addr.sh --env-file lab/compose/android-ue.env --user ue1
```

The backup is `/var/lib/open5g-android-ue/subscriber-ue1.json`, mode 0600. Rollback puts back the address stored in that backup, or unsets the field when the backup had none. It does not delete the subscriber. The address must be inside `UE_POOL` and unused by any other subscriber. The seed script applies the same two checks before it inserts.

```bash
sudo bash lab/scripts/android-ue-set-addr.sh --env-file lab/compose/android-ue.env --user ue1 --rollback
```

## One user

From the repo root:

```bash
sudo bash lab/scripts/android-ue-up.sh \
  --env-file lab/compose/android-ue.env \
  --user ue1
```

The script checks `/dev/kvm` and the memory headroom, rejects `REPLACE_` USIM values, and starts `ue1`, `enb1`, and the route sidecar before the emulator. It does not start `cgnat` and it does not change the UPF main default route. The eNB waits until the UE accepts its ZMQ port. The route sidecar waits until `tun_srsue` has an address and installs the default route and the OUTPUT drop. `ANDROID_UE_KVM_GID` must be a non-zero number and the same as `stat -c %g /dev/kvm`. A registry emulator image is refused unless its name contains `@sha256`. `open5g-android-emulator:local` is the image this repo builds.

IPv6 stays enabled. The sidecar writes `disable_ipv6=0` for `all`, `default`, `lo`, and every interface, then `accept_ra=0`, `autoconf=0`, and `forwarding=0` on each interface other than `lo`. It installs `ip -6 route replace unreachable default metric 1` and removes any other IPv6 default. If `ip6tables` or `ip6tables-nft` can open the filter table, IPv6 output is dropped except on `lo`. If neither can, the sidecar exits. `ANDROID_UE_IPV6_NO_FILTER_OK=1` is the only override, and only for a netns check. `::1` and a non-tentative `fe80` on an up interface are required. `up` reads those sysctls and the unreachable route again after the sidecar exits. If `l5gd-android1` is already running, `up` does not start the sidecar again. If the sidecar starts while `qemu` is already in the netns, it exits without changing IPv6. The image has no official modem-host setting. `-feature -ModemSimulator` is an optional `EXTRA_FLAGS` value, not the default.

`up` runs `docker wait l5gd-ue1-route` and continues only when that exit code is 0. The eNB container has no `NET_ADMIN`. After that wait, `up` uses `nsenter` from the host, the same way `lab-routes.sh` does for `l5gd-enb`. It finds the interface that holds `UE1_ENB_S1U` and installs `ANDROID_UE_SGWU_GTPU_ROUTE/32` on that interface. `ip route get` must show that device. A route on the UPF toward that S1-U address is not added. The lab capture showed the eNB route alone is enough for the SGi ping.

`up` then runs `ping -c 3 -I tun_srsue <ANDROID_UE_SGI_PROBE>`. A failed ping stops `up` before `android1` starts. That ping is only meaningful before `--install-upf-route`. After that flag, the test UE is steered to cgnat, which drops the lab subnet, so a ping to the lab SGi server fails on purpose.

`uu` is an internal network, so Docker does not publish ports from it. Do not use `127.0.0.1:15551`. On the guest:

```bash
adb connect <UE1_UU>:5555
scrcpy -s <UE1_UU>:5555
```

From the laptop, use the normal lab key, not the tunnel key:

```bash
ssh -N -J agen -L 15551:<UE1_UU>:5555 guest
adb connect 127.0.0.1:15551
```

Do not publish ADB or VNC on the libvirt bridge or the LAN. Do not attach a non-internal network to the UE. The image's socat already listens on the uu address, port 5555.

The api-33 image already starts the emulator with `-no-snapshot` and its watcher prints `Emulator failed to boot within 300 seconds` after 300 seconds. `up` keeps polling `sys.boot_completed` for `ANDROID_UE_BOOT_TIMEOUT` seconds (600 by default) and then prints the emulator log, `ip -6 addr`, `getent ahosts ::1`, `/dev/kvm`, the emulator uid, and `emulator -accel-check`. `ANDROID_UE_KVM_GID` is added to the emulator process with `group_add`. Set it to the numeric GID of the host group that owns `/dev/kvm`.

## Verification

Use the IMSI from the env file. Do not paste UE logs into a ticket; the image entrypoint is traced and the USIM is in the container environment.

1. **MME attach.** `sudo docker logs l5gd-mme 2>&1 | grep <test IMSI>` shows the attach for that IMSI. The container name is `ANDROID_UE_MME_CONTAINER` if the lab renamed it.
2. **UE address from the PGW pool.** `sudo docker exec l5gd-ue1 ip -4 addr show dev tun_srsue` is an address in `UE_POOL` (the published pool, not the uu address).
3. **Emulator path is the tun.** The emulator has no netns of its own (`network_mode: service:ue1`). In the shared netns:

   ```bash
   sudo docker exec l5gd-ue1 ip route get 1.1.1.1
   sudo docker exec l5gd-ue1 ip route get <UE1_ENB_UU>
   ```

   The first prints `dev tun_srsue`. The second does not. Then from the emulator, ping the SGi server by literal address (`SGI_SERVER` in the env file):

   ```bash
   adb -s <UE1_UU>:5555 shell ping -c 3 <SGI_SERVER>
   ```

   `adb shell ip route` shows the emulator's SLIRP route. That is expected. The packet leaves QEMU and hits the netns default route.
4. **iperf3.** The SGi server is already `iperf3 -s`. The srsRAN image and the Android image do not ship an iperf3 client. `nicolaka/netshoot` is the lab's existing server image and it does. Join the UE netns so the client uses the same default route as the emulator process:

   ```bash
   sudo docker run --rm --network container:l5gd-ue1 nicolaka/netshoot \
     iperf3 -c <SGI_SERVER> -t 3
   ```

   One TCP flow to the SGi server does not need CGNAT. Browsing does. The OUTPUT filter allows it because the route to that address is `tun_srsue`. Run this ping and iperf before `--install-upf-route`. After that flag, cgnat drops the lab subnet, so the same ping fails on purpose.
5. **Public address behind the SOCKS tunnel.** Skip this until the CGNAT section below has been run. The echo host must show the laptop's public address. Write that result as `<LAPTOP_PUBLIC_IP>` in notes. Do not put the real address in the PR.

A failed ZMQ wait or a route timeout means the UE did not attach. Read `sudo docker logs l5gd-ue1` and `sudo docker logs l5gd-enb1` on the guest, fix the subscriber or the addresses, and start again. After a detach, stop the UE and then the eNB before starting them again. The down script does that order.

## CGNAT via the SOCKS tunnel

Netdrive's approved path is CGNAT plus a SOCKS tunnel to the operator laptop. The egress docker network stays `--internal`. Do not recreate it without `--internal`.

```bash
sudo docker network inspect -f '{{.Internal}}' <ANDROID_UE_EGRESS_NETWORK>
```

That prints `true`. The up script refuses `--with-socks-egress` otherwise.

Prepare the guest before the tunnel. This writes `/etc/ssh/sshd_config.d/00-open5g-android-ue.conf` (backing up that file first), reloads sshd, and checks `sshd -T -C user=<tunnel user>` until the effective value is `clientspecified`. If `systemctl reload ssh` fails while `ssh.socket` is active, prepare starts `ssh`. It backs up `authorized_keys` and adds one line, `restrict,port-forwarding,permitlisten="<GW_IP>:1080"`, for `ANDROID_UE_TUNNEL_PUBKEY`. That option needs OpenSSH 7.8 or newer. Prepare refuses the key if that same public key is already present without those options, and it changes ownership of `~/.ssh` and `authorized_keys` to the tunnel user. The public key in the example is a placeholder. Do not commit a real key. It also installs two INPUT rules, with no destination address, and a systemd unit that puts them back after reboot: accept TCP 1080 on the egress bridge from `CGNAT_EGRESS_ADDR`, then drop every other packet to 1080. `<GW_IP>` comes from `ANDROID_UE_SOCKS_ADDR`. `CGNAT_EGRESS_ADDR` is cgnat's address on the egress network, not `CGNAT_SGI_ADDR`. Do not commit them.

```bash
sudo bash lab/scripts/android-ue-tunnel.sh prepare --env-file lab/compose/android-ue.env
```

The state directory is `/var/lib/open5g-android-ue` unless `ANDROID_UE_STATE_DIR` is set. Do not use `/tmp` for it. A second prepare refuses to overwrite the backup.

From WSL, open the reverse dynamic forward. The laptop ssh client is the SOCKS peer. Open `ssh -R` only while the laptop is not on the office VPN.

```bash
ssh -N -J agen -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -R <GW_IP>:1080 guest
```

`android-ue-up.sh --with-socks-egress` then checks `ss -ltn` and stops if port 1080 is listening on anything other than `<GW_IP>`.

In `android-ue.env`, set `ANDROID_UE_SOCKS_ADDR` to `<GW_IP>:1080`, `ANDROID_UE_LAB_SUBNET` to the lab prefix, and the tun2socks and DNS image names to the mirror. The DNS image reads the Corefile rendered into `/var/lib/open5g-android-ue/Corefile`. `ANDROID_UE_DNS_UPSTREAM` defaults to `1.1.1.1` and is always used over TCP. Set `ANDROID_UE_INSTALL_UPF_ROUTE=1` only for this window.

```bash
sudo bash lab/scripts/android-ue-up.sh \
  --env-file lab/compose/android-ue.env \
  --user ue1 \
  --with-socks-egress \
  --install-upf-route
```

`--with-socks-egress` starts `cgnat`, then `egress` (tun2socks), then `egress-dns`. The nft template stays at `/etc/cgnat`. The cgnat and egress scripts are mounted at `/opt/cgnat`, not inside that read-only config directory. Both sidecars use `network_mode: service:cgnat`. In that netns the only default route is `dev tun0`. A host route to `<GW_IP>` exists so tun2socks can reach the tunnel. It is not a second default route. nft drops anything else that does not leave via tun0.

Set `UE_POOL` to `<UE1_ADDR>/32` before this command. The script installs `ip rule from <UE1_ADDR>/32 lookup 1080` on the UPF and a default route only in that table. The main default route is not changed, so other UEs are not sent to the laptop. A second run does not add another rule. State is `/var/lib/open5g-android-ue/upf-rule.txt`. HSS, PCRF, and SMF configuration are not changed. The static address is the `ue.addr` written by the seed script.

### Proof

Use an echo host Netdrive named. Mask the laptop address in anything that is committed.

1. **Laptop address.** From the UE netns, `curl -4 --max-time 15 http://<echo>/` prints `<LAPTOP_PUBLIC_IP>`.
2. **DNS leaves tun_srsue, and both DNS and curl fail when the tunnel is down.** `ping` alone is not the proof. In one terminal on the UE netns:

   ```bash
   sudo tcpdump -ni tun_srsue port 53
   ```

   From the emulator, resolve a name (`adb -s <UE1_UU>:5555 shell ping -c 1 example.com`). tcpdump must show the query on `tun_srsue`. Then stop the ssh tunnel and repeat both of these. Both must fail:

   ```bash
   adb -s <UE1_UU>:5555 shell ping -c 1 example.com
   sudo docker run --rm --network container:l5gd-ue1 nicolaka/netshoot \
     curl -4 --max-time 10 http://<echo>/
   ```

   Start the ssh command again. The query shows on `tun_srsue` again, and curl prints `<LAPTOP_PUBLIC_IP>`. The emulator uses `-dns-server` and compose `dns:` set to `ANDROID_UE_PGW_DNS`, so Docker's embedded resolver is not a second path.
3. **Laptop LAN and localhost fail.** `curl -4 --max-time 5 http://<LAPTOP_LAN>/` fails. So does a destination in `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, or `127.0.0.0/8` that is not the UE's own stack. Write `<LAPTOP_LAN>` only in local notes.
4. **Other ports fail.** `curl -4 --max-time 5 http://<echo>:8080/` fails. TCP is 80 and 443 only. Other UDP is rejected.
5. **Kill switch.** Stop the ssh process. The same curl to the echo host fails. Start the ssh command again. The curl works again.
6. **Listeners and the persisted INPUT rule.** `sudo docker exec l5gd-cgnat nft list table ip cgnat` shows the policy. On the guest, `ss -ltn` shows `1080` only on `<GW_IP>`, not on `0.0.0.0` or `*`. Both of these show the accept from `CGNAT_EGRESS_ADDR` on the egress bridge and the drop of every other packet to 1080:

   ```bash
   sudo iptables -S INPUT | grep 1080
   sudo iptables-save | grep 1080
   ```

   Reboot the guest and run them again. The rules are still there because `open5g-android-ue-iptables.service` restores `/var/lib/open5g-android-ue/input-1080.rules`. After rollback, both commands show no 1080 rule.

Ping and iperf to the SGi server still do not prove this path. They never enter the tunnel.

### Phase 2

Not in this overlay: QCI 8, autossh, full UDP, IPv6, a GNU Radio multi-UE broker, dashboard control of the emulator, a screen path other than scrcpy, live Gx RAR, keeping USIM material out of the container environment, and a larger guest for a second emulator. Also later: deny the laptop WAN address and corporate VPN ranges, extra bogons, a cgnat input chain, and limiting the eNB TCP exception to the ZMQ ports. IPv6 forwarding on the cgnat netns is already dropped.

## Rollback

```bash
sudo bash lab/scripts/android-ue-down.sh --env-file lab/compose/android-ue.env
```

This restores the ssh drop-in and reloads sshd first, then removes only the tunnel `authorized_keys` line (the backup is taken by `prepare`; other keys stay), kills the guest listener on port 1080, deletes the INPUT rules, and removes `open5g-android-ue-iptables.service` so a reboot does not put them back. It then deletes the UPF `/32` policy rule and stops the profile in UE-before-eNB order. It does not change the UPF main default route. It does not stop the core, does not remove external networks, and does not delete the test subscriber. Removing that subscriber is a separate delete, done by hand, and only for the test IMSI that was inserted. Restoring the previous `ue.addr` is the `--rollback` command in the existing-IMSI section, not this script.

Set `ANDROID_UE_INSTALL_UPF_ROUTE` back to `0`.

## Second user

Do not set `ANDROID_UE_ALLOW_SECOND=1` on the 8 vCPU / 16 GiB guest. The file defines `ue2` so the mapping is reviewable. A second concurrent emulator needs a larger guest, a second seeded test IMSI, and nested KVM that still has room.

## Static checks

On a workstation, or in CI, without starting containers:

```bash
lab/scripts/check-android-ue.sh
```

That runs shellcheck, checks the generator still matches the overlay, renders the nftables rules and runs `nft -c` (or the syntax checker if `nft` is absent), checks the Corefile is TCP-only, and runs `docker compose config` with and without the `socks-egress` profile. CI uses standalone `docker-compose` v2.29.7. The example env is enough for `config`. It is not enough for `up`, on purpose.
