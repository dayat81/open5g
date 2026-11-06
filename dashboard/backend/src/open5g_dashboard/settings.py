"""Runtime settings come from the environment. Nothing here is a credential."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    database_url: str
    session_pepper: str
    cookie_secure: bool
    enable_demo_routes: bool

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
        return cls(database_url, pepper, secure, demo)
