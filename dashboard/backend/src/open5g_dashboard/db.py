"""PostgreSQL access and forward-only SQL migrations."""

from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path

from psycopg.types.json import Json

MIGRATIONS = Path(__file__).resolve().parents[2] / "migrations"


def split_sql(sql: str) -> list[str]:
    parts: list[str] = []
    buf: list[str] = []
    index = 0
    dollar: str | None = None
    while index < len(sql):
        if dollar is not None:
            if sql.startswith(dollar, index):
                buf.append(dollar)
                index += len(dollar)
                dollar = None
                continue
            buf.append(sql[index])
            index += 1
            continue
        if sql[index] == "$":
            match = re.match(r"\$[A-Za-z0-9_]*\$", sql[index:])
            if match:
                dollar = match.group(0)
                buf.append(dollar)
                index += len(dollar)
                continue
        if sql[index] == ";":
            statement = "".join(buf).strip()
            if statement:
                parts.append(statement)
            buf = []
            index += 1
            continue
        buf.append(sql[index])
        index += 1
    tail = "".join(buf).strip()
    if tail:
        parts.append(tail)
    return parts


def apply_migrations(conn) -> list[str]:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            name text PRIMARY KEY,
            applied_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    applied: list[str] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        existing = conn.execute(
            "SELECT 1 FROM schema_migrations WHERE name = %s",
            (path.name,),
        ).fetchone()
        if existing:
            continue
        for statement in split_sql(path.read_text()):
            conn.execute(statement)
        conn.execute("INSERT INTO schema_migrations (name) VALUES (%s)", (path.name,))
        applied.append(path.name)
    return applied


def insert_group(conn, name: str) -> str:
    row = conn.execute(
        "INSERT INTO groups (name) VALUES (%s) RETURNING id",
        (name,),
    ).fetchone()
    return str(row["id"])


def insert_user(conn, email: str, display_name: str, role: str, group_id: str | None, password_hash: str) -> str:
    row = conn.execute(
        """
        INSERT INTO users (email, display_name, role, group_id, password_hash)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id
        """,
        (email, display_name, role, group_id, password_hash),
    ).fetchone()
    return str(row["id"])


def insert_assignment(conn, imsi: str, owner_user_id: str, group_id: str, assigned_by: str) -> str:
    row = conn.execute(
        """
        INSERT INTO imsi_assignments (imsi, owner_user_id, group_id, assigned_by)
        VALUES (%s, %s, %s, %s)
        RETURNING id
        """,
        (imsi, owner_user_id, group_id, assigned_by),
    ).fetchone()
    return str(row["id"])


def create_session(conn, user_id: str, token_hash: str, csrf_token: str, expires_at) -> None:
    conn.execute(
        """
        INSERT INTO sessions (user_id, token_hash, csrf_token, expires_at)
        VALUES (%s, %s, %s, %s)
        """,
        (user_id, token_hash, csrf_token, expires_at),
    )


def session_user(conn, token_hash: str):
    return conn.execute(
        """
        SELECT s.id AS session_id, s.csrf_token, s.expires_at, s.user_id,
               u.email, u.display_name, u.role, u.group_id
        FROM sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.token_hash = %s
        """,
        (token_hash,),
    ).fetchone()


def delete_session(conn, session_id: str) -> None:
    conn.execute("DELETE FROM sessions WHERE id = %s", (session_id,))


def user_by_email(conn, email: str):
    return conn.execute("SELECT * FROM users WHERE email = %s", (email,)).fetchone()


def user_by_id(conn, user_id: str):
    return conn.execute(
        "SELECT id, email, display_name, role, group_id FROM users WHERE id = %s",
        (user_id,),
    ).fetchone()


def assignment_by_id(conn, assignment_id: str):
    return conn.execute("SELECT * FROM imsi_assignments WHERE id = %s", (assignment_id,)).fetchone()


def list_assignments(conn, role: str, user_id: str, group_id: str | None):
    if role == "admin":
        query = "SELECT * FROM imsi_assignments ORDER BY created_at"
        args: tuple = ()
    elif role == "instructor":
        query = "SELECT * FROM imsi_assignments WHERE group_id = %s ORDER BY created_at"
        args = (group_id,)
    else:
        query = "SELECT * FROM imsi_assignments WHERE owner_user_id = %s ORDER BY created_at"
        args = (user_id,)
    return conn.execute(query, args).fetchall()


def insert_profile(conn, assignment, content: dict, etag: str):
    return conn.execute(
        """
        INSERT INTO profiles (
            assignment_id, owner_user_id, group_id, desired_version, version_etag, lifecycle, content
        )
        VALUES (%s, %s, %s, 1, %s, 'saved', %s)
        RETURNING *
        """,
        (
            assignment["id"],
            assignment["owner_user_id"],
            assignment["group_id"],
            etag,
            Json(content),
        ),
    ).fetchone()


def profile_by_id(conn, profile_id: str):
    return conn.execute("SELECT * FROM profiles WHERE id = %s", (profile_id,)).fetchone()


def list_profiles(conn, role: str, user_id: str, group_id: str | None):
    if role == "admin":
        query = "SELECT * FROM profiles ORDER BY updated_at"
        args: tuple = ()
    elif role == "instructor":
        query = "SELECT * FROM profiles WHERE group_id = %s ORDER BY updated_at"
        args = (group_id,)
    else:
        query = "SELECT * FROM profiles WHERE owner_user_id = %s ORDER BY updated_at"
        args = (user_id,)
    return conn.execute(query, args).fetchall()


def update_profile_content(conn, profile_id: str, expected_etag: str, version: int, etag: str, content: dict):
    return conn.execute(
        """
        UPDATE profiles
        SET desired_version = %s,
            version_etag = %s,
            lifecycle = 'saved',
            content = %s,
            updated_at = now()
        WHERE id = %s AND version_etag = %s
        RETURNING *
        """,
        (version, etag, Json(content), profile_id, expected_etag),
    ).fetchone()


def set_lifecycle(conn, profile_id: str, expected_etag: str, lifecycle: str):
    return conn.execute(
        """
        UPDATE profiles
        SET lifecycle = %s, updated_at = now()
        WHERE id = %s AND version_etag = %s
        RETURNING *
        """,
        (lifecycle, profile_id, expected_etag),
    ).fetchone()


def insert_version(conn, profile, actor_id: str, action: str) -> None:
    conn.execute(
        """
        INSERT INTO profile_versions (
            profile_id, version, version_etag, content, actor_id, owner_user_id, action
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (
            profile["id"],
            profile["desired_version"],
            profile["version_etag"],
            Json(profile["content"]),
            actor_id,
            profile["owner_user_id"],
            action,
        ),
    )


def version_row(conn, profile_id: str, version: int):
    return conn.execute(
        """
        SELECT * FROM profile_versions
        WHERE profile_id = %s AND version = %s
        """,
        (profile_id, version),
    ).fetchone()


def insert_job(conn, profile, actor_id: str, idempotency_key: str, request_hash: str, result) -> dict:
    job = conn.execute(
        """
        INSERT INTO apply_jobs (
            profile_id, profile_version, actor_id, owner_user_id, idempotency_key,
            request_hash, path, status, reasons, executed, core_restart, data_origin
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING *
        """,
        (
            profile["id"],
            profile["desired_version"],
            actor_id,
            profile["owner_user_id"],
            idempotency_key,
            request_hash,
            result.path,
            result.status,
            Json(result.reasons),
            result.executed,
            result.core_restart,
            result.data_origin,
        ),
    ).fetchone()
    for target in result.targets:
        conn.execute(
            """
            INSERT INTO apply_targets (
                job_id, target, desired_version, applied_version, observed_version,
                freshness, error, evidence, state
            )
            VALUES (%s, %s, %s, %s, %s, NULL, %s, %s, %s)
            """,
            (
                job["id"],
                target.target,
                target.desired_version,
                target.applied_version,
                target.observed_version,
                target.error,
                Json(target.evidence),
                target.state,
            ),
        )
    return job


def job_by_key(conn, actor_id: str, idempotency_key: str):
    return conn.execute(
        """
        SELECT * FROM apply_jobs
        WHERE actor_id = %s AND idempotency_key = %s
        """,
        (actor_id, idempotency_key),
    ).fetchone()


def targets_for(conn, job_id: str):
    return conn.execute(
        "SELECT * FROM apply_targets WHERE job_id = %s ORDER BY target",
        (job_id,),
    ).fetchall()


def insert_audit(conn, actor_id, owner_user_id, group_id, action, resource, outcome, reason, detail) -> None:
    conn.execute(
        """
        INSERT INTO audit_events (
            actor_id, owner_user_id, group_id, action, resource, outcome, reason, detail
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (actor_id, owner_user_id, group_id, action, resource, outcome, reason, Json(detail)),
    )


def audit_for_resource(conn, resource: str):
    return conn.execute(
        "SELECT * FROM audit_events WHERE resource = %s ORDER BY at",
        (resource,),
    ).fetchall()


def insert_catalog(conn, kind: str, name: str, max_ambr_dl_bps, enforced: bool, example_pending: bool):
    return conn.execute(
        """
        INSERT INTO catalog_entries (
            kind, name, max_ambr_dl_bps, enforced, example_pending_environment_sizing
        )
        VALUES (%s, %s, %s, %s, %s)
        RETURNING *
        """,
        (kind, name, max_ambr_dl_bps, enforced, example_pending),
    ).fetchone()


def list_caps(conn):
    return conn.execute("SELECT * FROM catalog_entries ORDER BY name").fetchall()


def list_emulator_endpoints(conn):
    return conn.execute("SELECT * FROM emulator_endpoints ORDER BY ue_id").fetchall()


def emulator_endpoint(conn, ue_id: str):
    return conn.execute("SELECT * FROM emulator_endpoints WHERE ue_id = %s", (ue_id,)).fetchone()


def upsert_emulator_screen_status(conn, ue_id: str, status: str) -> None:
    conn.execute(
        """
        INSERT INTO emulator_screen_status (ue_id, status, checked_at)
        VALUES (%s, %s, now())
        ON CONFLICT (ue_id) DO UPDATE SET
            status = EXCLUDED.status,
            checked_at = now()
        """,
        (ue_id, status),
    )


def emulator_screen_is_up(conn, ue_id: str, stale_seconds: int) -> bool:
    row = conn.execute(
        """
        SELECT 1 FROM emulator_screen_status
        WHERE ue_id = %s
          AND status = 'up'
          AND checked_at >= now() - (%s * interval '1 second')
        """,
        (ue_id, stale_seconds),
    ).fetchone()
    return row is not None


def upsert_emulator_endpoint(conn, ue_id: str, assignment_id: str, host, port, apn, attach_ipv4):
    return conn.execute(
        """
        INSERT INTO emulator_endpoints (
            ue_id, assignment_id, internal_host, internal_port, apn, attach_ipv4
        )
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT (ue_id) DO UPDATE SET
            assignment_id = EXCLUDED.assignment_id,
            internal_host = EXCLUDED.internal_host,
            internal_port = EXCLUDED.internal_port,
            apn = EXCLUDED.apn,
            attach_ipv4 = EXCLUDED.attach_ipv4
        RETURNING *
        """,
        (ue_id, assignment_id, host, port, apn, attach_ipv4),
    ).fetchone()


def open_emulator_session(conn, ue_id: str):
    return conn.execute(
        """
        SELECT * FROM emulator_sessions
        WHERE ue_id = %s AND closed_at IS NULL
        """,
        (ue_id,),
    ).fetchone()


def emulator_session_by_token(conn, token_hash: str):
    return conn.execute(
        """
        SELECT * FROM emulator_sessions
        WHERE token_hash = %s AND closed_at IS NULL
        """,
        (token_hash,),
    ).fetchone()


def emulator_session_open(conn, session_id: str):
    return conn.execute(
        """
        SELECT 1 FROM emulator_sessions
        WHERE id = %s AND closed_at IS NULL
        """,
        (session_id,),
    ).fetchone()


def insert_emulator_session(conn, ue_id: str, actor_id: str, dashboard_session_id: str, exchange_hash: str, exchange_expires_at):
    return conn.execute(
        """
        INSERT INTO emulator_sessions (
            ue_id, actor_id, dashboard_session_id, exchange_hash, exchange_expires_at
        )
        VALUES (%s, %s, %s, %s, %s)
        RETURNING *
        """,
        (ue_id, actor_id, dashboard_session_id, exchange_hash, exchange_expires_at),
    ).fetchone()


def emulator_session_by_exchange(conn, exchange_hash: str):
    return conn.execute(
        """
        SELECT * FROM emulator_sessions
        WHERE exchange_hash = %s
          AND closed_at IS NULL
          AND exchange_used_at IS NULL
          AND exchange_expires_at > now()
        """,
        (exchange_hash,),
    ).fetchone()


def claim_emulator_exchange(conn, session_id: str, token_hash: str):
    return conn.execute(
        """
        UPDATE emulator_sessions
        SET exchange_used_at = now(), token_hash = %s, last_client_at = now()
        WHERE id = %s AND closed_at IS NULL AND exchange_used_at IS NULL
        RETURNING *
        """,
        (token_hash, session_id),
    ).fetchone()


def dashboard_session_alive(conn, session_id: str | None) -> bool:
    if not session_id:
        return False
    row = conn.execute("SELECT expires_at FROM sessions WHERE id = %s", (session_id,)).fetchone()
    if row is None:
        return False
    expires = row["expires_at"]
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    return expires > datetime.now(timezone.utc)


def close_emulator_sessions_for_actor(conn, actor_id: str, reason: str):
    return conn.execute(
        """
        UPDATE emulator_sessions
        SET closed_at = now(), close_reason = %s
        WHERE actor_id = %s AND closed_at IS NULL
        RETURNING *
        """,
        (reason, actor_id),
    ).fetchall()


def close_emulator_session(conn, session_id: str, reason: str):
    return conn.execute(
        """
        UPDATE emulator_sessions
        SET closed_at = now(), close_reason = %s
        WHERE id = %s AND closed_at IS NULL
        RETURNING *
        """,
        (reason, session_id),
    ).fetchone()


def touch_emulator_session(conn, session_id: str) -> None:
    conn.execute(
        """
        UPDATE emulator_sessions
        SET last_client_at = now()
        WHERE id = %s AND closed_at IS NULL
        """,
        (session_id,),
    )


def expired_emulator_sessions(conn, idle_cutoff, absolute_cutoff):
    return conn.execute(
        """
        SELECT * FROM emulator_sessions
        WHERE closed_at IS NULL
          AND (last_client_at <= %s OR opened_at <= %s)
        """,
        (idle_cutoff, absolute_cutoff),
    ).fetchall()


def profile_for_assignment(conn, assignment_id: str):
    return conn.execute("SELECT * FROM profiles WHERE assignment_id = %s", (assignment_id,)).fetchone()


def insert_sync(conn, profile_id: str, desired_version: int, state: str, detail: dict) -> str:
    row = conn.execute(
        """
        INSERT INTO subscriber_sync (profile_id, desired_version, state, detail)
        VALUES (%s, %s, %s, %s)
        RETURNING id
        """,
        (profile_id, desired_version, state, Json(detail)),
    ).fetchone()
    return str(row["id"])


def finish_sync(conn, sync_id: str, state: str, generation: int | None) -> None:
    conn.execute(
        """
        UPDATE subscriber_sync
        SET state = %s, mongo_generation = %s, observed_at = now()
        WHERE id = %s
        """,
        (state, generation, sync_id),
    )
