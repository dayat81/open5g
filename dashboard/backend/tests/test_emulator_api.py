"""RBAC and proxy behavior for /emulator. The upstream is a local stub, not a core."""

import os
import socket
import threading
import time

import psycopg
import pytest
import uvicorn
from fastapi.testclient import TestClient
from psycopg.rows import dict_row
from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route, WebSocketRoute
from starlette.testclient import WebSocketDenialResponse
from starlette.websockets import WebSocketDisconnect

from open5g_dashboard.api import HASHER, create_app
from open5g_dashboard.db import apply_migrations, upsert_emulator_screen_status
from open5g_dashboard.emulator_http import create_screen_app, record_screen_probes
from open5g_dashboard.settings import Settings

DATABASE_URL = os.environ.get("OPEN5G_TEST_DATABASE_URL", "postgresql:///open5g_test")
PEPPER = "test-pepper-not-a-secret-value-32b"


def _settings(port: int) -> Settings:
    return Settings(
        DATABASE_URL,
        PEPPER,
        cookie_secure=False,
        enable_demo_routes=False,
        emulator_enabled=True,
        emulator_targets={},
        emulator_origins=("http://127.0.0.1:3300",),
        emulator_idle_seconds=300,
        emulator_probe_seconds=0.4,
        emulator_allowed_nets=("127.0.0.1/32",),
        emulator_screen_port=port,
        emulator_screen_origin="http://testserver",
        emulator_max_age_seconds=3600,
        emulator_watch_seconds=0.2,
    )


class _Caller:
    def __init__(self, client: TestClient, csrf: str):
        self.client = client
        self.csrf = csrf

    def post(self, path: str, body: dict | None = None):
        return self.client.post(path, json=body or {}, headers={"x-csrf-token": self.csrf})

    def put(self, path: str, body: dict):
        return self.client.put(path, json=body, headers={"x-csrf-token": self.csrf})


def _login(client: TestClient, email: str, password: str) -> _Caller:
    response = client.post("/api/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return _Caller(client, response.json()["csrf_token"])


def _upstream_app(hits: dict[str, int]) -> Starlette:
    async def page(request):
        hits["http"] += 1
        path = request.path_params.get("path", "")
        return PlainTextResponse("screen:" + path)

    async def socket(websocket):
        hits["ws"] += 1
        await websocket.accept()
        try:
            while True:
                message = await websocket.receive_text()
                await websocket.send_text("echo:" + message)
        except WebSocketDisconnect:
            return

    return Starlette(
        routes=[
            Route("/emulator/{ue_id}", page),
            Route("/emulator/{ue_id}/{path:path}", page),
            WebSocketRoute("/emulator/{ue_id}", socket),
            WebSocketRoute("/emulator/{ue_id}/{path:path}", socket),
        ]
    )


@pytest.fixture()
def upstream():
    hits = {"http": 0, "ws": 0}
    app = _upstream_app(hits)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, log_level="error", access_log=False))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), 0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        raise RuntimeError("screen stub did not start")
    yield port, hits
    server.should_exit = True
    thread.join(timeout=3)


@pytest.fixture()
def env(upstream):
    port, hits = upstream
    settings = _settings(port)
    password = "student-password-1"
    other_password = "student-password-2"
    instructor_password = "instructor-password"
    admin_password = "admin-password-xx"
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        apply_migrations(conn)
        conn.execute(
            """
            TRUNCATE emulator_screen_status, emulator_sessions, emulator_endpoints, audit_events, apply_targets, apply_jobs,
                     profile_versions, profiles, catalog_entries, sessions, imsi_assignments, users, groups
            RESTART IDENTITY CASCADE
            """
        )
        admin_id = conn.execute(
            """
            INSERT INTO users (email, display_name, role, group_id, password_hash)
            VALUES ('admin@example.test', 'Admin', 'admin', NULL, %s)
            RETURNING id
            """,
            (HASHER.hash(admin_password),),
        ).fetchone()["id"]
        group_a = conn.execute("INSERT INTO groups (name) VALUES ('kelas-a') RETURNING id").fetchone()["id"]
        group_b = conn.execute("INSERT INTO groups (name) VALUES ('kelas-b') RETURNING id").fetchone()["id"]
        student_id = conn.execute(
            """
            INSERT INTO users (email, display_name, role, group_id, password_hash)
            VALUES ('student-a@example.test', 'Student A', 'student', %s, %s)
            RETURNING id
            """,
            (group_a, HASHER.hash(password)),
        ).fetchone()["id"]
        other_id = conn.execute(
            """
            INSERT INTO users (email, display_name, role, group_id, password_hash)
            VALUES ('student-b@example.test', 'Student B', 'student', %s, %s)
            RETURNING id
            """,
            (group_b, HASHER.hash(other_password)),
        ).fetchone()["id"]
        instructor_id = conn.execute(
            """
            INSERT INTO users (email, display_name, role, group_id, password_hash)
            VALUES ('instructor-a@example.test', 'Instructor A', 'instructor', %s, %s)
            RETURNING id
            """,
            (group_a, HASHER.hash(instructor_password)),
        ).fetchone()["id"]
        assignment = conn.execute(
            """
            INSERT INTO imsi_assignments (imsi, owner_user_id, group_id, assigned_by)
            VALUES ('001010000000001', %s, %s, %s)
            RETURNING id
            """,
            (student_id, group_a, admin_id),
        ).fetchone()["id"]
        other_assignment = conn.execute(
            """
            INSERT INTO imsi_assignments (imsi, owner_user_id, group_id, assigned_by)
            VALUES ('001010000000002', %s, %s, %s)
            RETURNING id
            """,
            (other_id, group_b, admin_id),
        ).fetchone()["id"]
    app = create_app(settings)
    admin = _login(TestClient(app), "admin@example.test", admin_password)
    for ue_id, assignment_id in (("ue1", assignment), ("ue2", other_assignment)):
        stored = admin.put(
            f"/api/admin/emulator-endpoints/{ue_id}",
            {
                "assignment_id": str(assignment_id),
                "internal_host": "127.0.0.1",
                "internal_port": port,
                "apn": "internet",
                "attach_ipv4": "192.0.2.10" if ue_id == "ue1" else "192.0.2.11",
            },
        )
        assert stored.status_code == 200, stored.text
    with psycopg.connect(DATABASE_URL, row_factory=dict_row, autocommit=True) as conn:
        upsert_emulator_screen_status(conn, "ue1", "up")
        upsert_emulator_screen_status(conn, "ue2", "up")
    return {
        "app": app,
        "settings": settings,
        "port": port,
        "hits": hits,
        "admin": admin,
        "student": _login(TestClient(app), "student-a@example.test", password),
        "other": _login(TestClient(app), "student-b@example.test", other_password),
        "instructor": _login(TestClient(app), "instructor-a@example.test", instructor_password),
        "student_id": str(student_id),
        "instructor_id": str(instructor_id),
    }


def _screen(env, opened):
    screen = TestClient(create_screen_app(env["settings"]))
    url = opened.json()["screen_url"]
    path = url.split("http://testserver", 1)[1]
    response = screen.get(path, follow_redirects=False)
    assert response.status_code == 302, response.text
    assert "frame-ancestors http://127.0.0.1:3300" in response.headers["content-security-policy"]
    return screen


def _denied(call):
    with pytest.raises(WebSocketDenialResponse) as caught:
        with call:
            pass
    return caught.value


def test_anonymous_is_rejected_before_the_screen(env):
    bare = TestClient(env["app"])
    listing = bare.get("/api/emulator")
    assert listing.status_code == 401
    status = bare.get("/api/emulator/ue1")
    assert status.status_code == 401
    opened = bare.post("/api/emulator/ue1/session")
    assert opened.status_code == 401
    denied = _denied(TestClient(create_screen_app(env["settings"])).websocket_connect("/emulator/ue1/socket", headers={"origin": "http://testserver"}))
    assert denied.status_code == 401
    assert bare.get("/emulator/ue1/index.html").status_code == 404
    assert env["hits"]["ws"] == 0
    assert env["hits"]["http"] == 0


def test_user_cannot_open_another_users_ue(env):
    status = env["other"].client.get("/api/emulator/ue1")
    assert status.status_code == 403
    assert status.json()["error"]["code"] == "not_owner"
    opened = env["other"].post("/api/emulator/ue1/session")
    assert opened.status_code == 403
    listing = env["student"].client.get("/api/emulator")
    assert listing.status_code == 200
    assert [item["ue_id"] for item in listing.json()] == ["ue1"]
    allowed = env["student"].client.get("/api/emulator/ue1")
    assert allowed.status_code == 200
    body = allowed.json()
    assert body["attach_ipv4"] == "192.0.2.10"
    assert body["apn"] == "internet"
    assert body["screen"] == "up"
    assert "internal_host" not in body
    instructor = env["instructor"].client.get("/api/emulator/ue2")
    assert instructor.status_code == 403
    assert instructor.json()["error"]["code"] == "cross_group_forbidden"
    own = env["instructor"].client.get("/api/emulator/ue1")
    assert own.status_code == 200
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        row = conn.execute(
            "SELECT actor_id::text, resource FROM audit_events WHERE reason = 'not_owner' AND resource = 'emulator:ue1'"
        ).fetchone()
    assert row["resource"] == "emulator:ue1"


def test_wrong_origin_is_rejected_and_second_control_session_is_busy(env):
    first = env["student"].post("/api/emulator/ue1/session")
    assert first.status_code == 200, first.text
    assert first.json()["mode"] == "control"
    screen = _screen(env, first)
    denied = _denied(screen.websocket_connect("/emulator/ue1/socket", headers={"origin": "http://evil.example"}))
    assert denied.status_code == 403
    assert denied.json()["error"]["code"] == "origin_rejected"
    assert env["hits"]["ws"] == 0
    missing = _denied(TestClient(create_screen_app(env["settings"])).websocket_connect("/emulator/ue1/socket", headers={"origin": "http://testserver"}))
    assert missing.status_code == 401
    second = env["instructor"].post("/api/emulator/ue1/session")
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "emulator_control_busy"
    page = screen.get("/emulator/ue1/index.html")
    assert page.status_code == 200, page.text
    assert page.text == "screen:index.html"
    assert "127.0.0.1" not in page.text
    again = env["student"].post("/api/emulator/ue1/session")
    assert again.status_code == 200, again.text
    assert again.json()["replaced"] is True
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        open_rows = conn.execute("SELECT actor_id::text FROM emulator_sessions WHERE ue_id = 'ue1' AND closed_at IS NULL").fetchall()
    assert len(open_rows) == 1
    assert open_rows[0]["actor_id"] == env["student_id"]
    fresh = _screen(env, again)
    with fresh.websocket_connect("/emulator/ue1/socket", headers={"origin": "http://testserver"}) as socket:
        socket.send_text("ping")
        assert socket.receive_text() == "echo:ping"
    still_open = [{"?column?": 1}]
    closed = None
    audited = None
    for _ in range(20):
        with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
            still_open = conn.execute(
                "SELECT 1 FROM emulator_sessions WHERE ue_id = 'ue1' AND closed_at IS NULL"
            ).fetchall()
            closed = conn.execute(
                """
                SELECT close_reason FROM emulator_sessions
                WHERE ue_id = 'ue1' AND closed_at IS NOT NULL
                ORDER BY closed_at DESC
                """
            ).fetchone()
            if closed is not None and not still_open:
                audited = conn.execute(
                    """
                    SELECT reason FROM audit_events
                    WHERE action = 'emulator_close' AND resource = 'emulator:ue1' AND reason = %s
                    """,
                    (closed["close_reason"],),
                ).fetchone()
                break
        time.sleep(0.05)
    assert still_open == []
    assert closed["close_reason"] in {"client_close", "upstream_closed", "idle_timeout"}
    assert audited is not None


def test_idle_session_is_closed_and_a_down_screen_is_status_only(env):
    first = env["student"].post("/api/emulator/ue1/session")
    assert first.status_code == 200, first.text
    with psycopg.connect(DATABASE_URL) as conn:
        conn.execute("UPDATE emulator_sessions SET last_client_at = now() - interval '2 hours' WHERE closed_at IS NULL")
    taken = env["instructor"].post("/api/emulator/ue1/session")
    assert taken.status_code == 200, taken.text
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        idle = conn.execute(
            "SELECT actor_id::text, reason FROM audit_events WHERE action = 'emulator_close' AND reason = 'idle_timeout'"
        ).fetchone()
    assert idle["actor_id"] == env["student_id"]
    closed = env["instructor"].post("/api/emulator/ue1/session/close")
    assert closed.status_code == 200
    assert closed.json()["closed"] is True
    with psycopg.connect(DATABASE_URL) as conn:
        conn.execute("UPDATE emulator_endpoints SET internal_host = NULL, internal_port = NULL WHERE ue_id = 'ue1'")
    status = env["student"].client.get("/api/emulator/ue1")
    assert status.status_code == 200
    assert status.json()["screen"] == "down"
    assert status.json()["attach_ipv4"] == "192.0.2.10"
    blocked = env["student"].post("/api/emulator/ue1/session")
    assert blocked.status_code == 503
    assert blocked.json()["error"]["code"] == "emulator_down"
    assert "127.0.0.1" not in blocked.text
    assert "reset" not in blocked.text.lower()
    rejected = env["admin"].put(
        "/api/admin/emulator-endpoints/ue1",
        {"assignment_id": _assignment_id(env), "internal_host": "127.0.0.1", "internal_port": 1, "reset": True},
    )
    assert rejected.status_code == 400
    unspecified = env["admin"].put(
        "/api/admin/emulator-endpoints/ue1",
        {"assignment_id": _assignment_id(env), "internal_host": "0.0.0.0", "internal_port": 8000},
    )
    assert unspecified.status_code == 422


def _assignment_id(env) -> str:
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        return str(conn.execute("SELECT assignment_id FROM emulator_endpoints WHERE ue_id = 'ue1'").fetchone()["assignment_id"])


def test_instructor_socket_closes_when_their_group_changes(env):
    opened = env["instructor"].post("/api/emulator/ue1/session")
    assert opened.status_code == 200, opened.text
    screen = _screen(env, opened)
    with screen.websocket_connect("/emulator/ue1/socket", headers={"origin": "http://testserver"}) as socket:
        socket.send_text("ping")
        assert socket.receive_text() == "echo:ping"
        with psycopg.connect(DATABASE_URL) as conn:
            conn.execute(
                """
                UPDATE users
                SET group_id = (SELECT id FROM groups WHERE name = 'kelas-b')
                WHERE email = 'instructor-a@example.test'
                """
            )
        with pytest.raises(WebSocketDisconnect):
            socket.receive_text()
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        reason = conn.execute(
            "SELECT close_reason FROM emulator_sessions WHERE ue_id = 'ue1' ORDER BY opened_at DESC LIMIT 1"
        ).fetchone()
    assert reason["close_reason"] == "revoked"


def test_websocket_without_the_csrf_ticket_is_rejected(env):
    opened = env["student"].post("/api/emulator/ue1/session")
    assert opened.status_code == 200, opened.text
    screen = TestClient(create_screen_app(env["settings"]))
    bad = screen.get("/emulator/ue1/exchange?code=not-a-real-code")
    assert bad.status_code == 403
    assert bad.json()["error"]["code"] == "csrf_required"
    denied = _denied(screen.websocket_connect("/emulator/ue1/socket", headers={"origin": "http://testserver"}))
    assert denied.status_code == 401
    assert env["hits"]["ws"] == 0


def test_api_uses_the_listener_status_row(env):
    status = env["student"].client.get("/api/emulator/ue1")
    assert status.json()["screen"] == "up"
    with psycopg.connect(DATABASE_URL, row_factory=dict_row, autocommit=True) as conn:
        conn.execute("UPDATE emulator_screen_status SET checked_at = now() - interval '1 hour' WHERE ue_id = 'ue1'")
    stale = env["student"].client.get("/api/emulator/ue1")
    assert stale.status_code == 200
    assert stale.json()["screen"] == "down"
    blocked = env["student"].post("/api/emulator/ue1/session")
    assert blocked.status_code == 503
    with psycopg.connect(DATABASE_URL, row_factory=dict_row, autocommit=True) as conn:
        record_screen_probes(conn, env["settings"])
    fresh = env["student"].client.get("/api/emulator/ue1")
    assert fresh.json()["screen"] == "up"


def test_write_from_the_screen_origin_is_rejected(env):
    foreign = env["student"].client.post(
        "/api/emulator/ue1/session",
        json={},
        headers={"x-csrf-token": env["student"].csrf, "origin": "http://localhost:3301"},
    )
    assert foreign.status_code == 403
    assert foreign.json()["error"]["code"] == "origin_rejected"
    allowed = env["student"].client.post(
        "/api/emulator/ue1/session",
        json={},
        headers={"x-csrf-token": env["student"].csrf, "origin": "http://127.0.0.1:3300"},
    )
    assert allowed.status_code == 200, allowed.text


def test_repeated_session_posts_are_limited(env):
    last = None
    for _ in range(11):
        last = env["student"].post("/api/emulator/ue1/session")
    assert last is not None
    assert last.status_code == 429
    assert last.json()["error"]["code"] == "emulator_rate_limited"


def test_disabled_screen_stays_closed(env):
    disabled = Settings(
        DATABASE_URL,
        PEPPER,
        cookie_secure=False,
        enable_demo_routes=False,
        emulator_enabled=False,
    )
    client = TestClient(create_app(disabled))
    anonymous = client.get("/api/emulator/ue1")
    assert anonymous.status_code == 401
    logged = _login(client, "student-a@example.test", "student-password-1")
    hidden = logged.client.get("/api/emulator/ue1")
    assert hidden.status_code == 404
    assert hidden.json()["error"]["code"] == "emulator_disabled"
