# eBPF

This directory is a classifier skeleton and an exporter contract. It is not a detector.

`classifier/app_classifier.bpf.c` is a tc program that returns `TC_ACT_UNSPEC` and does not read the packet. The map `app_counters` has at most 64 entries keyed by a numeric `app_id`. It does not parse DNS, TLS, QUIC, or Server Name Indication. Nothing in this tree loads or attaches the object.

`scripts/check_build.py` compiles that file when `clang` and `/usr/include/bpf/bpf_helpers.h` exist. Exit 0 means an object was produced in a temp directory and discarded. Exit 2 means the toolchain is missing and the build is untested. The script never calls a loader.

`exporter/contract.py` renders Prometheus text with a fixed label set: source, exporter instance, interface, capture point, rule version, and data origin. IMSI, SNI, hostname, and flow labels are rejected. `stub_series()` is labeled `data_origin="stub"` and is not a counter read from the kernel. The value zero in that stub is a placeholder series, not an observation that traffic was absent.

`lab/config/examples/ebpf/` remains the Network Architect placeholder and is **DRAFT-UNTESTED**. It is a different file from this skeleton.

## Limits still open

Kernel, BTF, and hook compatibility on lab5g-dev are **not verified**. TLS Encrypted Client Hello, encrypted DNS, and CDN hostnames are not handled because parsing is not implemented. A future collector would be a separate process with restricted capabilities, not the web backend, and it would not mount the Docker socket.

eBPF output is not a PCRF decision, not an installed PCC rule, and not measured user traffic.

## Check

```bash
python3 scripts/check_build.py
python3 -m pytest tests
```

Run the pytest command from this directory, or pass `ebpf/tests` from the repository root with `PYTHONPATH=ebpf`.
