"""Emulator screen policy. No core, no VNC password, no host port."""

from __future__ import annotations

import hashlib
import ipaddress
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qsl, urlencode, urlparse

UE_ID_RE = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
_DROP_QUERY = {"ticket", "csrf", "password", "token", "vnc_password", "code"}
EXCHANGE_SECONDS = 60


def token_hash(pepper: str, token: str) -> str:
    return hashlib.sha256(f"{pepper}:{token}".encode()).hexdigest()


def session_rate_limited(hits: dict[str, list[float]], key: str, now: float, limit: int, window: float) -> bool:
    """True when this caller already used the session budget in the window."""

    recent = [item for item in hits.get(key, []) if now - item < window]
    if len(recent) >= limit:
        hits[key] = recent
        return True
    recent.append(now)
    hits[key] = recent
    return False


def _aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def session_expired(
    opened_at: datetime,
    last_client_at: datetime,
    now: datetime,
    idle_seconds: int,
    max_age_seconds: int,
) -> str | None:
    """Idle follows client input only. Upstream video frames are not an argument."""

    opened_at = _aware(opened_at)
    last_client_at = _aware(last_client_at)
    now = _aware(now)
    if now - opened_at >= timedelta(seconds=max_age_seconds):
        return "absolute_timeout"
    if now - last_client_at >= timedelta(seconds=idle_seconds):
        return "idle_timeout"
    return None


def target_allowed(host: str, port: int, nets: tuple[str, ...], screen_port: int) -> tuple[str, int]:
    if port != screen_port or port < 1 or port > 65535:
        raise ValueError("emulator target port is not the screen port")
    try:
        address = ipaddress.ip_address(host.strip())
    except ValueError as exc:
        raise ValueError("emulator target host must be an IPv4 address") from exc
    if not isinstance(address, ipaddress.IPv4Address) or address.is_unspecified:
        raise ValueError("emulator target host must not be an unspecified address")
    if not nets:
        raise ValueError("emulator target allowlist is empty")
    networks = []
    for item in nets:
        try:
            networks.append(ipaddress.ip_network(item, strict=False))
        except ValueError as exc:
            raise ValueError("emulator target allowlist is not a network") from exc
    if not any(address in network and isinstance(network, ipaddress.IPv4Network) for network in networks):
        raise ValueError("emulator target is outside the allowlist")
    return str(address), port


def parse_targets(raw: str, nets: tuple[str, ...] = (), screen_port: int = 8000) -> dict[str, tuple[str, int]]:
    found: dict[str, tuple[str, int]] = {}
    if not raw.strip():
        return found
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        ue_id, separator, address = item.partition("=")
        host, port_separator, port_text = address.rpartition(":")
        if (
            not separator
            or not port_separator
            or UE_ID_RE.fullmatch(ue_id) is None
            or not port_text.isdigit()
        ):
            raise ValueError("emulator target must be ue_id=host:port")
        if ue_id in found:
            raise ValueError("emulator target is duplicated")
        found[ue_id] = target_allowed(host, int(port_text), nets, screen_port)
    return found


def parse_screen_mode(raw: str) -> str:
    mode = raw.strip() or "guest"
    if mode not in {"guest", "host-agen"}:
        raise ValueError("emulator screen mode must be guest or host-agen")
    return mode


def parse_screen_upstream(raw: str) -> tuple[str, int] | None:
    """Loopback base URL used only by host-agen mode. Empty means the dial stays off."""

    text = raw.strip()
    if not text:
        return None
    parsed = urlparse(text)
    if parsed.username or parsed.password or parsed.scheme not in {"http", "ws"}:
        raise ValueError("screen upstream must be http://127.0.0.1:port or ws://127.0.0.1:port")
    if parsed.hostname != "127.0.0.1" or parsed.port is None or not 1 <= parsed.port <= 65535:
        raise ValueError("screen upstream must use 127.0.0.1 and an explicit port")
    if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise ValueError("screen upstream must not include a path or query")
    return "127.0.0.1", parsed.port


def origin_allowed(origin: str | None, allowed: tuple[str, ...]) -> bool:
    if not origin or origin == "null" or not allowed:
        return False
    normal = origin.rstrip("/")
    return normal in {item.rstrip("/") for item in allowed}


def _origin_key(origin: str) -> tuple[str, str, int] | None:
    parsed = urlparse(origin)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return None
    if parsed.hostname in {"0.0.0.0", "::"}:
        return None
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80
    return parsed.scheme, parsed.hostname, port


def origins_are_isolated(screen_origin: str, dashboard_origins: tuple[str, ...]) -> bool:
    """Cookies ignore ports, so the screen hostname must differ from the dashboard host."""

    screen = _origin_key(screen_origin)
    if screen is None:
        return False
    for item in dashboard_origins:
        other = _origin_key(item)
        if other is not None and other[1] == screen[1]:
            return False
    return True


def clean_path(path: str) -> str | None:
    if "\\" in path or "://" in path or path.startswith("/"):
        return None
    parts = [part for part in path.split("/") if part]
    if any(part == ".." for part in parts):
        return None
    return "/".join(parts)


def safe_query(raw: str) -> str:
    kept: list[tuple[str, str]] = []
    for key, value in parse_qsl(raw, keep_blank_values=True):
        if key.lower() in _DROP_QUERY:
            continue
        if any(char in key or char in value for char in "\r\n"):
            continue
        kept.append((key, value))
    return urlencode(kept)


def build_upstream(host: str, port: int, ue_id: str, path: str, query: str, scheme: str) -> str:
    url = f"{scheme}://{host}:{port}/emulator/{ue_id}"
    if path:
        url += "/" + path
    if query:
        url += "?" + query
    return url


def rewrite_location(value: str, upstream_base: str, public_prefix: str) -> str:
    base = upstream_base.rstrip("/")
    if not value.startswith(base):
        return value
    remainder = value[len(base) :]
    if remainder.startswith("/"):
        return remainder
    return public_prefix + remainder


def parse_attach_ipv4(value: str) -> str:
    try:
        address = ipaddress.ip_address(value.strip())
    except ValueError as exc:
        raise ValueError("attach address must be an IPv4 address") from exc
    if not isinstance(address, ipaddress.IPv4Address) or address.is_unspecified:
        raise ValueError("attach address must be an IPv4 address")
    return str(address)


def is_idle(last_active: datetime, now: datetime, idle_seconds: int) -> bool:
    return session_expired(last_active, last_active, now, idle_seconds, 10**9) == "idle_timeout"
