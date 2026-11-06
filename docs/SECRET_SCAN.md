> Repository note: checked in from the Network Architect sanitized WIP package. This checkout did not run the lab, compile the PCRF patch, or re-verify the result below. lab5g-vm was not used.

# Secret scan result — WIP package v1

**Status: `CLEAN`**  
Scan time: 2026-11-06 20:22:35 +07 (Asia/Bangkok). Scope: entire tree including \`lab/patches/pcrf-admin-rar*\`, \`lab/config/examples/slicing-poc/\`, \`docs/research/sgnb/\`.

## Checks
- Known lab Ki/OPc values
- \`KEY=\`/\`OPC=\` hex assignments
- Raw milenage \`amf:'…'\`
- PEM private keys
- Corporate host/IP/user markers
- Unexpected 32+ hex (allowlist: public image Ids / git SHAs)

## Result
| Metric | Value |
|---|---|
| Forbidden findings | 0 |
| Keyword rg hits (benign expected) | 123 |
| Hex≥32 rg hits | 8 (public digests/SHAs counted separately: 8) |

Problems: `[]`

PCRF draft references \`PCRF_ADMIN_TOKEN\` env var by **name** only (no token value). Admin socket path is local unix — not a secret.
