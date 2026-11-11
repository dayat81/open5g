"""The emulator runbook must match the l5gd-screen and localhost:3301 design."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNBOOK = ROOT / "docs" / "deploy" / "android-emulator-dashboard.md"
SCREEN = ROOT / "lab" / "scripts" / "android-ue-screen.sh"
ROUTE = ROOT / "lab" / "scripts" / "android-ue-route.sh"


def test_emulator_runbook_matches_the_screen_network():
    text = RUNBOOK.read_text(encoding="utf-8")
    for banned in (
        "join the `uu` network",
        "http://127.0.0.1:8000",
        "Next rewrite",
        "forwarded the websocket",
        "server.host` to `UE*_UU`",
    ):
        assert banned not in text, banned
    for required in (
        "l5gd-screen",
        "UE*_SCREEN_ADDR",
        "http://localhost:3301",
        "127.0.0.1:3301",
        "WEB_PORT",
        "same browser profile",
        "127.0.0.1:5432",
        "dashboard-api",
        "101 Switching Protocols",
    ):
        assert required in text, required
    assert "uu address" not in SCREEN.read_text(encoding="utf-8")
    route = ROUTE.read_text(encoding="utf-8")
    assert "-i " in route
    assert "multiport" in route
    assert "name eth0" in route
    assert "--dport 5555" not in route
