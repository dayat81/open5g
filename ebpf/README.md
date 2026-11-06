# eBPF

Per-application detection with libbpf and CO-RE is **proposed**. It is not implemented in this tree.

`lab/config/examples/ebpf/` is the Network Architect placeholder from the sanitized WIP package. Its label is **DRAFT-UNTESTED**. It is not a CO-RE program and it is not a metrics exporter.

There is no classifier object, no loader, and no Prometheus exporter. Kernel, BTF, and hook compatibility are unverified. DNS, TLS, and QUIC parsing are not claimed. TLS ECH, encrypted DNS, and CDN ambiguity remain open limits.

A future detector would publish bounded aggregate counters (source, exporter instance, interface, capture point, rule version). It would not label metrics with an unrestricted IMSI, SNI, or flow key. The collector would be a separate privileged process, not the web backend, and it would not mount the Docker socket.

eBPF detection is not a PCRF decision, not an installed PCC rule, and not measured user traffic. No metric integration is done.
