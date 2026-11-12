"""Policy for the emulator screen. No database and no core."""

from datetime import datetime, timedelta, timezone

import pytest

from open5g_dashboard.domain import Actor, authorize_emulator
from open5g_dashboard.emulator import (
    build_upstream,
    clean_path,
    is_idle,
    origin_allowed,
    origins_are_isolated,
    parse_screen_mode,
    parse_screen_upstream,
    parse_targets,
    rewrite_location,
    safe_query,
    session_expired,
)


def test_students_are_limited_to_their_assignment():
    student = Actor("student-a", "student", "group-a")
    assert authorize_emulator(student, "student-a", "group-a").allow
    denied = authorize_emulator(student, "student-b", "group-b")
    assert not denied.allow
    assert denied.status_code == 403
    assert denied.reason == "not_owner"
    assert not authorize_emulator(student, None, None).allow


def test_instructor_is_limited_to_their_own_group():
    instructor = Actor("instructor", "instructor", "group-a")
    assert authorize_emulator(instructor, "student-a", "group-a").allow
    denied = authorize_emulator(instructor, "student-b", "group-b")
    assert denied.status_code == 403
    assert denied.reason == "cross_group_forbidden"
    admin = Actor("admin", "admin", None)
    assert authorize_emulator(admin, "student-b", "group-b").allow


def test_targets_stay_inside_the_screen_allowlist():
    nets = ("192.0.2.0/24",)
    parsed = parse_targets("ue1=192.0.2.32:8000", nets, 8000)
    assert parsed["ue1"] == ("192.0.2.32", 8000)
    with pytest.raises(ValueError):
        parse_targets("ue1=0.0.0.0:8000", nets, 8000)
    with pytest.raises(ValueError):
        parse_targets("ue1=198.51.100.10:8000", nets, 8000)
    with pytest.raises(ValueError):
        parse_targets("ue1=ue1.internal:8000", nets, 8000)
    with pytest.raises(ValueError):
        parse_targets("ue1=192.0.2.32:27017", nets, 8000)


def test_host_agen_upstream_stays_on_loopback():
    assert parse_screen_mode("") == "guest"
    assert parse_screen_mode("guest") == "guest"
    assert parse_screen_mode("host-agen") == "host-agen"
    with pytest.raises(ValueError):
        parse_screen_mode("public")
    assert parse_screen_upstream("") is None
    assert parse_screen_upstream("http://127.0.0.1:3302/") == ("127.0.0.1", 3302)
    assert parse_screen_upstream("ws://127.0.0.1:3302") == ("127.0.0.1", 3302)
    for raw in (
        "http://0.0.0.0:3301",
        "http://198.51.100.10:3301",
        "http://localhost:3301",
        "http://127.0.0.1:3301/emulator/ue1",
        "http://user:secret@127.0.0.1:3301",
    ):
        with pytest.raises(ValueError):
            parse_screen_upstream(raw)


def test_origin_csrf_query_and_idle_rules():
    assert origin_allowed("http://127.0.0.1:3300", ("http://127.0.0.1:3300",))
    assert not origin_allowed("http://evil.example", ("http://127.0.0.1:3300",))
    assert not origin_allowed(None, ("http://127.0.0.1:3300",))
    assert not origin_allowed("http://127.0.0.1:3300", ())
    assert safe_query("csrf=secret&path=1&password=no") == "path=1"
    assert clean_path("vnc.html") == "vnc.html"
    assert clean_path("../etc/passwd") is None
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert is_idle(now - timedelta(seconds=300), now, 300)
    assert not is_idle(now - timedelta(seconds=299), now, 300)
    assert session_expired(now - timedelta(seconds=10), now - timedelta(seconds=300), now, 300, 3600) == "idle_timeout"
    assert session_expired(now - timedelta(seconds=3600), now, now, 300, 3600) == "absolute_timeout"
    assert origins_are_isolated("http://localhost:3301", ("http://127.0.0.1:3300",))
    assert not origins_are_isolated("http://127.0.0.1:3301", ("http://127.0.0.1:3300",))
    assert build_upstream("192.0.2.32", 8000, "ue1", "vnc.html", "path=1", "http") == (
        "http://192.0.2.32:8000/emulator/ue1/vnc.html?path=1"
    )
    assert rewrite_location("http://192.0.2.32:8000/emulator/ue1/a", "http://192.0.2.32:8000", "/emulator/ue1") == (
        "/emulator/ue1/a"
    )
