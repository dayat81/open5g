# open5g

Scaffold for a lab dashboard that checks per-application policy intent
against an Open5GS EPC CUPS core. The goal is APN-based logical
segmentation and PCC observability. It is not an implementation of
end-to-end 3GPP slicing or URSP, and it is not an EN-DC test result.

`main` on GitHub is the untouched initial commit. `master` is the
integration branch for this work. See `docs/BOOTSTRAP.md`.

Deployment is not authorized. Do not point this tree at lab5g-vm.
Future lab work, when authorized, targets lab5g-dev only. No SSH,
hypervisor, or workstation copy is part of this repository.
