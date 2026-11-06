# IN PROGRESS — WIP v1 2026-11-06 20:21:58 +07 (Asia/Bangkok)
# Feasibility: NSA with 5G Core (NGEN-DC Opt7 / NE-DC Opt4) + slicing notes
**Research only — no lab access or changes.**  
**As of:** 2026-11-06 (Asia/Bangkok).  
**Goal context:** Hidayat wants “NSA with 5G core” in a virtual lab, plus per-application network slicing experiments over 5GC (AMF/SMF/UPF).

Terminology (3GPP TS 37.340 / industry option labels):
- **EN-DC (Option 3/3a/3x):** eNB MN + en-gNB SN, **EPC** (X2). Not “NSA with 5GC”.
- **NGEN-DC (Option 7/7a/7x):** **ng-eNB MN + gNB SN**, **5GC**, Xn.
- **NE-DC (Option 4/4a):** **gNB MN + ng-eNB SN**, **5GC**, Xn.
- **Option 5:** ng-eNB alone → 5GC (no NR secondary). Prerequisite building block for Opt7.
- **SA (Option 2):** gNB → 5GC. Target for slicing PoC.

---

## 1) Support matrix (facts)

### Open-source RAN / core

| Component | Capability | Class | Evidence |
|---|---|---|---|
| **OAI gNB** | SA; EN-DC (NSA via X2 with eNB); **NR-DC** documented | EN-DC: **partial** (FEATURE_SET: “unstable, only one UE”); NGEN-DC/NE-DC: **unsupported** | [FEATURE_SET.md](https://raw.githubusercontent.com/OPENAIRINTERFACE/openairinterface5g/develop/doc/FEATURE_SET.md): NSA = EN-DC only; X2 SgNB Addition; XnAP “initial” (Setup/paging/retrieve UE context) — **no** Xn SN Addition for NGEN-DC/NE-DC; no ng-eNB |
| **OAI LTE eNB** | EN-DC with OAI gNB | **partial** | Same FEATURE_SET eNB X2AP EN-DC section |
| **OAI ng-eNB (E-UTRA→5GC / Opt5)** | — | **unsupported** | FEATURE_SET: eNB uses **S1AP**, not NGAP; no ng-eNB feature |
| **OAI nrUE** | SA; **not** NSA EN-DC | SA: **supported**; EN-DC/NGEN-DC/NE-DC: **unsupported** | FEATURE_SET: NSA listed for gNB only; nrUE = SA NAS/RRC |
| **srsRAN Project (gNB)** | SA; **no** EN-DC/NGEN-DC/NE-DC/ng-eNB on roadmap page | Opt7/4: **unsupported** | [Features & Roadmap](https://docs.srsran.com/projects/project/en/latest/general/source/2_features_and_roadmap.html): SA features + CU-DU; slicing listed; no MR-DC variants |
| **srsRAN 4G (eNB+embedded NR)** | EN-DC prototype | EN-DC: **partial**; Opt7/4: **unsupported** | Community reports unstable / LTE-only traffic ([#1378](https://github.com/srsran/srsRAN_4G/issues/1378)); no ng-eNB→5GC |
| **Open5GS AMF** | NGSetup accepts **Global gNB ID only** | ng-eNB NGSetup: **unsupported** | Source: `src/amf/ngap-handler.c` — if `GlobalRANNodeID` is not `globalGNB_ID`, rejects with semantic error; HO path also “Not implemented” for non-gNB IDs |
| **Open5GS** | EPC+5GC dual-mode; SMF/UPF shared | SA / EPC NSA 3x path: **supported** as architecture; Opt7/4: blocked by missing ng-eNB + AMF GlobalNgENB | Docs + prior lab: Open5GS 2.8.0 |
| **free5GC** | **NR-DC** (gNB–gNB) SMF/UPF dual-tunnel | NR-DC: **partial** (core-side); NGEN-DC/NE-DC: **unsupported** | [free5GC NR-DC](https://free5gc.org/doc/NR-DC/nrdc/): “RAN and UE … without real implementation” |
| **Magma** | 5G SA | Opt7/4: **unsupported** / **unknown** beyond SA | Magma 5G SA docs: gNB+CPE FWA focus |
| **OAI CN5G** | 5GC SA | Opt7/4: **unsupported** (needs ng-eNB RAN) | [openairinterface.org/core-network](https://openairinterface.org/core-network/) |
| **Academic (POWDER, Colosseum, 5GENESIS, OpenAirX)** | OAI/srs SA & some EN-DC experiments | Opt7/4 end-to-end: **unknown** (no clear public Opt7 report found) | POWDER 5G pages; no NGEN-DC claim located |

### Commercial / lab products

| Product | Capability | Class | Virtual RF / sim UE | Notes |
|---|---|---|---|---|
| **Amarisoft Callbox / LTEENB** | Explicit **ng-eNodeB**; NGAP; XnAP “between gNodeBs and **ng-eNodeBs**”; EN-DC; **NR-DC**; Option 5 building blocks (`plmn_list_5gc`, `amf_list`) | Opt5: **supported**; EN-DC/NR-DC: **supported**; **NGEN-DC/NE-DC full Opt7/4: unknown** (building blocks present; **no** explicit “NGEN-DC/NE-DC/Option 7/4” feature bullet in public docs reviewed) | Channel sim; **UE Simbox** (software UE) | [lteenb.doc](https://tech-academy.amarisoft.com/lteenb.doc), [device-products](https://amarisoft.com/test-and-measurement/device-testing/device-products), OutOfBox NSA = **Option 3.x only** |
| **Amarisoft LTEMME/5GC** | “gNodeBs, **ng-eNBs** or N3IWFs” | Opt5 CN: **supported** | N/A | [ltemme.doc](https://tech-academy.amarisoft.com/ltemme.doc) |
| **Amarisoft UE Simbox** | SA; EN-DC NSA; “connecting to 5GC through **ng-eNB**”; URSP via Manage UE Policy (remote API); multi-slice tests | Opt5 UE: **supported**; EN-DC: **supported**; Opt7/4 DC: **unknown** | Yes (sim + SDR) | [lteue.doc](https://tech-academy.amarisoft.com/lteue.doc), [NR_SA_NetworkSlice](https://tech-academy.amarisoft.com/NR_SA_NetworkSlice.html) |
| **Keysight / Spirent / R&S / Viavi TM500** | General 5G SA/NSA / O-RAN Option 7-2 **fronthaul** (≠ 3GPP Opt7 NGEN-DC) | Opt7/4 NGEN-DC/NE-DC: **unknown** from public pages checked | Emulators exist; mode-specific claims not verified | Do not confuse O-RAN Split Option 7-2 with NGEN-DC Opt7 |
| **Ericsson / Nokia / Mavenir** | Vendors historically discouraged Opt4/5/7 (Ericsson 2018); commercial Opt7 rare | Commercial Opt7: **unknown** / industry-disfavored | N/A | [Ericsson ETR](https://www.ericsson.com/en/reports-and-papers/ericsson-technology-review/articles/simplifying-the-5g-ecosystem-by-reducing-architecture-options); GSMA 2019 asked vendors for Opt4/5/7 ([PDF](https://www.gsma.com/solutions-and-impact/technologies/networks/wp-content/uploads/2019/05/20190515-GSMA-Operator-Requirements-for-5G-Core-Connectivity-Options.pdf)) |

### UE / chipset

| UE | Opt7 NGEN-DC | Opt4 NE-DC | Notes |
|---|---|---|---|
| OAI nrUE | **unsupported** | **unsupported** | SA only |
| srsUE | **unsupported** | **unsupported** | SA; optional EN-DC via srsRAN 4G stack (partial) |
| UERANSIM | **unsupported** (no LTE radio) | **unsupported** | SA gNB simulator only |
| Amarisoft UE Simbox | **unknown** for DC Opt7/4 | **unknown** | Explicit Opt5 (ng-eNB→5GC) + EN-DC; no public Opt7 DC tutorial found |
| Commercial modems (Qualcomm/MediaTek public claims) | **unknown** / rarely marketed | **unknown** | Public showcases emphasize **EN-DC** and **NR-DC**, not Opt4/7 |
| Industry deployment | Opt4/7 largely avoided | same | Ericsson: avoid 4/5/7; focus Opt3 then Opt2 |

---

## 2) Go / no-go gates (proposal)

Use only if Hidayat insists on true Opt7 (LTE master + NR secondary **on 5GC**). Each gate is read-only or isolated PoC — **not** on live `lab5g-vm` without approval.

| Gate | Pass criteria | Likely stack | Fallback if fail |
|---|---|---|---|
| **Gate 0 (recommended first)** | SA 5GC slicing PoC: ≥2 S-NSSAI, 2 PDU sessions, SMF/UPF selected per slice, app traffic on distinct N6 (or host policy routing) | Open5GS 5GC + srsRAN Project or OAI gNB + UERANSIM/srsUE/OAI nrUE | Still valuable for SMF/UPF/dashboard; keep Opt7 as research track |
| **Gate 1** | AMF accepts **NGSetup** with **Global ng-eNB ID** (not only Global gNB ID) | Amarisoft ng-eNB → Open5GS (expect fail today) or Amarisoft 5GC | Patch Open5GS AMF **or** use Amarisoft 5GC; else stop Opt7 on Open5GS |
| **Gate 2** | ng-eNB ↔ gNB **Xn Setup** + **SN Addition** (NGEN-DC) or reverse (NE-DC); UE gets SCG | Amarisoft Callbox (only candidate with both roles) | If Amarisoft also cannot complete Xn SN Addition for NGEN-DC → **no-go** for Opt7 in this lab class |
| **Gate 3** | UE with NGEN-DC (or NE-DC) **split bearer**; user plane through **UPF** with correct S-NSSAI | Commercial UE or Amarisoft UEsim if Opt7 supported | Fall back to SA + slicing (Gate 0) or EN-DC Opt3x on EPC (no S-NSSAI) |
| **Gate 4** | ≥N concurrent UEs stable (define N, e.g. 4–8 lab users) | Same | Reduce concurrency; isolate instances |
| **Gate 5** | Virtual RF (ZMQ/rfsim/channel sim) **without** SDR for teaching multi-user | Prefer ZMQ/rfsim stacks | Accept SDR Callbox cost; or SA-only virtual |

**Proposed go/no-go:** After Gate 0 success, attempt Gate 1–2 only with explicit budget for Amarisoft (or equivalent). If Gate 1 fails on Open5GS and Gate 2 is unknown on Amarisoft without vendor confirmation → **no-go for OSS Opt7**; keep hybrid “EN-DC 3x + SA 5GC side-by-side” for teaching NSA *and* 5GC.

---

## 3) Slicing (Hidayat’s per-app / per-slice experiments)

### 3.1 Facts: slicing vs architecture

- **S-NSSAI network slicing is a 5GS feature** (TS 23.501 §5.15; TS 38.300 §16.3): RAN part + CN part; traffic for different slices → **different PDU sessions**.
- **NGEN-DC / NE-DC** (if ever available) sit on **5GC**, so slicing *can* apply to the NG-RAN/5GC path in principle — but **no verified OSS Opt7/4 stack** exists to exercise it.
- **EN-DC Option 3x uses EPC**: there is **no native S-NSSAI slicing** on the EPC control path. EPC may map APN↔S-NSSAI only for **5GS↔EPS interworking** via SMF+PGW-C/PCO (TS 23.501 §5.15.7) — that is **not** EN-DC NSA slicing.

### 3.2 Open5GS 2.8 slicing (facts)

- **NSSF** present since v2.2; **SMF selection** by S-NSSAI / DNN / TAI via SmfInfo registered to NRF ([smf.yaml.in](https://github.com/open5gs/open5gs/blob/main/configs/open5gs/smf.yaml.in); [release v2.2.0](https://open5gs.org/open5gs/release/2021/03/08/release-v2.2.0.html)).
- Pattern: multiple S-NSSAI (SST + optional SD); **one SMF (and UPF) per slice** (or shared with SmfInfo filters); DNN per slice; AMF discovers SMF via NRF (optionally after NSSF NSI).
- Subscriber DB must list allowed S-NSSAI(s) per UE.

### 3.3 Open5GS PCF → URSP delivery

- Open5GS PCF implements **Npcf_AMPolicyControl** and **Npcf_SMPolicyControl** (session PCC) — see `src/pcf/npcf-handler.c`.
- **Npcf_UEPolicyControl / MANAGE UE POLICY COMMAND (URSP)** end-to-end delivery: **unsupported** in stock Open5GS based on public source layout and absence of URSP rule provisioning docs; third-party cores (e.g. ClaudIA) add URSP explicitly and patch UERANSIM.
- Classification: Open5GS PCF URSP = **unsupported** (not merely “unknown”).

### 3.4 gNB multi S-NSSAI in NGSetup

| gNB | Multi S-NSSAI in Supported TA / NGSetup | Class |
|---|---|---|
| **srsRAN Project** | `cell_cfg.slicing[]` with sst/sd (+ PRB ratios); advertised to AMF | **supported** ([config ref](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html); [discussion #1107](https://github.com/srsran/srsRAN_Project/discussions/1107)) |
| **OAI gNB** | `plmn_list.snssaiList` multiple `{sst, sd}` | **supported** ([RUNMODEM](https://github.com/OPENAIRINTERFACE/openairinterface5g/blob/develop/doc/RUNMODEM.md); oai-cn5g slicing tutorial) |

### 3.5 Software UE & Android: URSP / multi-PDU / Requested NSSAI

Distinguish clearly:

**(A) Native 3GPP per-app slicing (URSP-driven)**  
PCF (or preconfigured) URSP → UE OS/modem matches app/traffic descriptor → selects S-NSSAI+DNN → establishes/reuses PDU session → OS routes that app onto that PDU.  
**(B) Traffic-steering emulation**  
Config/API creates multiple PDU sessions (possibly different S-NSSAI); host binds apps to TUNs via policy routing/`ip rule`/`NetworkNamespace`. **Routing apps via a single TUN does not prove (A).**

| Client | Receives URSP from PCF? | Applies URSP? | Multiple concurrent PDU + different S-NSSAI | Requested NSSAI / slice select | Class for (A) vs (B) |
|---|---|---|---|---|---|
| **UERANSIM (stock)** | **No** (logs unhandled UE policy container; ClaudIA docs) | **No** | **Yes** — `sessions[]` each with `slice: {sst, sd}` ([wiki Config](https://github.com/aligungr/UERANSIM/wiki/Configuration); [discussion #286](https://github.com/aligungr/UERANSIM/discussions/286)); one TUN per session | **Yes** — `configured-nssai` / `default-nssai` + per-session slice | **(B) supported**; **(A) unsupported** unless patched |
| **UERANSIM (ClaudIA patches)** | **Yes** (MANAGE UE POLICY) | **Partial/Yes** in patch (`ursp-match` / `ursp-establish`) | Yes | Yes | **(A) partial** on non-stock fork |
| **OAI nrUE** | **No** evidence of UPDP/URSP | **No** | **Yes** — FEATURE_SET: multiple PDU sessions via `uicc0.pdu_sessions` | **Partial** — SA registration with NSSAI from config; OAI CN slicing tutorial notes some RAN sims limit multi-slice UE | **(B) partial/supported**; **(A) unsupported** |
| **srsUE** | **No** | **No** | **Unknown / likely limited** — config `[slicing] nssai-sst/sd` for one requested slice; community: single PDU per modem often | **Yes** — single configured S-NSSAI | **(B) partial** (one slice); **(A) unsupported** |
| **Amarisoft UE Simbox** | **Yes** (network can push Manage UE Policy / `ursp_rules` remote API) | **Yes** (intended; Test 5 documents NAS) | **Yes** — multi-slice + `pdn_connect` with snssai | **Yes** — Requested/Allowed NSSAI tests | **(A) and (B) supported** (commercial) |
| **Android 12+ (AOSP telephony)** | Framework expects modem to hold/apply URSP; carrier provisions rules | **Yes on device with capable modem** (`setupDataCall_1_6` + TrafficDescriptor) | Yes (enterprise / capability slices → separate data calls) | Via modem + Allowed NSSAI | **(A) supported in AOSP design** — needs **real 5G SA modem**, not emulator RF |
| **Android emulator / redroid** | **No** real 5G modem URSP path | **No** | N/A over cellular | N/A | **(A) unsupported**; **(B)** only if traffic is NATed into a software UE TUN |

Sources: [AOSP 5G slicing](https://source.android.com/docs/core/connect/5g-slicing); [TrafficDescriptor](https://developer.android.com/reference/android/telephony/data/TrafficDescriptor); [UrspRule](https://developer.android.com/reference/android/telephony/data/UrspRule); Amarisoft NR SA Network Slice Test 5; UERANSIM wiki; OAI FEATURE_SET; ClaudIA UERANSIM URSP docs.

### 3.6 Evidence required (proposal — do not claim without this)

**For (B) multi-PDU slice demo (minimum for SMF/UPF lab):**
1. NAS Registration: Requested NSSAI + Allowed NSSAI (≥2 S-NSSAI).
2. Two PDU Session Establishment Accepts with **different S-NSSAI** (and ideally different DNN).
3. NGAP/N11/N4: AMF→SMF selection / SMF→UPF per S-NSSAI (Open5GS logs or NRF discovery).
4. Two UE TUN IPs; `tcpdump` on **different N3 TEIDs / N6 interfaces** showing app A vs app B.
5. Optional: per-slice UPF counters / separate UPF containers.

**For (A) native URSP per-app slicing (strict):**
1. PCF→AMF→UE: **DL NAS Transport, payload container type UE policy**, **MANAGE UE POLICY COMMAND** with URSP TLVs (TS 24.501 Annex D / TS 24.526).
2. UE **MANAGE UE POLICY COMPLETE**.
3. App start → UE establishes/selects PDU with RSD’s S-NSSAI/DNN **without** manual TUN binding.
4. Same user-plane isolation evidence as (B).
5. On Android: modem `setupDataCall` with TrafficDescriptor; work-profile or capability routing — **not** emulator-only.

**Explicit non-proof:** “App works through `uesimtun0`” or “ping via one PDU” ≠ per-app slicing.

---

## 4) Recommendation (proposal)

**Realistic path now (Gate 0):**  
Build **SA 5GC slicing PoC** on a **dev** VM (e.g. `lab5g-dev`), not necessarily live lab5g-vm:
- Open5GS 5GC (AMF, NSSF, NRF, multiple SMF/UPF, UDM) + srsRAN Project **or** OAI gNB (multi S-NSSAI) + **UERANSIM** (easiest multi-PDU + per-session S-NSSAI) or OAI nrUE.
- Prove **(B)** first: two slices, two PDU sessions, host policy routing per app → separate N6.
- Dashboard: status/log per IMSI and per S-NSSAI; no raw Docker socket.

**Keep Opt7/4 as a feasibility track only:**  
OSS = **no-go today**. Commercial = Amarisoft is the only stack with documented **ng-eNB + gNB + XnAP + 5GC** building blocks; still need **vendor confirmation** that NGEN-DC/NE-DC SN Addition is supported (public docs reviewed do **not** claim Opt7/4 by name). Budget and license required; virtual multi-user teaching still hard.

**Do not rename “EN-DC 3x + SA side-by-side” as “NSA with 5GC”.** That hybrid remains the honest teaching architecture for NSA *and* 5GC/SMF/UPF/slicing, matching Hidayat’s earlier chat choice for the shared lab, while Gate 0 delivers the slicing experiments he needs.

---

## 5) Facts vs proposals (summary)

**Facts:** No OSS stack officially supports Opt7/4; Open5GS AMF rejects Global ng-eNB ID; OAI/srsRAN document EN-DC and/or SA/NR-DC only; Amarisoft documents ng-eNB, EN-DC, NR-DC, Opt5, URSP on UEsim; slicing is 5GC; EN-DC/EPC has no S-NSSAI; Open5GS can do multi-SMF/UPF by S-NSSAI; stock UEs lack URSP except Amarisoft (and Android+real modem); Android emulator cannot do (A).

**Proposals:** Gate 0 SA slicing PoC; Gates 1–5 for Opt7; prefer (B) then optionally commercial (A); hybrid EN-DC+SA for shared lab naming honesty; Amarisoft PoC only after license + written Opt7 confirmation.
