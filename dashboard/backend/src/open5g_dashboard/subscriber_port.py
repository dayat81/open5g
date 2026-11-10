"""Subscriber store port.

The lab Compose project has no Open5GS WebUI, so the only write path is the
MongoDB ``subscribers`` collection. An empty URI disables the port. The port
never returns Ki, OPc, or the MongoDB URI.
"""

from __future__ import annotations

from typing import Any, Protocol
from urllib.parse import parse_qs, urlsplit

from open5g_dashboard.domain import ProfileError
from open5g_dashboard.open5gs_schema import apply_profile_to_document, credentials_present, drop_secrets, project_subscriber

_SAFE_ERRORS = {
    "TimeoutError": "MongoDB timed out",
    "ServerSelectionTimeoutError": "MongoDB timed out",
    "ConnectionFailure": "MongoDB connection failed",
    "NetworkTimeout": "MongoDB timed out",
    "AutoReconnect": "MongoDB connection failed",
    "ConfigurationError": "MongoDB URI was rejected",
}


class SubscriberUnavailable(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def describe_mongo_target(uri: str) -> dict[str, str | bool]:
    """Say whether auth and TLS are requested. The host is not included."""
    if not uri:
        return {"configured": False, "auth": "not_configured", "tls": "not_configured"}
    parsed = urlsplit(uri)
    flags = [item.lower() for item in parse_qs(parsed.query).get("tls", []) + parse_qs(parsed.query).get("ssl", [])]
    tls = "enabled" if any(flag in {"1", "true", "yes"} for flag in flags) else "not_requested"
    return {"configured": True, "auth": "present" if parsed.username else "absent", "tls": tls}


def _safe_message(exc: Exception) -> str:
    return _SAFE_ERRORS.get(type(exc).__name__, "MongoDB request failed")


class SubscriberPort(Protocol):
    configured: bool

    def describe(self) -> dict[str, str | bool]: ...

    def probe(self) -> dict[str, Any]: ...

    def read(self, imsi: str) -> dict[str, Any]: ...

    def provision(self, imsi: str, content: dict[str, Any]) -> dict[str, Any]: ...


class DisabledSubscriberPort:
    configured = False

    def describe(self) -> dict[str, str | bool]:
        return describe_mongo_target("")

    def probe(self) -> dict[str, Any]:
        return {"name": "mongo-subscriber", "status": "not_configured", "error": None, "http_status": None}

    def read(self, imsi: str) -> dict[str, Any]:
        return {
            "status": "not_configured",
            "found": False,
            "configured": False,
            "imsi": imsi,
            "credentials_present": False,
            "attach_ready": False,
            "security_returned": False,
            "sessions": [],
            "session_count": 0,
            "live_gx_rar": False,
        }

    def provision(self, imsi: str, content: dict[str, Any]) -> dict[str, Any]:
        raise SubscriberUnavailable("subscriber_store_not_configured", "OPEN5G_MONGO_URI is empty")


class MongoSubscriberPort:
    configured = True

    def __init__(self, uri: str, database: str, collection: str, timeout_ms: int, client: Any = None):
        self._uri = uri
        self._database = database
        self._collection = collection
        self._timeout_ms = timeout_ms
        self._client = client

    def describe(self) -> dict[str, str | bool]:
        return describe_mongo_target(self._uri)

    def _client_handle(self):
        if self._client is not None:
            return self._client
        from pymongo import MongoClient

        self._client = MongoClient(
            self._uri,
            serverSelectionTimeoutMS=self._timeout_ms,
            connectTimeoutMS=self._timeout_ms,
            socketTimeoutMS=self._timeout_ms,
        )
        return self._client

    def _coll(self):
        return self._client_handle()[self._database][self._collection]

    def probe(self) -> dict[str, Any]:
        try:
            self._coll().find_one({"imsi": "__open5g_ping__"}, {"_id": 1})
        except Exception as exc:
            return {"name": "mongo-subscriber", "status": "down", "error": _safe_message(exc), "http_status": None}
        return {"name": "mongo-subscriber", "status": "reachable", "error": None, "http_status": None}

    def read(self, imsi: str) -> dict[str, Any]:
        try:
            document = self._coll().find_one({"imsi": imsi})
        except Exception as exc:
            raise SubscriberUnavailable("subscriber_store_unavailable", _safe_message(exc)) from None
        if document is None:
            return {
                "status": "absent",
                "found": False,
                "configured": True,
                "imsi": imsi,
                "credentials_present": False,
                "attach_ready": False,
                "security_returned": False,
                "sessions": [],
                "session_count": 0,
                "live_gx_rar": False,
            }
        return project_subscriber(document, imsi)

    def provision(self, imsi: str, content: dict[str, Any]) -> dict[str, Any]:
        try:
            collection = self._coll()
            existing = collection.find_one({"imsi": imsi})
            updated, notes = apply_profile_to_document(existing, imsi, content)
            created = existing is None
            if created:
                collection.insert_one(updated)
            else:
                collection.replace_one({"imsi": imsi}, updated)
            stored = collection.find_one({"imsi": imsi})
        except (SubscriberUnavailable, ProfileError):
            raise
        except Exception as exc:
            raise SubscriberUnavailable("subscriber_store_unavailable", _safe_message(exc)) from None
        if stored is None:
            raise SubscriberUnavailable("subscriber_store_unavailable", "MongoDB read after write failed")
        body = project_subscriber(stored, imsi)
        if credentials_present(existing) and not body["credentials_present"]:
            raise SubscriberUnavailable("subscriber_store_unavailable", "MongoDB read after write failed")
        return drop_secrets(
            {
                "status": "written",
                "created": created,
                "effect": "subscriber_document_only",
                "session_effect": "not_pushed_to_active_session",
                "live_gx_rar": False,
                "notes": notes,
                "subscriber": body,
            }
        )


def build_subscriber_port(settings) -> DisabledSubscriberPort | MongoSubscriberPort:
    if not settings.mongo_uri:
        return DisabledSubscriberPort()
    return MongoSubscriberPort(
        settings.mongo_uri,
        settings.mongo_database,
        settings.mongo_collection,
        settings.mongo_timeout_ms,
    )
