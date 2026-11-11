# Emulator screen on the dashboard

Runbook for opening the Android emulator from the dashboard. The UE, eNB, CGNAT, and SOCKS path stay as they are in [`android-ue-lab5g-dev.md`](android-ue-lab5g-dev.md). This page does not start the core, does not edit HSS, PCRF, SGW, or PGW, and does not change the egress filter.

Nothing here was executed on lab5g-dev. Do not deploy it from this change.

## Why ws-scrcpy, not noVNC

The pinned image is `halimqarroum/docker-android:api-33`. Its Docker Hub description and `scripts/start-emulator.sh` start a headless emulator. ADB is published inside the container with `adb -a` and with `socat` bound to the container IPv4 (eth0) for ports 5554 and 5555, forwarding to loopback. That script does not start x11vnc, websockify, or noVNC. There is no `WEB_VNC`, no `VNC_PORT`, and no `VNC_PASSWORD`.

`budtmo/docker-android` is a different image. It is the one that documents `WEB_VNC=true`, noVNC on 6080, and VNC on 5900. It is not the image this overlay pins, so those variables are not used.

The screen path is a ws-scrcpy sidecar (`NetrisTV/ws-scrcpy`) in the UE netns (`network_mode: service:ueN`). The sidecar writes a config that sets `server.host` to `UE*_UU` and `server.port` to `ANDROID_UE_SCREEN_PORT` (8000 in the example). `WS_SCRCPY_PATHNAME` is `/emulator/ueN`. ADB from the sidecar dials `127.0.0.1:5555` inside that netns. It does not use a host port, and it does not read `UE*_ADB_HOST_PORT` (that variable is gone; publishing on the internal `uu` network does not work).

There is no VNC password because there is no VNC server. Do not invent one in git. The sidecar itself has no login. The dashboard session is the gate, and the listen address is the uu address only.

## What is not published

- The compose service `ueN-screen` has no `ports:` key.
- The entrypoint refuses to bind `0.0.0.0`, `::`, or `127.0.0.0/8`.
- The API process keeps its own listener on `127.0.0.1:8000`. Next listens on `127.0.0.1:3000`.
- The browser never dials the uu address. It only talks to the dashboard origin.

The API reaches the sidecar at the internal target. Set that with either of these, not with a host port:

- `OPEN5G_EMULATOR_TARGETS=ue1=<UE1_UU>:8000,ue2=<UE2_UU>:8000`
- or `internal_host` and `internal_port` on the `emulator_endpoints` row. A row wins over the env value for that UE.

`<UE1_UU>` is the same address the UE container already has on the `uu` network. Copy it into the gitignored dashboard env. Do not commit the lab value.

The API process has to route to that address. On the guest, the Docker bridge for `uu` is enough when the API runs on the host. A later containerized API must join the `uu` network and still must not publish the screen port.

## Build the sidecar image

Mirror a ws-scrcpy image that contains `npm`, `adb`, and the app at `/opt/ws-scrcpy`. Build with Android enabled and with the extra surfaces off:

- `INCLUDE_GOOG` true
- `INCLUDE_APPL`, `INCLUDE_ADB_SHELL`, `INCLUDE_DEV_TOOLS`, and `INCLUDE_FILE_LISTING` false
- `SCRCPY_LISTENS_ON_ALL_INTERFACES` false

Put the image name in the gitignored `lab/compose/android-ue.env` as `ANDROID_UE_SCREEN_IMAGE`. The example keeps `REPLACE_ANDROID_UE_SCREEN_IMAGE`, and `android-ue-up.sh` then skips the sidecar. Set `ANDROID_UE_SCREEN_PORT=8000`.

## Enable

1. Bring the UE up with the existing runbook. Core containers are not restarted by that script.
2. Set `ANDROID_UE_SCREEN_IMAGE` to the mirrored image and run `android-ue-up.sh` again, or start only the sidecar:

   ```bash
   sudo docker-compose -f lab/compose/docker-compose.android-ue.optional.yml \
     --env-file lab/compose/android-ue.env --profile android-ue up -d ue1-screen
   ```

3. Create the dashboard row as an admin. `assignment_id` is the student's assignment. `internal_host` is optional when `OPEN5G_EMULATOR_TARGETS` already has the uu address. `attach_ipv4` and `apn` are the values to display. This call does not read the PGW and does not change it.

   ```bash
   curl -sS -c /tmp/dash.ck -b /tmp/dash.ck \
     -H 'content-type: application/json' \
     -d '{"email":"<admin>","password":"<password>"}' \
     http://127.0.0.1:8000/api/auth/login
   ```

   Take `csrf_token` from that JSON and the cookie, then PUT `/api/admin/emulator-endpoints/ue1` with `x-csrf-token`.

4. Dashboard env, all gitignored:

   ```bash
   OPEN5G_EMULATOR_ENABLED=1
   OPEN5G_EMULATOR_ORIGINS=http://127.0.0.1:3000
   OPEN5G_EMULATOR_IDLE_SECONDS=300
   OPEN5G_EMULATOR_TARGETS=ue1=<UE1_UU>:8000
   ```

   `OPEN5G_DATABASE_URL` and `OPEN5G_SESSION_PEPPER` stay as they are. Pepper is at least 32 characters and is not a VNC password.

5. Start the API on loopback and Next on loopback. `OPEN5G_API_PROXY` is the API, seen only by the Next server. `NEXT_PUBLIC_API_BASE` is the browser origin so cookies stay on one host.

   ```bash
   python -m open5g_dashboard
   OPEN5G_API_PROXY=http://127.0.0.1:8000 \
     NEXT_PUBLIC_API_BASE=http://127.0.0.1:3000 \
     npx next dev -H 127.0.0.1 -p 3000
   ```

   Next rewrites `/api` and `/emulator` to the API, including the websocket upgrade. Confirm that upgrade on the guest; it is not proven in CI.

## Who can open a screen

A student can open only a UE whose assignment owner is that student. An admin or an instructor can open every configured UE. Anyone else gets 403. No session gets 401.

One control session per UE. A second user gets **409 `emulator_control_busy`**. The holder can refresh; that replaces their own session and closes the previous one. A second session is not view-only: ws-scrcpy carries input and video on the same socket, and filtering part of it could grant control by mistake. The UI shows the busy status and does not open a second frame.

The websocket upgrade also checks `Origin` against `OPEN5G_EMULATOR_ORIGINS`. A missing or foreign origin is 403. The upgrade also needs the path-scoped HttpOnly cookie minted by the CSRF-checked `POST /api/emulator/<ue_id>/session`, or the same session's `x-csrf-token` header. Idle time defaults to 300 seconds. Open and close are rows in `audit_events` (`emulator_open`, `emulator_close`) with the user, the `ue_id`, and `at`.

## Disable

Set `OPEN5G_EMULATOR_ENABLED=0` and restart the API. Logged-in calls get 404 `emulator_disabled`. The sidecar can keep running; the proxy will not dial it. Stopping only the sidecar leaves the UE attached:

```bash
sudo docker-compose -f lab/compose/docker-compose.android-ue.optional.yml \
  --env-file lab/compose/android-ue.env --profile android-ue stop ue1-screen
```

The dashboard then shows the attach address and APN with the screen down. It does not offer a reset or a wipe.

## Rollback

1. Disable the flag as above and stop `ue1-screen` and `ue2-screen` if they were started.
2. Leave CGNAT, the SOCKS tunnel, the UPF rule, and the core running. Do not run `android-ue-down.sh` unless the whole UE overlay should go away. That script now stops the screen containers first, then the rest of the profile, and still does not edit the core.
3. `emulator_endpoints` rows can stay. They are ignored while the flag is off.
4. Remove `OPEN5G_EMULATOR_*` from the gitignored dashboard env if the process should not even parse targets.

## Smoke from a laptop

This needs the lab guest, KVM, and an attached UE. CI does not run it.

1. From the laptop, tunnel only the dashboard port:

   ```bash
   ssh -L 3000:127.0.0.1:3000 <guest>
   ```

2. Open `http://127.0.0.1:3000`, log in as the student who owns ue1, and open Emulator.
3. The frame should show the Android screen. Open Chrome in the guest Android UI.
4. On the guest, check the UE path from the ue1 netns. Do not publish a port to do this, and do not use a host ADB port:

   ```bash
   sudo docker exec l5gd-ue1 ping -c 3 -w 5 <SGI_OR_ECHO>
   ```

   The SOCKS proof in the android-ue runbook still applies when that profile is up. This screen path does not move it.

If the frame stays empty while the status says the screen is up, the usual lab check is whether Next forwarded the websocket upgrade and whether `OPEN5G_EMULATOR_ORIGINS` is exactly `http://127.0.0.1:3000`.

## Phase 2

- A real view-only watcher, after input and video can be split without granting control.
- Read the attach address from `tun_srsue` instead of the value stored on the endpoint. Still no write to the PGW.
- Start and stop the emulator from the dashboard.
- Authenticate the sidecar. Today the uu address and the dashboard session are the controls.
- Confirm the Next rewrite upgrades websockets on the guest image of Node that the lab runs.
