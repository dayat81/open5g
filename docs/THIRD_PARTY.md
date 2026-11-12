# Third-party screen components

The emulator screen image is built from `lab/images/ws-scrcpy/Dockerfile`.

| Piece | Project | License | Pin |
| --- | --- | --- | --- |
| Screen server | [NetrisTV/ws-scrcpy](https://github.com/NetrisTV/ws-scrcpy) v0.8.1 | MIT | commit `ef273d97c6ac0c05d03b41d4b55d59a25b95c505` |
| Pathname | upstream commit `9d12bdd2240388113e1f397794494ab63c479817` | MIT | applied as `patches/0001-pathname.patch` |
| Device stream | scrcpy-server vendored by the v0.8.1 commit | Apache-2.0 | same commit |

The build turns off the adb shell, file listing, devtools, and iOS paths. `patches/0002-open5g-bind.patch` makes the server listen on the configured host and sets the starting video limits to max-size 800, 2 Mbit/s, and 15 fps. The runtime image name used on the guest must be pinned with `@sha256:`. The tarball pin stays the v0.8.1 archive; the patches are applied after it is unpacked.
