"""Policy rules that do not talk to a core, a kernel, or a lab.

The hi-fi mock is not a capability statement. In particular, a sample chip
that says a Gx RAR operation is supported is not adopted here.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import re
from dataclasses import dataclass
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError

Role = Literal["student", "instructor", "admin"]
SECRET_KEYS = {
    "ki",
    "opc",
    "op",
    "k",
    "key",
    "password",
    "password_hash",
    "secret",
    "session_secret",
    "csrf_token",
    "token_hash",
}
CLIENT_SCOPE_KEYS = {"owner_user_id", "group_id", "imsi", "owner", "group"}
UNIT_TO_BPS = {"bps": 1, "kbps": 1_000, "mbps": 1_000_000, "gbps": 1_000_000_000}
HOSTNAME_RE = re.compile(
    r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?:\.(?!-)[A-Za-z0-9-]{1,63})+$"
)
APP_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
APN_RE = re.compile(r"^[a-z0-9][a-z0-9.-]{0,62}$")
FORBIDDEN_METRIC_LABELS = {"imsi", "sni", "hostname", "flow", "ue_ip", "app_pattern"}
ALLOWED_METRIC_LABELS = {
    "source",
    "exporter_instance",
    "interface",
    "capture_point",
    "rule_version",
    "data_origin",
}
TARGETS = ("subscriber_db", "pcrf", "ebpf", "session")
REATTACH_NOTICE = (
    "Re-attach memutus sesi UE pada IMSI ini. "
    "Scaffold ini tidak menjalankan re-attach dan tidak me-restart core."
)


class ProfileError(Exception):
    def __init__(self, code: str, message: str, details: dict[str, Any] | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}


class BitrateModel(BaseModel):
    model_config = ConfigDict(extra="forbid")
    value: int = Field(ge=0, le=10**15)
    unit: Literal["bps", "kbps", "mbps", "gbps"]


class ArpModel(BaseModel):
    model_config = ConfigDict(extra="forbid")
    priority: int = Field(ge=1, le=15)
    preemption_capability: Literal["may_preempt", "not_preempt"]
    preemption_vulnerability: Literal["preemptable", "not_preemptable"]


class AppRuleModel(BaseModel):
    model_config = ConfigDict(extra="forbid")
    match_type: Literal["ip", "hostname", "sni"]
    pattern: str = Field(min_length=1, max_length=253)
    app_id: str
    logical_slice: str = Field(min_length=1, max_length=64)
    enabled: bool
    precedence: int = Field(ge=0, le=1024)


class UsageModel(BaseModel):
    model_config = ConfigDict(extra="forbid")
    scope: Literal["app", "session"]
    app_id: str | None = None
    threshold: int = Field(ge=0, le=10**15)
    unit: Literal["bytes", "packets", "KB", "MB", "GB"]
    window_seconds: int = Field(ge=1, le=86400)


class ProfileModel(BaseModel):
    model_config = ConfigDict(extra="forbid")
    apn: str
    logical_slice_template: str = Field(min_length=1, max_length=64)
    qci: int = Field(ge=1, le=9)
    arp: ArpModel
    ambr_ul: BitrateModel
    ambr_dl: BitrateModel
    mbr_ul: BitrateModel
    mbr_dl: BitrateModel
    gbr_ul: BitrateModel
    gbr_dl: BitrateModel
    app_rules: list[AppRuleModel] = Field(max_length=32)
    usage: UsageModel | None = None
    acknowledge_ambiguity: bool = False


@dataclass(frozen=True)
class Actor:
    id: str
    role: str
    group_id: str | None


@dataclass(frozen=True)
class Assignment:
    id: str
    imsi: str
    owner_user_id: str
    group_id: str


@dataclass(frozen=True)
class Decision:
    allow: bool
    status_code: int
    reason: str


@dataclass(frozen=True)
class CatalogCap:
    name: str
    max_ambr_dl_bps: int | None
    enforced: bool
    example_pending_environment_sizing: bool


@dataclass(frozen=True)
class Operation:
    name: str
    capability: str
    reason: str


@dataclass(frozen=True)
class TargetState:
    target: str
    state: str
    desired_version: int | None
    applied_version: int | None
    observed_version: int | None
    error: str | None
    evidence: dict[str, Any]


@dataclass(frozen=True)
class ApplyResult:
    status: str
    executed: bool
    core_restart: bool
    data_origin: str
    reasons: list[dict[str, str]]
    targets: list[TargetState]
    path: str


def authorize(actor: Actor, assignment: Assignment, action: str) -> Decision:
    if action not in {"read", "edit", "apply"}:
        return Decision(False, 403, "action_forbidden")
    if actor.role == "admin":
        if action == "read":
            return Decision(True, 200, "admin_read")
        return Decision(False, 403, "admin_profile_control_forbidden")
    if actor.role == "student":
        if actor.id != assignment.owner_user_id:
            return Decision(False, 403, "not_owner")
        return Decision(True, 200, "owner")
    if actor.role == "instructor":
        if not actor.group_id or actor.group_id != assignment.group_id:
            return Decision(False, 403, "cross_group_forbidden")
        return Decision(True, 200, "in_group_instructor")
    return Decision(False, 403, "role_forbidden")


def authorize_emulator(actor: Actor, owner_user_id: str | None, assignment_group_id: str | None = None) -> Decision:
    """Screen access uses the same group rule as profile read (FR-17).

    Admin may open every UE. An instructor may open a UE only when their
    current group is the assignment group. A student may open only a UE
    assigned to them.
    """

    if not owner_user_id or not assignment_group_id:
        if actor.role == "admin":
            return Decision(True, 200, "admin_read")
        if actor.role == "instructor":
            return Decision(False, 403, "cross_group_forbidden")
        return Decision(False, 403, "not_owner")
    return authorize(
        actor,
        Assignment("emulator", "", owner_user_id, assignment_group_id),
        "read",
    )


def _walk_keys(payload: Any) -> list[tuple[str, Any]]:
    found: list[tuple[str, Any]] = []
    if isinstance(payload, dict):
        for key, value in payload.items():
            found.append((str(key), value))
            found.extend(_walk_keys(value))
    elif isinstance(payload, list):
        for item in payload:
            found.extend(_walk_keys(item))
    return found


def secret_fields(payload: Any) -> list[str]:
    return [key for key, _value in _walk_keys(payload) if key.lower() in SECRET_KEYS]


def redact(payload: Any) -> Any:
    if isinstance(payload, dict):
        cleaned: dict[str, Any] = {}
        for key, value in payload.items():
            if str(key).lower() in SECRET_KEYS:
                cleaned[key] = "[redacted]"
            else:
                cleaned[key] = redact(value)
        return cleaned
    if isinstance(payload, list):
        return [redact(item) for item in payload]
    return payload


def client_scope_keys(payload: dict[str, Any]) -> list[str]:
    return sorted(CLIENT_SCOPE_KEYS.intersection(payload.keys()))


def _bps(bitrate: BitrateModel) -> int:
    return bitrate.value * UNIT_TO_BPS[bitrate.unit]


def _check_rule(rule: AppRuleModel) -> None:
    if not APP_ID_RE.fullmatch(rule.app_id):
        raise ProfileError("invalid_app_id", f"app_id {rule.app_id!r} is not a bounded identifier")
    if not APN_RE.fullmatch(rule.logical_slice):
        raise ProfileError("invalid_logical_slice", "logical_slice must be a short example label")
    if rule.match_type == "ip":
        try:
            ipaddress.ip_network(rule.pattern, strict=False)
        except ValueError as exc:
            raise ProfileError("invalid_ip_pattern", "IP rule pattern must be an IP network") from exc
    elif not HOSTNAME_RE.fullmatch(rule.pattern):
        raise ProfileError(
            "invalid_hostname_pattern",
            "Hostname and SNI patterns must be a single DNS name, not a URL",
        )


def _check_usage(usage: UsageModel | None) -> None:
    if usage is None:
        return
    if usage.scope == "app":
        if not usage.app_id or not APP_ID_RE.fullmatch(usage.app_id):
            raise ProfileError("usage_app_id_required", "scope=app requires a bounded app_id")
    elif usage.app_id is not None:
        raise ProfileError("usage_app_id_forbidden", "scope=session does not take an app_id")


def parse_profile(data: Any) -> tuple[ProfileModel, list[str]]:
    if not isinstance(data, dict):
        raise ProfileError("invalid_profile", "Profile content must be an object")
    if secret_fields(data):
        raise ProfileError("secret_field_rejected", "Ki, OPc, K, and passwords are not accepted")
    if client_scope_keys(data):
        raise ProfileError(
            "client_scope_override_rejected",
            "Owner, group, and IMSI are server-assigned and cannot be sent by the client",
        )
    if "dnn" in data:
        raise ProfileError("dnn_is_not_apn", "This EPC profile uses APN. DNN is not stored")
    if "s_nssai" in data or "snssai" in data:
        raise ProfileError("snssai_not_applicable", "S-NSSAI is not an EPC APN and is not stored")
    try:
        model = ProfileModel.model_validate(data)
    except ValidationError as exc:
        raise ProfileError(
            "invalid_profile",
            "Profile content is invalid",
            {"errors": json.loads(exc.json())},
        ) from exc
    if not APN_RE.fullmatch(model.apn):
        raise ProfileError("invalid_apn", "APN must be a short synthetic label")
    if not APN_RE.fullmatch(model.logical_slice_template):
        raise ProfileError("invalid_logical_slice", "logical_slice_template must be a short example label")
    if _bps(model.gbr_ul) > _bps(model.mbr_ul):
        raise ProfileError("gbr_exceeds_mbr", "gbr_ul must be less than or equal to mbr_ul")
    if _bps(model.gbr_dl) > _bps(model.mbr_dl):
        raise ProfileError("gbr_exceeds_mbr", "gbr_dl must be less than or equal to mbr_dl")
    for rule in model.app_rules:
        _check_rule(rule)
    _check_usage(model.usage)
    enabled = [rule for rule in model.app_rules if rule.enabled]
    ambiguous = len({rule.precedence for rule in enabled}) != len(enabled)
    if ambiguous and not model.acknowledge_ambiguity:
        raise ProfileError(
            "classification_ambiguous",
            "Enabled rules share a precedence. Save them only with acknowledge_ambiguity",
        )
    warnings: list[str] = []
    if ambiguous:
        warnings.append("classification_ambiguous_acknowledged")
    networks: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
    for rule in enabled:
        if rule.match_type == "ip":
            networks.append(ipaddress.ip_network(rule.pattern, strict=False))
    for left in range(len(networks)):
        for right in range(left + 1, len(networks)):
            if networks[left].overlaps(networks[right]):
                warnings.append("ip_rules_overlap")
                break
    return model, warnings


def apply_caps(model: ProfileModel, caps: list[CatalogCap]) -> list[str]:
    warnings: list[str] = []
    downlink = _bps(model.ambr_dl)
    for cap in caps:
        if cap.max_ambr_dl_bps is None or downlink <= cap.max_ambr_dl_bps:
            continue
        if cap.enforced:
            raise ProfileError(
                "catalog_limit_exceeded",
                f"Downlink AMBR exceeds enforced catalog cap {cap.name}",
                {"cap": cap.name, "example_pending_environment_sizing": cap.example_pending_environment_sizing},
            )
        if cap.example_pending_environment_sizing:
            warnings.append(f"example_limit_exceeded_not_enforced:{cap.name}")
    return warnings


def _rule_dict(rule: AppRuleModel) -> dict[str, Any]:
    if rule.match_type == "ip":
        enforcement = "unverified_ipfilter_intent"
    else:
        enforcement = "not_native_gx"
    return {
        "match_type": rule.match_type,
        "pattern": rule.pattern,
        "app_id": rule.app_id,
        "logical_slice": rule.logical_slice,
        "enabled": rule.enabled,
        "precedence": rule.precedence,
        "enforcement": enforcement,
        "automatic_enforcement": False,
    }


def _bitrate(bitrate: BitrateModel) -> dict[str, Any]:
    return {"value": bitrate.value, "unit": bitrate.unit, "bps": _bps(bitrate)}


def content_dict(model: ProfileModel) -> dict[str, Any]:
    usage = None
    if model.usage is not None:
        usage = model.usage.model_dump()
        usage["stock_gx_usage_monitoring"] = "not_claimed"
    return {
        "apn": model.apn,
        "dnn": None,
        "s_nssai": None,
        "logical_slice_template": model.logical_slice_template,
        "qci": model.qci,
        "arp": model.arp.model_dump(),
        "ambr_ul": _bitrate(model.ambr_ul),
        "ambr_dl": _bitrate(model.ambr_dl),
        "mbr_ul": _bitrate(model.mbr_ul),
        "mbr_dl": _bitrate(model.mbr_dl),
        "gbr_ul": _bitrate(model.gbr_ul),
        "gbr_dl": _bitrate(model.gbr_dl),
        "app_rules": [_rule_dict(rule) for rule in model.app_rules],
        "usage": usage,
        "acknowledge_ambiguity": model.acknowledge_ambiguity,
        "epc_note": "APN is not S-NSSAI. PCRF is not PCF. Host and SNI rules are not native Gx enforcement.",
    }


def canonical(payload: dict[str, Any]) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def make_etag(version: int, content: dict[str, Any]) -> str:
    digest = hashlib.sha256(f"{version}.{canonical(content)}".encode()).hexdigest()
    return f'"{digest[:32]}"'


def _without_bps(content: dict[str, Any]) -> dict[str, Any]:
    """Compare authored fields. Derived bps and server notes are not a user diff."""
    skip = {"bps", "enforcement", "automatic_enforcement", "stock_gx_usage_monitoring", "dnn", "s_nssai", "epc_note"}

    def walk(value: Any) -> Any:
        if isinstance(value, dict):
            return {key: walk(item) for key, item in value.items() if key not in skip}
        if isinstance(value, list):
            return [walk(item) for item in value]
        return value

    return walk(content)


def diff_operations(previous: dict[str, Any] | None, desired: dict[str, Any]) -> list[Operation]:
    before = None if previous is None else _without_bps(previous)
    after = _without_bps(desired)
    ops: list[Operation] = []
    ambr_changed = before is None or before["ambr_ul"] != after["ambr_ul"] or before["ambr_dl"] != after["ambr_dl"]
    if ambr_changed:
        ops.append(
            Operation(
                "apn_ambr_rar",
                "unsupported",
                "stock Open5GS 2.8 immediate APN-AMBR RAR is unsupported until a verified patch exists",
            )
        )
    if before is not None and before["qci"] != after["qci"]:
        ops.append(
            Operation(
                "modify_qci_existing_bearer",
                "unsupported",
                "stock Open5GS 2.8 immediate QCI modification of an existing bearer is unsupported",
            )
        )
    if before is not None and before["arp"] != after["arp"]:
        ops.append(
            Operation(
                "modify_arp_existing_bearer",
                "unsupported",
                "stock Open5GS 2.8 immediate ARP modification of an existing bearer is unsupported",
            )
        )
    if before is not None and (
        before["mbr_ul"] != after["mbr_ul"]
        or before["mbr_dl"] != after["mbr_dl"]
        or before["gbr_ul"] != after["gbr_ul"]
        or before["gbr_dl"] != after["gbr_dl"]
    ):
        ops.append(
            Operation(
                "modify_bearer_mbr_gbr",
                "unverified",
                "MBR/GBR bearer modification has no verified adapter",
            )
        )
    if before is not None and before["apn"] != after["apn"]:
        ops.append(Operation("apn_change", "unverified", "APN change has no verified immediate Gx adapter"))
    previous_rules = set() if before is None else {canonical(rule) for rule in before["app_rules"]}
    for rule in after["app_rules"]:
        if canonical(rule) in previous_rules:
            continue
        if rule["match_type"] == "ip":
            ops.append(
                Operation(
                    "new_pcc_rule_rar",
                    "unverified",
                    "A new PCC rule via Gx RAR is not a verified adapter. Example copy that calls it supported is not evidence",
                )
            )
        else:
            ops.append(
                Operation(
                    "host_sni_classification_intent",
                    "not_native",
                    "Hostname and TLS SNI are classification intent, not a native IPFilterRule or Gx install",
                )
            )
    if after["usage"] != (None if before is None else before["usage"]):
        if after["usage"] is not None:
            ops.append(
                Operation(
                    "gx_usage_monitoring",
                    "unsupported_do_not_claim",
                    "Gx usage monitoring on stock Open5GS is not claimed",
                )
            )
    if not ops:
        ops.append(Operation("no_change", "rejected", "Desired content matches the stored applied snapshot"))
    return ops


def _targets(desired_version: int, error: str) -> list[TargetState]:
    return [
        TargetState(
            target=target,
            state="not_executed",
            desired_version=desired_version,
            applied_version=None,
            observed_version=None,
            error=error,
            evidence={"data_origin": "none", "core_restart": False},
        )
        for target in TARGETS
    ]


def stock_immediate_apply(ops: list[Operation], desired_version: int) -> ApplyResult:
    reasons = [{"op": op.name, "capability": op.capability, "reason": op.reason} for op in ops]
    reasons.append(
        {
            "op": "gx_rar",
            "capability": "not_integrated",
            "reason": "No Gx RAR adapter is implemented. Immediate apply is rejected instead of reporting pushed or active.",
        }
    )
    return ApplyResult(
        status="rejected",
        executed=False,
        core_restart=False,
        data_origin="none",
        reasons=reasons,
        targets=_targets(desired_version, "adapter_rejected"),
        path="gx_rar_immediate",
    )


def reattach_notice_id(profile_id: str, version: int) -> str:
    digest = hashlib.sha256(f"{profile_id}.{version}.{REATTACH_NOTICE}".encode()).hexdigest()
    return digest[:16]


def stock_reattach(confirmed: bool, notice_id: str, expected: str, desired_version: int) -> ApplyResult:
    if not confirmed or notice_id != expected:
        raise ProfileError(
            "reattach_confirmation_required",
            "Re-attach requires confirm_disruption and the server notice id",
        )
    return ApplyResult(
        status="rejected",
        executed=False,
        core_restart=False,
        data_origin="none",
        reasons=[
            {
                "op": "reattach_fallback",
                "capability": "not_executed",
                "reason": "The disruption notice was confirmed. No UE was detached and the core was not restarted.",
            }
        ],
        targets=_targets(desired_version, "reattach_not_executed"),
        path="reattach_fallback",
    )


def raa_ack_status(result_code: int | None) -> str:
    if result_code == 2001:
        return "pushed"
    return "insufficient"


def active_allowed(operation: str, evidence: dict[str, Any]) -> bool:
    if evidence.get("kind") == "raa" or evidence.get("raa_result_code") == 2001 and evidence.get("kind") != "session":
        if evidence.get("kind") != "session" and evidence.get("kind") not in {"pgw_c", "pfcp"}:
            return False
    if evidence.get("kind") not in {"session", "pgw_c", "pfcp"}:
        return False
    for key in ("imsi", "session_id", "profile_id", "profile_version"):
        if evidence.get(key) in (None, ""):
            return False
    bearer_ops = {
        "modify_qci_existing_bearer",
        "modify_arp_existing_bearer",
        "modify_bearer_mbr_gbr",
        "apn_ambr_rar",
    }
    if operation in bearer_ops and not evidence.get("bearer_id"):
        return False
    if operation == "new_pcc_rule_rar" and not evidence.get("rule_id"):
        return False
    return True


def aggregate_status(target_states: list[str]) -> str:
    states = set(target_states)
    if not states:
        return "unknown"
    if "timeout" in states:
        return "timeout" if states <= {"timeout", "not_executed", "rejected"} or "failed" in states or "pushed" in states else "timeout"
    if "failed" in states and ("pushed" in states or "active" in states):
        return "partial"
    if states == {"active"}:
        return "active"
    if "failed" in states:
        return "failed"
    if "pushed" in states:
        return "pushed"
    if "rejected" in states or "not_executed" in states:
        return "rejected"
    return "unknown"


def interpret_counter(value: int | None, freshness: str) -> dict[str, Any]:
    if freshness in {"unknown", "missing"} or value is None:
        return {"interpretation": "unknown", "value": None, "is_zero": False}
    if freshness == "failed":
        return {"interpretation": "failed", "value": None, "is_zero": False}
    return {"interpretation": "measured", "value": value, "is_zero": value == 0}


def render_prometheus(series: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for item in series:
        labels: dict[str, str] = item["labels"]
        unknown = set(labels) - ALLOWED_METRIC_LABELS
        forbidden = set(labels) & FORBIDDEN_METRIC_LABELS
        if unknown or forbidden:
            raise ProfileError(
                "metric_label_rejected",
                "Metric labels must stay inside the bounded aggregate set",
                {"rejected": sorted(unknown | forbidden)},
            )
        rendered = ",".join(f'{key}="{labels[key]}"' for key in sorted(labels))
        lines.append(f"{item['name']}{{{rendered}}} {item['value']}")
    return ("\n".join(lines) + "\n") if lines else ""


def demo_sample() -> dict[str, Any]:
    return {
        "data_origin": "sample",
        "fake": True,
        "not_lab_evidence": True,
        "note": "Isolated demo payload. It is not an Open5GS, PCRF, PFCP, or eBPF observation.",
        "active_sessions": None,
        "lifecycle": None,
    }


def capability_catalog() -> list[dict[str, str]]:
    return [
        {
            "op": "apn_ambr_rar",
            "capability": "unsupported",
            "scope": "stock Open5GS 2.8 immediate APN-AMBR RAR",
            "evidence": "none — WIP pending a real patch and the Network Architect package",
        },
        {
            "op": "modify_qci_existing_bearer",
            "capability": "unsupported",
            "scope": "stock Open5GS 2.8 immediate QCI change on an existing bearer",
            "evidence": "none",
        },
        {
            "op": "modify_arp_existing_bearer",
            "capability": "unsupported",
            "scope": "stock Open5GS 2.8 immediate ARP change on an existing bearer",
            "evidence": "none",
        },
        {
            "op": "new_pcc_rule_rar",
            "capability": "unverified",
            "scope": "Gx RAR install of a new PCC rule",
            "evidence": "none — hi-fi supported chip is an example, not a capability",
        },
        {
            "op": "host_sni_classification_intent",
            "capability": "not_native",
            "scope": "hostname or TLS SNI to app_id",
            "evidence": "none — not an IPFilterRule and not automatic enforcement",
        },
        {
            "op": "gx_usage_monitoring",
            "capability": "unsupported_do_not_claim",
            "scope": "stock Open5GS Gx usage monitoring",
            "evidence": "none",
        },
        {
            "op": "endc_option_3x",
            "capability": "planned_unverified",
            "scope": "eNB plus NR gNB with EPC core",
            "evidence": "none — srsRAN 4G reference does not include a gNB",
        },
    ]
