#!/bin/bash
# poc-phase2: uji mglt.zeek offline dengan pcap sintetis (VLAN102 GTP-U + VLAN109 SGi + echo), container sekali pakai --network none.
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
push_vm zeek/mglt.zeek zeek/run-local.zeek zeek/test-mglt.pcap
$V "sudo -n bash -s" <<VEOF
cd $VM_P2/zeek && rm -rf selftest && mkdir selftest && cp mglt.zeek run-local.zeek test-mglt.pcap selftest/
docker run --rm --network none -v $VM_P2/zeek/selftest:/z -w /z --entrypoint zeek $ZIMG -C -r test-mglt.pcap ./run-local.zeek 2>&1 | head -30
ls selftest; cat selftest/mglt*.log; echo; grep -h 10.45.0.39 selftest/conn*.log | head -3
VEOF
