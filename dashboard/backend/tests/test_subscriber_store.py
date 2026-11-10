"""Mongo subscriber port against mongomock. No lab and no real credentials."""

from bson import encode

from open5g_dashboard.subscriber_port import MongoSubscriberPort


PLANTED_K = "PLANTED-KI-VALUE-not-a-real-key"
PLANTED_OPC = "PLANTED-OPC-VALUE-not-a-real-opc"


def _content():
    return {
        "apn": "internet",
        "qci": 6,
        "arp": {"priority": 5, "preemption_capability": "not_preempt", "preemption_vulnerability": "not_preemptable"},
        "ambr_ul": {"value": 50, "unit": "mbps"},
        "ambr_dl": {"value": 100, "unit": "mbps"},
        "mbr_ul": {"value": 20, "unit": "mbps"},
        "mbr_dl": {"value": 40, "unit": "mbps"},
        "gbr_ul": {"value": 5, "unit": "mbps"},
        "gbr_dl": {"value": 10, "unit": "mbps"},
        "app_rules": [
            {
                "match_type": "ip",
                "pattern": "203.0.113.10/32",
                "enabled": True,
                "precedence": 1,
            }
        ],
        "usage": {"scope": "session"},
    }


def test_written_integers_are_bson_int32():
    # PyMongo 4 stores a Python int that fits as BSON int32, which is what Open5GS reads.
    payload = encode({"index": 9, "name": "internet"})
    assert b"\x10index\x00" in payload
    assert b"\x12index\x00" not in payload


def test_mongomock_round_trip_preserves_credentials_and_second_session():
    mongomock = __import__("mongomock")
    client = mongomock.MongoClient()
    collection = client["open5gs"]["subscribers"]
    collection.insert_one(
        {
            "imsi": "001010000000001",
            "security": {"k": PLANTED_K, "opc": PLANTED_OPC, "amf": "8000"},
            "slice": [
                {
                    "sst": 1,
                    "default_indicator": True,
                    "session": [
                        {"name": "internet", "type": 3, "pcc_rule": []},
                        {"name": "upf-b", "type": 3, "pcc_rule": []},
                    ],
                }
            ],
        }
    )
    port = MongoSubscriberPort("mongodb://mongo.invalid/open5gs", "open5gs", "subscribers", 2000, client=client)
    assert port.describe()["auth"] == "absent"
    assert port.probe()["status"] == "reachable"
    written = port.provision("001010000000001", _content())
    assert written["status"] == "written"
    assert written["created"] is False
    assert written["live_gx_rar"] is False
    assert written["subscriber"]["sessions"][0]["qci"] == 6
    assert PLANTED_K not in str(written)
    stored = collection.find_one({"imsi": "001010000000001"})
    assert stored["security"]["k"] == PLANTED_K
    assert stored["security"]["opc"] == PLANTED_OPC
    assert [item["name"] for item in stored["slice"][0]["session"]] == ["internet", "upf-b"]
    again = port.read("001010000000001")
    assert again["found"] is True
    assert again["credentials_present"] is True
    assert again["session_count"] == 2
    missing = port.read("001010000000099")
    assert missing["status"] == "absent"


def test_mongo_timeout_does_not_echo_the_driver_message():
    class Down:
        def __getitem__(self, _name):
            return self

        def find_one(self, *_args, **_kwargs):
            raise TimeoutError("mongodb://secret-user:secret-pass@hidden/open5gs")

        def replace_one(self, *_args, **_kwargs):
            raise TimeoutError("mongodb://secret-user:secret-pass@hidden/open5gs")

    port = MongoSubscriberPort("mongodb://hidden/open5gs", "open5gs", "subscribers", 200, client=Down())
    assert port.probe()["status"] == "down"
    assert "secret-pass" not in str(port.probe())
    try:
        port.read("001010000000001")
    except Exception as exc:
        assert exc.code == "subscriber_store_unavailable"
        assert exc.message == "MongoDB timed out"
        assert "secret-pass" not in exc.message
    else:
        raise AssertionError("down store was treated as reachable")
