"""Open5GS document mapping. No database."""

from open5g_dashboard.domain import ProfileError, content_dict, parse_profile
from open5g_dashboard.open5gs_schema import (
    MAX_DEDICATED_BEARERS,
    MAX_PCC_RULES,
    MAX_SESSIONS,
    PREEMPTION_ENABLED,
    encode_bitrate,
    plan_session_update,
    project_subscriber,
)


def _content(**overrides):
    raw = {
        "apn": "internet",
        "logical_slice_template": "slice-class-a",
        "qci": 6,
        "arp": {"priority": 5, "preemption_capability": "may_preempt", "preemption_vulnerability": "preemptable"},
        "ambr_ul": {"value": 50, "unit": "mbps"},
        "ambr_dl": {"value": 100, "unit": "mbps"},
        "mbr_ul": {"value": 20, "unit": "mbps"},
        "mbr_dl": {"value": 40, "unit": "mbps"},
        "gbr_ul": {"value": 0, "unit": "mbps"},
        "gbr_dl": {"value": 0, "unit": "mbps"},
        "app_rules": [
            {
                "match_type": "ip",
                "pattern": "203.0.113.0/24",
                "app_id": "bulk-dl",
                "logical_slice": "slice-class-a",
                "enabled": True,
                "precedence": 20,
            },
            {
                "match_type": "sni",
                "pattern": "example.test",
                "app_id": "web",
                "logical_slice": "slice-class-a",
                "enabled": True,
                "precedence": 30,
            },
        ],
    }
    raw.update(overrides)
    model, _warnings = parse_profile(raw)
    return content_dict(model)


def test_bitrate_stays_inside_int32_and_matches_open5gs_units():
    assert encode_bitrate(100, "mbps") == {"value": 100, "unit": 2}
    assert encode_bitrate(3_000_000_000, "bps") == {"value": 3_000_000, "unit": 1}


def _seeded(**sessions):
    return {
        "imsi": "001010000000001",
        "ambr": {"downlink": {"value": 1, "unit": 3}, "uplink": {"value": 1, "unit": 3}},
        "slice": [{"sst": 1, "default_indicator": True, "session": sessions["rows"]}],
    }


def test_refuses_to_insert_a_subscriber_without_security():
    try:
        plan_session_update(None, _content(), role="instructor")
    except ProfileError as exc:
        assert exc.code == "subscriber_not_seeded"
    else:
        raise AssertionError("insert without a seeded subscriber was accepted")


def test_enabled_preemption_is_the_5gc_value_stock_hss_honors():
    patch = plan_session_update(_seeded(rows=[{"name": "internet", "type": 3, "pcc_rule": []}]), _content(), role="instructor")
    assert patch.qos["arp"]["pre_emption_capability"] == PREEMPTION_ENABLED
    assert patch.qos["arp"]["pre_emption_vulnerability"] == PREEMPTION_ENABLED
    assert "security_not_written" in patch.notes
    assert "ue_ambr_not_written" in patch.notes
    assert "session_rename_not_performed" in patch.notes


def test_hostname_is_not_a_flow_and_foreign_pcc_rules_stay():
    existing = _seeded(
        rows=[
            {
                "name": "internet",
                "type": 3,
                "qos": {"index": 9, "arp": {}},
                "ambr": {},
                "pcc_rule": [{"flow": [{"direction": 1, "description": "permit out udp from 192.0.2.10/32 53 to assigned"}], "qos": {"index": 5}}],
            },
            {"name": "slice-b", "type": 3, "qos": {"index": 8, "arp": {}}, "ambr": {}, "pcc_rule": []},
        ]
    )
    patch = plan_session_update(existing, _content(), role="instructor")
    descriptions = [flow["description"] for rule in patch.pcc_rule for flow in rule["flow"]]
    assert "permit out udp from 192.0.2.10/32 53 to assigned" in descriptions
    assert "permit out ip from 203.0.113.0/24 to assigned" in descriptions
    assert "example.test" not in str(patch.pcc_rule)
    assert "hostname_sni_not_written" in patch.notes
    assert patch.session_index == 0
    assert "security" not in existing or existing.get("security") is None


def test_unmatched_apn_is_added_without_renaming():
    existing = _seeded(rows=[{"name": "upf-a", "type": 3, "pcc_rule": []}, {"name": "upf-b", "type": 3, "pcc_rule": []}])
    patch = plan_session_update(existing, _content(apn="internet"), role="instructor")
    assert patch.session_index is None
    assert patch.new_session is not None
    assert patch.new_session["name"] == "internet"
    assert existing["slice"][0]["session"][0]["name"] == "upf-a"
    assert "session_rename_not_performed" in patch.notes


def test_open5gs_limits_count_existing_sessions_and_rules():
    sessions = [{"name": f"apn-{index}", "type": 3, "pcc_rule": []} for index in range(MAX_SESSIONS)]
    try:
        plan_session_update(_seeded(rows=sessions), _content(apn="internet"), role="instructor")
    except ProfileError as exc:
        assert exc.code == "session_limit"
    else:
        raise AssertionError("a fifth session was accepted")
    foreign = [
        {"flow": [{"direction": 1, "description": f"permit out udp from 192.0.2.{index}/32 53 to assigned"}], "qos": {"index": 5}}
        for index in range(MAX_DEDICATED_BEARERS)
    ]
    try:
        plan_session_update(
            _seeded(rows=[{"name": "internet", "type": 3, "pcc_rule": foreign}]),
            _content(),
            role="instructor",
        )
    except ProfileError as exc:
        assert exc.code == "dedicated_bearer_limit"
    else:
        raise AssertionError("a fourth dedicated bearer was accepted")
    packed = [{"qos": {"index": 9}} for _ in range(MAX_PCC_RULES)]
    try:
        plan_session_update(
            _seeded(rows=[{"name": "internet", "type": 3, "pcc_rule": packed}]),
            _content(),
            role="instructor",
        )
    except ProfileError as exc:
        assert exc.code == "pcc_rule_limit"
    else:
        raise AssertionError("a ninth PCC rule was accepted")


def test_student_cannot_store_gbr_qci_and_non_gbr_qci_rejects_gbr():
    try:
        plan_session_update(_seeded(rows=[{"name": "internet", "pcc_rule": []}]), _content(qci=1), role="student")
    except ProfileError as exc:
        assert exc.code == "role_qos_forbidden"
    else:
        raise AssertionError("student GBR QCI was accepted")
    try:
        plan_session_update(
            _seeded(rows=[{"name": "internet", "pcc_rule": []}]),
            _content(gbr_ul={"value": 1, "unit": "mbps"}, gbr_dl={"value": 1, "unit": "mbps"}),
            role="instructor",
        )
    except ProfileError as exc:
        assert exc.code == "gbr_on_non_gbr_qci"
    else:
        raise AssertionError("GBR on QCI 6 was accepted")


def test_rejected_profile_still_rejects_a_secret_key():
    try:
        parse_profile({"ki": "nope"})
    except ProfileError as exc:
        assert exc.code == "secret_field_rejected"
    else:
        raise AssertionError("secret field was accepted")
