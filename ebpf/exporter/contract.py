"""Prometheus text for bounded app counters.

This module does not open a BPF map, a socket, or a network interface.
A rendered sample is labeled data_origin=stub and is not measured traffic.
"""

from __future__ import annotations

ALLOWED_LABELS = {
    "source",
    "exporter_instance",
    "interface",
    "capture_point",
    "rule_version",
    "data_origin",
}
FORBIDDEN_LABELS = {"imsi", "sni", "hostname", "flow", "ue_ip", "app_pattern"}


class LabelError(ValueError):
    def __init__(self, rejected: list[str]):
        super().__init__("metric labels must stay inside the bounded aggregate set")
        self.rejected = rejected


def render_prometheus(series: list[dict]) -> str:
    lines: list[str] = []
    for item in series:
        labels: dict[str, str] = item["labels"]
        rejected = sorted((set(labels) - ALLOWED_LABELS) | (set(labels) & FORBIDDEN_LABELS))
        if rejected:
            raise LabelError(rejected)
        if labels.get("data_origin") not in {"stub", "ebpf"}:
            raise LabelError(["data_origin"])
        rendered = ",".join(f'{key}="{labels[key]}"' for key in sorted(labels))
        lines.append(f"{item['name']}{{{rendered}}} {int(item['value'])}")
    return ("\n".join(lines) + "\n") if lines else ""


def stub_series() -> list[dict]:
    return [
        {
            "name": "open5g_app_bytes_total",
            "value": 0,
            "labels": {
                "source": "ebpf",
                "exporter_instance": "not-running",
                "interface": "unspecified",
                "capture_point": "unspecified",
                "rule_version": "none",
                "data_origin": "stub",
            },
        }
    ]
