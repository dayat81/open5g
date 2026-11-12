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

Before QEMU, `magen-up` enters the emulator netns. Root with `nsenter` uses `nsenter -t <pid> -n`. A docker-group user uses `docker run --rm --network container:o5g-android1 --cap-add NET_ADMIN --pull never`. `NET_ADMIN` is enough for `iptables-legacy`. `NET_RAW` is not added. The helper does not write sysctl: `/proc/sys` is read-only in that container, so a write would fail closed before the chain exists. Compose already sets `disable_ipv6=1` on `default`, `eth0`, and `eth1`. The helper only reads those values and stops if one is wrong, and only then installs `ANDROID_UE_SCREEN`. Host iptables are not changed. The emulator process has no `NET_ADMIN`. `all` is never written. The inspect id and pid must match `o5g-android1` or `o5g-ue1`/`o5g-ue2` when the EPC flag is on. A failed check stops the run.

## GUI profile

The default on magen is `gui` (`--gui-only`, Ansible `magen_gui_only=true`). It starts only `o5g-android1`, `o5g-screen1`, `o5g-dashboard-listener`, `o5g-dashboard-api`, `o5g-dashboard-web`, and `o5g-dashboard-postgres`. Mongo, the EPC, and srsRAN stay behind `--with-epc` for phase 2. Preflight does not ask for `sctp`, `gtp`, or `ogstun` in gui mode. `o5g-egress` is not attached. `--gui-only` together with `--with-sgi-egress` is rejected.

Postgres is the upstream `postgres:16` image, pinned by digest in `magen.images.env` and loaded from `o5g-postgres.tar.gz`. That archive is separate from `o5g-images-a680f8b.tar.gz`, so the four-image tar does not change. The container name starts with `o5g-` and it publishes no port, so host `5432` is left alone.

The API does not receive `OPEN5G_MONGO_URI`. At `a680f8b`, an empty URI selects `DisabledSubscriberPort` in `build_subscriber_port`, which reports `not_configured` and does not write. `OPEN5G_ENABLE_GX_RAR=0` keeps PCC writes off. Metrics and health endpoint lists stay unset, so the UI shows the lab as not configured. The process still starts. `OPEN5G_EMULATOR_ENABLED=1` is the default; set it to `0` to roll the screen back without removing the emulator.

Reach the UI with `ssh -L 3300:127.0.0.1:3300 -L 3301:127.0.0.1:3301`. The only host publishes are `127.0.0.1:3300` and `127.0.0.1:3301`.

The listener cannot bind `127.0.0.1` inside the container: Docker DNAT delivers the published port to the container's dash address, and `a680f8b` refuses a bind of `0.0.0.0`. It therefore binds `O5G_LISTENER_DASH` and belongs only to `o5g-dash` and `o5g-screen`. The web proxy binds `0.0.0.0` inside its own container and is only on `o5g-dash`, so host `127.0.0.1:3300` reaches it. Next itself stays on `127.0.0.1:3001` inside that container and is not published. The browser loads `http://127.0.0.1:3300`, the page asks the API for a screen session, and the frame uses `http://localhost:3301/emulator/ue1/`, which the tunnel delivers to the listener. The listener then dials the sidecar on the screen network at port 8000. Host port 8000 stays closed.

Smoke in gui mode records the radio gate and attach as `SKIPPED (gui-only)`. Those lines are not S1–S8 evidence. It still requires `boot_completed=1`, websocket status 101, a closed host path to port 8000, and a successful curl of both `127.0.0.1:3300` and `127.0.0.1:3301`.

## Phase 2

Not built. `--with-epc` keeps the current core services for later.

- The API will read the guest read-only through `LAB_GUEST_ADDR` (a placeholder). Egress is allowlisted only to that guest address and port.
- srsUE stays on the guest. `androidN` would reach the guest `ueN` through an L3 tunnel. The mechanism is not chosen: WireGuard is not available on this 3.10 kernel, and GRE or a host route needs Netdrive approval.
- SGi, socks, and S1–S8 stay off until that approval.

Live smoke reads `adb getprop sys.boot_completed`, `gsm.sim.state`, `dumpsys telephony.registry`, and logcat from the emulator. It does not use the radio-ok fixture unless `--fixture` is set. Missing evidence is a failure. The radio gate passes only when `boot_completed` is 1, `gsm.sim.state` is READY or LOADED, `telephony.registry` is non-empty, and logcat contains a ModemSimulator line. An empty logcat or empty adb output fails. A failure is reported with the evidence and stops. There is no automatic fallback. The preferred later option, only if Architect picks it, is a `dummy0` ULA anchor installed by the host with `nsenter -n` and a pid guard before QEMU, still without `NET_ADMIN` and never with `all=1`. `-feature -ModemSimulator` is only the last resort.

The gui profile does not load `sctp`. `--with-epc` still prints `sudo modprobe sctp` and stops until someone approves that command. It does not load the module. The same pattern is used when host `ip_forward` is not 1 and SGi was requested: the script prints `sudo sysctl net.ipv4.ip_forward=1` and does not change the sysctl.

Postgres is not published. Host port 5432 stays with the Postgres that is already on the machine. The only published ports are `127.0.0.1:3300` (dashboard) and `127.0.0.1:3301` (screen listener). Preflight reads `ss -ltn` and refuses the run when 3300 or 3301 is already taken. It does not bind 5555 or 5900. `b0-agen-emu` is left alone, including its listener on `127.0.0.1:5900`. `down` deletes only names that start with `o5g-` inside project `open5g`.

## Images from PR #13

Lab Ops builds the emulator, the screen sidecar, the dashboard/listener image, and the dashboard web image from commit `a680f8b469d51e4c1d95d433f4b97c84d153a622`. That is the PR #13 tree this profile expects. `compose.magen.yml` reads `O5G_DASHBOARD_WEB_IMAGE` for the web service and `O5G_DASHBOARD_API_IMAGE` for both the API and the listener (`python -m open5g_dashboard.screen`). `dashboard/frontend/Dockerfile` and `dashboard/backend/Dockerfile` both exist at that commit, so one pin script builds all four. CI does not build or push them. `magen-build-images.sh` refuses every other SHA, including the previous pin and the #12 local tag `open5g-android-emulator:local`. It can `docker save` an archive for a host that has no internet, and it writes `lab/compose/magen.images.env` with `sha256:` image ids, including `O5G_DASHBOARD_WEB_IMAGE`. That file is gitignored. Copy the four keys into the gitignored env. The example file keeps `REPLACE_` placeholders.

The emulator image at that SHA runs `/opt/open5g-preflight.sh` before QEMU. The copy baked into `a680f8b` requires `dummy0`, a ULA, and `getaddrinfo(::1, AI_ADDRCONFIG)`, and it has no `ANDROID_UE_IPV6_MODE`. Architect's decision for this profile is no `dummy0` and no ULA by default, with `::1` on `lo` still mandatory. Compose bind-mounts the #20 `open5g-preflight.sh` onto `/opt/open5g-preflight.sh` and sets `ANDROID_UE_IPV6_MODE=off`. That script still requires `::1`, refuses `all=1`, requires `disable_ipv6=1` on every non-lo interface, and does not enter the `dummy0` branch. The #13 branch is not changed. The dashboard profile opens only when the API, web, screen, and Postgres digests are all present and SGi is off.

```bash
bash lab/scripts/magen-build-images.sh --save "$HOME/o5g-state"
# on MAGEN_HOST, after copying both archives:
docker load < o5g-images-a680f8b.tar.gz
docker load < o5g-postgres.tar.gz
```

`o5g-postgres.tar.gz` is only the upstream `postgres:16` image. It is not part of the four-image archive.

The dashboard profile stays closed while any of those digests is empty, and also while `--with-sgi-egress` is set.

## Screen

`o5g-screen` is internal and IPv4-only. The emulators and the screen listener are the only members. ws-scrcpy binds the emulator address on that network, not `127.0.0.1`, because Docker DNAT does not reach a loopback socket inside a container netns. The `ANDROID_UE_SCREEN` chain accepts TCP 8000 only from the listener address and drops every other source. The listener publishes `127.0.0.1:3301` and no other host port.

The sidecar, the listener, and the web image are built by `magen-build-images.sh` from `a680f8b`. Do not combine that tree with another commit by hand. Until the four digests replace the `REPLACE_` placeholders, the `dashboard` profile stays off and `--with-dashboard` fails closed.

## State, backup, restore

State lives in `$HOME/o5g-state`, mode `0700`. Guest dumps go to `$HOME/o5g-state/backup/<timestamp>` with sha256 files beside them. The scripts do not print dump bytes. Restore refuses a non-empty Mongo or Postgres target unless `--force-nonempty` is passed. Dump paths have to be absolute and outside the repo.

## Cutover and rollback

1. Run `--tags preflight` and stop if it asks for approval.
2. `--tags backup` reads the guest. It does not change the guest.
3. `--tags up` starts project `open5g`. The VM lab is still the fallback.
4. `--tags restore` loads the dumps into `o5g-mongo` and the dashboard Postgres.
5. `--tags smoke` writes `$HOME/o5g-state/smoke.json` and `smoke.md`. The tag is `never`, so a default play does not run it. CI runs the script with fixtures, including a screen fixture that expects websocket status 101 on `127.0.0.1:3301/emulator/ue1` and a closed host path to emulator port 8000. The live run does the same two checks against the listener and is the S1 evidence when Lab Ops runs it.

Rollback is `--tags down`. That removes `o5g-` resources only. Add `--volumes` on `magen-down.sh` only when the volumes should go too. The VM lab is unchanged, and `b0-agen-emu` is unchanged.

A second preflight reports `changed=0`.
