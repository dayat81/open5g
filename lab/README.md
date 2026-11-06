# Lab

Open5GS EPC CUPS is the intended core for the EN-DC Option 3x target (separate SgNB). This directory does not contain a sanitized lab package, image digests, APNs, or a compose project. Those stay WIP until the Network Architect package is checked in.

Gate B does not accept an integrated eNB NR cell as separate-SgNB EN-DC. See [`../docs/DELIVERABLES.md`](../docs/DELIVERABLES.md).

Nothing here was deployed. lab5g-vm is out of scope. No SSH, hypervisor, or workstation copy is used.

## Future run on lab5g-dev

These steps are for a person later, after both of these are true:

1. The user explicitly authorizes a run on **lab5g-dev**.
2. The sanitized lab package is in this directory and has been reviewed.

They were **not** executed for this repository. Do not run them against lab5g-vm.

1. Read the checked-in versions, digests, and configs from that package. Do not invent a digest or a subscriber key to fill a gap.
2. On lab5g-dev only, render and validate the package's compose and config files.
3. Start only the services that package names, on lab5g-dev, under the authorization from step 1 above.
4. Keep Ki, OPc, K, and passwords out of git. Keep core restart and re-attach as explicit operator actions; this scaffold does not perform them.
5. Treat EN-DC as still WIP unless a later evidence summary records a separate SgNB. An integrated NR cell on the eNB does not close that gap.

This commit has no compose file to render and no service to start.
