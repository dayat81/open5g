#!/usr/bin/env python3
"""Validate rendered Compose resources against the official Compose JSON schema."""
import json
from pathlib import Path
import urllib.request
import yaml
from jsonschema import Draft7Validator
root = Path(__file__).resolve().parents[1]
cache = root / 'tests/compose-spec.json'
if not cache.exists():
    with urllib.request.urlopen('https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json', timeout=60) as response:
        cache.write_bytes(response.read())
schema = json.loads(cache.read_text())
for doc in ('open5gs_epc_cups/docker-compose.yml', 'ran_srsran/docker-compose-ran.yml'):
    data = yaml.safe_load((root / 'rendered' / doc).read_text())
    errors = sorted(Draft7Validator(schema).iter_errors(data), key=lambda item: list(item.path))
    for error in errors:
        print(f'{doc}: {list(error.path)}: {error.message}')
    assert not errors, f'{len(errors)} Compose schema error(s) in {doc}'
    print(f'PASS: Compose schema: {doc}')
