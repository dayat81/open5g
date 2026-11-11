"""Runtime settings come from the environment. Nothing here is a credential."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from open5g_dashboard.emulator import origins_are_isolated, parse_targets


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
    emulator_screen_host: str = "127.0.0.2"
    emulator_screen_bind_port: int = 3001
    emulator_max_age_seconds: int = 3600
    emulator_watch_seconds: float = 5.0

    @classmethod
    def from_env(cls) -> "Settings":
        pepper = os.environ.get("OPEN5G_SESSION_PEPPER", "")
        database_url = os.environ.get("OPEN5G_DATABASE_URL", "")
        if len(pepper) < 32:
            raise RuntimeError("OPEN5G_SESSION_PEPPER must be set to at least 32 characters")
        if not database_url:
            raise RuntimeError("OPEN5G_DATABASE_URL must be set")
        secure = os.environ.get("OPEN5G_COOKIE_SECURE", "1") != "0"
        demo = os.environ.get("OPEN5G_ENABLE_DEMO_ROUTES", "0") == "1"
        enabled = os.environ.get("OPEN5G_EMULATOR_ENABLED", "0") == "1"
        origins = tuple(
            part.strip().rstrip("/")
            for part in os.environ.get("OPEN5G_EMULATOR_ORIGINS", "").split(",")
            if part.strip()
        )
        nets = tuple(
            part.strip()
            for part in os.environ.get("OPEN5G_EMULATOR_ALLOWED_NETS", "").split(",")
            if part.strip()
        )
        try:
            screen_port = int(os.environ.get("OPEN5G_EMULATOR_SCREEN_PORT", "8000"))
            idle = int(os.environ.get("OPEN5G_EMULATOR_IDLE_SECONDS", "300"))
            max_age = int(os.environ.get("OPEN5G_EMULATOR_MAX_AGE_SECONDS", "3600"))
            bind_port = int(os.environ.get("OPEN5G_EMULATOR_SCREEN_BIND_PORT", "3001"))
            probe = float(os.environ.get("OPEN5G_EMULATOR_PROBE_SECONDS", "0.5"))
            watch = float(os.environ.get("OPEN5G_EMULATOR_WATCH_SECONDS", "5"))
        except ValueError as exc:
            raise RuntimeError("emulator timing or port settings are not numbers") from exc
        if idle < 1 or max_age < idle or probe <= 0 or watch <= 0:
            raise RuntimeError("emulator timing settings are out of range")
        if screen_port < 1 or screen_port > 65535 or bind_port < 1 or bind_port > 65535:
            raise RuntimeError("emulator port settings are out of range")
        screen_origin = os.environ.get("OPEN5G_EMULATOR_SCREEN_ORIGIN", "").strip().rstrip("/")
        screen_host = os.environ.get("OPEN5G_EMULATOR_SCREEN_HOST", "127.0.0.2").strip()
        try:
            targets = parse_targets(os.environ.get("OPEN5G_EMULATOR_TARGETS", ""), nets, screen_port)
        except ValueError as exc:
            raise RuntimeError(str(exc)) from exc
        if enabled:
            if not nets or not origins or not screen_origin:
                raise RuntimeError("emulator allowlist, dashboard origins, and screen origin are required")
            if screen_host in {"", "0.0.0.0", "::"} or not origins_are_isolated(screen_origin, origins):
                raise RuntimeError("the screen origin must use a different host from the dashboard")
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
            bind_port,
            max_age,
            watch,
        )
