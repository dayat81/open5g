# Bootstrap

This commit establishes the integration branch. The implementation scaffold
is added on a feature branch and reviewed through a pull request.

## Branches

GitHub's default branch is `main`. That branch still contains only the
original initial commit and is not rewritten. `master` is the integration
branch requested for this work. It starts from that same initial commit.

## Out of scope for every commit in this effort

* No lab deployment, compose up, or core restart.
* No access to lab5g-vm, lab5g-dev, SSH, hypervisors, or a workstation copy
  of the tree.
* No subscriber Ki, OPc, K, or passwords in git.
* No claim that EN-DC, Gx RAR, or eBPF classification is implemented.
* The Network Architect sanitized lab package is pending. Versions, image
  digests, APNs, and EN-DC notes stay WIP until that package is checked in
  by a later change. Observations of public upstream tags are labeled as
  observations, not as a verified lab pin.

## Expected layout

The feature branch fills this in:

* `lab/compose/` render-only Compose template
* `lab/config/examples/` synthetic templates, not a copy of lab5g-dev
* `lab/scripts/` config validation that does not start containers
* `lab/patches/` notes only; `pcrf-admin-rar.patch` is added when a real
  patch exists
* `lab/versions.md` upstream observations and WIP markers
* `docs/capabilities.md` capability matrix
* `docs/evidence/<gate>/SUMMARY.md` only for checks this repository actually ran
