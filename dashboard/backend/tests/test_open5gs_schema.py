"""Open5GS document mapping. No database."""

from open5g_dashboard.domain import ProfileError, content_dict, parse_profile
from open5g_dashboard.open5gs_schema import (
    PREEMPTION_ENABLED,
    apply_profile_to_document,
    credentials_present,
    encode_bitrate,
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
        "gbr_ul": {"value": 5, "unit": "mbps"},
        "gbr_dl": {"value": 10, "unit": "mbps"},
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


def test_enabled_preemption_is_the_5gc_value_stock_hss_honors():
    _document, notes = apply_profile_to_document(None, "001010000000001", _content())
    session = _document["slice"][0]["session"][0]
    assert session["qos"]["arp"]["pre_emption_capability"] == PREEMPTION_ENABLED
    assert session["qos"]["arp"]["pre_emption_vulnerability"] == PREEMPTION_ENABLED
    assert "created_without_credentials" in notes
    assert "security" not in _document
    assert credentials_present(_document) is False


def test_hostname_is_not_a_flow_and_extra_sessions_stay():
    existing = {
        "imsi": "001010000000001",
        "security": {"k": "PLANTED-KI-VALUE-not-a-real-key", "opc": "PLANTED-OPC-VALUE-not-a-real-opc", "amf": "8000"},
        "slice": [
            {
                "sst": 1,
                "default_indicator": True,
                "session": [
                    {"name": "internet", "type": 3, "qos": {"index": 9, "arp": {}}, "ambr": {}, "pcc_rule": [{"flow": []}]},
                    {"name": "slice-b", "type": 3, "qos": {"index": 8, "arp": {}}, "ambr": {}, "pcc_rule": []},
                ],
            }
        ],
    }
    updated, notes = apply_profile_to_document(existing, "001010000000001", _content())
    sessions = updated["slice"][0]["session"]
    assert [item["name"] for item in sessions] == ["internet", "slice-b"]
    assert sessions[1]["qos"]["index"] == 8
    flows = sessions[0]["pcc_rule"][0]["flow"]
    assert flows == [{"direction": 3, "description": "permit out ip from 203.0.113.0/24 to assigned"}]
    assert "example.test" not in str(updated["slice"])
    assert "hostname_sni_not_written" in notes
    assert "other_sessions_preserved" in notes
    assert updated["security"]["k"] == "PLANTED-KI-VALUE-not-a-real-key"
    view = project_subscriber(updated, "001010000000001")
    assert "PLANTED-KI-VALUE-not-a-real-key" not in str(view)
    assert view["credentials_present"] is True
    assert view["session_count"] == 2


def test_unmatched_apn_is_added_beside_existing_sessions():
    existing = {
        "imsi": "001010000000001",
        "slice": [
            {
                "default_indicator": True,
                "session": [
                    {"name": "upf-a", "type": 3},
                    {"name": "upf-b", "type": 3},
                ],
            }
        ],
    }
    updated, notes = apply_profile_to_document(existing, "001010000000001", _content(apn="internet"))
    names = [item["name"] for item in updated["slice"][0]["session"]]
    assert names == ["upf-a", "upf-b", "internet"]
    assert "session_added_alongside_existing" in notes


def test_rejected_profile_still_rejects_a_secret_key():
    try:
        parse_profile({"ki": "nope"})
    except ProfileError as exc:
        assert exc.code == "secret_field_rejected"
    else:
        raise AssertionError("secret field was accepted")
