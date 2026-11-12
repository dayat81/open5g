"""Screen proxy on its own origin. It does not call the core."""

from __future__ import annotations

import asyncio
import secrets
import socket
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx
import websockets
from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import JSONResponse, RedirectResponse, StreamingResponse
from psycopg import connect
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row
from starlette.websockets import WebSocketState

from open5g_dashboard import db
from open5g_dashboard.domain import APN_RE, Actor, authorize_emulator, redact
from open5g_dashboard.emulator import (
    EXCHANGE_SECONDS,
    UE_ID_RE,
    build_upstream,
    clean_path,
    origin_allowed,
    parse_attach_ipv4,
    safe_query,
    target_allowed,
    token_hash,
)
from open5g_dashboard.settings import Settings

SCREEN_COOKIE = "open5g_screen"
FRAME_LIMIT = 16 * 1024 * 1024
REQUEST_HEADERS = {"accept", "accept-language", "user-agent"}
RESPONSE_DROP = {
    "set-cookie",
    "content-security-policy",
    "content-length",
    "transfer-encoding",
    "connection",
    "server",
    "x-frame-options",
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


def record_screen_probes(conn, settings: Settings) -> None:
    """Dial each screen target from the listener and store up/down for the API."""

    rows = {row["ue_id"]: row for row in db.list_emulator_endpoints(conn)}
    for ue_id in sorted(set(rows) | set(settings.emulator_targets)):
        target = _target_for(settings, ue_id, rows.get(ue_id))
        status = "down"
        if target is not None and screen_open(target[0], target[1], settings.emulator_probe_seconds):
            status = "up"
        db.upsert_emulator_screen_status(conn, ue_id, status)


def _actor_from_user(user) -> Actor | None:
    if user is None:
        return None
    group = None if user["group_id"] is None else str(user["group_id"])
    return Actor(str(user["id"]), user["role"], group)


def _scope(conn, settings: Settings, ue_id: str):
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


def _target_for(settings: Settings, ue_id: str, row):
    if settings.emulator_screen_mode == "host-agen":
        return settings.screen_upstream
    if row is not None and row["internal_host"] and row["internal_port"]:
        host, port = str(row["internal_host"]), int(row["internal_port"])
    else:
        found = settings.emulator_targets.get(ue_id)
        if found is None:
            return None
        host, port = found
    try:
        return target_allowed(host, port, settings.emulator_allowed_nets, settings.emulator_screen_port)
    except ValueError:
        return None


def _client_detail(request, ue_id: str, extra: dict | None = None) -> dict:
    host = None if request is None or request.client is None else request.client.host
    agent = None if request is None else request.headers.get("user-agent")
    detail = {"ue_id": ue_id, "client": host, "user_agent": agent, "mode": "control"}
    if extra:
        detail.update(extra)
    return detail


def _close_row(conn, hooks_audit, row, reason: str, request=None) -> None:
    closed = db.close_emulator_session(conn, str(row["id"]), reason)
    if closed is None:
        return
    user = db.user_by_id(conn, str(row["actor_id"]))
    actor = _actor_from_user(user)
    opened = row["opened_at"]
    if opened.tzinfo is None:
        opened = opened.replace(tzinfo=timezone.utc)
    duration = int((datetime.now(timezone.utc) - opened).total_seconds())
    _known, _endpoint, owner, group = _scope(conn, hooks_audit.settings, row["ue_id"]) if hasattr(hooks_audit, "settings") else (False, None, None, None)
    detail = _client_detail(request, row["ue_id"], {"duration_seconds": max(duration, 0)})
    hooks_audit.audit(conn, actor, owner, group, "emulator_close", f"emulator:{row['ue_id']}", "allowed", reason, detail)


class _Audit:
    def __init__(self, settings: Settings, audit: Callable):
        self.settings = settings
        self.audit = audit


def _sweep(conn, settings: Settings, audit: Callable) -> None:
    now = datetime.now(timezone.utc)
    idle_cutoff = now - timedelta(seconds=settings.emulator_idle_seconds)
    absolute_cutoff = now - timedelta(seconds=settings.emulator_max_age_seconds)
    book = _Audit(settings, audit)
    for row in db.expired_emulator_sessions(conn, idle_cutoff, absolute_cutoff):
        opened = row["opened_at"]
        if opened.tzinfo is None:
            opened = opened.replace(tzinfo=timezone.utc)
        reason = "absolute_timeout" if opened <= absolute_cutoff else "idle_timeout"
        _close_row(conn, book, row, reason)
    open_rows = conn.execute("SELECT * FROM emulator_sessions WHERE closed_at IS NULL").fetchall()
    for row in open_rows:
        if _access_reason(conn, settings, row) is not None:
            _close_row(conn, book, row, "revoked")


def _access_reason(conn, settings: Settings, row) -> str | None:
    if not db.dashboard_session_alive(conn, None if row["dashboard_session_id"] is None else str(row["dashboard_session_id"])):
        return "revoked"
    user = db.user_by_id(conn, str(row["actor_id"]))
    actor = _actor_from_user(user)
    if actor is None:
        return "revoked"
    _known, _row, owner, group = _scope(conn, settings, row["ue_id"])
    decision = authorize_emulator(actor, owner, group)
    if not decision.allow:
        return "revoked"
    return None


def _frame_ancestors(settings: Settings) -> str:
    allowed = " ".join(settings.emulator_origins) if settings.emulator_origins else "'none'"
    return f"frame-ancestors {allowed}"


def register_emulator(app: FastAPI, settings: Settings, hooks: DashboardHooks) -> None:
    def audit(conn, actor, owner, group, action, resource, outcome, reason, detail):
        hooks.audit(conn, actor, owner, group, action, resource, outcome, reason, detail)

    def status_for(conn, ue_id: str, row, actor_id: str) -> dict:
        target = _target_for(settings, ue_id, row)
        if target is None:
            screen, detail = "down", "unconfigured"
        elif db.emulator_screen_is_up(conn, ue_id, settings.emulator_status_stale_seconds):
            screen, detail = "up", "ready"
        else:
            screen, detail = "down", "unreachable"
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
            return None, error
        if not settings.emulator_enabled:
            return None, hooks.fail(404, "emulator_disabled", "The emulator screen is disabled")
        if UE_ID_RE.fullmatch(ue_id) is None:
            return None, hooks.fail(404, "emulator_not_found", "UE was not found")
        _sweep(conn, settings, audit)
        known, row, owner, group = _scope(conn, settings, ue_id)
        if not known:
            return None, hooks.fail(404, "emulator_not_found", "UE was not found")
        actor = hooks.actor_from(session)
        decision = authorize_emulator(actor, owner, group)
        if not decision.allow:
            audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", decision.reason, _client_detail(request, ue_id))
            return None, hooks.fail(decision.status_code, decision.reason, "Request is outside the caller scope")
        return (session, actor, row, owner, group), None

    @app.get("/api/emulator")
    def list_emulator(request: Request):
        with hooks.connect_db() as conn:
            session, error = hooks.require_user(conn, request, False)
            if error:
                return error
            if not settings.emulator_enabled:
                return hooks.fail(404, "emulator_disabled", "The emulator screen is disabled")
            _sweep(conn, settings, audit)
            actor = hooks.actor_from(session)
            rows = {row["ue_id"]: row for row in db.list_emulator_endpoints(conn)}
            visible = []
            for ue_id in sorted(set(rows) | set(settings.emulator_targets)):
                _known, _row, owner, group = _scope(conn, settings, ue_id)
                if authorize_emulator(actor, owner, group).allow:
                    visible.append(status_for(conn, ue_id, rows.get(ue_id), actor.id))
            return visible

    @app.get("/api/emulator/{ue_id}")
    def get_emulator(ue_id: str, request: Request):
        with hooks.connect_db() as conn:
            granted, error = gate(conn, request, ue_id, False)
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
                audit(conn, actor, None, actor.group_id, "emulator_configure", f"emulator:{ue_id}", "denied", "admin_required", _client_detail(request, ue_id))
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
                    host, port = target_allowed(str(host), int(port), settings.emulator_allowed_nets, settings.emulator_screen_port)
                except (TypeError, ValueError):
                    return hooks.fail(422, "invalid_target", "The internal target is outside the screen allowlist")
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
            previous = db.emulator_endpoint(conn, ue_id)
            stored = db.upsert_emulator_endpoint(conn, ue_id, str(assignment["id"]), host, port, apn, attach)
            if previous is not None and str(previous["assignment_id"]) != str(stored["assignment_id"]):
                open_row = db.open_emulator_session(conn, ue_id)
                if open_row is not None:
                    _close_row(conn, _Audit(settings, audit), open_row, "reassigned", request)
            audit(
                conn,
                actor,
                str(assignment["owner_user_id"]),
                str(assignment["group_id"]),
                "emulator_configure",
                f"emulator:{ue_id}",
                "allowed",
                "configured",
                _client_detail(request, ue_id),
            )
            return {
                "ue_id": stored["ue_id"],
                "assignment_id": str(stored["assignment_id"]),
                "apn": stored["apn"],
                "attach_ipv4": stored["attach_ipv4"],
            }

    @app.post("/api/emulator/{ue_id}/session")
    def open_session(ue_id: str, request: Request):
        with hooks.connect_db() as conn:
            granted, error = gate(conn, request, ue_id, True)
            if error:
                return error
            session, actor, row, owner, group = granted
            if not settings.emulator_screen_origin:
                return hooks.fail(404, "emulator_disabled", "The screen origin is not configured")
            target = _target_for(settings, ue_id, row)
            if target is None or not db.emulator_screen_is_up(conn, ue_id, settings.emulator_status_stale_seconds):
                audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", "emulator_down", _client_detail(request, ue_id))
                return hooks.fail(503, "emulator_down", DOWN_MESSAGE)
            replaced = False
            existing = db.open_emulator_session(conn, ue_id)
            if existing is not None and str(existing["actor_id"]) != actor.id:
                audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", "emulator_control_busy", _client_detail(request, ue_id))
                return hooks.fail(409, "emulator_control_busy", "Another control session is open for this UE")
            if existing is not None:
                _close_row(conn, _Audit(settings, audit), existing, "replaced", request)
                replaced = True
            code = secrets.token_urlsafe(32)
            try:
                db.insert_emulator_session(
                    conn,
                    ue_id,
                    actor.id,
                    str(session["session_id"]),
                    token_hash(settings.session_pepper, code),
                    datetime.now(timezone.utc) + timedelta(seconds=EXCHANGE_SECONDS),
                )
            except UniqueViolation:
                conn.rollback()
                audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "denied", "emulator_control_busy", _client_detail(request, ue_id))
                return hooks.fail(409, "emulator_control_busy", "Another control session is open for this UE")
            audit(conn, actor, owner, group, "emulator_open", f"emulator:{ue_id}", "allowed", "control", _client_detail(request, ue_id))
            screen_url = f"{settings.emulator_screen_origin.rstrip('/')}/emulator/{ue_id}/exchange?{urlencode({'code': code})}"
            return {"ue_id": ue_id, "mode": "control", "screen": "up", "replaced": replaced, "screen_url": screen_url}

    @app.post("/api/emulator/{ue_id}/session/close")
    def close_session(ue_id: str, request: Request):
        with hooks.connect_db() as conn:
            granted, error = gate(conn, request, ue_id, True)
            if error:
                return error
            _session, actor, _row, owner, group = granted
            open_row = db.open_emulator_session(conn, ue_id)
            if open_row is not None and str(open_row["actor_id"]) != actor.id:
                audit(conn, actor, owner, group, "emulator_close", f"emulator:{ue_id}", "denied", "not_holder", _client_detail(request, ue_id))
                return hooks.fail(403, "not_holder", "Only the control holder can close this session")
            if open_row is not None:
                _close_row(conn, _Audit(settings, audit), open_row, "operator_close", request)
            return {"ue_id": ue_id, "closed": open_row is not None}


def create_screen_app(settings: Settings) -> FastAPI:
    app = FastAPI(title="open5g emulator screen", version="0.1.0")

    def connect_db():
        return connect(settings.database_url, row_factory=dict_row)

    def fail(status: int, code: str, message: str) -> JSONResponse:
        return JSONResponse(status_code=status, content={"error": {"code": code, "message": message}})

    def audit(conn, actor, owner, group, action, resource, outcome, reason, detail):
        db.insert_audit(
            conn,
            None if actor is None else actor.id,
            owner,
            group,
            action,
            resource,
            outcome,
            reason,
            redact(detail),
        )

    @app.middleware("http")
    async def screen_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = _frame_ancestors(settings)
        response.headers["Referrer-Policy"] = "no-referrer"
        return response

    def load_screen_session(conn, request):
        token = request.cookies.get(SCREEN_COOKIE)
        if not token:
            return None
        return db.emulator_session_by_token(conn, token_hash(settings.session_pepper, token))

    async def deny_ws(websocket: WebSocket, response: JSONResponse) -> None:
        if websocket.application_state != WebSocketState.CONNECTING:
            await websocket.close()
            return
        await websocket.send_denial_response(response)

    def screen_gate(conn, request, ue_id: str, require_origin: bool):
        if not settings.emulator_enabled:
            return None, fail(404, "emulator_disabled", "The emulator screen is disabled")
        if UE_ID_RE.fullmatch(ue_id) is None:
            return None, fail(404, "emulator_not_found", "UE was not found")
        _sweep(conn, settings, audit)
        row = load_screen_session(conn, request)
        if row is None or row["ue_id"] != ue_id:
            return None, fail(401, "unauthenticated", "Login required")
        origin = request.headers.get("origin")
        if require_origin and not origin_allowed(origin, (settings.emulator_screen_origin,)):
            reason = "origin_rejected" if origin else "origin_required"
            return None, fail(403, reason, "The websocket origin is not allowed")
        if origin and not origin_allowed(origin, (settings.emulator_screen_origin,)):
            return None, fail(403, "origin_rejected", "The websocket origin is not allowed")
        reason = _access_reason(conn, settings, row)
        if reason is not None:
            _close_row(conn, _Audit(settings, audit), row, reason, request)
            return None, fail(403, reason, "The screen session is no longer allowed")
        _known, endpoint, _owner, _group = _scope(conn, settings, ue_id)
        target = _target_for(settings, ue_id, endpoint)
        if target is None or not screen_open(target[0], target[1], settings.emulator_probe_seconds):
            return None, fail(503, "emulator_down", DOWN_MESSAGE)
        return (row, target), None

    @app.get("/emulator/{ue_id}/exchange")
    def exchange(ue_id: str, request: Request):
        if not settings.emulator_enabled:
            return fail(404, "emulator_disabled", "The emulator screen is disabled")
        code = request.query_params.get("code", "")
        with connect_db() as conn:
            row = db.emulator_session_by_exchange(conn, token_hash(settings.session_pepper, code))
            if row is None or row["ue_id"] != ue_id:
                return fail(403, "csrf_required", "The screen exchange code is not valid")
            if _access_reason(conn, settings, row) is not None:
                _close_row(conn, _Audit(settings, audit), row, "revoked", request)
                return fail(403, "revoked", "The screen session is no longer allowed")
            token = secrets.token_urlsafe(32)
            claimed = db.claim_emulator_exchange(conn, str(row["id"]), token_hash(settings.session_pepper, token))
            if claimed is None:
                return fail(403, "csrf_required", "The screen exchange code is not valid")
        response = RedirectResponse(f"/emulator/{ue_id}/", status_code=302)
        response.set_cookie(
            SCREEN_COOKIE,
            token,
            httponly=True,
            secure=settings.cookie_secure,
            samesite="lax",
            max_age=settings.emulator_max_age_seconds,
            path=f"/emulator/{ue_id}",
        )
        return response

    async def proxy_http(request: Request, ue_id: str, path: str):
        if request.method not in {"GET", "HEAD"}:
            return fail(405, "method_not_allowed", "Only GET and HEAD are proxied")
        with connect_db() as conn:
            granted, error = screen_gate(conn, request, ue_id, False)
            if error:
                return error
            _row, target = granted
        cleaned = clean_path(path)
        if cleaned is None:
            return fail(404, "emulator_not_found", "UE was not found")
        upstream_url = build_upstream(target[0], target[1], ue_id, cleaned, safe_query(request.url.query), "http")
        forwarded = {key: value for key, value in request.headers.items() if key.lower() in REQUEST_HEADERS}
        client = httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=2.0), follow_redirects=False)
        try:
            upstream = await client.send(client.build_request(request.method, upstream_url, headers=forwarded), stream=True)
        except httpx.HTTPError:
            await client.aclose()
            return fail(503, "emulator_down", DOWN_MESSAGE)
        headers = {}
        base = f"http://{target[0]}:{target[1]}"
        for key, value in upstream.headers.items():
            if key.lower() in RESPONSE_DROP:
                continue
            if key.lower() == "location":
                value = value[len(base) :] if value.startswith(base) else value
            headers[key] = value

        async def chunks():
            try:
                async for chunk in upstream.aiter_raw():
                    yield chunk
            finally:
                await upstream.aclose()
                await client.aclose()

        return StreamingResponse(chunks(), status_code=upstream.status_code, headers=headers)

    async def proxy_ws(websocket: WebSocket, ue_id: str, path: str) -> None:
        with connect_db() as conn:
            granted, error = screen_gate(conn, websocket, ue_id, True)
            if error:
                await deny_ws(websocket, error)
                return
            row, target = granted
            session_id = str(row["id"])
            actor_id = str(row["actor_id"])
            cleaned = clean_path(path)
            if cleaned is None:
                await deny_ws(websocket, fail(404, "emulator_not_found", "UE was not found"))
                return
            raw_query = websocket.scope.get("query_string", b"")
            if isinstance(raw_query, bytes):
                raw_query = raw_query.decode()
            upstream_url = build_upstream(target[0], target[1], ue_id, cleaned, safe_query(raw_query), "ws")
        try:
            upstream = await websockets.connect(upstream_url, max_size=FRAME_LIMIT, open_timeout=2)
        except Exception:
            await deny_ws(websocket, fail(503, "emulator_down", DOWN_MESSAGE))
            return
        try:
            await websocket.accept()
        except Exception:
            await upstream.close()
            return
        started = time.monotonic()
        last_client = time.monotonic()

        def note_client() -> None:
            nonlocal last_client
            last_client = time.monotonic()
            with connect_db() as conn:
                db.touch_emulator_session(conn, session_id)

        async def client_to_upstream() -> str:
            try:
                while True:
                    message = await websocket.receive()
                    if message["type"] == "websocket.disconnect":
                        return "client_close"
                    note_client()
                    if message.get("text") is not None:
                        await upstream.send(message["text"])
                    elif message.get("bytes") is not None:
                        await upstream.send(message["bytes"])
            except Exception:
                return "client_close"

        async def upstream_to_client() -> str:
            try:
                async for payload in upstream:
                    if isinstance(payload, str):
                        await websocket.send_text(payload)
                    else:
                        await websocket.send_bytes(payload)
                return "upstream_closed"
            except Exception:
                return "upstream_closed"

        async def watch() -> str:
            while True:
                await asyncio.sleep(settings.emulator_watch_seconds)
                now = time.monotonic()
                if now - started >= settings.emulator_max_age_seconds:
                    return "absolute_timeout"
                if now - last_client >= settings.emulator_idle_seconds:
                    return "idle_timeout"
                with connect_db() as conn:
                    current = db.emulator_session_by_token(conn, token_hash(settings.session_pepper, websocket.cookies.get(SCREEN_COOKIE, "")))
                    if current is None or str(current["id"]) != session_id:
                        return "replaced"
                    reason = _access_reason(conn, settings, current)
                    if reason is not None:
                        return reason

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
            stored = reason if reason != "replaced" else "client_close"
            try:
                with connect_db() as conn:
                    current = conn.execute("SELECT * FROM emulator_sessions WHERE id = %s", (session_id,)).fetchone()
                    if current is not None and current["closed_at"] is None:
                        _close_row(conn, _Audit(settings, audit), current, stored, websocket)
            except Exception:
                pass
            try:
                await upstream.close()
            except Exception:
                pass
            try:
                await websocket.close()
            except Exception:
                pass

    @app.api_route("/emulator/{ue_id}", methods=["GET", "HEAD"])
    async def http_root(request: Request, ue_id: str):
        return await proxy_http(request, ue_id, "")

    @app.api_route("/emulator/{ue_id}/{path:path}", methods=["GET", "HEAD"])
    async def http_path(request: Request, ue_id: str, path: str):
        if path == "exchange":
            return fail(404, "emulator_not_found", "UE was not found")
        return await proxy_http(request, ue_id, path)

    @app.websocket("/emulator/{ue_id}")
    async def ws_root(websocket: WebSocket, ue_id: str):
        await proxy_ws(websocket, ue_id, "")

    @app.websocket("/emulator/{ue_id}/{path:path}")
    async def ws_path(websocket: WebSocket, ue_id: str, path: str):
        await proxy_ws(websocket, ue_id, path)

    return app
