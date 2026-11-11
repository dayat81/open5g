"""The dashboard web UI must not claim port 3000. That port is Grafana."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCAN_ROOTS = (
    ROOT / "dashboard",
    ROOT / "lab" / "compose" / "docker-compose.dashboard.optional.yml",
    ROOT / "lab" / "compose" / "dashboard.env.example",
    ROOT / "docs" / "deploy" / "dashboard-lab5g-dev.md",
    ROOT / "infra" / "roles" / "dashboard_optional",
    ROOT / "infra" / "group_vars" / "all" / "lab.yml",
    ROOT / ".github" / "workflows" / "dashboard.yml",
)
SKIP_DIR_NAMES = {".next", "node_modules", ".venv", "__pycache__", ".pytest_cache"}
SKIP_FILE_NAMES = {"package-lock.json"}
GRAFANA_PORT = re.compile(r"(?<![\d.])3000(?!\d)")  # Grafana keeps this port


def _files():
    for root in SCAN_ROOTS:
        if root.is_file():
            yield root
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if SKIP_DIR_NAMES.intersection(path.parts) or path.name in SKIP_FILE_NAMES:
                continue
            yield path


def test_dashboard_sources_leave_the_grafana_port_alone():
    hits: list[str] = []
    for path in _files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if "grafana" in line.lower():
                continue
            if GRAFANA_PORT.search(line):
                hits.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
    assert hits == []


def test_dashboard_web_default_port_is_3300():
    compose = (ROOT / "lab" / "compose" / "docker-compose.dashboard.optional.yml").read_text(encoding="utf-8")
    dockerfile = (ROOT / "dashboard" / "frontend" / "Dockerfile").read_text(encoding="utf-8")
    proxy = (ROOT / "dashboard" / "frontend" / "proxy.mjs").read_text(encoding="utf-8")
    assert "WEB_PORT:-3300" in compose
    assert "EXPOSE 3300" in dockerfile
    assert "WEB_PORT || process.env.PORT || 3300" in proxy
