> Repository note: checked in from the Network Architect sanitized WIP package. This checkout did not run the lab, compile the PCRF patch, or re-verify the result below. lab5g-vm was not used.

# Capability table — RAR / PCC / PFCP (Open5GS v2.8.0)

Extracted from `docs/plan-poc-slicing-core.md`. All `file:line` references are against upstream Open5GS tag **`v2.8.0`**  
(`https://github.com/open5gs/open5gs/blob/v2.8.0/<path>#L<line>`).

Snapshot: 2026-11-06 20:17:38 +07 (Asia/Bangkok).

## Stock capability matrix

| Capability | Status | Source evidence |
|---|---|---|
| Gx CCR-I/CCA-I; Charging-Rule Install/Remove; Flow-Description | **FACT: present** | `src/pcrf/pcrf-gx-path.c:614-652,1669-1716`; `src/smf/gx-path.c:1034-1102` |
| IP 5-tuple SDF in UPF; URR volume/time + threshold-report | **FACT: present** | `lib/pfcp/handler.c:507-564`; `src/upf/n4-handler.c:25-41,339-352`; `src/upf/context.c:709-720,771-890` |
| Native UPF hostname/SNI; PDI Application-ID / PFD | **FACT: absent** | TLV decode in `lib/pfcp/message.h:1278,1287`; `src/upf/pfcp-sm.c:118-283` does not dispatch PFD |
| SGW-U URR | **FACT: absent** | `src/sgwu/sxa-handler.c`, `sxa-build.c` — no URR path |
| UPF URR Session Report → SMF | **FACT: present**, routed to **Gy**, not Gx usage | `src/smf/n4-handler.c:1728-1762` |
| Gx Usage-Monitoring AVP runtime + CCR-U `USAGE_REPORT` | **FACT: absent** (dictionary only) | `lib/diameter/gx/dict.c:172,240,270`; `src/smf/gsm-sm.c:108-110,148-150` INITIAL/TERMINATION only |
| PCC loaded from Mongo on CCR-I/U | **FACT: DB re-read** | `src/pcrf/pcrf-gx-path.c:614-628`; `src/pcrf/pcrf-context.c:388-420` |

## Gx RAR live-apply

| Topic | Status | Source evidence |
|---|---|---|
| Mongo change auto-triggers RAR | **FACT: no** | `pcrf_gx_send_rar()` at `src/pcrf/pcrf-gx-path.c:1033-1055`; call sites only Rx AAR/STR `src/pcrf/pcrf-rx-path.c:450-452,946-952` |
| HSS Mongo change-stream → IDR (not Gx) | **FACT: yes (S6a)** | `lib/dbi/ogs-mongoc.c:200-203`; `src/hss/hss-context.c:1411-1429,1509-1522,1535-1537` |
| SMF RAR callback; Charging-Rule Install/Remove | **FACT: yes** | `src/smf/gx-path.c:1493-1519,1301-1408`; `src/smf/gx-handler.c:259-270` |
| RAR → PFCP mod → Create/Update/Delete Bearer | **FACT: yes** | `src/smf/binding.c:140-223,335-344`; `src/smf/n4-handler.c:1340-1355,1357-1384,1434,1455`; SGW-C `src/sgwc/sgwc-sm.c:193-204`; `src/sgwc/s5c-handler.c:625,750,861` |
| RAA 2001 means policy active | **FACT: no** (RAA before bearer binding runs) | `src/smf/gx-path.c:1411-1456` vs `src/smf/gx-handler.c:259-270` |
| Top-level APN-AMBR / QoS-Information on RAR | **FACT: not accepted** | `src/smf/gx-path.c:1404-1406` |
| MBR/GBR update on existing dedicated bearer | **FACT: compared** → PFCP+Update Bearer | `src/smf/binding.c:228-241,352-360` |
| QCI/ARP update on existing dedicated bearer | **Do not assume** (compare is MBR/GBR only) | `src/smf/binding.c:228-241` |
| Default bearer QCI/ARP via RAR | **FACT: no** — initial CCA only | `src/smf/gx-handler.c:64-106` |

## Recommended RAR trigger (plan)

| Option | Verdict |
|---|---|
| (1) Rx AF shim | Spike only; QCI limited to 1/2/5 (`pcrf-gx-path.c:1123-1205`) |
| (2) PCRF admin-trigger / change-stream patch | **Recommended** — new `pcrf_gx_send_pcc_rar()` sharing encoder `pcrf-gx-path.c:1669-1800` |
| (3) External Gx RAR injector | Emergency test tool only |

## Profile-change matrix (live vs re-attach)

| Change | Live via RAR? | Notes |
|---|---|---|
| PCC Install (5-tuple, QCI/ARP/MBR) | Yes (after trigger) | E2E UNKNOWN |
| PCC Remove | Yes | E2E UNKNOWN |
| MBR/GBR on existing dedicated | Yes | |
| QCI/ARP on existing dedicated | Do not assume | fallback remove+install/reconnect |
| Add flow 5-tuple | Yes | individual flow remove needs test/patch |
| APN-AMBR | No (stock RAR) | PDN reconnect |
| APN / slice / IP pool / static UE IP | No | PDN reconnect / re-attach |
| Default bearer QCI/ARP | No | re-attach / PDN reconnect |
| UE-AMBR (HSS) | Not Gx; S6a IDR if change-stream on | |
| Usage-monitoring key/threshold | No stock | needs PCRF+SMF+URR patch |
| eBPF classifier map | Live out-of-band | not Diameter |

## PoC implication

- IP/PCC path = **GO** (stock).
- Hostname/SNI = **GO only via eBPF** (not built in this snapshot).
- Native Gx per-app usage = **NO-GO stock**.
- Live IMSI profile apply = requires PCRF patch (not yet in `lab/patches/`).
