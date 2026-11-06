# lab5g-dev Infrastructure as Code

**DEPLOYMENT AND EVIDENCE NOT RUN — author + offline dry-run only.**

This `infra/` payload is intended for a separate `infra/iac-lab5g-dev` PR.
It models a NEW isolated development instance derived from the sanitized
Open5GS 2.8.0 EPC-CUPS and srsRAN configuration. It did not connect to,
modify, or test any lab, VM, hypervisor, or laptop.

## Scope

- Optional, disabled-by-default KVM network/disk/cloud-init definition.
- Ubuntu VM packages, Docker and Compose, SCTP, forwarding, and `/dev/net/tun`.
- Open5GS MongoDB, HSS, PCRF, MME, SGW-C/U, SMF, UPF and SGi server.
- Templated APN sessions and two slice UPFs: slice-a `10.99.6.15`, pool
  `10.46.0.0/16`; slice-b `10.99.6.16`, pool `10.47.0.0/16`.
- srsRAN ZMQ EN-DC baseline, with `ran_srsran_profile: lte-only` as an option.
  UE starts before eNodeB, matching the observed ZMQ requirement.
- An idempotent MongoDB `replaceOne` subscriber seed, with Ki/OPc only from
  Ansible Vault. The template for a per-user CSV inventory is an example only.
- Verify role waits for `Network attach successful`, pings `10.99.9.20`,
  and requires positive SMF PFCP-association log evidence.

## Important limitations / WIP

- **No deployment or evidence was run.** No attach, SGi ping, or PFCP checks
  have been performed from this Ansible implementation.
- OAI eNB + separate en-gNB is a disabled, empty Compose scaffold. It is not an
  SgNB implementation and has no X2/SgNB/E-RAB/S1-U-switching evidence.
- Internet egress is disabled. `cgnat: 10.99.9.30`, SOCKS/tun2socks, DNS over
  TCP and NAT are design inputs only; the rendered script intentionally exits
  without changing anything. No external egress is claimed.
- Stock Docker apt repositories require connectivity or an internal mirror on
  the isolated guest. Static/offline artifacts are not bundled. The box dry-run
  skips packages, services, Docker modules, routing and live verification.
- Interface indices in `lab-routes.sh` reproduce the observed topology. Review
  them before deploying against different Compose/network versions.
- Slice UPFs are per-APN infrastructure templates. They do not claim that the
  full PCRF PCC/eBPF slicing PoC has been applied or validated.
- `lab_vm_create` defaults false; the host role is never selected in offline
  rendering. KVM/cloud-init and host teardown have not been tested.

## Intended usage (not executed)

Copy `inventory/lab5g-dev.yml.example` to `inventory/lab5g-dev.yml`, provide
appropriate new-VM credentials, and put real `vault_ue_ki`/`vault_ue_opc` in an
encrypted `vault.yml` (never in `.env` tracked by git). Keep the inventory and
inventory hostnames pointed only at a fresh development VM. Review `make down`
carefully: it stops Compose workloads and is deliberately not run here.

```sh
make up                 # host VM provisioning remains opt-in
# make verify           # live checks only after a separately approved deployment
make verify
# make down             # future fresh development environment only
```

Ansible tags: `host`, `base`, `core`, `subscribers`, `ran`, `up`, `verify`,
`oai`, `internet`. The `site.yml` precondition rejects the protected live-lab
address and requires the development environment name. This is a safeguard,
not authorization; obtain approval before any real application.

See [iac-offline-validation.md](iac-offline-validation.md) for exact
repeatable offline checks and results.
