# Magen profile

Run the lab on one Docker host. The host alias in the inventory example is `MAGEN_HOST`. This page does not name a real host and does not contain a lab address. `lab5g-dev` stays the fallback. Nothing here connects to that host.

The entrypoint is `infra/deploy/magen.yml`. It has no `become`. Tags are `preflight`, `backup`, `render`, `up`, `restore`, `smoke`, and `down`.

```bash
ansible-playbook -i infra/inventory/magen.yml infra/deploy/magen.yml --tags preflight
```

Copy `infra/inventory/magen.example` to the gitignored `infra/inventory/magen.yml`, and `infra/group_vars/magen.yml.example` to `infra/group_vars/magen.yml`. Put the guest address and key path only in those gitignored files. Copy `lab/compose/env.example.magen` to `lab/compose/magen.env`. Secrets stay in that env file or in an ansible-vault file that is not committed.

## What the profile starts

`gen-android-ue.sh --target magen` writes `lab/compose/compose.magen.yml`. The project name is `open5g`. Container, network, and volume names start with `o5g-`. `androidN` is the same `emit_android` body as the lab, with the magen arguments only: `ANDROID_UE_ADB_MODE=standalone`, `ANDROID_UE_IPV6_MODE=off`, no published adb port, and no `NET_ADMIN`. The lab branch does not set those two variables.

`lo` keeps `::1`. `default` and each non-lo interface get `disable_ipv6=1`. `all` is not set to 1. When the host itself has IPv6 off, preflight skips the `unshare -n ip6tables` probe instead of failing it. The emulator netns still has to show `::1` on `lo` before a boot is accepted.

The UPF creates a userspace TUN named `ogstun`. It does not use `gtp` or `gtp5g`. Preflight requires `/dev/net/tun`. By default the UPF is not attached to `o5g-egress` or any other non-internal network, so SGi curl is `SKIPPED`. `--with-sgi-egress` (Ansible `magen_sgi_egress`, default false) is the only way to attach it, and that command prints `needs Netdrive approval: egress via host`.

Before QEMU, `magen-up` enters the emulator netns from the host with `nsenter -t <pid> -n`. The pid has to belong to `o5g-androidN`. It sets `disable_ipv6=1` on every non-lo interface, including the `o5g-screen` interface, and never writes `all`. It then installs `ANDROID_UE_SCREEN`, which accepts TCP 8000 only from the listener address and drops every other source, including `o5g-uemuN`. The same IPv6 lock and an `ip6tables` DROP policy are applied in `ueN` when the host IPv6 stack is on. The emulator has no `NET_ADMIN`.

Live smoke reads `adb getprop sys.boot_completed`, `gsm.sim.state`, `dumpsys telephony.registry`, and logcat from the emulator. It does not use the radio-ok fixture unless `--fixture` is set. Missing evidence is a failure. The radio gate reads `sys.boot_completed`, `gsm.sim.state`, and logcat. A failure is reported with the evidence and stops. There is no automatic fallback. The preferred later option, only if Architect picks it, is a `dummy0` ULA anchor installed by the host with `nsenter -n` and a pid guard before QEMU, still without `NET_ADMIN` and never with `all=1`. `-feature -ModemSimulator` is only the last resort.

SCTP is not loaded for you. Preflight prints `sudo modprobe sctp` and stops until someone approves that command. The same pattern is used when host `ip_forward` is not 1: the script prints `sudo sysctl net.ipv4.ip_forward=1` and does not change the sysctl.

Postgres is not published. Host port 5432 stays with the Postgres that is already on the machine. The only published ports are `127.0.0.1:3300` (dashboard) and `127.0.0.1:3301` (screen listener). Preflight reads `ss -ltn` and refuses the run when 3300 or 3301 is already taken. It does not bind 5555 or 5900. `b0-agen-emu` is left alone, including its listener on `127.0.0.1:5900`. `down` deletes only names that start with `o5g-` inside project `open5g`.

## Images from PR #13

Lab Ops builds the emulator, the screen sidecar, and the dashboard/listener image from commit `7fe7e85cdae36f0615b115627e36c73412a4644c`. CI does not build or push them. `magen-build-images.sh` refuses every other SHA, including the #12 local tag `open5g-android-emulator:local`. It can `docker save` an archive for a host that has no internet, and it writes `lab/compose/magen.images.env` with `sha256:` image ids. That file is gitignored.

```bash
bash lab/scripts/magen-build-images.sh --save "$HOME/o5g-state"
# on MAGEN_HOST, after copying the archive:
docker load < o5g-images-7fe7e85.tar.gz
```

The dashboard profile stays closed while any of those digests is empty, and also while `--with-sgi-egress` is set.

## Screen

`o5g-screen` is internal and IPv4-only. The emulators and the screen listener are the only members. ws-scrcpy binds the emulator address on that network, not `127.0.0.1`, because Docker DNAT does not reach a loopback socket inside a container netns. The `ANDROID_UE_SCREEN` chain accepts TCP 8000 only from the listener address and drops every other source. The listener publishes `127.0.0.1:3301` and no other host port.

The sidecar and listener programs are built from the PR #13 tree. Do not combine that tree with another commit by hand. After Architect gives a GO for a #13 SHA, build the dashboard API image, the web image, and the screen image from that tree, then pin each digest in `magen.env`. Until those digests replace the `REPLACE_` placeholders, the `dashboard` profile stays off and `--with-dashboard` fails closed.

```bash
git fetch origin cursor/android-emulator-dashboard-8cae
git checkout <PR13_SHA_WITH_GO>
docker build -f dashboard/backend/Dockerfile -t open5g-dashboard-api:build dashboard/backend
docker build -f dashboard/frontend/Dockerfile -t open5g-dashboard-web:build dashboard/frontend
docker image inspect --format '{{index .RepoDigests 0}}' open5g-dashboard-api:build
```

Record the `@sha256:` value in the gitignored env. Do not commit it.

## State, backup, restore

State lives in `$HOME/o5g-state`, mode `0700`. Guest dumps go to `$HOME/o5g-state/backup/<timestamp>` with sha256 files beside them. The scripts do not print dump bytes. Restore refuses a non-empty Mongo or Postgres target unless `--force-nonempty` is passed. Dump paths have to be absolute and outside the repo.

## Cutover and rollback

1. Run `--tags preflight` and stop if it asks for approval.
2. `--tags backup` reads the guest. It does not change the guest.
3. `--tags up` starts project `open5g`. The VM lab is still the fallback.
4. `--tags restore` loads the dumps into `o5g-mongo` and the dashboard Postgres.
5. `--tags smoke` writes `$HOME/o5g-state/smoke.json` and `smoke.md`. CI runs this with fixtures. The live core, attach, and screen session run in a later Lab Ops window.

Rollback is `--tags down`. That removes `o5g-` resources only. Add `--volumes` on `magen-down.sh` only when the volumes should go too. The VM lab is unchanged, and `b0-agen-emu` is unchanged.

A second preflight reports `changed=0`.
