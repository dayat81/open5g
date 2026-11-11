# Third-party screen components

The emulator screen image is built from `lab/images/ws-scrcpy/Dockerfile`.

| Piece | Project | License | Pin |
| --- | --- | --- | --- |
| Screen server | [NetrisTV/ws-scrcpy](https://github.com/NetrisTV/ws-scrcpy) v0.8.1 | MIT | commit `ef273d97c6ac0c05d03b41d4b55d59a25b95c505` |
| Device stream | scrcpy-server vendored by that commit | Apache-2.0 | same commit |

The build turns off the adb shell, file listing, devtools, and iOS paths. The runtime image name used on the guest must be pinned with `@sha256:`.
