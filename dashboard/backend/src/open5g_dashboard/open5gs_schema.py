"""Map a dashboard profile onto the Open5GS 2.8 subscriber document.

The integer enums follow upstream tag v2.8.0, which this tree does not vendor:

- bitrate ``unit`` is an exponent of 1000 (``lib/dbi/session.c`` multiplies
  ``value`` by 1000 once per unit). 0 bps, 1 kbps, 2 mbps, 3 gbps, 4 tbps.
  The same decoder accepts only BSON int32, so values are kept inside int32.
- ARP pre-emption uses the 5GC constants in ``lib/proto/types.h``:
  disabled = 1, enabled = 2. HSS and PCRF emit the EPC enabled value only
  when the stored integer is 2 (``src/hss/hss-s6a-path.c``,
  ``src/pcrf/pcrf-gx-path.c``).
- Flow direction 3 is bidirectional (``lib/proto/types.h``).

Nothing here opens a socket or writes a credential.
"""

from __future__ import annotations

import ipaddress
import re
from dataclasses import dataclass
from typing import Any

from open5g_dashboard.domain import ProfileError

# Verified against Open5GS tag v2.8.0 lib/proto/types.h and the ogs_assert
# call sites in lib/dbi/session.c and lib/dbi/subscription.c.
# OGS_MAX_NUM_OF_BEARER is 4 per session, including the default bearer.
MAX_PCC_RULES = 8
MAX_SESSIONS = 4
MAX_DEDICATED_BEARERS = 3
MAX_FLOWS_PER_RULE = 15
MAX_SLICES = 8
GBR_QCI = {1, 2, 3, 4}
STUDENT_QCI = {5, 6, 7, 8, 9}
STUDENT_MIN_ARP = 5
INT32_MIN = -2147483648
INT32_MAX = 2147483647
_DASHBOARD_FLOW = re.compile(r"^permit out ip from \S+ to assigned$")
UNIT_NAME_TO_CODE = {"bps": 0, "kbps": 1, "mbps": 2, "gbps": 3}
CODE_TO_NAME = {0: "bps", 1: "kbps", 2: "mbps", 3: "gbps", 4: "tbps"}
PREEMPTION_DISABLED = 1
PREEMPTION_ENABLED = 2
FLOW_BIDIRECTIONAL = 3
_SECRET_KEYS = {"k", "ki", "opc", "op", "security", "password", "password_hash", "token", "token_hash"}


def encode_bitrate(value: int, unit: str) -> dict[str, int]:
    if unit not in UNIT_NAME_TO_CODE:
        raise ProfileError("bitrate_unit_unsupported", "Bitrate unit is not one Open5GS stores")
    code = UNIT_NAME_TO_CODE[unit]
    amount = int(value)
    if amount < 0:
        raise ProfileError("bitrate_not_representable", "Bitrate cannot be negative")
    while amount > INT32_MAX and code < 4:
        if amount % 1000 != 0:
            raise ProfileError(
                "bitrate_not_representable",
                "Open5GS stores this bitrate as a 32-bit value plus a decimal unit",
            )
        amount //= 1000
        code += 1
    if amount > INT32_MAX:
        raise ProfileError("bitrate_not_representable", "Bitrate does not fit in an Open5GS int32 field")
    return {"value": amount, "unit": code}


def decode_bitrate(node: Any) -> dict[str, Any] | None:
    if not isinstance(node, dict):
        return None
    value = node.get("value")
    unit = node.get("unit")
    if isinstance(value, bool) or isinstance(unit, bool):
        return {"value": None, "unit": None, "unit_name": "unparsed", "bps": None}
    if not isinstance(value, int) or not isinstance(unit, int):
        return {"value": None, "unit": None, "unit_name": "unparsed", "bps": None}
    bps = None
    if 0 <= unit <= 4:
        bps = int(value) * (1000**int(unit))
    return {
        "value": int(value),
        "unit": int(unit),
        "unit_name": CODE_TO_NAME.get(int(unit), "unknown"),
        "bps": bps,
    }


def encode_arp(arp: dict[str, Any]) -> dict[str, int]:
    priority = int(arp["priority"])
    if not 1 <= priority <= 15:
        raise ProfileError("invalid_arp", "ARP priority must stay between 1 and 15")
    return {
        "priority_level": priority,
        "pre_emption_capability": PREEMPTION_ENABLED if arp.get("preemption_capability") == "may_preempt" else PREEMPTION_DISABLED,
        "pre_emption_vulnerability": PREEMPTION_ENABLED if arp.get("preemption_vulnerability") == "preemptable" else PREEMPTION_DISABLED,
    }


def decode_arp(arp: Any) -> dict[str, Any] | None:
    if not isinstance(arp, dict):
        return None
    capability = arp.get("pre_emption_capability")
    vulnerability = arp.get("pre_emption_vulnerability")
    priority = arp.get("priority_level")
    return {
        "priority": None if isinstance(priority, bool) or not isinstance(priority, int) else int(priority),
        "preemption_capability": "may_preempt" if capability == PREEMPTION_ENABLED else "not_preempt",
        "preemption_vulnerability": "preemptable" if vulnerability == PREEMPTION_ENABLED else "not_preemptable",
        "stored_pre_emption_capability": None if isinstance(capability, bool) or not isinstance(capability, int) else int(capability),
        "stored_pre_emption_vulnerability": None if isinstance(vulnerability, bool) or not isinstance(vulnerability, int) else int(vulnerability),
    }


def _bitrate_pair(content: dict[str, Any], prefix: str) -> dict[str, dict[str, int]]:
    downlink = content[f"{prefix}_dl"]
    uplink = content[f"{prefix}_ul"]
    return {
        "downlink": encode_bitrate(int(downlink["value"]), str(downlink["unit"])),
        "uplink": encode_bitrate(int(uplink["value"]), str(uplink["unit"])),
    }


@dataclass(frozen=True)
class SessionPatch:
    slice_index: int
    session_index: int | None
    session_name: str
    qos: dict[str, Any]
    ambr: dict[str, Any]
    pcc_rule: list[dict[str, Any]]
    new_session: dict[str, Any] | None
    expected_generation: int | None
    expected_session_count: int
    notes: list[str]


def _bps_of(node: dict[str, Any] | None) -> int:
    if not node:
        return 0
    if "bps" in node and isinstance(node["bps"], int):
        return int(node["bps"])
    encoded = encode_bitrate(int(node["value"]), str(node["unit"]))
    return int(encoded["value"]) * (1000 ** int(encoded["unit"]))


def editor_range_error(content: dict[str, Any]) -> None:
    """Reject QoS the editor must not store. Does not write a subscriber."""
    qci = content.get("qci")
    if isinstance(qci, bool) or not isinstance(qci, int) or qci not in STUDENT_QCI:
        raise ProfileError(
            "default_bearer_qci_forbidden",
            "Default bearer QCI must be non-GBR (5-9) for every role",
        )
    arp = content.get("arp") if isinstance(content.get("arp"), dict) else {}
    priority = arp.get("priority")
    if isinstance(priority, bool) or not isinstance(priority, int) or not 1 <= priority <= 15:
        raise ProfileError("invalid_arp", "ARP priority must stay between 1 and 15")
    for key in ("ambr_ul", "ambr_dl"):
        node = content.get(key)
        if not isinstance(node, dict):
            raise ProfileError("ambr_not_positive", "AMBR uplink and downlink must be greater than zero")
        unit = node.get("unit")
        if unit is not None and unit not in UNIT_NAME_TO_CODE:
            raise ProfileError("bitrate_unit_unsupported", "Bitrate unit is not one Open5GS stores")
        if _bps_of(node) <= 0:
            raise ProfileError("ambr_not_positive", "AMBR uplink and downlink must be greater than zero")


def enforce_role_qos(role: str, content: dict[str, Any]) -> None:
    """Session QoS is the default bearer. Open5GS default bearer QCI must be non-GBR."""
    editor_range_error(content)
    priority = int(content["arp"]["priority"])
    if role == "student" and priority < STUDENT_MIN_ARP:
        raise ProfileError(
            "role_qos_forbidden",
            "Students may store ARP priority 5 through 15",
        )
    if _bps_of(content.get("gbr_ul")) > 0 or _bps_of(content.get("gbr_dl")) > 0:
        raise ProfileError(
            "gbr_on_non_gbr_qci",
            "PCRF emits a GBR AVP whenever the stored GBR is non-zero. A non-GBR default bearer cannot carry GBR.",
        )


def _normalize_cidr(pattern: str) -> str:
    return str(ipaddress.ip_network(pattern, strict=False))


OWNER_FIELD = "open5g_owner"
OWNER_VALUE = "dashboard"


def _dashboard_rule(rule: dict[str, Any]) -> bool:
    return rule.get(OWNER_FIELD) == OWNER_VALUE


def _flows_for(content: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    notes: list[str] = []
    rules = content.get("app_rules") or []
    if any(isinstance(rule, dict) and rule.get("enabled") is False for rule in rules):
        notes.append("disabled_rules_skipped")
    enabled = [rule for rule in rules if isinstance(rule, dict) and rule.get("enabled") is True]
    enabled.sort(key=lambda rule: int(rule.get("precedence") or 0))
    flows: list[dict[str, Any]] = []
    omitted = False
    for rule in enabled:
        if rule.get("match_type") != "ip":
            omitted = True
            continue
        flows.append(
            {
                "direction": FLOW_BIDIRECTIONAL,
                "description": f"permit out ip from {_normalize_cidr(str(rule['pattern']))} to assigned",
            }
        )
    if omitted:
        notes.append("hostname_sni_not_written")
    if len(flows) > MAX_FLOWS_PER_RULE:
        raise ProfileError(
            "flow_limit",
            "Open5GS 2.8.0 allows at most 15 flows in one PCC rule",
            {"limit": MAX_FLOWS_PER_RULE, "flows": len(flows)},
        )
    return flows, notes


def _qos_block(content: dict[str, Any]) -> dict[str, Any]:
    qos: dict[str, Any] = {
        "index": int(content["qci"]),
        "arp": encode_arp(content["arp"]),
        "mbr": _bitrate_pair(content, "mbr"),
    }
    if int(content["qci"]) in GBR_QCI:
        qos["gbr"] = _bitrate_pair(content, "gbr")
    return qos


def _prefix_collision(names: list[str]) -> bool:
    folded = [name.lower() for name in names]
    for index, left in enumerate(folded):
        for right in folded[index + 1 :]:
            if left.startswith(right) or right.startswith(left):
                return True
    return False


def _target_slice(document: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    slices = document.get("slice") if isinstance(document.get("slice"), list) else []
    if len(slices) > MAX_SLICES:
        raise ProfileError("slice_limit", "Open5GS 2.8.0 asserts above 8 slices", {"limit": MAX_SLICES})
    chosen: tuple[int, dict[str, Any]] | None = None
    for index, item in enumerate(slices):
        if isinstance(item, dict) and item.get("default_indicator") is True:
            chosen = (index, item)
            break
    if chosen is None:
        for index, item in enumerate(slices):
            if isinstance(item, dict):
                chosen = (index, item)
                break
    if chosen is None:
        raise ProfileError("slice_missing", "Subscriber has no slice. This writer does not create one.")
    if not isinstance(chosen[1].get("session"), list):
        raise ProfileError("slice_missing", "Subscriber slice has no session array")
    return chosen


def _generation(document: dict[str, Any]) -> int | None:
    dashboard = document.get("open5g_dashboard")
    if not isinstance(dashboard, dict) or "generation" not in dashboard:
        return None
    value = dashboard.get("generation")
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return int(value)


def _merge_pcc(existing_rules: list[Any], content: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    notes: list[str] = []
    flows, flow_notes = _flows_for(content)
    notes.extend(flow_notes)
    kept: list[dict[str, Any]] = []
    owned_before = 0
    for rule in existing_rules:
        if not isinstance(rule, dict):
            continue
        if _dashboard_rule(rule):
            owned_before += 1
        else:
            kept.append(rule)
    qos = _qos_block(content) if flows else None
    merged = list(kept)
    if flows and qos is not None:
        merged.append({OWNER_FIELD: OWNER_VALUE, "flow": flows, "qos": qos})
        notes.append("dashboard_pcc_rule_replaced" if owned_before else "dashboard_pcc_rule_added")
        notes.append("flows_merged_into_one_pcc_rule")
    elif owned_before:
        notes.append("dashboard_pcc_rules_removed")
    elif not flows:
        notes.append("no_ip_pcc_rule")
    dedicated = sum(1 for rule in merged if isinstance(rule.get("flow"), list) and rule["flow"])
    if len(merged) > MAX_PCC_RULES:
        raise ProfileError(
            "pcc_rule_limit",
            "Open5GS 2.8.0 asserts when a session has more than 8 PCC rules",
            {"limit": MAX_PCC_RULES, "rules": len(merged)},
        )
    if dedicated > MAX_DEDICATED_BEARERS:
        raise ProfileError(
            "dedicated_bearer_limit",
            "Open5GS 2.8.0 allows 4 bearers per session, including the default bearer",
            {"limit": MAX_DEDICATED_BEARERS, "dedicated": dedicated},
        )
    notes.append("foreign_pcc_rules_kept")
    return merged, notes


def plan_session_update(
    existing: dict[str, Any] | None,
    content: dict[str, Any],
    *,
    role: str,
    apn_allowlist: tuple[str, ...] = (),
) -> SessionPatch:
    """Plan an allowlisted session update. Does not copy or return security."""
    if not isinstance(existing, dict):
        raise ProfileError(
            "subscriber_not_seeded",
            "Refusing to insert a subscriber. Seed Ki and OPc first, then update the session.",
        )
    enforce_role_qos(role, content)
    apn = str(content["apn"])
    if apn_allowlist and apn not in apn_allowlist:
        raise ProfileError("apn_not_allowlisted", "APN is not on the configured SMF/UPF allowlist", {"apn": apn})
    if not apn_allowlist:
        notes_allow = ["apn_allowlist_not_configured"]
    else:
        notes_allow = ["apn_allowlist_matched"]
    slice_index, slice_doc = _target_slice(existing)
    sessions = [item for item in slice_doc.get("session") or [] if isinstance(item, dict)]
    match_index = next((index for index, session in enumerate(sessions) if session.get("name") == apn), None)
    names = [str(session.get("name") or "") for session in sessions]
    if match_index is None:
        names = [*names, apn]
    if _prefix_collision([name for name in names if name]):
        raise ProfileError(
            "apn_prefix_collision",
            "Open5GS matches a stored APN as a prefix of the requested DNN",
        )
    if content.get("usage"):
        notes_allow.append("usage_monitoring_not_written")
    notes_allow.append("ue_ambr_not_written")
    notes_allow.append("security_not_written")
    notes_allow.append("live_session_not_modified")
    if match_index is None:
        if len(sessions) + 1 > MAX_SESSIONS:
            raise ProfileError(
                "session_limit",
                "Open5GS 2.8.0 asserts when a slice has more than 4 sessions",
                {"limit": MAX_SESSIONS, "sessions": len(sessions) + 1},
            )
        pcc_rule, rule_notes = _merge_pcc([], content)
        new_session = {
            "name": apn,
            "type": 3,
            "qos": {"index": int(content["qci"]), "arp": encode_arp(content["arp"])},
            "ambr": _bitrate_pair(content, "ambr"),
            "pcc_rule": pcc_rule,
        }
        return SessionPatch(
            slice_index,
            None,
            apn,
            new_session["qos"],
            new_session["ambr"],
            pcc_rule,
            new_session,
            _generation(existing),
            len(sessions),
            [*notes_allow, *rule_notes, "session_added_alongside_existing", "session_rename_not_performed"],
        )
    target = sessions[match_index]
    pcc_rule, rule_notes = _merge_pcc(list(target.get("pcc_rule") or []), content)
    qos = {"index": int(content["qci"]), "arp": encode_arp(content["arp"])}
    ambr = _bitrate_pair(content, "ambr")
    return SessionPatch(
        slice_index,
        match_index,
        apn,
        qos,
        ambr,
        pcc_rule,
        None,
        _generation(existing),
        len(sessions),
        [*notes_allow, *rule_notes, "session_matched", "session_rename_not_performed"],
    )


def drift_fields(content: dict[str, Any], sessions: list[dict[str, Any]]) -> list[str]:
    """Compare intent with the session of the same APN. UE-AMBR is not part of the write."""
    match = next((session for session in sessions if session.get("name") == content.get("apn")), None)
    if match is None:
        return ["apn"]
    drifted: list[str] = []
    if match.get("qci") != content.get("qci"):
        drifted.append("qci")
    arp = match.get("arp") if isinstance(match.get("arp"), dict) else {}
    wanted = content.get("arp") if isinstance(content.get("arp"), dict) else {}
    if arp.get("priority") != wanted.get("priority"):
        drifted.append("arp")
    for key in ("ambr_ul", "ambr_dl"):
        observed = match.get(key) if isinstance(match.get(key), dict) else {}
        desired = content.get(key) if isinstance(content.get(key), dict) else {}
        if observed.get("bps") != desired.get("bps"):
            drifted.append(key)
    observed_flows = []
    for rule in match.get("pcc_rules") or []:
        if not rule.get("owned"):
            continue
        for flow in rule.get("flows") or []:
            if isinstance(flow, dict) and flow.get("description"):
                observed_flows.append(flow["description"])
    desired_flows = []
    for rule in content.get("app_rules") or []:
        if isinstance(rule, dict) and rule.get("enabled") is True and rule.get("match_type") == "ip":
            desired_flows.append(f"permit out ip from {_normalize_cidr(str(rule['pattern']))} to assigned")
    if sorted(observed_flows) != sorted(desired_flows):
        drifted.append("pcc_rule")
    return drifted


def credentials_present(document: dict[str, Any] | None) -> bool:
    if not isinstance(document, dict):
        return False
    security = document.get("security")
    if not isinstance(security, dict):
        return False
    key = security.get("k")
    opc = security.get("opc")
    return isinstance(key, str) and bool(key) and isinstance(opc, str) and bool(opc)


def _plain_int(value: Any) -> Any:
    if isinstance(value, bool) or not isinstance(value, int):
        return value
    return int(value)


def _session_view(session: dict[str, Any]) -> dict[str, Any]:
    qos = session.get("qos") if isinstance(session.get("qos"), dict) else {}
    ambr = session.get("ambr") if isinstance(session.get("ambr"), dict) else {}
    rules = []
    for rule in session.get("pcc_rule") or []:
        if not isinstance(rule, dict):
            continue
        rule_qos = rule.get("qos") if isinstance(rule.get("qos"), dict) else {}
        flows = []
        for flow in rule.get("flow") or []:
            if isinstance(flow, dict):
                flows.append({"direction": _plain_int(flow.get("direction")), "description": flow.get("description")})
        rules.append(
            {
                "qci": _plain_int(rule_qos.get("index")),
                "flows": flows,
                "owned": rule.get(OWNER_FIELD) == OWNER_VALUE,
            }
        )
    return {
        "name": session.get("name"),
        "type": _plain_int(session.get("type")),
        "qci": _plain_int(qos.get("index")),
        "arp": decode_arp(qos.get("arp")),
        "ambr_ul": decode_bitrate(ambr.get("uplink")),
        "ambr_dl": decode_bitrate(ambr.get("downlink")),
        "pcc_rules": rules,
    }


def project_subscriber(document: dict[str, Any], imsi: str) -> dict[str, Any]:
    """Public subscriber view. Credential fields are not copied out of the document."""
    sessions: list[dict[str, Any]] = []
    for slice_doc in document.get("slice") or []:
        if not isinstance(slice_doc, dict):
            continue
        for session in slice_doc.get("session") or []:
            if isinstance(session, dict):
                sessions.append(_session_view(session))
    ambr = document.get("ambr") if isinstance(document.get("ambr"), dict) else {}
    present = credentials_present(document)
    projected = {
        "status": "present",
        "found": True,
        "configured": True,
        "imsi": imsi,
        "credentials_present": present,
        "attach_ready": present,
        "security_returned": False,
        "ue_ambr_ul": decode_bitrate(ambr.get("uplink")),
        "ue_ambr_dl": decode_bitrate(ambr.get("downlink")),
        "sessions": sessions,
        "session_count": len(sessions),
        "live_gx_rar": False,
    }
    return drop_secrets(projected)


def drop_secrets(payload: Any) -> Any:
    if isinstance(payload, dict):
        return {key: drop_secrets(value) for key, value in payload.items() if str(key).lower() not in _SECRET_KEYS}
    if isinstance(payload, list):
        return [drop_secrets(item) for item in payload]
    return payload
