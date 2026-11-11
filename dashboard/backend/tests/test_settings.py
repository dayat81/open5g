"""Startup rejects placeholder secrets. No database is opened."""

import pytest

from open5g_dashboard.settings import Settings


def _env(monkeypatch, **overrides):
    values = {
        "OPEN5G_SESSION_PEPPER": "test-pepper-not-a-secret-value-32b",
        "OPEN5G_DATABASE_URL": "postgresql://open5g:local-only@127.0.0.1/open5g",
        "OPEN5G_MONGO_URI": "",
        "OPEN5G_BIND_HOST": "127.0.0.1",
        "OPEN5G_BIND_PORT": "8000",
    }
    values.update(overrides)
    for key, value in values.items():
        monkeypatch.setenv(key, value)


def test_placeholder_pepper_and_database_url_are_rejected(monkeypatch):
    _env(monkeypatch, OPEN5G_SESSION_PEPPER="REPLACE_WITH_32_CHARACTER_LOCAL_SECRET")
    with pytest.raises(RuntimeError, match="OPEN5G_SESSION_PEPPER"):
        Settings.from_env()
    _env(monkeypatch, OPEN5G_DATABASE_URL="postgresql://open5g:REPLACE_WITH_LOCAL_PASSWORD@dashboard-postgres/open5g")
    with pytest.raises(RuntimeError, match="OPEN5G_DATABASE_URL"):
        Settings.from_env()


def test_cors_origin_on_the_grafana_port_is_rejected(monkeypatch):
    _env(monkeypatch, OPEN5G_CORS_ORIGINS="http://127.0.0.1:3000")  # Grafana owns this port
    with pytest.raises(RuntimeError, match="Grafana"):
        Settings.from_env()
    _env(monkeypatch, OPEN5G_CORS_ORIGINS="http://127.0.0.1:3300")
    assert Settings.from_env().cors_origins == ("http://127.0.0.1:3300",)


def test_cors_origin_on_the_screen_port_is_rejected(monkeypatch):
    _env(monkeypatch, OPEN5G_CORS_ORIGINS="http://localhost:3301")
    with pytest.raises(RuntimeError, match="3301"):
        Settings.from_env()


def test_screen_origin_must_use_a_different_host(monkeypatch):
    shared = {
        "OPEN5G_EMULATOR_ENABLED": "1",
        "OPEN5G_EMULATOR_ALLOWED_NETS": "192.0.2.0/24",
        "OPEN5G_EMULATOR_ORIGINS": "http://127.0.0.1:3300",
        "OPEN5G_EMULATOR_SCREEN_ORIGIN": "http://127.0.0.1:3301",
    }
    _env(monkeypatch, **shared)
    with pytest.raises(RuntimeError, match="different host"):
        Settings.from_env()
    shared["OPEN5G_EMULATOR_SCREEN_ORIGIN"] = "http://localhost:3301"
    _env(monkeypatch, **shared)
    assert Settings.from_env().emulator_screen_origin == "http://localhost:3301"


def test_real_looking_local_values_bind_loopback_by_default(monkeypatch):
    _env(monkeypatch)
    settings = Settings.from_env()
    assert settings.bind_host == "127.0.0.1"
    assert settings.bind_port == 8000
    assert settings.cors_origins == ()
