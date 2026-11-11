"""Runtime settings come from the environment. Nothing here is a credential."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from open5g_dashboard.emulator import parse_targets


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
        try:
            targets = parse_targets(os.environ.get("OPEN5G_EMULATOR_TARGETS", ""))
        except ValueError as exc:
            raise RuntimeError(str(exc)) from exc
        origins = tuple(
            part.strip().rstrip("/")
            for part in os.environ.get("OPEN5G_EMULATOR_ORIGINS", "").split(",")
            if part.strip()
        )
        try:
            idle = int(os.environ.get("OPEN5G_EMULATOR_IDLE_SECONDS", "300"))
        except ValueError as exc:
            raise RuntimeError("OPEN5G_EMULATOR_IDLE_SECONDS must be an integer") from exc
        if idle < 1:
            raise RuntimeError("OPEN5G_EMULATOR_IDLE_SECONDS must be at least 1")
        try:
            probe = float(os.environ.get("OPEN5G_EMULATOR_PROBE_SECONDS", "0.5"))
        except ValueError as exc:
            raise RuntimeError("OPEN5G_EMULATOR_PROBE_SECONDS must be a number") from exc
        if probe <= 0:
            raise RuntimeError("OPEN5G_EMULATOR_PROBE_SECONDS must be greater than 0")
        return cls(database_url, pepper, secure, demo, enabled, targets, origins, idle, probe)
