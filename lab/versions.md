# Upstream image and source versions

Snapshot time: **2026-11-06 20:17:38 +07** (Asia/Bangkok).  
Host VM: `lab5g-dev` (`172.22.20.21`). Read-only inventory; not a deployable mirror.

## Container images used by `l5gd-*`

RepoDigests were **empty** on this host (images loaded without registry digest metadata). Image IDs below are the local content digests (`docker image inspect .Id`).

| Image | Tag | Local image Id (sha256) | Approx created | Size |
|---|---|---|---|---|
| `gradiant/open5gs` | `2.8.0` | `1740bc23cc56401b81cb1661342879dbe413560613df21fcd64999c49ac7996d` | 2026-06-22 | 300MB |
| `gradiant/srsran-4g` | `25_10` | `f4d5136370016fa8a0613c98190b512620612b11e2dc76b21e055f4bbc428315` | 2026-02-02 | 264MB |
| `mongo` | `7.0` | `bf46c3fd4f186a3569a6c8d180ee6f55e46cc81e98c0cadaee2f56718c84979f` | ~2026-10-26 | 866MB |
| `nicolaka/netshoot` | `latest` | `2298d942ce5f8e8083c036b6d62e129379998712ef78343f88d41d782d507141` | ~2026-07-01 | 627MB |

### Containers → image

| Container | Image |
|---|---|
| l5gd-mme, l5gd-hss, l5gd-smf, l5gd-pcrf, l5gd-sgwc, l5gd-sgwu, l5gd-upf | gradiant/open5gs:2.8.0 |
| l5gd-enb, l5gd-ue | gradiant/srsran-4g:25_10 |
| l5gd-mongo | mongo:7.0 |
| l5gd-server | nicolaka/netshoot:latest |

## open5gs-src (in-VM tree for SMF/UPF development)

| Field | Value |
|---|---|
| Branch | `dev-smf-upf` |
| HEAD | `3d4023c6b6c0b1faee4b072907f3a58858aeb77e` |
| Describe | `3d4023c` |
| Log tip | `3d4023c open5gs v2.8.0 import` |
| Tags at HEAD | _(none)_ |
| Plan baseline cited | Open5GS tag `v2.8.0` (upstream); PoC plan also references commit `157f611a530e292e40ec50f9d23f0ef5d4fcd6a6` as documentation baseline |

Rebuild path (not E2E-verified in this snapshot): `rebuild-smf-upf.sh` + `docker-compose.override.dev.yml` bind-mounts.

## Notes

- `docker images --digests` reported `<none>` for DIGEST on all four images.
- EN-DC and slicing PoC workers may advance configs after this snapshot; treat EN-DC-related files as **WIP**.
