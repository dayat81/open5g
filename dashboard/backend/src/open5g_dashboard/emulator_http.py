"""Reverse proxy for one emulator screen. It does not call the core."""

from __future__ import annotations

import asyncio
import secrets
import socket
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx
import websockets
from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import JSONResponse, StreamingResponse
from psycopg.errors import UniqueViolation
from starlette.websockets import WebSocketState

from open5g_dashboard import db
from open5g_dashboard.domain import APN_RE, Actor, authorize_emulator
from open5g_dashboard.emulator import (
    UE_ID_RE,
    build_upstream,
    clean_path,
    origin_allowed,
    parse_attach_ipv4,
    safe_query,
    token_hash,
    validate_screen_host,
    rewrite_location,
)
from open5g_dashboard.settings import Settings

TICKET_COOKIE = "open5g_emulator"
TICKET_MAX_AGE = 8 * 3600
FRAME_LIMIT = 16 * 1024 * 1024
REQUEST_HEADERS = {"accept", "accept-language", "user-agent"}
RESPONSE_DROP = {
    "set-cookie",
    "x-frame-options",
    "content-security-policy",
    "content-length",
    "transfer-encoding",
    "connection",
    "server",
}
REJECTED_FIELDS = {"reset", "wipe", "ki", "opc", "password", "vnc_password"}
DOWN_MESSAGE = "The emulator screen is not reachable. The core was not changed."


@dataclass(frozen=True)
class DashboardHooks:
    connect_db: Callable
    fail: Callable
    require_user: Callable
    actor_from: Callable
    audit: Callable


def screen_open(host: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def register_emulator(app: FastAPI, settings: Settings, hooks: DashboardHooks) -> None:
    def scope(conn, ue_id: str):
        row = db.emulator_endpoint(conn, ue_id)
        known = row is not None or ue_id in settings.emulator_targets
        owner = None
        group = None
        if row is not None and row["assignment_id"] is not None:
            assignment = db.assignment_by_id(conn, str(row["assignment_id"]))
            if assignment is not None:
                owner = str(assignment["owner_user_id"])
                group = str(assignment["group_id"])
        return known, row, owner, group

    def target_for(ue_id: str, row):
        if row is not None and row["internal_host"] and row["internal_port"]:
            return str(row["internal_host"]), int(row["internal_port"])
        return settings.emulator_targets.get(ue_id)

    def sweep(conn) -> None:
        cutoff = datetime.now(timezone.utc) - timedelta(seconds=settings.emulator_idle_seconds)
        for row in db.idle_emulator_sessions(conn, cutoff):
            closed = db.close_emulator_session(conn, str(row["id"]), "idle_timeout")
            if closed is None:
                continue
            user = db.user_by_id(conn, str(row["actor_id"]))
            role = user["role"] if user is not None else "student"
            actor_group = None if user is None or user["group_id"] is None else str(user["group_id"])
            _known, _endpoint, owner, group = scope(conn, row["ue_id"])
            hooks.audit(
                conn,
                Actor(str(row["actor_id"]), role, actor_group),
                owner,
                group,
                "emulator_close",
                f"emulator:{row['ue_id']}",
                "allowed",
                "idle_timeout",
                {"ue_id": row["ue_id"], "mode": "control"},
            )

    def status_for(conn, ue_id: str, row, actor_id: str) -> dict:
        target = target_for(ue_id, row)
        if target is None:
            screen = "down"
            detail = "unconfigured"
        elif screen_open(target[0], target[1], settings.emulator_probe_seconds):
            screen = "up"
            detail = "ready"
        else:
            screen = "down"
            detail = "unreachable"
        open_row = db.open_emulator_session(conn, ue_id)
        if open_row is None:
            control = "free"
        elif str(open_row["actor_id"]) == actor_id:
            control = "self"
        else:
            control = "busy"
        return {
            "ue_id": ue_id,
            "apn": None if row is None else row["apn"],
            "attach_ipv4": None if row is None else row["attach_ipv4"],
            "screen": screen,
            "control": control,
            "detail": detail,
        }

    def gate(conn, request, ue_id: str, mutating: bool):
        session, error = hooks.require_user(conn, request, mutating)
        if error:
            return None, None, error
        if not settings.emulator_enabled:
            return None, None, hooks.fail(404, "emulator_disabled", "The emulator screen is disabled")
        if UE_ID_RE.fullmatch(ue_id) is None:
            return None, None, hooks.fail(404, "emulator_not_found", "UE was not found")
        sweep(conn)
        known, row, owner, group = scope(conn, ue_id)
        if not known:
            return None, None, hooks.fail(404, "emulator_not_found", "UE was not found")
        actor = hooks.actor_from(session)
        decision = authorize_emulator(actor, owner)
        if not decision.allow:
            hooks.audit(
                conn,
                actor,
                owner,
                group,
                "emulator_open",
                f"emulator:{ue_id}",
                "denied",
                decision.reason,
                {"ue_id": ue_id},
            )
            return None, None, hooks.fail(decision.status_code, decision.reason, "Request is outside the caller scope")
        return (session, actor, row, owner, group), None, None

    def close_owned(conn, actor: Actor, ue_id: str, reason: str):
        open_row = db.open_emulator_session(conn, ue_id)
        if open_row is None:
            return None
        if str(open_row["actor_id"]) != actor.id:
            return False
        closed = db.close_emulator_session(conn, str(open_row["id"]), reason)
        if closed is None:
            return None
        _known, _row, owner, group = scope(conn, ue_id)
        hooks.audit(
            conn,
            actor,
            owner,
            group,
            "emulator_close",
            f"emulator:{ue_id}",
            "allowed",
            reason,
            {"ue_id": ue_id, "mode": "control"},
        )
        return closed

    @app.get("/api/emulator")
    def list_emulator(request: Request):
        with hooks.connect_db() as conn:
            session, error = hooks.require_user(conn, request, False)
            if error:
                return error
            if not settings.emulator_enabled:
                return hooks.fail(404, "emulator_disabled", "The emulator screen is disabled")
            sweep(conn)
            actor = hooks.actor_from(session)
            rows = {row["ue_id"]: row for row in db.list_emulator_endpoints(conn)}
            names = sorted(set(rows) | set(settings.emulator_targets))
            visible = []
            for ue_id in names:
                row = rows.get(ue_id)
                _known, _row, owner, _group = scope(conn, ue_id)
                if authorize_emulator(actor, owner).allow:
                    visible.append(status_for(conn, ue_id, row, actor.id))
            return visible

    @app.get("/api/emulator/{ue_id}")
    def get_emulator(ue_id: str, request: Request):
        with hooks.connect_db() as conn:
            granted, _empty, error = gate(conn, request, ue_id, False)
            if error:
                return error
            _session, actor, row, _owner, _group = granted
            return status_for(conn, ue_id, row, actor.id)

    @app.put("/api/admin/emulator-endpoints/{ue_id}")
    async def put_endpoint(ue_id: str, request: Request):
        if UE_ID_RE.fullmatch(ue_id) is None:
            return hooks.fail(422, "invalid_ue", "UE id must be a short lowercase name")
        body = await request.json()
        if not isinstance(body, dict) or REJECTED_FIELDS.intersection(str(key).lower() for key in body):
            return hooks.fail(400, "emulator_field_rejected", "That field is not accepted")
        with hooks.connect_db() as conn:
            session, error = hooks.require_user(conn, request, True)
            if error:
                return error
            actor = hooks.actor_from(session)
            if actor.role != "admin":
                hooks.audit(conn, actor, None, actor.group_id, "emulator_configure", f"emulator:{ue_id}", "denied", "admin_required", {"ue_id": ue_id})
                return hooks.fail(403, "admin_required", "Only an admin configures an emulator endpoint")
            assignment = db.assignment_by_id(conn, str(body.get("assignment_id", "")))
            if assignment is None:
                return hooks.fail(404, "assignment_not_found", "Assignment was not found")
            host = body.get("internal_host")
            port = body.get("internal_port")
            if host in ("", None) and port in ("", None):
                host, port = None, None
            elif host in ("", None) or port in ("", None):
                return hooks.fail(422, "invalid_target", "Host and port are set together")
            else:
                try:
                    host = validate_screen_host(str(host))
                    port = int(port)
                except (TypeError, ValueError):
                    return hooks.fail(422, "invalid_target", "The internal target is not a usable host and port")
                if port < 1 or port > 65535:
                    return hooks.fail(422, "invalid_target", "The internal target is not a usable host and port")
            apn = body.get("apn")
            if apn in ("", None):
                apn = None
            elif not isinstance(apn, str) or APN_RE.fullmatch(apn) is None:
                return hooks.fail(422, "invalid_apn", "APN is not usable")
            attach = body.get("attach_ipv4")
            if attach in ("", None):
                attach = None
            else:
                try:
                    attach = parse_attach_ipv4(str(attach))
                except ValueError:
                    return hooks.fail(422, "invalid_attach", "Attach address must be an IPv4 address")
            stored = db.upsert_emulator_endpoint(conn, ue_id, str(assignment["id"]), host, port, apn, attach)
            hooks.audit(
                conn,
                actor,
                str(assignment["owner_user_id"]),
                str(assignment["group_id"]),
                "emulator_configure",
                f"emulator:{ue_id}",
                "allowed",
                "configured",
                {"ue_id": ue_id},
            )
            return {
                "ue_id": stored["ue_id"],
                "assignment_id": str(stored["assignment_id"]),
                "internal_host": stored["internal_host"],
                "internal_port": stored["internal_port"],
                "apn": stored["apn"],
                "attach_ipv4": stored["attach_ipv4"],
            }

    @app.post("/api/emulator/{ue_id}/session")
    def open_session(ue_id: str, request: Request):
        with hooks.connect_db() as conn:
            granted, _empty, error = gate(conn, request, ue_id, True)
            if error:
                return error
            session, actor, row, owner, group = granted
            target = target_for(ue_id, row)
            if target is None or not screen_open(target[0], target[1], settings.emulator_probe_seconds):
                hooks.audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", "emulator_down", {"ue_id": ue_id})
                return hooks.fail(503, "emulator_down", DOWN_MESSAGE)
            replaced = False
            existing = db.open_emulator_session(conn, ue_id)
            if existing is not None and str(existing["actor_id"]) != actor.id:
                hooks.audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", "emulator_control_busy", {"ue_id": ue_id})
                return hooks.fail(409, "emulator_control_busy", "Another control session is open for this UE")
            if existing is not None:
                db.close_emulator_session(conn, str(existing["id"]), "replaced")
                hooks.audit(conn, actor, owner, group, "emulator_close", f"emulator:{ue_id}", "allowed", "replaced", {"ue_id": ue_id, "mode": "control"})
                replaced = True
            token = secrets.token_urlsafe(32)
            try:
                db.insert_emulator_session(conn, ue_id, actor.id, token_hash(settings.session_pepper, token))
            except UniqueViolation:
                conn.rollback()
                hooks.audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", "emulator_control_busy", {"ue_id": ue_id})
                return hooks.fail(409, "emulator_control_busy", "Another control session is open for this UE")
            hooks.audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "allowed", "control", {"ue_id": ue_id, "mode": "control"})
            response = JSONResponse({"ue_id": ue_id, "mode": "control", "screen": "up", "replaced": replaced})
            response.set_cookie(
                TICKET_COOKIE,
                token,
                httponly=True,
                secure=settings.cookie_secure,
                samesite="lax",
                max_age=TICKET_MAX_AGE,
                path=f"/emulator/{ue_id}",
            )
            return response

    @app.post("/api/emulator/{ue_id}/session/close")
    def close_session(ue_id: str, request: Request):
        with hooks.connect_db() as conn:
            granted, _empty, error = gate(conn, request, ue_id, True)
            if error:
                return error
            _session, actor, _row, owner, group = granted
            open_row = db.open_emulator_session(conn, ue_id)
            if open_row is not None and str(open_row["actor_id"]) != actor.id:
                hooks.audit(conn, actor, owner, group, "emulator_close", f"emulator:{ue_id}", "denied", "not_holder", {"ue_id": ue_id})
                return hooks.fail(403, "not_holder", "Only the control holder can close this session")
            closed = close_owned(conn, actor, ue_id, "operator_close")
            response = JSONResponse({"ue_id": ue_id, "closed": closed is not None})
            response.delete_cookie(TICKET_COOKIE, path=f"/emulator/{ue_id}")
            return response

    def stream_grant(conn, request, ue_id: str, path: str, require_origin: bool):
        granted, _empty, error = gate(conn, request, ue_id, False)
        if error:
            return None, error
        session, actor, row, owner, group = granted
        origin = request.headers.get("origin")
        if require_origin and not origin_allowed(origin, settings.emulator_origins):
            reason = "origin_rejected" if origin else "origin_required"
        elif origin and not origin_allowed(origin, settings.emulator_origins):
            reason = "origin_rejected"
        else:
            reason = None
        if reason:
            hooks.audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", reason, {"ue_id": ue_id})
            return None, hooks.fail(403, reason, "The websocket origin is not allowed")
        open_row = db.open_emulator_session(conn, ue_id)
        ticket = request.cookies.get(TICKET_COOKIE)
        header = request.headers.get("x-csrf-token")
        ticket_ok = False
        if ticket and open_row is not None:
            hashed = token_hash(settings.session_pepper, ticket)
            if hashed == open_row["token_hash"] and str(open_row["actor_id"]) == actor.id:
                ticket_ok = True
        header_ok = bool(header) and header == session["csrf_token"] and open_row is not None and str(open_row["actor_id"]) == actor.id
        if open_row is None or str(open_row["actor_id"]) != actor.id or not (ticket_ok or header_ok):
            reason = "emulator_control_busy" if open_row is not None and str(open_row["actor_id"]) != actor.id else "csrf_required"
            hooks.audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", reason, {"ue_id": ue_id})
            status = 409 if reason == "emulator_control_busy" else 403
            message = "Another control session is open for this UE" if status == 409 else "The websocket upgrade is missing its CSRF ticket"
            return None, hooks.fail(status, reason, message)
        target = target_for(ue_id, row)
        if target is None or not screen_open(target[0], target[1], settings.emulator_probe_seconds):
            return None, hooks.fail(503, "emulator_down", DOWN_MESSAGE)
        cleaned = clean_path(path)
        if cleaned is None:
            return None, hooks.fail(404, "emulator_not_found", "UE was not found")
        return (actor, owner, group, open_row, target, cleaned), None

    async def deny_ws(websocket: WebSocket, response: JSONResponse) -> None:
        if websocket.application_state != WebSocketState.CONNECTING:
            await websocket.close()
            return
        await websocket.send_denial_response(response)

    async def proxy_ws(websocket: WebSocket, ue_id: str, path: str) -> None:
        with hooks.connect_db() as conn:
            granted, error = stream_grant(conn, websocket, ue_id, path, True)
            if error:
                await deny_ws(websocket, error)
                return
            actor, owner, group, open_row, target, cleaned = granted
            session_id = str(open_row["id"])
            query = safe_query(websocket.scope.get("query_string", b"").decode())
            upstream_url = build_upstream(target[0], target[1], ue_id, cleaned, query, "ws")
        try:
            upstream = await websockets.connect(upstream_url, max_size=FRAME_LIMIT, open_timeout=2)
        except Exception:
            await deny_ws(websocket, hooks.fail(503, "emulator_down", DOWN_MESSAGE))
            return
        try:
            await websocket.accept()
        except Exception:
            await upstream.close()
            with hooks.connect_db() as conn:
                closed = db.close_emulator_session(conn, session_id, "client_close")
                if closed is not None:
                    hooks.audit(conn, actor, owner, group, "emulator_close", f"emulator:{ue_id}", "allowed", "client_close", {"ue_id": ue_id, "mode": "control"})
            return
        last = time.monotonic()
        last_db = 0.0

        def note() -> None:
            nonlocal last, last_db
            last = time.monotonic()
            now = last
            if now - last_db < 15:
                return
            last_db = now
            with hooks.connect_db() as conn:
                db.touch_emulator_session(conn, session_id)

        async def client_to_upstream() -> str:
            try:
                while True:
                    message = await websocket.receive()
                    if message["type"] == "websocket.disconnect":
                        return "client_close"
                    note()
                    if message.get("text") is not None:
                        await upstream.send(message["text"])
                    elif message.get("bytes") is not None:
                        await upstream.send(message["bytes"])
            except Exception:
                return "client_close"

        async def upstream_to_client() -> str:
            try:
                async for payload in upstream:
                    note()
                    if isinstance(payload, str):
                        await websocket.send_text(payload)
                    else:
                        await websocket.send_bytes(payload)
                return "upstream_closed"
            except Exception:
                return "upstream_closed"

        async def watch() -> str:
            while True:
                await asyncio.sleep(1)
                if time.monotonic() - last >= settings.emulator_idle_seconds:
                    return "idle_timeout"
                with hooks.connect_db() as conn:
                    if db.emulator_session_open(conn, session_id) is None:
                        return "replaced"

        tasks = {
            asyncio.create_task(client_to_upstream()),
            asyncio.create_task(upstream_to_client()),
            asyncio.create_task(watch()),
        }
        reason = "client_close"
        try:
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            for task in done:
                try:
                    reason = task.result()
                except Exception:
                    reason = "upstream_closed"
                break
        finally:
            await upstream.close()
            if reason != "replaced":
                with hooks.connect_db() as conn:
                    closed = db.close_emulator_session(conn, session_id, reason)
                    if closed is not None:
                        hooks.audit(
                            conn,
                            actor,
                            owner,
                            group,
                            "emulator_close",
                            f"emulator:{ue_id}",
                            "allowed",
                            reason,
                            {"ue_id": ue_id, "mode": "control"},
                        )
            try:
                await websocket.close()
            except Exception:
                pass

    @app.websocket("/emulator/{ue_id}")
    async def ws_root(websocket: WebSocket, ue_id: str):
        await proxy_ws(websocket, ue_id, "")

    @app.websocket("/emulator/{ue_id}/{path:path}")
    async def ws_path(websocket: WebSocket, ue_id: str, path: str):
        await proxy_ws(websocket, ue_id, path)

    async def proxy_http(request: Request, ue_id: str, path: str):
        if request.method not in {"GET", "HEAD"}:
            return hooks.fail(405, "method_not_allowed", "Only GET and HEAD are proxied")
        with hooks.connect_db() as conn:
            granted, error = stream_grant(conn, request, ue_id, path, False)
            if error:
                return error
            _actor, _owner, _group, _open_row, target, cleaned = granted
        query = safe_query(request.url.query)
        upstream_url = build_upstream(target[0], target[1], ue_id, cleaned, query, "http")
        forwarded = {key: value for key, value in request.headers.items() if key.lower() in REQUEST_HEADERS}
        client = httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=2.0), follow_redirects=False)
        try:
            upstream = await client.send(client.build_request(request.method, upstream_url, headers=forwarded), stream=True)
        except httpx.HTTPError:
            await client.aclose()
            return hooks.fail(503, "emulator_down", DOWN_MESSAGE)
        headers = {}
        base = f"http://{target[0]}:{target[1]}"
        prefix = f"/emulator/{ue_id}"
        for key, value in upstream.headers.items():
            if key.lower() in RESPONSE_DROP:
                continue
            if key.lower() == "location":
                value = rewrite_location(value, base, prefix)
            headers[key] = value

        async def chunks():
            try:
                async for chunk in upstream.aiter_raw():
                    yield chunk
            finally:
                await upstream.aclose()
                await client.aclose()

        return StreamingResponse(chunks(), status_code=upstream.status_code, headers=headers)

    @app.api_route("/emulator/{ue_id}", methods=["GET", "HEAD"])
    async def http_root(request: Request, ue_id: str):
        return await proxy_http(request, ue_id, "")

    @app.api_route("/emulator/{ue_id}/{path:path}", methods=["GET", "HEAD"])
    async def http_path(request: Request, ue_id: str, path: str):
        return await proxy_http(request, ue_id, path)
