"""Policy for the emulator screen. No database and no core."""

from datetime import datetime, timedelta, timezone

import pytest

from open5g_dashboard.domain import Actor, authorize_emulator
from open5g_dashboard.emulator import (
    build_upstream,
    clean_path,
    is_idle,
    origin_allowed,
    parse_targets,
    rewrite_location,
    safe_query,
)


def test_students_are_limited_to_their_assignment():
    student = Actor("student-a", "student", "group-a")
    assert authorize_emulator(student, "student-a").allow
    denied = authorize_emulator(student, "student-b")
    assert not denied.allow
    assert denied.status_code == 403
    assert denied.reason == "not_owner"
    assert not authorize_emulator(student, None).allow


def test_admin_and_instructor_can_open_any_ue():
    admin = Actor("admin", "admin", None)
    instructor = Actor("instructor", "instructor", "group-a")
    assert authorize_emulator(admin, "student-b").reason == "emulator_staff"
    assert authorize_emulator(instructor, "student-b").allow
    assert authorize_emulator(instructor, None).allow


def test_targets_reject_an_unspecified_address():
    parsed = parse_targets("ue1=192.0.2.32:8000, ue2=ue2.internal:8000")
    assert parsed["ue1"] == ("192.0.2.32", 8000)
    assert parsed["ue2"] == ("ue2.internal", 8000)
    with pytest.raises(ValueError):
        parse_targets("ue1=0.0.0.0:8000")
    with pytest.raises(ValueError):
        parse_targets("ue1=:::8000")
    with pytest.raises(ValueError):
        parse_targets("ue1=192.0.2.32")


def test_origin_csrf_query_and_idle_rules():
    assert origin_allowed("http://127.0.0.1:3000", ("http://127.0.0.1:3000",))
    assert not origin_allowed("http://evil.example", ("http://127.0.0.1:3000",))
    assert not origin_allowed(None, ("http://127.0.0.1:3000",))
    assert not origin_allowed("http://127.0.0.1:3000", ())
    assert safe_query("csrf=secret&path=1&password=no") == "path=1"
    assert clean_path("vnc.html") == "vnc.html"
    assert clean_path("../etc/passwd") is None
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert is_idle(now - timedelta(seconds=300), now, 300)
    assert not is_idle(now - timedelta(seconds=299), now, 300)
    assert build_upstream("192.0.2.32", 8000, "ue1", "vnc.html", "path=1", "http") == (
        "http://192.0.2.32:8000/emulator/ue1/vnc.html?path=1"
    )
    assert rewrite_location("http://192.0.2.32:8000/emulator/ue1/a", "http://192.0.2.32:8000", "/emulator/ue1") == (
        "/emulator/ue1/a"
    )
