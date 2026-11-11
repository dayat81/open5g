"""Emulator screen policy. No core, no VNC password, no host port."""

from __future__ import annotations

import hashlib
import ipaddress
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qsl, urlencode

UE_ID_RE = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
_LABEL_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
_DROP_QUERY = {"ticket", "csrf", "password", "token", "vnc_password"}
UNSPECIFIED_HOSTS = {"", "0.0.0.0", "::", "::0", "*"}


def token_hash(pepper: str, token: str) -> str:
    return hashlib.sha256(f"{pepper}:{token}".encode()).hexdigest()


def validate_screen_host(host: str) -> str:
    """A destination the API may dial. Not an unspecified bind address."""

    cleaned = host.strip()
    if cleaned in UNSPECIFIED_HOSTS:
        raise ValueError("emulator target host must not be an unspecified address")
    try:
        address = ipaddress.ip_address(cleaned)
    except ValueError:
        labels = cleaned.split(".")
        if not labels or len(cleaned) > 253 or any(_LABEL_RE.fullmatch(label) is None for label in labels):
            raise ValueError("emulator target host is not a usable address") from None
        return cleaned
    if not isinstance(address, ipaddress.IPv4Address) or address.is_unspecified:
        raise ValueError("emulator target host must not be an unspecified address")
    return str(address)


def parse_targets(raw: str) -> dict[str, tuple[str, int]]:
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
        port = int(port_text)
        if port < 1 or port > 65535:
            raise ValueError("emulator target port is out of range")
        if ue_id in found:
            raise ValueError("emulator target is duplicated")
        found[ue_id] = (validate_screen_host(host), port)
    return found


def origin_allowed(origin: str | None, allowed: tuple[str, ...]) -> bool:
    if not origin or origin == "null" or not allowed:
        return False
    normal = origin.rstrip("/")
    return normal in {item.rstrip("/") for item in allowed}


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
    """Turn an absolute upstream redirect into a same-origin path.

    The sidecar already serves under `/emulator/<ue_id>`, so stripping the
    origin keeps that path. `public_prefix` is only used when the redirect
    has no path.
    """

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
    if last_active.tzinfo is None:
        last_active = last_active.replace(tzinfo=timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now - last_active >= timedelta(seconds=idle_seconds)
