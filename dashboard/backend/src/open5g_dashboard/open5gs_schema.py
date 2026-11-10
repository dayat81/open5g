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

import copy
from typing import Any

from open5g_dashboard.domain import ProfileError

INT32_MIN = -2147483648
INT32_MAX = 2147483647
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


def _default_slice(document: dict[str, Any]) -> dict[str, Any]:
    slices = document.get("slice")
    if not isinstance(slices, list):
        slices = []
        document["slice"] = slices
    for item in slices:
        if isinstance(item, dict) and item.get("default_indicator") is True:
            if not isinstance(item.get("session"), list):
                item["session"] = []
            return item
    if slices and isinstance(slices[0], dict):
        if not isinstance(slices[0].get("session"), list):
            slices[0]["session"] = []
        return slices[0]
    created = {"sst": 1, "default_indicator": True, "session": []}
    slices.append(created)
    return created


def _select_session(sessions: list[Any], apn: str) -> tuple[dict[str, Any] | None, str]:
    records = [item for item in sessions if isinstance(item, dict)]
    for session in records:
        if session.get("name") == apn:
            return session, "matched"
    if len(records) == 1:
        return records[0], "rename_only"
    if not records:
        return None, "create"
    return None, "add"


def _ip_rules(content: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    notes: list[str] = []
    rules = content.get("app_rules") or []
    if any(isinstance(rule, dict) and rule.get("enabled") is False for rule in rules):
        notes.append("disabled_rules_skipped")
    enabled = [rule for rule in rules if isinstance(rule, dict) and rule.get("enabled") is True]
    enabled.sort(key=lambda rule: int(rule.get("precedence") or 0))
    written: list[dict[str, Any]] = []
    qos = {
        "index": int(content["qci"]),
        "arp": encode_arp(content["arp"]),
        "mbr": _bitrate_pair(content, "mbr"),
        "gbr": _bitrate_pair(content, "gbr"),
    }
    omitted = False
    for rule in enabled:
        if rule.get("match_type") != "ip":
            omitted = True
            continue
        written.append(
            {
                "flow": [
                    {
                        "direction": FLOW_BIDIRECTIONAL,
                        "description": f"permit out ip from {rule['pattern']} to assigned",
                    }
                ],
                "qos": qos,
            }
        )
    if omitted:
        notes.append("hostname_sni_not_written")
    return written, notes


def apply_profile_to_document(existing: dict[str, Any] | None, imsi: str, content: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    """Return a subscriber document and stable note codes. Security keys are preserved, never created."""
    notes: list[str] = []
    if existing is None:
        document: dict[str, Any] = {
            "imsi": imsi,
            "schema_version": 1,
            "msisdn": [],
            "imeisv": [],
            "mme_host": [],
            "mme_realm": [],
            "purge_flag": [],
            "access_restriction_data": 32,
            "network_access_mode": 0,
            "subscriber_status": 0,
            "operator_determined_barring": 0,
            "subscribed_rau_tau_timer": 12,
            "slice": [],
        }
        notes.append("created_without_credentials")
    else:
        if existing.get("imsi") not in (None, imsi):
            raise ProfileError("imsi_mismatch", "Refusing to rewrite a subscriber document for a different IMSI")
        document = copy.deepcopy(existing)
        notes.append("updated_existing")
    document["imsi"] = imsi
    session_ambr = _bitrate_pair(content, "ambr")
    document["ambr"] = session_ambr
    notes.append("ue_ambr_matches_selected_session_ambr")
    slice_doc = _default_slice(document)
    sessions = slice_doc["session"]
    target, how = _select_session(sessions, str(content["apn"]))
    if how == "create":
        target = {"name": content["apn"], "type": 3}
        sessions.append(target)
        notes.append("session_created")
    elif how == "add":
        target = {"name": content["apn"], "type": 3}
        sessions.append(target)
        notes.append("session_added_alongside_existing")
        notes.append("other_sessions_preserved")
    elif how == "rename_only" and target is not None and target.get("name") != content["apn"]:
        notes.append("only_session_renamed")
    elif how == "matched" and len([item for item in sessions if isinstance(item, dict)]) > 1:
        notes.append("other_sessions_preserved")
    if target is None:
        raise ProfileError("session_not_selected", "No subscriber session could be selected")
    if "type" not in target:
        target["type"] = 3
    previous = target.get("pcc_rule")
    if isinstance(previous, list) and previous:
        notes.append("pcc_rules_replaced_on_selected_session")
    target["name"] = content["apn"]
    target["qos"] = {"index": int(content["qci"]), "arp": encode_arp(content["arp"])}
    target["ambr"] = session_ambr
    pcc_rules, rule_notes = _ip_rules(content)
    target["pcc_rule"] = pcc_rules
    notes.extend(rule_notes)
    if content.get("usage"):
        notes.append("usage_monitoring_not_written")
    notes.append("live_session_not_modified")
    return document, notes


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
        rules.append({"qci": _plain_int(rule_qos.get("index")), "flows": flows})
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
