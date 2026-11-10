"""NF scrape port.

No Docker socket is opened. An empty endpoint list is ``not_configured``,
which is not a scrape failure. A configured endpoint that times out or
refuses the connection is ``down`` for that target only.
"""

from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any
from urllib.parse import urlsplit

import httpx

# Names the lab may expose. upf-a and upf-b are the live slicing PoC labels;
# a configured endpoint list replaces this static inventory.
DEFAULT_TARGETS = (
    "mongo",
    "hss",
    "pcrf",
    "mme",
    "sgwc",
    "sgwu",
    "smf",
    "upf",
    "upf-a",
    "upf-b",
)
_NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
_METRIC_NAME = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)")
_NOT_CONFIGURED_NOTE = (
    "No Prometheus metrics server is configured. "
    "Upstream Open5GS documents metrics for MME and SMF; this EPC lab has no AMF. "
    "HSS, PCRF, SGW, and UPF are not claimed to export metrics. "
    "Enabling a metrics block is a separate lab change."
)


def parse_endpoints(raw: str) -> tuple[tuple[str, str], ...]:
    text = raw.strip()
    if not text:
        return ()
    items: list[tuple[str, str]] = []
    seen: set[str] = set()
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise RuntimeError("NF endpoint entries must be name=url pairs")
        name, url = part.split("=", 1)
        name = name.strip().lower()
        url = url.strip()
        if not _NAME.fullmatch(name) or name in seen:
            raise RuntimeError("NF endpoint name is invalid or duplicated")
        parsed = urlsplit(url)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
            raise RuntimeError("NF endpoint URL must be http(s) and must not carry userinfo")
        seen.add(name)
        items.append((name, url))
    return tuple(items)


def merge_endpoints(*groups: tuple[tuple[str, str], ...]) -> tuple[tuple[str, str], ...]:
    merged: list[tuple[str, str]] = []
    seen: set[str] = set()
    for group in groups:
        for name, url in group:
            if name in seen:
                raise RuntimeError("NF endpoint name is invalid or duplicated")
            seen.add(name)
            merged.append((name, url))
    return tuple(merged)


def _metric_names(body: str) -> list[str]:
    names: list[str] = []
    for line in body.splitlines():
        if not line or line.startswith("#"):
            continue
        match = _METRIC_NAME.match(line)
        if match and match.group(1) not in names:
            names.append(match.group(1))
        if len(names) >= 32:
            break
    return names


def _overall(targets: list[dict[str, Any]]) -> tuple[str, bool]:
    states = {str(target["status"]) for target in targets}
    if "down" in states and "reachable" in states:
        return "partial", True
    if "down" in states:
        return "down", False
    if "reachable" in states and states == {"reachable"}:
        return "reachable", False
    if "reachable" in states:
        return "partial", True
    if states == {"not_configured"}:
        return "not_configured", False
    return "partial", True


class HttpMetricsReader:
    def __init__(self, endpoints: tuple[tuple[str, str], ...], timeout_s: float, client: httpx.Client | None = None):
        self._endpoints = endpoints
        self._timeout = timeout_s
        self._client = client

    def collect(self) -> dict[str, Any]:
        if not self._endpoints:
            targets = [
                {"name": name, "status": "not_configured", "error": None, "http_status": None, "metric_names": []}
                for name in DEFAULT_TARGETS
            ]
            status, partial = _overall(targets)
            return {
                "configured": False,
                "status": status,
                "partial": partial,
                "data_origin": "none",
                "targets": targets,
                "note": _NOT_CONFIGURED_NOTE,
            }
        client = self._client or httpx.Client(timeout=self._timeout, follow_redirects=False)
        close = self._client is None
        try:
            workers = min(8, len(self._endpoints))
            with ThreadPoolExecutor(max_workers=workers) as pool:
                targets = list(pool.map(lambda item: self._scrape(client, item[0], item[1]), self._endpoints))
        finally:
            if close:
                client.close()
        status, partial = _overall(targets)
        return {
            "configured": True,
            "status": status,
            "partial": partial,
            "data_origin": "prometheus",
            "targets": targets,
            "note": "One down NF does not drop the other targets.",
        }

    def _scrape(self, client: httpx.Client, name: str, url: str) -> dict[str, Any]:
        try:
            response = client.get(url, timeout=self._timeout)
        except Exception as exc:
            return {
                "name": name,
                "status": "down",
                "error": type(exc).__name__,
                "http_status": None,
                "metric_names": [],
            }
        if response.status_code != 200:
            return {
                "name": name,
                "status": "down",
                "error": f"http_{response.status_code}",
                "http_status": response.status_code,
                "metric_names": [],
            }
        return {
            "name": name,
            "status": "reachable",
            "error": None,
            "http_status": 200,
            "metric_names": _metric_names(response.text),
        }


def build_metrics_reader(settings) -> HttpMetricsReader:
    return HttpMetricsReader(settings.metrics_endpoints, settings.metrics_timeout_s)


def combine_status(metrics: dict[str, Any], probe: dict[str, Any]) -> dict[str, Any]:
    """Merge the subscriber-store probe with NF scrapes. A down probe does not raise."""
    targets = [probe, *metrics.get("targets", [])]
    status, partial = _overall(targets)
    configured = bool(metrics.get("configured")) or probe.get("status") != "not_configured"
    return {
        "configured": configured,
        "status": status,
        "partial": partial,
        "data_origin": metrics.get("data_origin", "none"),
        "targets": targets,
        "note": metrics.get("note", ""),
    }
