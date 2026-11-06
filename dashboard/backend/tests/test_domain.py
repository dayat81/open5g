"""Unit tests for policy rules. No database and no core adapter."""

import pytest

from open5g_dashboard.domain import (
    Actor,
    Assignment,
    CatalogCap,
    active_allowed,
    aggregate_status,
    apply_caps,
    authorize,
    capability_catalog,
    content_dict,
    demo_sample,
    diff_operations,
    interpret_counter,
    make_etag,
    parse_profile,
    raa_ack_status,
    reattach_notice_id,
    redact,
    render_prometheus,
    stock_immediate_apply,
    stock_reattach,
)


def profile(**overrides):
    data = {
        "apn": "internet",
        "logical_slice_template": "slice-class-a",
        "qci": 6,
        "arp": {
            "priority": 5,
            "preemption_capability": "not_preempt",
            "preemption_vulnerability": "not_preemptable",
        },
        "ambr_ul": {"value": 50, "unit": "mbps"},
        "ambr_dl": {"value": 100, "unit": "mbps"},
        "mbr_ul": {"value": 20, "unit": "mbps"},
        "mbr_dl": {"value": 40, "unit": "mbps"},
        "gbr_ul": {"value": 5, "unit": "mbps"},
        "gbr_dl": {"value": 10, "unit": "mbps"},
        "app_rules": [
            {
                "match_type": "sni",
                "pattern": "meet.example",
                "app_id": "video-conf",
                "logical_slice": "slice-class-a",
                "enabled": True,
                "precedence": 10,
            }
        ],
        "usage": {
            "scope": "app",
            "app_id": "video-conf",
            "threshold": 500,
            "unit": "MB",
            "window_seconds": 300,
        },
    }
    data.update(overrides)
    model, warnings = parse_profile(data)
    return model, warnings, content_dict(model)


def test_student_owns_only_assigned_imsi():
    assignment = Assignment("a", "001010000000001", "student", "group-a")
    assert authorize(Actor("student", "student", "group-a"), assignment, "edit").allow
    denied = authorize(Actor("other", "student", "group-a"), assignment, "apply")
    assert not denied.allow
    assert denied.reason == "not_owner"


def test_instructor_is_group_bound():
    assignment = Assignment("a", "001010000000001", "student", "group-a")
    assert authorize(Actor("inst", "instructor", "group-a"), assignment, "apply").allow
    denied = authorize(Actor("inst", "instructor", "group-b"), assignment, "read")
    assert denied.status_code == 403
    assert denied.reason == "cross_group_forbidden"


def test_admin_reads_but_does_not_edit_profiles():
    assignment = Assignment("a", "001010000000001", "student", "group-a")
    assert authorize(Actor("admin", "admin", None), assignment, "read").allow
    denied = authorize(Actor("admin", "admin", None), assignment, "edit")
    assert denied.reason == "admin_profile_control_forbidden"


def test_rejects_secrets_scope_dnn_and_snssai():
    with pytest.raises(Exception) as secret:
        parse_profile({"ki": "00112233445566778899aabbccddeeff", "apn": "internet"})
    assert secret.value.code == "secret_field_rejected"
    with pytest.raises(Exception) as scope:
        parse_profile({"owner_user_id": "student", "apn": "internet"})
    assert scope.value.code == "client_scope_override_rejected"
    with pytest.raises(Exception) as dnn:
        profile(dnn="internet")
    assert dnn.value.code == "dnn_is_not_apn"
    with pytest.raises(Exception) as snssai:
        profile(s_nssai="01-000001")
    assert snssai.value.code == "snssai_not_applicable"


def test_gbr_must_not_exceed_mbr_per_direction_after_unit_conversion():
    _model, _warnings, stored = profile(
        gbr_ul={"value": 5, "unit": "mbps"},
        mbr_ul={"value": 5000, "unit": "kbps"},
    )
    assert stored["gbr_ul"]["bps"] == stored["mbr_ul"]["bps"]
    with pytest.raises(Exception) as exceeded:
        profile(gbr_dl={"value": 41, "unit": "mbps"}, mbr_dl={"value": 40, "unit": "mbps"})
    assert exceeded.value.code == "gbr_exceeds_mbr"
    assert "gbr_dl" in exceeded.value.message


def test_shared_precedence_requires_acknowledgement_and_sni_is_not_native():
    rules = [
        {
            "match_type": "sni",
            "pattern": "meet.example",
            "app_id": "video-conf",
            "logical_slice": "slice-class-a",
            "enabled": True,
            "precedence": 10,
        },
        {
            "match_type": "hostname",
            "pattern": "cdn.example",
            "app_id": "web-cdn",
            "logical_slice": "slice-class-a",
            "enabled": True,
            "precedence": 10,
        },
    ]
    with pytest.raises(Exception) as ambiguous:
        profile(app_rules=rules)
    assert ambiguous.value.code == "classification_ambiguous"
    model, warnings, stored = profile(app_rules=rules, acknowledge_ambiguity=True)
    assert model.acknowledge_ambiguity
    assert "classification_ambiguous_acknowledged" in warnings
    assert stored["app_rules"][0]["enforcement"] == "not_native_gx"
    assert stored["app_rules"][0]["automatic_enforcement"] is False


def test_example_cap_warns_and_enforced_cap_rejects():
    model, _warnings, _stored = profile()
    warnings = apply_caps(
        model,
        [CatalogCap("example-downlink", 50_000_000, enforced=False, example_pending_environment_sizing=True)],
    )
    assert warnings == ["example_limit_exceeded_not_enforced:example-downlink"]
    with pytest.raises(Exception) as enforced:
        apply_caps(
            model,
            [CatalogCap("sized-later", 50_000_000, enforced=True, example_pending_environment_sizing=True)],
        )
    assert enforced.value.code == "catalog_limit_exceeded"


def test_stock_apply_rejects_ambr_and_existing_bearer_qos_without_success():
    _model, _warnings, first = profile()
    initial = diff_operations(None, first)
    assert any(op.name == "apn_ambr_rar" and op.capability == "unsupported" for op in initial)
    changed = profile(qci=7, arp={
        "priority": 4,
        "preemption_capability": "not_preempt",
        "preemption_vulnerability": "not_preemptable",
    })[2]
    # Keep AMBR identical so the QCI/ARP reasons are visible on their own.
    changed["ambr_ul"] = first["ambr_ul"]
    changed["ambr_dl"] = first["ambr_dl"]
    ops = diff_operations(first, changed)
    names = {op.name for op in ops}
    assert "modify_qci_existing_bearer" in names
    assert "modify_arp_existing_bearer" in names
    assert "apn_ambr_rar" not in names
    result = stock_immediate_apply(ops, desired_version=3)
    assert result.status == "rejected"
    assert result.executed is False
    assert result.core_restart is False
    assert result.data_origin == "none"
    assert {target.state for target in result.targets} == {"not_executed"}
    assert all(target.applied_version is None for target in result.targets)
    assert "pushed" not in result.status
    assert "active" not in result.status


def test_reattach_confirmation_does_not_execute_or_restart():
    with pytest.raises(Exception) as missing:
        stock_reattach(False, "wrong", "expected", 3)
    assert missing.value.code == "reattach_confirmation_required"
    result = stock_reattach(True, "notice", "notice", 3)
    assert result.path == "reattach_fallback"
    assert result.status == "rejected"
    assert result.executed is False
    assert result.core_restart is False


def test_raa_ack_is_pushed_and_active_needs_correlated_evidence():
    assert raa_ack_status(2001) == "pushed"
    assert raa_ack_status(2002) == "insufficient"
    ack = {"kind": "raa", "raa_result_code": 2001, "imsi": "001010000000001"}
    assert active_allowed("new_pcc_rule_rar", ack) is False
    session = {
        "kind": "session",
        "imsi": "001010000000001",
        "session_id": "sess-1",
        "profile_id": "prf-1",
        "profile_version": 3,
        "bearer_id": "ebi-5",
        "rule_id": "rule-1",
    }
    assert active_allowed("new_pcc_rule_rar", session) is True
    assert active_allowed("modify_qci_existing_bearer", {**session, "bearer_id": None}) is False
    assert aggregate_status(["pushed", "failed"]) == "partial"
    assert aggregate_status(["timeout", "pushed"]) == "timeout"
    assert aggregate_status(["not_executed"]) == "rejected"


def test_unknown_counter_is_not_zero_and_labels_stay_bounded():
    unknown = interpret_counter(None, "unknown")
    assert unknown["value"] is None
    assert unknown["is_zero"] is False
    failed = interpret_counter(0, "failed")
    assert failed["interpretation"] == "failed"
    assert failed["value"] is None
    text = render_prometheus(
        [{
            "name": "open5g_app_bytes_total",
            "value": 10,
            "labels": {
                "source": "ebpf",
                "exporter_instance": "stub",
                "interface": "sgi",
                "capture_point": "sgi",
                "rule_version": "none",
                "data_origin": "stub",
            },
        }]
    )
    assert 'data_origin="stub"' in text
    with pytest.raises(Exception) as rejected:
        render_prometheus([{"name": "open5g_app_bytes_total", "value": 1, "labels": {"imsi": "001010000000001"}}])
    assert rejected.value.code == "metric_label_rejected"


def test_redaction_etag_and_demo_isolation():
    assert redact({"nested": {"opc": "secret-value", "apn": "internet"}})["nested"]["opc"] == "[redacted]"
    _model, _warnings, stored = profile()
    assert make_etag(1, stored) == make_etag(1, stored)
    assert make_etag(1, stored) != make_etag(2, stored)
    sample = demo_sample()
    assert sample["fake"] is True
    assert sample["data_origin"] == "sample"
    assert sample["active_sessions"] is None
    assert any(item["op"] == "endc_option_3x" and item["capability"] == "planned_unverified" for item in capability_catalog())
    assert reattach_notice_id("prf", 1) != reattach_notice_id("prf", 2)
