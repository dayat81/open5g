# Open5G Android emulator image

This tree vendors [docker-android](https://github.com/HQarroum/docker-android) at commit `f569246983ee994aed06517bf8e06a3f10547b6d` (2026-05-07T11:34:08Z). The MIT license is `upstream/LICENSE`. Open5G changes are only `patches/0001-open5g-boot.patch` and `open5g-preflight.sh`.

`upstream/keys/` is not included. Do not commit `adbkey` or `adbkey.pub`. The container creates an ADB key on first start, or the lab mounts one from outside git.

The patch pins:

- `eclipse-temurin:25@sha256:83f4a7fc27df94dcc7b8de04d14cbbba8da14406f921e966969c3b09000aa507`
- command-line tools zip `commandlinetools-linux-9477386_latest.zip`, SHA-256 `bd1aa17c7ef10066949c88dc6c9c8d536be27f992a1f3b5a584f9bd2ba5646a0`

API level, image type, architecture, and device stay at the upstream values: 33, `google_apis`, `x86_64`, `pixel`.

Build:

```bash
sudo bash lab/images/android-emulator/build.sh
```

The tag is `open5g-android-emulator:local` unless `ANDROID_UE_ANDROID_IMAGE` is set. `up` accepts that local tag, or a registry name that contains `@sha256`. The local tag is allowed because this Dockerfile pins its base with `@sha256`.
