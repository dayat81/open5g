# Slicing PoC staged configs

**STAGED, NOT DEPLOYED** — WIP package v1 (2026-11-06 20:21:58 +07 Asia/Bangkok).

Source: `/workspace/poc-stage/`. **Not applied** to `lab5g-dev`.

| File | Role |
|---|---|
| `upf-a.yaml` / `upf-b.yaml` | UPF per DNN (`slice-a`/`slice-b`) |
| `core.compose.append` | Compose services `upf-a` / `upf-b` |
| `smf-slice-snippet.yaml.example` | SMF PFCP client + session DNN fragment |
| `apply.py` | Staging applicator (do not run from this package) |
| `run-guest.sh.example` | Guest runner without subscriber rewrite |

**Excluded:** `subscriber-a.js` (non-additive) and any mongo dumps.  
**SGW:** no separate staged SGW YAML in poc-stage at snapshot time.  
**eBPF:** none present (see `../ebpf/README.md`).
