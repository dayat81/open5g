# Independent offline validation — lab5g-dev IaC

**DEPLOYMENT AND EVIDENCE NOT RUN.**

This file is the integration check for the frozen `iac-lab5g-dev` archive.
It is not the author log in [iac-offline-validation.md](iac-offline-validation.md).
Nothing here was applied to a VM, hypervisor, lab host, or workstation.
No SSH session was opened, no lab endpoint was requested, and no container
or KVM guest was created, started, pulled, or built.

Gate B is **not accepted**. A rendered srsRAN `nr_cell_list` and an empty OAI
Compose file are configuration text only. They are not EN-DC acceptance and
not evidence of X2 SgNB addition, E-RAB modification, or S1-U switching.
Per-APN slice UPF templates are not a validated slicing result.

OAI X2 SgNB stays WIP and disabled (`oai_profile_enabled: false`, Compose
`services: {}`). cgnat/tun2socks stays WIP and disabled
(`internet_egress_enabled: false`). The rendered egress script prints a WIP
line and exits 2.

## Archive inspection (before copy)

| Check | Result |
|---|---|
| Archive SHA-256 | `d151e935ae6ee39a780618bdc1d1c51a882e4afbc947c8c76d5886fa663e17f9` (matches the stated digest) |
| Members | 107: empty wrapper directory `iac-lab5g-dev`, 46 directories, 61 files |
| Links and special files | None. No symlink, hardlink, device, or fifo |
| Path safety | No absolute path, `..` segment, or NUL. The wrapper directory is the only member outside `infra/` and was not copied |
| Manifest | 60 file hashes, `MANIFEST.txt` excluded. All 60 matched the extracted bytes. No missing, extra, or duplicate paths |

## Sanitization

Scanned the extracted tree before staging, then scanned the integrated tree
again. No private-key blocks, cloud or Git tokens, URI userinfo, packet
captures, certificate bundles, or personal `/Users` or Windows profile paths.

| Item | Treatment |
|---|---|
| Vault and CSV Ki/OPc | Placeholders (`REPLACE_WITH_32_HEX_CHARACTERS`, `REPLACE_WITH_VAULT_LOOKUP`). Not literal key material |
| Dry-run `ran.env` KEY and OPC | 32 zero digits, used only when `iac_dry_run` is true. Not a subscriber secret |
| Example IMSI | Test PLMN 001/01 placeholder already in the frozen roles. Not a live subscriber |
| SSH key path | Placeholder `/absolute/path/to/lab_id_ed25519` |
| `lab_root` | Generic role path `/home/lab/lab5g-dev` |
| Secret-scan denylist | The frozen `scripts/secret-scan.sh` embedded environment-specific host, address, and path tokens and excluded itself from the scan. Those tokens were removed before commit and are absent from this tree. The script now looks for private-key blocks, credential assignments, 32-hex Ki/OPc literals, and personal path prefixes |
| Live-lab guard | `site.yml` still refuses one hardcoded protected-lab `ansible_host`. Kept as a guard, not treated as a credential |

## What changed from the frozen payload

| Path | Change |
|---|---|
| `scripts/secret-scan.sh` | Removed environment-specific denylist tokens. Generic detectors only |
| `scripts/render-compose.py` | `.sh.j2` templates now render to a `.sh` filename. Frozen output for the egress script was `internet-up.sh.j2.sh` |
| `requirements.yml` | Declares `community.general` 13.5.1 and `ansible.posix` 2.2.2, and pins `community.docker` 5.4.0 and `community.libvirt` 2.4.0. The frozen file named only docker and libvirt, with no versions. `vm_base` uses `community.general.modprobe` and `ansible.posix.sysctl`. Syntax check cannot resolve `modprobe` without `community.general`. Collection 14.0.0 requires Ansible `>=2.19.0`, which `requirements.txt` excludes, so 13.5.1 is pinned (`requires_ansible >=2.18.0`) |
| `inventory/local-dry-run.yml` | Adds an empty `kvm_hosts` group so the optional host play matches no hosts. Without it, syntax check warned `Could not match supplied host pattern, ignoring: kvm_hosts` |
| `CHANGELOG.md`, `README.md`, `MANIFEST.txt` | Record the integration delta and the refreshed hashes |
| `docs/iac-independent-validation.md` | This report |
| Repository `README.md` | One layout-table row for `infra/`. No other root document was edited. `docs/DELIVERABLES.md` still describes the earlier scaffold branch and was left as it was |
| Repository `.gitignore` | Ignores `.ansible/`, which Ansible created at the repository root during local parsing. That directory is scratch and is not part of the payload |

`MANIFEST.txt` was regenerated after these edits. It is no longer byte-identical to the frozen 60-file manifest.

Not changed, and still true of the frozen roles:

- `make up`, `make verify`, and `make down` target `inventory/lab5g-dev.yml` (gitignored, not in the tree). They were not run.
- `make render` and `make check` invoke `ansible-playbook --check`. They were not run.
- `ansible.cfg` still defaults `inventory` to `inventory/lab5g-dev.yml` and sets `host_key_checking = false`. Every command below passed `-i inventory/local-dry-run.yml`.
- `tests/validate_compose_schema.py` can download a Compose schema if `tests/compose-spec.json` is missing. The vendored file was present. The run was inside a network namespace, so the download path could not succeed.

## Commands run here

Tools were installed on this cloud VM from PyPI, Galaxy, and the Docker Compose
GitHub release. Validation commands then ran with `unshare --user --map-root-user --net`.
A probe to `1.1.1.1:443` failed with `OSError` before the checks (`NETWORK_CLOSED`).

Working directory: `infra/`. Collections path: a scratch directory outside the
repository. `ANSIBLE_HOME` and `ANSIBLE_LOCAL_TEMP` were also outside the
repository.

| Tool | Version used here | Author reported |
|---|---|---|
| Python | 3.12.3 | 3.13 |
| ansible-core | 2.18.20 (venv). System 2.16.3 was not used | 2.18.20 |
| ansible-lint | 25.12.2 (`--offline`) | 25.12.2 |
| yamllint | 1.38.0 | 1.38.0 |
| Docker Compose | standalone v2.40.3, SHA-256 `dba9d98e1ba5bfe11d88c99b9bd32fc4a0624a30fafe68eea34d61a3e42fd372`, matched upstream `checksums.txt` | v2.40.3 |
| PyYAML / Jinja2 / jsonschema | 6.0.3 / 3.1.6 / 4.26.0 | not numerically reported |
| community.docker | 5.4.0 | 5.4.0 |
| community.libvirt | 2.4.0 | 2.4.0 |
| ansible.posix | 2.2.2 | 2.2.2 |
| community.general | 13.5.1 | not reported |
| community.library_inventory_filtering_v1 | 1.1.5 (Galaxy dependency of the collections above) | not reported |

```sh
yamllint -c .yamllint.yml site.yml teardown.yml requirements.yml \
  group_vars inventory roles host_vars
ansible-playbook -i inventory/local-dry-run.yml site.yml --syntax-check
ansible-playbook -i inventory/local-dry-run.yml teardown.yml --syntax-check
ansible-lint --offline -c .ansible-lint site.yml teardown.yml
python3 scripts/render-compose.py
python3 tests/validate_rendered.py
python3 tests/validate_compose_schema.py
docker-compose -f rendered/open5gs_epc_cups/docker-compose.yml config --quiet
docker-compose -f rendered/ran_srsran/docker-compose-ran.yml config --quiet
bash scripts/secret-scan.sh
```

`docker-compose` in that list is the verified standalone binary, not a daemon
client. `config` was also run without `--quiet` long enough to read service
names. Output did not include a pull or download.

## Results from this run

| Check | This run | Author log only |
|---|---|---|
| yamllint | PASS, exit 0, no messages | PASS, 0 errors |
| `site.yml` syntax check | PASS, exit 0, `playbook: site.yml`. First attempt, before `community.general` was installed, failed: unresolved `community.general.modprobe` | PASS, no VM connection |
| `teardown.yml` syntax check | PASS, exit 0. Author procedure did not include this file | not reported |
| ansible-lint production profile | PASS: `0 failure(s), 0 warning(s) in 17 files processed of 17 encountered`. Stderr still printed two non-rule notices: offline mode skipped collection dependency installs, and `.yamllint.yml` does not meet ansible-lint's bundled yamllint profile (`comments-indentation`, `braces.max-spaces-inside`, `octal-values`). Rule summary stayed 0/0. `.yamllint.yml` was not rewritten | PASS, 0 failures / 0 warnings in 17 files |
| `ansible-playbook --check --diff` | **Not run.** Check mode can still call modules that support it, and `vm_base` creates directories even when `iac_dry_run` is true. Not in the cloud-local allowlist | PASS: ok=11, changed=9, unreachable=0, failed=0, skipped=26 |
| Template render | PASS. 9 Open5GS YAML files (`hss`, `pcrf`, `mme`, `sgwc`, `sgwu`, `smf`, `upf`, `slice-upf-slice-a`, `slice-upf-slice-b`), core Compose, RAN Compose. Egress script path is `rendered/internet_egress/internet-up.sh` | PASS: 9 Open5GS configs, core and RAN Compose, two slice UPFs |
| `validate_rendered.py` | PASS, same summary line as the script | included in the template result |
| Compose JSON schema | PASS for core and RAN, using vendored `tests/compose-spec.json` | PASS |
| `docker-compose config` | PASS for core and RAN. Core services: `mongo`, `hss`, `pcrf`, `mme`, `sgwc`, `sgwu`, `smf`, `upf`, `upf-slice-a`, `upf-slice-b`, `server`. RAN services: `enb`, `ue` | PASS |
| Secret scan script | PASS after the denylist edit | PASS on the authoring box, against the old denylist |

Rendered review, still not a deployment:

- Core Compose networks in the standalone render are `internal: true` except `uu`, which is omitted from the core file.
- `ran.env` KEY and OPC are 32 zero digits.
- OAI Compose has `services: {}`.
- Egress script starts with `#!/bin/bash` and ends with `exit 2`.
- srsRAN `rr.conf` contains `nr_cell_list`. That is the integrated-cell text in the template. It does not accept Gate B.
- The standalone renderer still emits only `fd-hss.conf`. The Ansible role templates four freeDiameter peers. `seed-subscriber.js.j2`, `cloud-user-data.yml.j2`, and `lab-routes.sh.j2` are skipped by the renderer on purpose.

## Explicitly not run

- `ansible-playbook` apply, `--check`, or `--check --diff`
- `make up`, `make down`, `make verify`, `make render`, `make check`
- Any inventory other than `inventory/local-dry-run.yml`
- SSH, `virsh`, `virt-install`, libvirt, cloud-init, apt, or package install on a guest
- `docker compose up`, `start`, `build`, or `pull`
- Attach, SGi ping, PFCP log evidence, or any other lab evidence
