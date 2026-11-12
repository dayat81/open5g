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
    screen = SCREEN.read_text(encoding="utf-8")
    assert "ANDROID_ADB_SERVER_PORT=5038" in screen
    assert 'adb_target="${ANDROID_UE_UU}:5555"' in screen
    assert 'adb_target=127.0.0.1:5555' in screen
    assert "adb -P 5037" not in screen
    route = ROUTE.read_text(encoding="utf-8")
    assert "ANDROID_UE_ADB" in route
    assert "-A INPUT -j" in route
    assert "-P INPUT" not in route
    assert "name eth0" not in route


def test_dashboard_api_does_not_join_ue_networks():
    text = (ROOT / "lab" / "compose" / "docker-compose.dashboard.optional.yml").read_text(encoding="utf-8")
    body = text.split("  dashboard-api:", 1)[1].split("  dashboard-web:", 1)[0]
    assert "l5gd-screen" not in body
    assert "uu" not in body
    assert "networks: [dashboard, mgmt]" in body
