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
- Images are already loaded: `gradiant/srsran-4g:25_10`, `halimqarroum/docker-android:api-33`, and a local cgnat image that contains `nft`, `ip`, `awk`, and `sh`. No pulls.
- `adb` and `scrcpy` are installed on the guest from the mirror.
- One new test IMSI is seeded with the existing subscriber `replaceOne` (`infra/roles/subscribers/templates/seed-subscriber.js.j2`). Ki and OPc stay in the vault and in the gitignored env. Do not reuse the stock srsUE's IMSI. Do not `drop` the subscriber collection.
- Stock `l5gd-enb` and `l5gd-ue` are stopped if the guest cannot spare another eNB and UE (2 CPU and 2048 MiB each in this overlay, plus the emulator).
- The S1-MME, S1-U, uu, and SGi networks already exist (`lab5g-dev_s1mme`, `lab5g-dev_s1u`, `lab5g-dev_uu`, `lab5g-dev_sgi` in the example).
- Egress network: until Netdrive approves a path, create it internal. That is not internet access.

```bash
sudo docker network create --internal lab5g-dev-android-ue-egress
```

Use that name only in the gitignored env. Leave `android-ue.env.example` as it is.

## Env file

```bash
cp lab/compose/android-ue.env.example lab/compose/android-ue.env
chmod 600 lab/compose/android-ue.env
```

Set `UE1_IMSI`, `UE1_KI`, `UE1_OPC`, and `UE1_IMEI` to the seeded test subscriber. Set `ANDROID_UE_EGRESS_NETWORK` to the network created above. Leave `ANDROID_UE_CGNAT_IMAGE` as a placeholder until the cgnat step, then set it to the mirrored image name. Leave `ANDROID_UE_ALLOW_SECOND=0` and `ANDROID_UE_INSTALL_UPF_ROUTE=0`.

`lab/compose/android-ue.env` is gitignored. Do not commit it.

## One user

From the repo root:

```bash
sudo bash lab/scripts/android-ue-up.sh \
  --env-file lab/compose/android-ue.env \
  --user ue1
```

The script checks `/dev/kvm`, rejects `REPLACE_` USIM values, and starts only `ue1`, `enb1`, the route sidecar, and `android1`. It does not start `cgnat` and it does not touch the UPF. The eNB waits until the UE accepts its ZMQ port. The route sidecar waits until `tun_srsue` has an address, installs the default route and the OUTPUT drop, then exits. The emulator starts only after that exit is 0.

Give the emulator time to boot, then:

```bash
adb connect 127.0.0.1:15551
scrcpy -s 127.0.0.1:15551
```

The port is the guest loopback. From a laptop, tunnel it over SSH. Do not publish it on the libvirt bridge.

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
   adb -s 127.0.0.1:15551 shell ping -c 3 <SGI_SERVER>
   ```

   `adb shell ip route` shows the emulator's SLIRP route. That is expected. The packet leaves QEMU and hits the netns default route.
4. **iperf3.** The SGi server is already `iperf3 -s`. The srsRAN image and the Android image do not ship an iperf3 client. `nicolaka/netshoot` is the lab's existing server image and it does. Join the UE netns so the client uses the same default route as the emulator process:

   ```bash
   sudo docker run --rm --network container:l5gd-ue1 nicolaka/netshoot \
     iperf3 -c <SGI_SERVER> -t 3
   ```

   One TCP flow to the SGi server does not need CGNAT. Browsing does. The OUTPUT filter allows it because the route to that address is `tun_srsue`.
5. **Public address behind the SOCKS tunnel.** Skip this until the CGNAT section below has been run. The echo host must show the laptop's public address. Write that result as `<LAPTOP_PUBLIC_IP>` in notes. Do not put the real address in the PR.

A failed ZMQ wait or a route timeout means the UE did not attach. Read `sudo docker logs l5gd-ue1` and `sudo docker logs l5gd-enb1` on the guest, fix the subscriber or the addresses, and start again. After a detach, stop the UE and then the eNB before starting them again. The down script does that order.

## CGNAT via the SOCKS tunnel

Netdrive's approved path is CGNAT plus a SOCKS tunnel to the operator laptop. The egress docker network stays `--internal`. Do not recreate it without `--internal`.

```bash
sudo docker network inspect -f '{{.Internal}}' <ANDROID_UE_EGRESS_NETWORK>
```

That prints `true`. The up script refuses `--with-socks-egress` otherwise.

On the guest sshd, set `GatewayPorts clientspecified` and reload sshd. This repo does not edit sshd and does not deploy that change. Without it, sshd will not bind `<GW_IP>:1080`.

Allow guest INPUT on TCP 1080 only from the cgnat container address:

```bash
sudo iptables -I INPUT 1 -p tcp -d <GW_IP> --dport 1080 -s <CGNAT_IP> -j ACCEPT
sudo iptables -I INPUT 2 -p tcp -d <GW_IP> --dport 1080 -j DROP
```

`<GW_IP>` and `<CGNAT_IP>` stay in the gitignored env and in this local shell. Do not commit them.

From WSL, open the reverse dynamic forward. The laptop ssh client is the SOCKS peer. Nothing else on the guest should listen on 1080.

```bash
ssh -N -J agen -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -R <GW_IP>:1080 guest
```

In `android-ue.env`, set `ANDROID_UE_SOCKS_ADDR` to `<GW_IP>:1080`, `ANDROID_UE_LAB_SUBNET` to the lab prefix, and the tun2socks and DNS image names to the mirror. The DNS image must serve `lab/config/cgnat/Corefile` (`forward . tcp://1.1.1.1 { force_tcp }`). Set `ANDROID_UE_INSTALL_UPF_ROUTE=1` only for this window.

```bash
sudo bash lab/scripts/android-ue-up.sh \
  --env-file lab/compose/android-ue.env \
  --user ue1 \
  --with-socks-egress \
  --install-upf-route
```

`--with-socks-egress` starts `cgnat`, then `egress` (tun2socks), then `egress-dns`. Both sidecars use `network_mode: service:cgnat`. In that netns the only default route is `dev tun0`. A host route to `<GW_IP>` exists so tun2socks can reach the tunnel. It is not a second default route. nft drops anything else that does not leave via tun0.

The script saves the previous UPF default route under `/tmp/open5g-android-ue-state/` before replacing it with the cgnat address on SGi. That route exists only for this window. Rollback restores the saved route. HSS, PCRF, and SMF configuration are not changed.

### Proof

Use an echo host Netdrive named. Mask the laptop address in anything that is committed.

1. **Laptop address.** From the UE netns, `curl -4 --max-time 15 http://<echo>/` prints `<LAPTOP_PUBLIC_IP>`.
2. **DNS.** From the emulator, `adb -s 127.0.0.1:15551 shell ping -c 1 example.com` resolves. The resolver is TCP-only and does not log the query.
3. **Laptop LAN and localhost fail.** `curl -4 --max-time 5 http://<LAPTOP_LAN>/` fails. So does a destination in `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, or `127.0.0.0/8` that is not the UE's own stack. Write `<LAPTOP_LAN>` only in local notes.
4. **Other ports fail.** `curl -4 --max-time 5 http://<echo>:8080/` fails. TCP is 80 and 443 only. Other UDP is rejected.
5. **Kill switch.** Stop the ssh process. The same curl to the echo host fails. Start the ssh command again. The curl works again.
6. **Listeners.** `sudo docker exec l5gd-cgnat nft list table ip cgnat` shows the policy. On the guest, `ss -ltn` shows `1080` only on `<GW_IP>`, not on `0.0.0.0` or `*`.

Ping and iperf to the SGi server still do not prove this path. They never enter the tunnel.

### Phase 2

autossh, full UDP, and IPv6. None of those are in this overlay. IPv6 forwarding on the cgnat netns is dropped.

## Rollback

```bash
sudo bash lab/scripts/android-ue-down.sh --env-file lab/compose/android-ue.env
```

This stops the profile in UE-before-eNB order, removes those containers, and restores the UPF default route if this runbook changed it. It does not stop the core, does not remove external networks, and does not delete the test subscriber. Removing that subscriber is a separate `replaceOne` or delete, done by hand, and only for the test IMSI.

Set `ANDROID_UE_INSTALL_UPF_ROUTE` back to `0`.

## Second user

Do not set `ANDROID_UE_ALLOW_SECOND=1` on the 8 vCPU / 16 GiB guest. The file defines `ue2` so the mapping is reviewable. A second concurrent emulator needs a larger guest, a second seeded test IMSI, and nested KVM that still has room.

## Static checks

On a workstation, or in CI, without starting containers:

```bash
lab/scripts/check-android-ue.sh
```

That runs shellcheck, checks the generator still matches the overlay, renders the nftables rules and runs `nft -c` (or the syntax checker if `nft` is absent), checks the Corefile is TCP-only, and runs `docker compose config` with and without the `socks-egress` profile. CI uses standalone `docker-compose` v2.29.7. The example env is enough for `config`. It is not enough for `up`, on purpose.
