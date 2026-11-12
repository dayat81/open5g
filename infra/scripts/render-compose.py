#!/usr/bin/env python3
"""Standalone Jinja rendering for offline review, using group_vars as inputs."""
from pathlib import Path
import yaml
from jinja2 import Environment, StrictUndefined
root = Path(__file__).resolve().parents[1]
context = {}
for file in (root / 'group_vars/all').glob('*.yml'):
    context.update(yaml.safe_load(file.read_text()) or {})
context.update(iac_dry_run=True, ran_srsran_profile='endc')
env = Environment(undefined=StrictUndefined, keep_trailing_newline=True)
for source in root.glob('roles/*/templates/*.j2'):
    if source.name in ('seed-subscriber.js.j2', 'cloud-user-data.yml.j2', 'lab-routes.sh.j2', 'dashboard.env.j2'):
        continue
    if source.name == 'fd.conf.j2':
        items = [{'identity': 'hss', 'peer': 'mme', 'peer_address': context['core']['mme_s6a']}]
    elif source.name == 'slice-upf.yaml.j2':
        items = context['slice_upfs']
    else:
        items = [{}]
    for item in items:
        context['item'] = item
        output = env.from_string(source.read_text()).render(**context)
        suffix = f'-{item.get("name", item.get("identity", ""))}' if item else ''
        stem = source.name
        for ending in ('.yml.j2', '.yaml.j2', '.xml.j2', '.conf.j2', '.env.j2', '.sh.j2'):
            if stem.endswith(ending):
                stem = stem[: -len(ending)]
                break
        ext = '.env' if source.name == 'ran.env.j2' else source.suffixes[-2]
        dest = root / 'rendered' / source.parent.parent.name / (stem + suffix + ext)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(output)
print('Templates rendered without secrets to rendered/.')
