"""Int64 SQN round-trip against real MongoDB 7.

Skipped with a clear marker when neither OPEN5G_TEST_MONGO_URI nor Docker is
available. CI sets OPEN5G_TEST_MONGO_URI to a mongo:7 service.
"""

from __future__ import annotations

import os
import shutil

import pytest
from bson.int64 import Int64
from pymongo import MongoClient

from open5g_dashboard.subscriber_port import MongoSubscriberPort

pytestmark = pytest.mark.skipif(
    not os.environ.get("OPEN5G_TEST_MONGO_URI") and shutil.which("docker") is None,
    reason="real MongoDB 7 is not available; set OPEN5G_TEST_MONGO_URI or provide Docker so mongo:7 can run. CI must set OPEN5G_TEST_MONGO_URI.",
)


def _uri() -> str:
    uri = os.environ.get("OPEN5G_TEST_MONGO_URI")
    if uri:
        return uri
    pytest.skip("OPEN5G_TEST_MONGO_URI is not set. Docker is present but this test does not start a container itself.")


def test_sqn_int64_survives_allowlisted_update():
    client = MongoClient(_uri(), serverSelectionTimeoutMS=2000)
    collection = client["open5g_int64"]["subscribers"]
    imsi = "001010000000077"
    collection.delete_many({"imsi": imsi})
    sqn = Int64(2**62 + 32)
    collection.insert_one(
        {
            "imsi": imsi,
            "security": {"k": "planted-k", "opc": "planted-opc", "amf": "8000", "sqn": sqn},
            "ambr": {"downlink": {"value": 1, "unit": 3}, "uplink": {"value": 1, "unit": 3}},
            "slice": [{"sst": 1, "default_indicator": True, "session": [{"name": "internet", "type": 3, "pcc_rule": []}]}],
        }
    )
    port = MongoSubscriberPort(_uri(), "open5g_int64", "subscribers", 2000, client=client)
    written = port.provision(
        imsi,
        {
            "apn": "internet",
            "qci": 6,
            "arp": {"priority": 5, "preemption_capability": "not_preempt", "preemption_vulnerability": "not_preemptable"},
            "ambr_ul": {"value": 1, "unit": "mbps"},
            "ambr_dl": {"value": 2, "unit": "mbps"},
            "mbr_ul": {"value": 1, "unit": "mbps"},
            "mbr_dl": {"value": 2, "unit": "mbps"},
            "gbr_ul": {"value": 0, "unit": "mbps"},
            "gbr_dl": {"value": 0, "unit": "mbps"},
            "app_rules": [],
        },
        role="student",
    )
    assert written["status"] == "written"
    assert "planted-k" not in str(written)
    stored = collection.find_one({"imsi": imsi})
    assert isinstance(stored["security"]["sqn"], Int64)
    assert stored["security"]["sqn"] == sqn
    assert stored["ambr"]["downlink"]["value"] == 1
    assert stored["slice"][0]["session"][0]["qos"]["index"] == 6
