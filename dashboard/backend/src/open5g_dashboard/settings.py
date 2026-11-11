"""Runtime settings come from the environment. Nothing here is a credential."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from open5g_dashboard.emulator import origins_are_isolated, parse_targets
from open5g_dashboard.telemetry import merge_endpoints, parse_endpoints


def _bounded_int(raw: str, low: int, high: int, name: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer") from exc
    if not low <= value <= high:
        raise RuntimeError(f"{name} is outside {low}..{high}")
    return value


def _reject_placeholder(name: str, value: str) -> None:
    folded = value.upper()
    if not value.strip() or "REPLACE_" in folded or "CHANGEME" in folded:
        raise RuntimeError(f"{name} is empty or still a placeholder")


def _bind_host(raw: str) -> str:
    host = raw.strip()
    _reject_placeholder("OPEN5G_BIND_HOST", host)
    if host in {"*", "0.0.0.0", "::"}:
        raise RuntimeError("OPEN5G_BIND_HOST must be a specific address")
    return host


def _bind_port(raw: str) -> int:
    return _bounded_int(raw, 1, 65535, "OPEN5G_BIND_PORT")


def _csv(raw: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in raw.split(",") if item.strip())


def _origin_port(origin: str) -> str | None:
    raw = origin.strip()
    if "://" not in raw:
        return None
    host = raw.split("://", 1)[1].split("/", 1)[0]
    if host.startswith("[") and "]" in host:
        host = host.split("]", 1)[1]
    if ":" not in host:
        return None
    return host.rsplit(":", 1)[1]


def _bounded_float(raw: str, low: float, high: float, name: str) -> float:
    try:
        value = float(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be a number") from exc
    if not low <= value <= high:
        raise RuntimeError(f"{name} is outside {low}..{high}")
    return value


@dataclass(frozen=True)
class Settings:
    database_url: str
    session_pepper: str
    cookie_secure: bool
    enable_demo_routes: bool
    emulator_enabled: bool = False
    emulator_targets: dict[str, tuple[str, int]] = field(default_factory=dict)
    emulator_origins: tuple[str, ...] = ()
    emulator_idle_seconds: int = 300
    emulator_probe_seconds: float = 0.5
    emulator_allowed_nets: tuple[str, ...] = ()
    emulator_screen_port: int = 8000
    emulator_screen_origin: str = ""
    emulator_screen_host: str = "127.0.0.1"
    emulator_screen_bind_port: int = 3301
    emulator_max_age_seconds: int = 3600
    emulator_watch_seconds: float = 5.0
    mongo_uri: str = ""
    mongo_database: str = "open5gs"
    mongo_collection: str = "subscribers"
    mongo_timeout_ms: int = 2000
    enable_gx_rar: bool = False
    metrics_endpoints: tuple[tuple[str, str], ...] = ()
    metrics_timeout_s: float = 2.0
    apn_allowlist: tuple[str, ...] = ()
    cors_origins: tuple[str, ...] = ()
    bind_host: str = "127.0.0.1"
    bind_port: int = 8000

    @classmethod
    def from_env(cls) -> "Settings":
        pepper = os.environ.get("OPEN5G_SESSION_PEPPER", "")
        database_url = os.environ.get("OPEN5G_DATABASE_URL", "")
        _reject_placeholder("OPEN5G_SESSION_PEPPER", pepper)
        _reject_placeholder("OPEN5G_DATABASE_URL", database_url)
        if len(pepper) < 32:
            raise RuntimeError("OPEN5G_SESSION_PEPPER must be set to at least 32 characters")
        if "REPLACE_" in os.environ.get("OPEN5G_MONGO_URI", "").upper():
            raise RuntimeError("OPEN5G_MONGO_URI is still a placeholder")
        cors = _csv(os.environ.get("OPEN5G_CORS_ORIGINS", ""))
        if "*" in cors:
            raise RuntimeError("OPEN5G_CORS_ORIGINS must list explicit origins")
        for origin in cors:
            if _origin_port(origin) == "3000":  # Grafana keeps this port
                raise RuntimeError(
                    "OPEN5G_CORS_ORIGINS must not use port 3000; that port is Grafana. The dashboard web default is WEB_PORT 3300."
                )
        secure = os.environ.get("OPEN5G_COOKIE_SECURE", "1") != "0"
        demo = os.environ.get("OPEN5G_ENABLE_DEMO_ROUTES", "0") == "1"
        enabled = os.environ.get("OPEN5G_EMULATOR_ENABLED", "0") == "1"
        origins = tuple(part.strip().rstrip("/") for part in os.environ.get("OPEN5G_EMULATOR_ORIGINS", "").split(",") if part.strip())
        nets = tuple(part.strip() for part in os.environ.get("OPEN5G_EMULATOR_ALLOWED_NETS", "").split(",") if part.strip())
        screen_port = _bounded_int(os.environ.get("OPEN5G_EMULATOR_SCREEN_PORT", "8000"), 1, 65535, "OPEN5G_EMULATOR_SCREEN_PORT")
        idle = _bounded_int(os.environ.get("OPEN5G_EMULATOR_IDLE_SECONDS", "300"), 1, 86400, "OPEN5G_EMULATOR_IDLE_SECONDS")
        max_age = _bounded_int(os.environ.get("OPEN5G_EMULATOR_MAX_AGE_SECONDS", "3600"), idle, 86400, "OPEN5G_EMULATOR_MAX_AGE_SECONDS")
        screen_bind_port = _bounded_int(os.environ.get("OPEN5G_EMULATOR_SCREEN_BIND_PORT", "3301"), 1, 65535, "OPEN5G_EMULATOR_SCREEN_BIND_PORT")
        probe = _bounded_float(os.environ.get("OPEN5G_EMULATOR_PROBE_SECONDS", "0.5"), 0.05, 5.0, "OPEN5G_EMULATOR_PROBE_SECONDS")
        watch = _bounded_float(os.environ.get("OPEN5G_EMULATOR_WATCH_SECONDS", "5"), 0.05, 60.0, "OPEN5G_EMULATOR_WATCH_SECONDS")
        screen_origin = os.environ.get("OPEN5G_EMULATOR_SCREEN_ORIGIN", "").strip().rstrip("/")
        screen_host = os.environ.get("OPEN5G_EMULATOR_SCREEN_HOST", "127.0.0.1").strip()
        if screen_bind_port in {3000, 3001}:  # Grafana keeps 3000; 3001 is Next inside the web image
            raise RuntimeError("the screen listener must not use port 3000 (Grafana) or 3001 (Next inside the web image)")
        try:
            targets = parse_targets(os.environ.get("OPEN5G_EMULATOR_TARGETS", ""), nets, screen_port)
        except ValueError as exc:
            raise RuntimeError(str(exc)) from exc
        if enabled:
            if not nets or not origins or not screen_origin:
                raise RuntimeError("emulator allowlist, dashboard origins, and screen origin are required")
            if screen_host in {"", "0.0.0.0", "::"} or not origins_are_isolated(screen_origin, origins):
                raise RuntimeError("the screen origin must differ from every dashboard origin")
            if _origin_port(screen_origin) in {"3000", "3001"}:  # Grafana keeps 3000; 3001 is Next inside the web image
                raise RuntimeError("the screen origin must not use port 3000 (Grafana) or 3001 (Next inside the web image)")
        mongo_database = os.environ.get("OPEN5G_MONGO_DATABASE", "open5gs").strip() or "open5gs"
        mongo_collection = os.environ.get("OPEN5G_MONGO_COLLECTION", "subscribers").strip() or "subscribers"
        return cls(
            database_url,
            pepper,
            secure,
            demo,
            enabled,
            targets,
            origins,
            idle,
            probe,
            nets,
            screen_port,
            screen_origin,
            screen_host,
            screen_bind_port,
            max_age,
            watch,
            mongo_uri=os.environ.get("OPEN5G_MONGO_URI", "").strip(),
            mongo_database=mongo_database,
            mongo_collection=mongo_collection,
            mongo_timeout_ms=_bounded_int(os.environ.get("OPEN5G_MONGO_TIMEOUT_MS", "2000"), 200, 10000, "OPEN5G_MONGO_TIMEOUT_MS"),
            enable_gx_rar=os.environ.get("OPEN5G_ENABLE_GX_RAR", "0") == "1",
            metrics_endpoints=merge_endpoints(
                parse_endpoints(os.environ.get("OPEN5G_METRICS_ENDPOINTS", "")),
                parse_endpoints(os.environ.get("OPEN5G_HEALTH_ENDPOINTS", "")),
            ),
            metrics_timeout_s=_bounded_float(os.environ.get("OPEN5G_METRICS_TIMEOUT_S", "2"), 0.2, 10.0, "OPEN5G_METRICS_TIMEOUT_S"),
            apn_allowlist=_csv(os.environ.get("OPEN5G_APN_ALLOWLIST", "")),
            cors_origins=cors,
            bind_host=_bind_host(os.environ.get("OPEN5G_BIND_HOST", "127.0.0.1")),
            bind_port=_bind_port(os.environ.get("OPEN5G_BIND_PORT", "8000")),
        )
