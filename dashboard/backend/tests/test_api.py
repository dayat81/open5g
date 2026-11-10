"""HTTP authorization and apply behavior against PostgreSQL."""

import json
import secrets
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.rows import dict_row
from psycopg.types.json import Json

from open5g_dashboard.api import HASHER, create_app
from open5g_dashboard.db import apply_migrations
from open5g_dashboard.settings import Settings

DATABASE_URL = "postgresql:///open5g_test"
PEPPER = "test-pepper-not-a-secret-value-32b"
PLANTED_KI = "PLANTED-KI-VALUE-not-a-real-key"


def sample_content(**overrides):
    data = {
        "apn": "internet",
        "logical_slice_template": "slice-class-a",
        "qci": 6,
        "arp": {
            "priority": 5,
            "preemption_capability": "not_preempt",
            "preemption_vulnerability": "not_preemptable",
        },
        "ambr_ul": {"value": 50, "unit": "mbps"},
        "ambr_dl": {"value": 100, "unit": "mbps"},
        "mbr_ul": {"value": 20, "unit": "mbps"},
        "mbr_dl": {"value": 40, "unit": "mbps"},
        "gbr_ul": {"value": 5, "unit": "mbps"},
        "gbr_dl": {"value": 10, "unit": "mbps"},
        "app_rules": [
            {
                "match_type": "ip",
                "pattern": "203.0.113.0/24",
                "app_id": "bulk-dl",
                "logical_slice": "slice-class-a",
                "enabled": True,
                "precedence": 20,
            }
        ],
        "usage": {
            "scope": "app",
            "app_id": "bulk-dl",
            "threshold": 500,
            "unit": "MB",
            "window_seconds": 300,
        },
    }
    data.update(overrides)
    return data


@pytest.fixture()
def env():
    password = secrets.token_urlsafe(18)
    settings = Settings(DATABASE_URL, PEPPER, cookie_secure=False, enable_demo_routes=False)
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        apply_migrations(conn)
        again = apply_migrations(conn)
        assert again == []
        conn.execute(
            """
            TRUNCATE audit_events, apply_targets, apply_jobs, profile_versions, profiles,
                     catalog_entries, sessions, imsi_assignments, users, groups
            RESTART IDENTITY CASCADE
            """
        )
        conn.execute(
            "INSERT INTO users (email, display_name, role, group_id, password_hash) VALUES (%s, %s, 'admin', NULL, %s)",
            ("admin@example.test", "Admin", HASHER.hash(password)),
        )
    admin_client = TestClient(create_app(settings))
    login = admin_client.post("/api/auth/login", json={"email": "admin@example.test", "password": password})
    assert login.status_code == 200, login.text
    admin = _Caller(admin_client, login.json()["csrf_token"])
    group_a = admin.post("/api/admin/groups", {"name": "kelas-5g-a"}).json()["id"]
    group_b = admin.post("/api/admin/groups", {"name": "kelas-5g-b"}).json()["id"]
    student_password = secrets.token_urlsafe(18)
    other_password = secrets.token_urlsafe(18)
    instructor_password = secrets.token_urlsafe(18)
    student_id = admin.post(
        "/api/admin/users",
        {"email": "student-a@example.test", "display_name": "Student A", "role": "student", "group_id": group_a, "password": student_password},
    ).json()["id"]
    other_id = admin.post(
        "/api/admin/users",
        {"email": "student-b@example.test", "display_name": "Student B", "role": "student", "group_id": group_b, "password": other_password},
    ).json()["id"]
    instructor_id = admin.post(
        "/api/admin/users",
        {"email": "instructor-a@example.test", "display_name": "Instructor A", "role": "instructor", "group_id": group_a, "password": instructor_password},
    ).json()["id"]
    assignment = admin.post(
        "/api/admin/assignments",
        {"imsi": "001010000000001", "owner_user_id": student_id, "group_id": group_a},
    ).json()
    other_assignment = admin.post(
        "/api/admin/assignments",
        {"imsi": "001010000000002", "owner_user_id": other_id, "group_id": group_b},
    ).json()
    return {
        "client": admin_client,
        "admin": admin,
        "settings": settings,
        "student": _login(TestClient(create_app(settings)), "student-a@example.test", student_password),
        "other": _login(TestClient(create_app(settings)), "student-b@example.test", other_password),
        "instructor": _login(TestClient(create_app(settings)), "instructor-a@example.test", instructor_password),
        "student_id": student_id,
        "instructor_id": instructor_id,
        "assignment": assignment,
        "other_assignment": other_assignment,
        "login_response": login,
        "student_password": student_password,
    }


class _Caller:
    def __init__(self, client: TestClient, csrf: str):
        self.client = client
        self.csrf = csrf

    def headers(self, etag: str | None = None, key: str | None = None):
        headers = {"x-csrf-token": self.csrf}
        if etag:
            headers["if-match"] = etag
        if key:
            headers["idempotency-key"] = key
        return headers

    def post(self, path: str, body: dict, etag: str | None = None, key: str | None = None):
        return self.client.post(path, json=body, headers=self.headers(etag, key))

    def put(self, path: str, body: dict, etag: str):
        return self.client.put(path, json=body, headers=self.headers(etag))


def _login(client: TestClient, email: str, password: str) -> _Caller:
    response = client.post("/api/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return _Caller(client, response.json()["csrf_token"])


def _profile(env, caller, assignment_id: str):
    created = caller.post("/api/profiles", {"assignment_id": assignment_id, "content": sample_content()})
    assert created.status_code == 201, created.text
    return created.json()


def test_session_cookie_is_httponly_and_csrf_is_readable(env):
    cookies = env["login_response"].headers.get_list("set-cookie")
    session = next(item for item in cookies if item.startswith("open5g_session="))
    csrf = next(item for item in cookies if item.startswith("open5g_csrf="))
    assert "HttpOnly" in session
    assert "HttpOnly" not in csrf
    assert "Secure" not in session
    missing = env["student"].post("/api/profiles", {"assignment_id": env["assignment"]["id"], "content": sample_content()})
    # student caller includes csrf; a fresh client without the header is checked below
    bare = TestClient(create_app(env["settings"]))
    bare.cookies.update(env["client"].cookies)
    denied = bare.post("/api/profiles", json={"assignment_id": env["assignment"]["id"], "content": sample_content()})
    assert denied.status_code == 403
    assert denied.json()["error"]["code"] == "csrf_required"
    assert missing.status_code == 201


def test_object_authz_group_boundary_and_audit(env):
    owned = _profile(env, env["student"], env["assignment"]["id"])
    other = env["other"].client.get(f"/api/profiles/{owned['id']}")
    assert other.status_code == 403
    assert other.json()["error"]["code"] == "not_owner"
    cross = env["instructor"].client.get(f"/api/profiles/{owned['id']}")
    # instructor is in group A, profile is group A, so this is allowed
    assert cross.status_code == 200
    foreign = _profile(env, env["other"], env["other_assignment"]["id"])
    blocked = env["instructor"].client.get(f"/api/profiles/{foreign['id']}")
    assert blocked.status_code == 403
    assert blocked.json()["error"]["code"] == "cross_group_forbidden"
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        row = conn.execute(
            "SELECT actor_id::text, owner_user_id::text, reason FROM audit_events WHERE reason = 'cross_group_forbidden'"
        ).fetchone()
    assert row["actor_id"] == env["instructor_id"]
    assert row["owner_user_id"] == foreign["owner_user_id"]
    admin_edit = env["admin"].put(f"/api/profiles/{owned['id']}", sample_content(), owned["version_etag"])
    assert admin_edit.status_code == 403
    assert admin_edit.json()["error"]["code"] == "admin_profile_control_forbidden"
    listed = env["student"].client.get("/api/profiles?owner_user_id=" + env["student_id"])
    assert listed.status_code == 400
    assert listed.json()["error"]["code"] == "client_scope_override_rejected"


def test_secrets_versions_limits_and_units(env):
    created = _profile(env, env["student"], env["assignment"]["id"])
    planted = sample_content()
    planted["ki"] = PLANTED_KI
    secret = env["student"].put(f"/api/profiles/{created['id']}", planted, created["version_etag"])
    assert secret.status_code == 400
    assert secret.json()["error"]["code"] == "secret_field_rejected"
    assert PLANTED_KI not in secret.text
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        blob = conn.execute("SELECT detail::text FROM audit_events WHERE reason = 'secret_field_rejected'").fetchone()["detail"]
    assert PLANTED_KI not in blob
    assert "[redacted]" in blob
    conflict_body = sample_content(qci=7)
    first = env["student"].put(f"/api/profiles/{created['id']}", conflict_body, created["version_etag"])
    assert first.status_code == 200, first.text
    stale = env["student"].put(f"/api/profiles/{created['id']}", sample_content(qci=8), created["version_etag"])
    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "version_conflict"
    too_big = sample_content(gbr_dl={"value": 50, "unit": "mbps"}, mbr_dl={"value": 40, "unit": "mbps"})
    invalid = env["student"].put(f"/api/profiles/{created['id']}", too_big, first.json()["version_etag"])
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "gbr_exceeds_mbr"
    env["admin"].post(
        "/api/admin/catalog",
        {"kind": "ambr_cap", "name": "example-downlink", "max_ambr_dl_bps": 1000, "enforced": False, "example_pending_environment_sizing": True},
    )
    warned = env["student"].put(f"/api/profiles/{created['id']}", sample_content(), first.json()["version_etag"])
    assert warned.status_code == 200
    assert any(item.startswith("example_limit_exceeded_not_enforced:") for item in warned.json()["warnings"])
    env["admin"].post(
        "/api/admin/catalog",
        {"kind": "ambr_cap", "name": "enforced-downlink", "max_ambr_dl_bps": 1000, "enforced": True, "example_pending_environment_sizing": True},
    )
    blocked = env["student"].put(f"/api/profiles/{created['id']}", sample_content(), warned.json()["version_etag"])
    assert blocked.status_code == 422
    assert blocked.json()["error"]["code"] == "catalog_limit_exceeded"


def test_apply_reject_idempotency_reattach_and_rollback(env):
    created = _profile(env, env["student"], env["assignment"]["id"])
    early = env["student"].post(f"/api/profiles/{created['id']}/apply", {}, etag=created["version_etag"], key="too-soon")
    assert early.status_code == 409
    assert early.json()["error"]["code"] == "not_validated"
    validated = env["student"].client.post(
        f"/api/profiles/{created['id']}/validate",
        headers=env["student"].headers(created["version_etag"]),
    )
    assert validated.status_code == 200
    assert validated.json()["lifecycle"] == "validated"
    applied = env["student"].post(
        f"/api/profiles/{created['id']}/apply",
        {"client_note": "a"},
        etag=created["version_etag"],
        key="apply-1",
    )
    assert applied.status_code == 409
    body = applied.json()
    assert body["status"] == "rejected"
    assert body["executed"] is False
    assert body["core_restart"] is False
    assert body["data_origin"] == "none"
    assert "active" != body["status"]
    assert "pushed" != body["status"]
    assert any(reason["op"] == "apn_ambr_rar" and reason["capability"] == "unsupported" for reason in body["reasons"])
    assert any(reason["op"] == "gx_rar" and reason["capability"] == "not_integrated" for reason in body["reasons"])
    assert {target["state"] for target in body["targets"]} == {"not_executed"}
    assert all(target["applied_version"] is None for target in body["targets"])
    replay = env["student"].post(
        f"/api/profiles/{created['id']}/apply",
        {"client_note": "a"},
        etag=created["version_etag"],
        key="apply-1",
    )
    assert replay.status_code == 200
    assert replay.json()["id"] == body["id"]
    assert replay.json()["idempotent_replay"] is True
    conflict = env["student"].post(
        f"/api/profiles/{created['id']}/apply",
        {"client_note": "b"},
        etag=created["version_etag"],
        key="apply-1",
    )
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "idempotency_conflict"
    notice = env["student"].post(f"/api/profiles/{created['id']}/reattach-notice", {})
    assert notice.json()["executed"] is False
    refused = env["student"].post(
        f"/api/profiles/{created['id']}/reattach",
        {"confirm_disruption": False, "notice_id": "nope"},
        key="reattach-1",
    )
    assert refused.status_code == 400
    confirmed = env["student"].post(
        f"/api/profiles/{created['id']}/reattach",
        {"confirm_disruption": True, "notice_id": notice.json()["notice_id"]},
        key="reattach-2",
    )
    assert confirmed.status_code == 409
    assert confirmed.json()["path"] == "reattach_fallback"
    assert confirmed.json()["executed"] is False
    assert confirmed.json()["core_restart"] is False
    rolled = env["student"].post(
        f"/api/profiles/{created['id']}/rollback",
        {"to_version": 1},
        etag=created["version_etag"],
        key="rollback-1",
    )
    assert rolled.status_code == 409, rolled.text
    assert rolled.json()["traffic_undone"] is False
    assert rolled.json()["profile"]["desired_version"] == 2
    assert rolled.json()["job"]["status"] == "rejected"
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        with pytest.raises(psycopg.errors.RaiseException):
            conn.execute("UPDATE profile_versions SET action = 'tamper'")
        conn.rollback()
        with pytest.raises(psycopg.errors.RaiseException):
            conn.execute("DELETE FROM audit_events")


def test_existing_bearer_qos_change_is_rejected_and_not_marked_applied(env):
    created = _profile(env, env["instructor"], env["assignment"]["id"])
    env["instructor"].client.post(
        f"/api/profiles/{created['id']}/validate",
        headers=env["instructor"].headers(created["version_etag"]),
    )
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        conn.execute(
            "UPDATE profiles SET applied_content = content, applied_version = desired_version WHERE id = %s",
            (created["id"],),
        )
    changed = sample_content(qci=7)
    saved = env["instructor"].put(f"/api/profiles/{created['id']}", changed, created["version_etag"])
    assert saved.status_code == 200, saved.text
    validated = env["instructor"].client.post(
        f"/api/profiles/{saved.json()['id']}/validate",
        headers=env["instructor"].headers(saved.json()["version_etag"]),
    )
    applied = env["instructor"].post(
        f"/api/profiles/{created['id']}/apply",
        {},
        etag=validated.json()["version_etag"],
        key="qci-1",
    )
    names = {reason["op"] for reason in applied.json()["reasons"]}
    assert "modify_qci_existing_bearer" in names
    current = env["instructor"].client.get(f"/api/profiles/{created['id']}")
    assert current.json()["lifecycle"] == "validated"
    assert current.json()["applied_content"]["qci"] == 6
    assert current.json()["content"]["qci"] == 7


def test_core_control_and_metric_stub_and_demo_isolation(env):
    restart = env["student"].post("/api/core/restart", {})
    assert restart.status_code == 403
    assert restart.json()["error"]["code"] == "core_control_forbidden"
    admin_restart = env["admin"].post("/api/core/restart", {})
    assert admin_restart.status_code == 501
    assert admin_restart.json()["error"]["code"] == "core_control_not_implemented"
    own = env["student"].client.get("/api/metrics/drilldown", params={"assignment_id": env["assignment"]["id"]})
    assert own.status_code == 200
    assert own.json()["data_origin"] == "stub"
    assert own.json()["fake"] is True
    assert own.json()["series"] == []
    assert "imsi" not in json.dumps(own.json()["series"])
    foreign = env["student"].client.get("/api/metrics/drilldown", params={"assignment_id": env["other_assignment"]["id"]})
    assert foreign.status_code == 403
    hidden = env["client"].get("/api/demo/sample")
    assert hidden.status_code == 404
    demo = TestClient(create_app(Settings(DATABASE_URL, PEPPER, False, True)))
    sample = demo.get("/api/demo/sample")
    assert sample.status_code == 200
    assert sample.json()["fake"] is True
    assert sample.json()["data_origin"] == "sample"
    health = env["client"].get("/health")
    assert health.json() == {"status": "ok", "core": "not_checked"}


def test_migration_file_is_the_one_applied():
    sql = Path("migrations/001_init.sql").read_text()
    assert "CREATE TABLE profiles" in sql
    assert "open5g_forbid_mutation" in sql


def test_core_status_is_not_configured_until_endpoints_exist(env):
    bare = TestClient(create_app(env["settings"]))
    assert bare.get("/api/core/status").status_code == 401
    status = env["student"].client.get("/api/core/status")
    assert status.status_code == 200, status.text
    body = status.json()
    assert body["status"] == "not_configured"
    assert body["gx_rar_enabled"] is False
    assert body["gx_rar_effective"] is False
    assert body["docker_socket"] == "not_used"
    assert body["multiple_upf_supported"] is True
    names = {item["name"]: item["status"] for item in body["targets"]}
    assert names["smf"] == "not_configured"
    assert names["upf-a"] == "not_configured"
    assert names["upf-b"] == "not_configured"
    assert names["mongo-subscriber"] == "not_configured"


def test_core_status_reports_down_nfs_without_failing(env):
    class PartialReader:
        def collect(self):
            return {
                "configured": True,
                "status": "partial",
                "partial": True,
                "data_origin": "prometheus",
                "targets": [
                    {"name": "smf", "status": "down", "error": "ConnectError", "http_status": None, "metric_names": []},
                    {"name": "upf-a", "status": "reachable", "error": None, "http_status": 200, "metric_names": ["ues_active"]},
                    {"name": "upf-b", "status": "down", "error": "TimeoutException", "http_status": None, "metric_names": []},
                ],
                "note": "One down NF does not drop the other targets.",
            }

    client = TestClient(create_app(env["settings"], metrics_reader=PartialReader()))
    caller = _login(client, "student-a@example.test", env["student_password"])
    status = caller.client.get("/api/core/status")
    assert status.status_code == 200, status.text
    body = status.json()
    assert body["status"] == "partial"
    by_name = {item["name"]: item["status"] for item in body["targets"]}
    assert by_name["smf"] == "down"
    assert by_name["upf-a"] == "reachable"
    assert by_name["upf-b"] == "down"


def test_provision_writes_mongo_and_keeps_credentials_and_extra_upf(env):
    mongomock = __import__("mongomock")
    mongo = mongomock.MongoClient()
    planted = "PLANTED-KI-VALUE-not-a-real-key"
    mongo["open5gs"]["subscribers"].insert_one(
        {
            "imsi": "001010000000001",
            "security": {"k": planted, "opc": "PLANTED-OPC-VALUE-not-a-real-opc", "amf": "8000"},
            "slice": [
                {
                    "sst": 1,
                    "default_indicator": True,
                    "session": [
                        {"name": "internet", "type": 3, "pcc_rule": []},
                        {"name": "upf-b", "type": 3, "pcc_rule": []},
                    ],
                }
            ],
        }
    )
    from open5g_dashboard.subscriber_port import MongoSubscriberPort

    port = MongoSubscriberPort("mongodb://mongo.invalid/open5gs", "open5gs", "subscribers", 2000, client=mongo)
    student = _login(TestClient(create_app(env["settings"], subscriber_port=port)), "student-a@example.test", env["student_password"])
    hidden = env["other"].client.get(f"/api/assignments/{env['assignment']['id']}/subscriber")
    assert hidden.status_code == 403
    created = student.post("/api/profiles", {"assignment_id": env["assignment"]["id"], "content": sample_content()})
    assert created.status_code == 201, created.text
    refused = student.post(f"/api/profiles/{created.json()['id']}/provision", {}, etag=created.json()["version_etag"])
    assert refused.status_code == 409
    assert refused.json()["error"]["code"] == "not_validated"
    validated = student.client.post(
        f"/api/profiles/{created.json()['id']}/validate",
        headers=student.headers(created.json()["version_etag"]),
    )
    assert validated.status_code == 200, validated.text
    written = student.post(
        f"/api/profiles/{created.json()['id']}/provision",
        {},
        etag=validated.json()["version_etag"],
    )
    assert written.status_code == 200, written.text
    body = written.json()
    assert body["status"] == "written"
    assert body["live_gx_rar"] is False
    assert body["postgres_lifecycle_unchanged"] is True
    assert body["session_effect"] == "not_pushed_to_active_session"
    assert planted not in written.text
    assert body["subscriber"]["credentials_present"] is True
    assert body["subscriber"]["session_count"] == 2
    stored = mongo["open5gs"]["subscribers"].find_one({"imsi": "001010000000001"})
    assert stored["security"]["k"] == planted
    assert [item["name"] for item in stored["slice"][0]["session"]] == ["internet", "upf-b"]
    current = student.client.get(f"/api/profiles/{created.json()['id']}")
    assert current.json()["lifecycle"] == "validated"
    assert current.json()["applied_content"] is None
    denied_admin = env["admin"].post(
        f"/api/profiles/{created.json()['id']}/provision",
        {},
        etag=validated.json()["version_etag"],
    )
    assert denied_admin.status_code == 403
    again = student.client.get(f"/api/assignments/{env['assignment']['id']}/subscriber")
    assert again.status_code == 200
    assert again.json()["found"] is True
    assert planted not in again.text


def test_down_subscriber_store_is_reported_and_does_not_leak_the_driver_error(env):
    class Down:
        def __getitem__(self, _name):
            return self

        def find_one(self, *_args, **_kwargs):
            raise TimeoutError("mongodb://secret-user:secret-pass@hidden/open5gs")

        def replace_one(self, *_args, **_kwargs):
            raise TimeoutError("mongodb://secret-user:secret-pass@hidden/open5gs")

    from open5g_dashboard.subscriber_port import MongoSubscriberPort

    port = MongoSubscriberPort("mongodb://hidden/open5gs", "open5gs", "subscribers", 200, client=Down())
    client = TestClient(create_app(env["settings"], subscriber_port=port))
    student = _login(client, "student-a@example.test", env["student_password"])
    read = student.client.get(f"/api/assignments/{env['assignment']['id']}/subscriber")
    assert read.status_code == 200, read.text
    assert read.json()["status"] == "down"
    assert "secret-pass" not in read.text
    created = student.post("/api/profiles", {"assignment_id": env["assignment"]["id"], "content": sample_content()})
    validated = student.client.post(
        f"/api/profiles/{created.json()['id']}/validate",
        headers=student.headers(created.json()["version_etag"]),
    )
    failed = student.post(
        f"/api/profiles/{validated.json()['id']}/provision",
        {},
        etag=validated.json()["version_etag"],
    )
    assert failed.status_code == 503
    assert failed.json()["error"]["code"] == "subscriber_store_unavailable"
    assert "secret-pass" not in failed.text


def test_gx_rar_flag_still_rejects(env):
    settings = Settings(DATABASE_URL, PEPPER, False, False, enable_gx_rar=True)
    client = TestClient(create_app(settings))
    student = _login(client, "student-a@example.test", env["student_password"])
    created = student.post("/api/profiles", {"assignment_id": env["assignment"]["id"], "content": sample_content()})
    assert created.status_code == 201, created.text
    validated = student.client.post(
        f"/api/profiles/{created.json()['id']}/validate",
        headers=student.headers(created.json()["version_etag"]),
    )
    applied = student.post(
        f"/api/profiles/{created.json()['id']}/apply",
        {},
        etag=validated.json()["version_etag"],
        key="gx-flag-1",
    )
    assert applied.status_code == 409, applied.text
    body = applied.json()
    assert body["status"] == "rejected"
    assert body["executed"] is False
    assert body["path"] == "gx_rar_admin_draft"
    assert body["status"] not in {"pushed", "active"}
    status = student.client.get("/api/core/status")
    assert status.json()["gx_rar_enabled"] is True
    assert status.json()["gx_rar_effective"] is False
