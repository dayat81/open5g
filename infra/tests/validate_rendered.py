#!/usr/bin/env python3
"""Validate addresses, Open5GS schema basics and rendered Compose structure."""
from pathlib import Path
import ipaddress
import yaml
root = Path(__file__).resolve().parents[1]
base = root / 'rendered/open5gs_epc_cups'
for name in ('hss', 'pcrf', 'mme', 'sgwc', 'sgwu', 'smf', 'upf', 'slice-upf-slice-a', 'slice-upf-slice-b'):
    doc = yaml.safe_load((base / f'{name}.yaml').read_text())
    assert doc, name
core = yaml.safe_load((base / 'docker-compose.yml').read_text())
assert set(core['services']) == {'mongo', 'hss', 'pcrf', 'mme', 'sgwc', 'sgwu', 'smf', 'upf', 'upf-slice-a', 'upf-slice-b', 'server'}
for name, net in core['networks'].items():
    ipaddress.ip_network(net['ipam']['config'][0]['subnet'])
ran = yaml.safe_load((root / 'rendered/ran_srsran/docker-compose-ran.yml').read_text())
assert {'enb', 'ue'} == set(ran['services'])
for network in core['networks'].values():
    assert network['internal'] is True
assert str(root / 'lab_root') not in (base / 'docker-compose.yml').read_text()
print('PASS: 9 Open5GS configs + core Compose + RAN Compose; 2 slice UPFs; IP subnets and isolation.')
