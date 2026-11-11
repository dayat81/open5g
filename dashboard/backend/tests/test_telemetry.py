"""NF scrapes. HTTP is mocked. No Docker socket and no lab."""

import httpx

from open5g_dashboard.telemetry import HttpMetricsReader, combine_status, parse_endpoints


def _client(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_empty_configuration_is_not_a_failure():
    body = HttpMetricsReader((), 0.2).collect()
    assert body["status"] == "not_configured"
    assert body["configured"] is False
    names = {item["name"] for item in body["targets"]}
    assert {"smf", "upf", "upf-a", "upf-b"} <= names
    assert all(item["status"] == "not_configured" for item in body["targets"])


def test_one_down_nf_keeps_the_other_upfs():
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "smf.invalid":
            raise httpx.ConnectError("connection refused")
        if request.url.host == "upf-b.invalid":
            raise httpx.TimeoutException("timed out")
        body = 'ues_active{imsi="001010000000001"} 2\nprocess_open_fds 3\n'
        return httpx.Response(200, text=body)

    reader = HttpMetricsReader(
        (
            ("smf", "http://smf.invalid/metrics"),
            ("upf-a", "http://upf-a.invalid/metrics"),
            ("upf-b", "http://upf-b.invalid/metrics"),
        ),
        0.2,
        client=_client(handler),
    )
    body = reader.collect()
    assert body["status"] == "partial"
    by_name = {item["name"]: item for item in body["targets"]}
    assert by_name["smf"]["status"] == "down"
    assert by_name["upf-a"]["status"] == "reachable"
    assert by_name["upf-b"]["status"] == "down"
    assert by_name["upf-a"]["metric_names"] == ["ues_active", "process_open_fds"]
    assert "001010000000001" not in str(by_name["upf-a"])


def test_http_error_is_down_for_that_target_only():
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, text="unavailable")

    body = HttpMetricsReader((("mme", "http://mme.invalid/metrics"),), 0.2, client=_client(handler)).collect()
    assert body["status"] == "down"
    assert body["targets"][0]["error"] == "http_503"


def test_endpoint_parser_rejects_userinfo_and_merges_a_down_probe():
    try:
        parse_endpoints("smf=http://user:secret@metrics.invalid/metrics")
    except RuntimeError:
        pass
    else:
        raise AssertionError("userinfo was accepted")
    merged = combine_status(
        {"configured": False, "data_origin": "none", "targets": [{"name": "smf", "status": "not_configured"}], "note": "idle"},
        {"name": "mongo-subscriber", "status": "down", "error": "MongoDB timed out"},
    )
    assert merged["status"] == "down"
    assert merged["targets"][0]["name"] == "mongo-subscriber"
