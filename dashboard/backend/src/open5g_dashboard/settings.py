"""Runtime settings come from the environment. Nothing here is a credential."""

from __future__ import annotations

import os
from dataclasses import dataclass

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
    if host == "*":
        raise RuntimeError("OPEN5G_BIND_HOST must be an address, not a wildcard")
    return host


def _bind_port(raw: str) -> int:
    try:
        port = int(raw)
    except ValueError as exc:
        raise RuntimeError("OPEN5G_BIND_PORT must be an integer") from exc
    if not 1 <= port <= 65535:
        raise RuntimeError("OPEN5G_BIND_PORT is outside 1..65535")
    return port


def _csv(raw: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in raw.split(",") if item.strip())


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
        secure = os.environ.get("OPEN5G_COOKIE_SECURE", "1") != "0"
        demo = os.environ.get("OPEN5G_ENABLE_DEMO_ROUTES", "0") == "1"
        mongo_database = os.environ.get("OPEN5G_MONGO_DATABASE", "open5gs").strip() or "open5gs"
        mongo_collection = os.environ.get("OPEN5G_MONGO_COLLECTION", "subscribers").strip() or "subscribers"
        return cls(
            database_url,
            pepper,
            secure,
            demo,
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
