"""HTTP scaffold. Stock apply calls the rejecting adapter only."""

from __future__ import annotations

import hashlib
import re
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from psycopg import connect
from psycopg.rows import dict_row

from open5g_dashboard import db
from open5g_dashboard.emulator_http import DashboardHooks, register_emulator
from open5g_dashboard.domain import (
    Actor,
    Assignment,
    CatalogCap,
    ProfileError,
    REATTACH_NOTICE,
    apply_caps,
    authorize,
    capability_catalog,
    content_dict,
    demo_sample,
    diff_operations,
    make_etag,
    parse_profile,
    reattach_notice_id,
    redact,
    stock_immediate_apply,
    stock_reattach,
)
from open5g_dashboard.settings import Settings

# Scaffold parameters, not a reviewed production KDF policy.
HASHER = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)
SESSION_HOURS = 8
IMSI_RE = re.compile(r"^[0-9]{15}$")
SCOPE_KEYS = {"owner_user_id", "group_id", "imsi", "owner", "group"}


def create_app(settings: Settings) -> FastAPI:
    app = FastAPI(title="open5g dashboard scaffold", version="0.1.0")
    app.state.settings = settings

    def connect_db():
        return connect(settings.database_url, row_factory=dict_row)

    def fail(status: int, code: str, message: str, **extra: Any) -> JSONResponse:
        return JSONResponse(status_code=status, content={"error": {"code": code, "message": message, **extra}})

    def token_hash(token: str) -> str:
        return hashlib.sha256(f"{settings.session_pepper}:{token}".encode()).hexdigest()

    def actor_from(row) -> Actor:
        group_id = None if row["group_id"] is None else str(row["group_id"])
        return Actor(str(row["user_id"]), row["role"], group_id)

    def assignment_from(row) -> Assignment:
        return Assignment(str(row["id"]), row["imsi"], str(row["owner_user_id"]), str(row["group_id"]))

    def public_user(row) -> dict[str, Any]:
        return {
            "id": str(row["id"] if "id" in row and "user_id" not in row else row.get("user_id", row["id"])),
            "email": row["email"],
            "display_name": row["display_name"],
            "role": row["role"],
            "group_id": None if row["group_id"] is None else str(row["group_id"]),
        }

    def public_profile(row) -> dict[str, Any]:
        applied = row["applied_content"]
        return {
            "id": str(row["id"]),
            "assignment_id": str(row["assignment_id"]),
            "owner_user_id": str(row["owner_user_id"]),
            "group_id": str(row["group_id"]),
            "desired_version": row["desired_version"],
            "version_etag": row["version_etag"],
            "lifecycle": row["lifecycle"],
            "content": redact(row["content"]),
            "applied_version": row["applied_version"],
            "applied_content": None if applied is None else redact(applied),
        }

    def public_job(conn, job, replay: bool = False) -> dict[str, Any]:
        targets = []
        for target in db.targets_for(conn, job["id"]):
            targets.append(
                {
                    "target": target["target"],
                    "state": target["state"],
                    "desired_version": target["desired_version"],
                    "applied_version": target["applied_version"],
                    "observed_version": target["observed_version"],
                    "freshness": None if target["freshness"] is None else target["freshness"].isoformat(),
                    "error": target["error"],
                    "evidence": target["evidence"],
                }
            )
        return {
            "id": str(job["id"]),
            "profile_id": str(job["profile_id"]),
            "profile_version": job["profile_version"],
            "actor_id": str(job["actor_id"]),
            "owner_user_id": str(job["owner_user_id"]),
            "path": job["path"],
            "status": job["status"],
            "reasons": job["reasons"],
            "executed": job["executed"],
            "core_restart": job["core_restart"],
            "data_origin": job["data_origin"],
            "targets": targets,
            "idempotent_replay": replay,
        }

    def audit(conn, actor, owner_user_id, group_id, action, resource, outcome, reason, detail) -> None:
        db.insert_audit(
            conn,
            None if actor is None else actor.id,
            owner_user_id,
            group_id,
            action,
            resource,
            outcome,
            reason,
            redact(detail),
        )

    def load_session(conn, request: Request):
        token = request.cookies.get("open5g_session")
        if not token:
            return None
        row = db.session_user(conn, token_hash(token))
        if row is None:
            return None
        expires = row["expires_at"]
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        if expires <= datetime.now(timezone.utc):
            return None
        return row

    def csrf_ok(request: Request, session) -> bool:
        return request.headers.get("x-csrf-token") == session["csrf_token"]

    def set_auth_cookies(response: JSONResponse, token: str, csrf: str) -> None:
        response.set_cookie(
            "open5g_session",
            token,
            httponly=True,
            secure=settings.cookie_secure,
            samesite="lax",
            max_age=SESSION_HOURS * 3600,
            path="/",
        )
        response.set_cookie(
            "open5g_csrf",
            csrf,
            httponly=False,
            secure=settings.cookie_secure,
            samesite="lax",
            max_age=SESSION_HOURS * 3600,
            path="/",
        )

    def require_user(conn, request: Request, mutating: bool):
        session = load_session(conn, request)
        if session is None:
            return None, fail(401, "unauthenticated", "Login required")
        if mutating and not csrf_ok(request, session):
            return None, fail(403, "csrf_required", "Mutating requests require the session CSRF token")
        return session, None

    def scope_rejected(payload: dict) -> bool:
        return bool(SCOPE_KEYS.intersection(payload.keys()))

    def caps(conn) -> list[CatalogCap]:
        return [
            CatalogCap(
                row["name"],
                row["max_ambr_dl_bps"],
                row["enforced"],
                row["example_pending_environment_sizing"],
            )
            for row in db.list_caps(conn)
        ]

    def store_profile_content(raw: dict, conn):
        model, warnings = parse_profile(raw)
        warnings.extend(apply_caps(model, caps(conn)))
        return content_dict(model), warnings

    @app.get("/health")
    def health():
        return {"status": "ok", "core": "not_checked"}

    @app.get("/api/capabilities")
    def capabilities():
        return {
            "data_origin": "scaffold",
            "lab_evidence": False,
            "operations": capability_catalog(),
        }

    @app.post("/api/auth/login")
    async def login(request: Request):
        body = await request.json()
        email = str(body.get("email", ""))
        password = str(body.get("password", ""))
        with connect_db() as conn:
            user = db.user_by_email(conn, email)
            if user is None:
                audit(conn, None, None, None, "login", "session", "denied", "unknown_user", {})
                return fail(401, "invalid_login", "Email or password is wrong")
            try:
                HASHER.verify(user["password_hash"], password)
            except VerifyMismatchError:
                audit(conn, Actor(str(user["id"]), user["role"], None), None, None, "login", "session", "denied", "bad_password", {})
                return fail(401, "invalid_login", "Email or password is wrong")
            token = secrets.token_urlsafe(32)
            csrf = secrets.token_urlsafe(32)
            db.create_session(
                conn,
                str(user["id"]),
                token_hash(token),
                csrf,
                datetime.now(timezone.utc) + timedelta(hours=SESSION_HOURS),
            )
            response = JSONResponse(
                {
                    "csrf_token": csrf,
                    "user": {
                        "id": str(user["id"]),
                        "email": user["email"],
                        "display_name": user["display_name"],
                        "role": user["role"],
                        "group_id": None if user["group_id"] is None else str(user["group_id"]),
                    },
                }
            )
            set_auth_cookies(response, token, csrf)
            return response

    @app.post("/api/auth/logout")
    async def logout(request: Request):
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            db.delete_session(conn, session["session_id"])
        response = JSONResponse({"status": "logged_out"})
        response.delete_cookie("open5g_session", path="/")
        response.delete_cookie("open5g_csrf", path="/")
        return response

    @app.get("/api/auth/me")
    def me(request: Request):
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=False)
            if error:
                return error
            return public_user(session)

    @app.post("/api/admin/groups")
    async def create_group(request: Request):
        body = await request.json()
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            if actor.role != "admin":
                audit(conn, actor, None, None, "create_group", "group", "denied", "admin_required", {})
                return fail(403, "admin_required", "Only an admin can manage groups")
            name = str(body.get("name", "")).strip()
            if not name:
                return fail(422, "invalid_group", "Group name is required")
            group_id = db.insert_group(conn, name)
            return {"id": group_id, "name": name}

    @app.post("/api/admin/users")
    async def create_user(request: Request):
        body = await request.json()
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            if actor.role != "admin":
                audit(conn, actor, None, None, "create_user", "user", "denied", "admin_required", {})
                return fail(403, "admin_required", "Only an admin can create users")
            password = str(body.get("password", ""))
            if len(password) < 12:
                return fail(422, "weak_password", "Password must be at least 12 characters")
            role = body.get("role")
            if role not in {"student", "instructor", "admin"}:
                return fail(422, "invalid_role", "Unknown role")
            group_id = body.get("group_id")
            if role == "admin":
                group_id = None
            elif not group_id:
                return fail(422, "group_required", "Students and instructors belong to one group")
            user_id = db.insert_user(
                conn,
                str(body.get("email", "")),
                str(body.get("display_name", "")),
                role,
                group_id,
                HASHER.hash(password),
            )
            audit(conn, actor, user_id, group_id, "create_user", f"user:{user_id}", "allowed", role, {})
            return {"id": user_id, "role": role, "group_id": group_id}

    @app.post("/api/admin/assignments")
    async def create_assignment(request: Request):
        body = await request.json()
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            if actor.role != "admin":
                audit(conn, actor, None, None, "assign_imsi", "assignment", "denied", "admin_required", {})
                return fail(403, "admin_required", "Only an admin assigns an IMSI")
            imsi = str(body.get("imsi", ""))
            if not IMSI_RE.fullmatch(imsi):
                return fail(422, "invalid_imsi", "IMSI must be 15 digits")
            owner = db.user_by_id(conn, str(body.get("owner_user_id", "")))
            if owner is None or owner["role"] != "student":
                return fail(422, "owner_group_mismatch", "IMSI owner must be a student")
            if str(owner["group_id"]) != str(body.get("group_id")):
                return fail(422, "owner_group_mismatch", "Assignment group must match the student group")
            assignment_id = db.insert_assignment(conn, imsi, str(owner["id"]), str(owner["group_id"]), actor.id)
            audit(conn, actor, str(owner["id"]), str(owner["group_id"]), "assign_imsi", f"assignment:{assignment_id}", "allowed", "assigned", {})
            return {
                "id": assignment_id,
                "imsi": imsi,
                "owner_user_id": str(owner["id"]),
                "group_id": str(owner["group_id"]),
            }

    @app.post("/api/admin/catalog")
    async def create_catalog(request: Request):
        body = await request.json()
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            if actor.role != "admin":
                return fail(403, "admin_required", "Only an admin edits the catalog")
            row = db.insert_catalog(
                conn,
                str(body.get("kind", "ambr_cap")),
                str(body.get("name", "")),
                body.get("max_ambr_dl_bps"),
                bool(body.get("enforced", False)),
                bool(body.get("example_pending_environment_sizing", True)),
            )
            return {
                "id": str(row["id"]),
                "name": row["name"],
                "enforced": row["enforced"],
                "example_pending_environment_sizing": row["example_pending_environment_sizing"],
            }

    @app.get("/api/assignments")
    def get_assignments(request: Request):
        if "owner_user_id" in request.query_params or "group_id" in request.query_params:
            return fail(400, "client_scope_override_rejected", "Owner and group filters are not accepted")
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=False)
            if error:
                return error
            actor = actor_from(session)
            rows = db.list_assignments(conn, actor.role, actor.id, actor.group_id)
            return [
                {
                    "id": str(row["id"]),
                    "imsi": row["imsi"],
                    "owner_user_id": str(row["owner_user_id"]),
                    "group_id": str(row["group_id"]),
                }
                for row in rows
            ]

    def decide(conn, actor: Actor, assignment_row, action: str, resource: str):
        assignment = assignment_from(assignment_row)
        decision = authorize(actor, assignment, action)
        if not decision.allow:
            audit(
                conn,
                actor,
                assignment.owner_user_id,
                assignment.group_id,
                action,
                resource,
                "denied",
                decision.reason,
                {},
            )
            return fail(decision.status_code, decision.reason, "Request is outside the caller scope")
        return None

    @app.get("/api/profiles")
    def get_profiles(request: Request):
        if "owner_user_id" in request.query_params or "group_id" in request.query_params:
            return fail(400, "client_scope_override_rejected", "Owner and group filters are not accepted")
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=False)
            if error:
                return error
            actor = actor_from(session)
            return [public_profile(row) for row in db.list_profiles(conn, actor.role, actor.id, actor.group_id)]

    @app.post("/api/profiles")
    async def create_profile(request: Request):
        body = await request.json()
        if scope_rejected(body):
            return fail(400, "client_scope_override_rejected", "Owner, group, and IMSI cannot be sent on a profile write")
        content = body.get("content")
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            assignment_row = db.assignment_by_id(conn, str(body.get("assignment_id", "")))
            if assignment_row is None:
                return fail(404, "assignment_not_found", "Assignment was not found")
            denied = decide(conn, actor, assignment_row, "edit", f"assignment:{assignment_row['id']}")
            if denied:
                return denied
            try:
                stored, warnings = store_profile_content(content, conn)
            except ProfileError as exc:
                audit(conn, actor, str(assignment_row["owner_user_id"]), str(assignment_row["group_id"]), "save_draft", f"assignment:{assignment_row['id']}", "denied", exc.code, {"content": content})
                return fail(400 if exc.code in {"secret_field_rejected", "client_scope_override_rejected"} else 422, exc.code, exc.message, details=exc.details)
            etag = make_etag(1, stored)
            profile = db.insert_profile(conn, assignment_row, stored, etag)
            db.insert_version(conn, profile, actor.id, "save_draft")
            audit(conn, actor, str(profile["owner_user_id"]), str(profile["group_id"]), "save_draft", f"profile:{profile['id']}", "allowed", "saved", {})
            body_out = public_profile(profile)
            body_out["warnings"] = warnings
            return JSONResponse(status_code=201, content=body_out)

    def load_profile_for(conn, actor: Actor, profile_id: str, action: str):
        profile = db.profile_by_id(conn, profile_id)
        if profile is None:
            return None, None, fail(404, "profile_not_found", "Profile was not found")
        assignment_row = db.assignment_by_id(conn, str(profile["assignment_id"]))
        denied = decide(conn, actor, assignment_row, action, f"profile:{profile['id']}")
        if denied:
            return None, None, denied
        return profile, assignment_row, None

    @app.get("/api/profiles/{profile_id}")
    def get_profile(profile_id: str, request: Request):
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=False)
            if error:
                return error
            profile, _assignment, denied = load_profile_for(conn, actor_from(session), profile_id, "read")
            if denied:
                return denied
            return public_profile(profile)

    @app.put("/api/profiles/{profile_id}")
    async def save_profile(profile_id: str, request: Request):
        content = await request.json()
        if not isinstance(content, dict) or scope_rejected(content):
            return fail(400, "client_scope_override_rejected", "Owner, group, and IMSI cannot be sent on a profile write")
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            profile, assignment_row, denied = load_profile_for(conn, actor, profile_id, "edit")
            if denied:
                return denied
            expected = request.headers.get("if-match")
            if not expected:
                return fail(428, "if_match_required", "If-Match must carry version_etag")
            try:
                stored, warnings = store_profile_content(content, conn)
            except ProfileError as exc:
                audit(conn, actor, str(profile["owner_user_id"]), str(profile["group_id"]), "save_draft", f"profile:{profile_id}", "denied", exc.code, {"content": content})
                status = 400 if exc.code in {"secret_field_rejected", "client_scope_override_rejected"} else 422
                return fail(status, exc.code, exc.message, details=exc.details)
            version = profile["desired_version"] + 1
            etag = make_etag(version, stored)
            updated = db.update_profile_content(conn, profile_id, expected, version, etag, stored)
            if updated is None:
                audit(conn, actor, str(profile["owner_user_id"]), str(profile["group_id"]), "save_draft", f"profile:{profile_id}", "denied", "version_conflict", {})
                return fail(409, "version_conflict", "version_etag does not match the stored profile")
            db.insert_version(conn, updated, actor.id, "save_draft")
            audit(conn, actor, str(updated["owner_user_id"]), str(updated["group_id"]), "save_draft", f"profile:{profile_id}", "allowed", "saved", {})
            body_out = public_profile(updated)
            body_out["warnings"] = warnings
            return body_out

    @app.post("/api/profiles/{profile_id}/validate")
    def validate_profile(profile_id: str, request: Request):
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            profile, _assignment, denied = load_profile_for(conn, actor, profile_id, "edit")
            if denied:
                return denied
            expected = request.headers.get("if-match")
            if expected != profile["version_etag"]:
                return fail(409, "version_conflict", "version_etag does not match the stored profile")
            try:
                parse_profile_from_stored(profile["content"])
            except ProfileError as exc:
                return fail(422, exc.code, exc.message)
            updated = db.set_lifecycle(conn, profile_id, profile["version_etag"], "validated")
            return public_profile(updated)

    def open_job(conn, actor: Actor, profile, idempotency_key: str, request_hash: str, result):
        existing = db.job_by_key(conn, actor.id, idempotency_key)
        if existing is not None:
            if existing["request_hash"] != request_hash:
                return fail(409, "idempotency_conflict", "This Idempotency-Key was already used for a different request")
            body = public_job(conn, existing, replay=True)
            return JSONResponse(body)
        job = db.insert_job(conn, profile, actor.id, idempotency_key, request_hash, result)
        audit(
            conn,
            actor,
            str(profile["owner_user_id"]),
            str(profile["group_id"]),
            result.path,
            f"profile:{profile['id']}",
            result.status,
            result.reasons[0]["op"] if result.reasons else result.status,
            {"job_id": str(job["id"]), "core_restart": result.core_restart, "executed": result.executed},
        )
        return JSONResponse(status_code=409, content=public_job(conn, job, replay=False))

    @app.post("/api/profiles/{profile_id}/apply")
    async def apply_profile(profile_id: str, request: Request):
        body = await request.json()
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            profile, _assignment, denied = load_profile_for(conn, actor, profile_id, "apply")
            if denied:
                return denied
            if request.headers.get("if-match") != profile["version_etag"]:
                return fail(409, "version_conflict", "version_etag does not match the stored profile")
            key = request.headers.get("idempotency-key", "").strip()
            if not key:
                return fail(400, "idempotency_key_required", "Idempotency-Key is required")
            if profile["lifecycle"] != "validated":
                return fail(409, "not_validated", "Validate the draft before immediate apply")
            request_hash = hashlib.sha256(
                f"apply.{profile_id}.{profile['version_etag']}.{body.get('client_note', '')}".encode()
            ).hexdigest()
            operations = diff_operations(profile["applied_content"], profile["content"])
            result = stock_immediate_apply(operations, profile["desired_version"])
            return open_job(conn, actor, profile, key, request_hash, result)

    @app.post("/api/profiles/{profile_id}/reattach-notice")
    def reattach_notice(profile_id: str, request: Request):
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            profile, _assignment, denied = load_profile_for(conn, actor_from(session), profile_id, "apply")
            if denied:
                return denied
            return {
                "notice_id": reattach_notice_id(str(profile["id"]), profile["desired_version"]),
                "notice": REATTACH_NOTICE,
                "executed": False,
            }

    @app.post("/api/profiles/{profile_id}/reattach")
    async def reattach(profile_id: str, request: Request):
        body = await request.json()
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            profile, _assignment, denied = load_profile_for(conn, actor, profile_id, "apply")
            if denied:
                return denied
            key = request.headers.get("idempotency-key", "").strip()
            if not key:
                return fail(400, "idempotency_key_required", "Idempotency-Key is required")
            expected = reattach_notice_id(str(profile["id"]), profile["desired_version"])
            try:
                result = stock_reattach(bool(body.get("confirm_disruption")), str(body.get("notice_id", "")), expected, profile["desired_version"])
            except ProfileError as exc:
                return fail(400, exc.code, exc.message)
            request_hash = hashlib.sha256(f"reattach.{profile_id}.{expected}".encode()).hexdigest()
            return open_job(conn, actor, profile, key, request_hash, result)

    @app.post("/api/profiles/{profile_id}/rollback")
    async def rollback(profile_id: str, request: Request):
        body = await request.json()
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            profile, _assignment, denied = load_profile_for(conn, actor, profile_id, "edit")
            if denied:
                return denied
            if request.headers.get("if-match") != profile["version_etag"]:
                return fail(409, "version_conflict", "version_etag does not match the stored profile")
            key = request.headers.get("idempotency-key", "").strip()
            if not key:
                return fail(400, "idempotency_key_required", "Idempotency-Key is required")
            historical = db.version_row(conn, profile_id, int(body.get("to_version", 0)))
            if historical is None:
                return fail(404, "version_not_found", "That profile version does not exist")
            version = profile["desired_version"] + 1
            stored = historical["content"]
            etag = make_etag(version, stored)
            updated = db.update_profile_content(conn, profile_id, profile["version_etag"], version, etag, stored)
            db.insert_version(conn, updated, actor.id, "rollback")
            operations = diff_operations(updated["applied_content"], updated["content"])
            result = stock_immediate_apply(operations, updated["desired_version"])
            request_hash = hashlib.sha256(f"rollback.{profile_id}.{body.get('to_version')}.{etag}".encode()).hexdigest()
            job_response = open_job(conn, actor, updated, key, request_hash, result)
            payload = job_response.body
            import json
            parsed = json.loads(payload)
            return JSONResponse(
                status_code=job_response.status_code,
                content={
                    "profile": public_profile(updated),
                    "job": parsed,
                    "traffic_undone": False,
                    "note": "Rollback stores a new desired version. It does not undo traffic already sent.",
                },
            )

    @app.get("/api/profiles/{profile_id}/audit")
    def profile_audit(profile_id: str, request: Request):
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=False)
            if error:
                return error
            profile, _assignment, denied = load_profile_for(conn, actor_from(session), profile_id, "read")
            if denied:
                return denied
            rows = db.audit_for_resource(conn, f"profile:{profile['id']}")
            return [
                {
                    "id": str(row["id"]),
                    "at": row["at"].isoformat(),
                    "actor_id": None if row["actor_id"] is None else str(row["actor_id"]),
                    "owner_user_id": None if row["owner_user_id"] is None else str(row["owner_user_id"]),
                    "action": row["action"],
                    "outcome": row["outcome"],
                    "reason": row["reason"],
                    "detail": redact(row["detail"]),
                }
                for row in rows
            ]

    @app.post("/api/core/restart")
    def core_restart(request: Request):
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=True)
            if error:
                return error
            actor = actor_from(session)
            if actor.role != "admin":
                audit(conn, actor, None, actor.group_id, "core_restart", "core", "denied", "core_control_forbidden", {})
                return fail(403, "core_control_forbidden", "Students and instructors have no core controls")
            audit(conn, actor, None, None, "core_restart", "core", "denied", "core_control_not_implemented", {})
            return fail(501, "core_control_not_implemented", "This scaffold does not restart a core")

    @app.get("/api/metrics/drilldown")
    def drilldown(request: Request):
        assignment_id = request.query_params.get("assignment_id", "")
        with connect_db() as conn:
            session, error = require_user(conn, request, mutating=False)
            if error:
                return error
            actor = actor_from(session)
            assignment_row = db.assignment_by_id(conn, assignment_id)
            if assignment_row is None:
                return fail(404, "assignment_not_found", "Assignment was not found")
            denied = decide(conn, actor, assignment_row, "read", f"metrics:{assignment_id}")
            if denied:
                return denied
            return {
                "data_origin": "stub",
                "fake": True,
                "supported": False,
                "reason": "No metric collector is connected. Unknown is not a zero counter.",
                "assignment_id": assignment_id,
                "series": [],
            }

    if settings.enable_demo_routes:

        @app.get("/api/demo/sample")
        def demo():
            return demo_sample()

    register_emulator(
        app,
        settings,
        DashboardHooks(
            connect_db=connect_db,
            fail=fail,
            require_user=require_user,
            actor_from=actor_from,
            audit=audit,
        ),
    )
    return app


def parse_profile_from_stored(stored: dict) -> None:
    """Re-validate a stored snapshot by rebuilding the authored input."""
    def bitrate(value: dict) -> dict:
        return {"value": value["value"], "unit": value["unit"]}

    rules = []
    for rule in stored["app_rules"]:
        rules.append(
            {
                "match_type": rule["match_type"],
                "pattern": rule["pattern"],
                "app_id": rule["app_id"],
                "logical_slice": rule["logical_slice"],
                "enabled": rule["enabled"],
                "precedence": rule["precedence"],
            }
        )
    usage = None
    if stored["usage"] is not None:
        usage = {
            "scope": stored["usage"]["scope"],
            "app_id": stored["usage"]["app_id"],
            "threshold": stored["usage"]["threshold"],
            "unit": stored["usage"]["unit"],
            "window_seconds": stored["usage"]["window_seconds"],
        }
    parse_profile(
        {
            "apn": stored["apn"],
            "logical_slice_template": stored["logical_slice_template"],
            "qci": stored["qci"],
            "arp": stored["arp"],
            "ambr_ul": bitrate(stored["ambr_ul"]),
            "ambr_dl": bitrate(stored["ambr_dl"]),
            "mbr_ul": bitrate(stored["mbr_ul"]),
            "mbr_dl": bitrate(stored["mbr_dl"]),
            "gbr_ul": bitrate(stored["gbr_ul"]),
            "gbr_dl": bitrate(stored["gbr_dl"]),
            "app_rules": rules,
            "usage": usage,
            "acknowledge_ambiguity": stored["acknowledge_ambiguity"],
        }
    )


def main() -> None:
    import uvicorn

    uvicorn.run(create_app(Settings.from_env()), host="127.0.0.1", port=8000)
