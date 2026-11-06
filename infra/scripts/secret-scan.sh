#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Generic detectors only. Do not embed hostnames, addresses, or filesystem paths
# from a real environment; this script is excluded from its own scan.
if rg -n --hidden --glob '!*.md' --glob '!rendered/**' --glob '!.venv/**' --glob '!.collections/**' --glob '!scripts/secret-scan.sh' --glob '!MANIFEST.txt' '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|(password|passwd)[=][[:space:]]*[^<[{:space:]]|(KEY|OPC|ki|opc):[[:space:]]*[0-9a-fA-F]{32}\b|/Users/[A-Za-z0-9._-]+|[A-Za-z]:\\Users\\|D:\\open5g)' .; then
  echo 'FAIL: possible secret material found' >&2
  exit 1
fi
echo 'PASS: no private-key blocks, credential assignments, literal Ki/OPc values, or personal path prefixes.'
